// SPDX-License-Identifier: GPL-2.0
/*
 * mts.c — driver de rede para a GBE do southbridge Baikal (PS4 Pro).
 *
 * O Orbis usa DOIS drivers de GBE diferentes: `msk`/`mskc` (Marvell Yukon) para
 * Aeolia/Belize, e `mts`/`mtsc_pci` (sys/dev/mts/if_mts.c) para o Baikal. São
 * silícios distintos. O `sky2` do Linux é o equivalente do `msk` e por isso
 * NÃO serve para o Baikal: ele lê B2_CHIP_ID em BAR0+0x11b, encontra o que o
 * MTS tiver ali (0x00) e aborta com "unsupported chip type 0x0".
 *
 * O hardware sempre esteve vivo: a BAR0 tem 30 registradores estáveis não-zero
 * e 12 contadores clear-on-read que já haviam contado tráfego real. Ver
 * memory/GBE-VIVA-driver-errado-mts-nao-sky2.md.
 *
 * Especificação da sequência de init: consolidado/MTS_INIT_SEQUENCE_dc5a31f0.md
 * (extraída de fcn.ffffffffdc5a31f0 do kernel Orbis 12.52 e cruzada com
 * medições ao vivo da BAR0).
 *
 * ---------------------------------------------------------------------------
 * BRING-UP EM ESTÁGIOS  (module param `stage`, default 4)
 *
 *   0 — só faz probe e mapeia a BAR0. Nenhuma escrita. Totalmente inócuo.
 *   1 — + dump completo dos registradores (comparável com o baseline medido).
 *   2 — + aloca os anéis de DMA e programa 0x3c/0x40/0x44/0x48.
 *   3 — + habilita os MAC cores (0x34/0x38) e escreve a IMR.
 *   4 — + pci_set_master(), IRQ e register_netdev().
 *
 * A escada existe porque este hardware já derrubou o vídeo do console e travou
 * o boot em tentativas anteriores. Cada estágio é testável isoladamente, e o
 * default NÃO escreve em lugar nenhum.
 *
 * ⚠️ POR QUE pci_set_master() SÓ NO ESTÁGIO 4: os registradores de anel chegam
 * ao Linux com os endereços FÍSICOS herdados do Orbis (medidos: TX 0x10000000,
 * RX 0x10004000). O /proc/iomem mostra `00700000-7efe7fff : System RAM` — ou
 * seja, ambos apontam para RAM que o Linux usa. Ligar o Bus Master antes de
 * reprogramar esses registradores faria o MAC ler descritores e escrever
 * pacotes recebidos dentro da memória do kernel.
 */

#include <linux/module.h>
#include <linux/pci.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/dma-mapping.h>
#include <linux/delay.h>
#include <linux/interrupt.h>
#include <linux/ethtool.h>
#include <linux/timer.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/if_vlan.h>
#include <asm/ps4.h>
/* baikal.h e header privado de drivers/ps4/; o sky2 ja usa esse mesmo padrao
 * de include relativo para aeolia.h. De la vem BAIKAL_FUNC_ID_MEM e os
 * offsets da SPM, usados so para ler o MAC address. */
#include "../../../ps4/baikal.h"

#include "mts.h"

#define DRV_NAME	"mts"
#define DRV_VERSION	"0.1"

static int stage = 4;
module_param(stage, int, 0444);
MODULE_PARM_DESC(stage,
	"Estagio de bring-up: 0=probe 1=+dump 2=+aneis DMA 3=+enable MAC 4=+netdev (default 4)");

static bool force_mac_reset;
module_param(force_mac_reset, bool, 0444);
MODULE_PARM_DESC(force_mac_reset,
	"Escreve a rotina de stop antes do init (default off)");

/* Module params para habilitação progressiva (fases A/B/C do plano) */
static bool enable_carrier = true;
module_param(enable_carrier, bool, 0644);
MODULE_PARM_DESC(enable_carrier, "Habilita detecção de carrier/link (default true)");


static bool enable_rx = true;
module_param(enable_rx, bool, 0644);
MODULE_PARM_DESC(enable_rx, "Habilita recepção RX (default true)");

static bool enable_tx = true;
module_param(enable_tx, bool, 0644);
MODULE_PARM_DESC(enable_tx, "Habilita transmissão TX (default true)");

static unsigned int poll_interval_ms = 10;
module_param(poll_interval_ms, uint, 0644);
MODULE_PARM_DESC(poll_interval_ms, "Intervalo do timer de polling em ms (default 10)");

/* PHY calibration (Orbis dc5a0ba0) */
static bool enable_phy_calib = true;
module_param(enable_phy_calib, bool, 0644);
MODULE_PARM_DESC(enable_phy_calib, "Habilita calibração PHY (Orbis dc5a0ba0) (default true)");

static bool enable_phy_calib_table = true;
module_param(enable_phy_calib_table, bool, 0644);
MODULE_PARM_DESC(enable_phy_calib_table, "Habilita tabela indexada 0x1bc-0x1d4 de calibragem (SAFE 128 entries, default true)");


static bool force_carrier = false;
module_param(force_carrier, bool, 0644);
MODULE_PARM_DESC(force_carrier, "Força carrier ON para testes de TX/RX via DMA (default false)");


/* Phase 1: IMR value para tentar irq real (default 0x0 = tudo mascarado) */
static unsigned int irq_mask = 0x0;
module_param(irq_mask, uint, 0644);
MODULE_PARM_DESC(irq_mask, "Valor de IMR (0x54) para habilitar interrupções (default 0x0 = tudo mascarado)");

/* Phase 2: IRQ storm guard — desabilita IRQ se mais de irq_storm_max_count
 * interrupcoes chegarem dentro de uma janela de irq_storm_threshold_ms. */
static unsigned int irq_storm_threshold_ms = 0;
module_param(irq_storm_threshold_ms, uint, 0644);
MODULE_PARM_DESC(irq_storm_threshold_ms, "Duracao da janela em ms para contagem de storm (0 = guarda desabilitada, default 0)");

static unsigned int irq_storm_max_count = 5000;
module_param(irq_storm_max_count, uint, 0644);
MODULE_PARM_DESC(irq_storm_max_count, "Numero maximo de IRQs permitido dentro da janela antes de desabilitar (default 5000)");


/* ------------------------------------------------------------------ */
/* Acesso a registrador                                               */
/* ------------------------------------------------------------------ */

static inline u32 mts_read(struct mts_priv *mp, u32 reg)
{
	return ioread32(mp->regs + reg);
}

static inline void mts_write(struct mts_priv *mp, u32 reg, u32 val)
{
	iowrite32(val, mp->regs + reg);
}

static inline void mts_set(struct mts_priv *mp, u32 reg, u32 bits)
{
	mts_write(mp, reg, mts_read(mp, reg) | bits);
}

static inline void mts_clear(struct mts_priv *mp, u32 reg, u32 bits)
{
	mts_write(mp, reg, mts_read(mp, reg) & ~bits);
}

/* ------------------------------------------------------------------ */
/* MDIO Clause 45  (transcrito de fcn.ffffffffdc5a2680)               */
/*                                                                     */
/* O registrador de comando/status fica em BAR0+0x00 — sem offset      */
/* adicional, confirmado tanto na decompilacao quanto por leitura (a   */
/* GBE so tem a BAR0, nao ha outro recurso onde pudesse estar).        */
/*                                                                     */
/* Formato do comando: [31:16] endereco do registrador do PHY,         */
/*                     [12:8]  devad,                                  */
/*                     [7:0]   opcode (0x20 = endereco, 0xe0 = leitura)*/
/* Pronto = bit 15 do half baixo.                                      */
/* ------------------------------------------------------------------ */

static int mts_mdio_wait(struct mts_priv *mp)
{
	int i;

	for (i = 0; i < MTS_MDIO_RETRIES; i++) {
		if (mts_read(mp, MTS_MDIO) & MTS_MDIO_READY)
			return 0;
		udelay(10);
	}
	return -ETIMEDOUT;
}

static int mts_mdio_read(struct mts_priv *mp, u8 devad, u16 reg, u16 *out)
{
	int ret;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO,
		  ((u32)reg << 16) | ((devad & 0x1f) << 8) | MTS_MDIO_OP_ADDR);

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO, ((devad & 0x1f) << 8) | MTS_MDIO_OP_READ);

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	*out = mts_read(mp, MTS_MDIO) >> 16;
	return 0;
}

static int mts_mdio_write(struct mts_priv *mp, u8 devad, u16 reg, u16 val)
{
	int ret;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO,
		  ((u32)reg << 16) | ((devad & 0x1f) << 8) | MTS_MDIO_OP_ADDR);

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO,
		  ((u32)val << 16) | ((devad & 0x1f) << 8) | 0x10); /* OP_WRITE */

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	return 0;
}

/* Page operations (Clause 45 MDIO devad=page, reg=0x0000) — decompilado dc5a2950/dc5a2840 */
static int mts_mdio_page_write(struct mts_priv *mp, u8 page, u16 val)
{
	return mts_mdio_write(mp, page, 0x0000, val);
}

static int mts_mdio_page_read(struct mts_priv *mp, u8 page, u16 *out)
{
	return mts_mdio_read(mp, page, 0x0000, out);
}

/* Helper para escrita MDIO usando endereço empacotado (formato Orbis: bits 15:0=reg, 23:16=devad, 31:24=page) */
static int mts_mdio_write_packed(struct mts_priv *mp, u32 packed_addr, u16 val)
{
	u8 devad = (packed_addr >> 16) & 0xff;
	u16 reg = packed_addr & 0xffff;
	return mts_mdio_write(mp, devad, reg, val);
}

static int mts_mdio_read_packed(struct mts_priv *mp, u32 packed_addr, u16 *out)
{
	u8 devad = (packed_addr >> 16) & 0xff;
	u16 reg = packed_addr & 0xffff;
	return mts_mdio_read(mp, devad, reg, out);
}

/* ================================================================ */
/* MDIO Clause 22 (MII) — alternativa se Clause 45 falhar          */
/* ================================================================ */

/* Clause 22 usa formato mais simples: sem "ADDR" phase separada */
#define MTS_MDIO_C22_OP_READ    0x02
#define MTS_MDIO_C22_OP_WRITE   0x01

static int mts_mdio_c22_read(struct mts_priv *mp, u8 phy_addr, u8 reg, u16 *out)
{
	int ret;
	u32 cmd;

	/* Formato Clause 22: [4:0]=opcode, [8:5]=reg, [12:9]=phy */
	cmd = (phy_addr & 0x1f) << 9 | (reg & 0x1f) << 5 | MTS_MDIO_C22_OP_READ;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO, cmd);

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	*out = mts_read(mp, MTS_MDIO) >> 16;
	return 0;
}

static int mts_mdio_c22_write(struct mts_priv *mp, u8 phy_addr, u8 reg, u16 val)
{
	int ret;
	u32 cmd;

	/* Formato Clause 22 */
	cmd = (phy_addr & 0x1f) << 9 | (reg & 0x1f) << 5 | MTS_MDIO_C22_OP_WRITE;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO, ((u32)val << 16) | cmd);

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	return 0;
}

/*
 * Sonda o PHY e valida o resultado de forma falseavel.
 *
 * Um teste anterior por telnet declarou sucesso porque os valores nao eram
 * 0x0000 nem 0xffff — mas os 8 alvos devolveram todos o MESMO valor, que era
 * residuo ja presente no registrador. Registradores distintos do PHY nao podem
 * ter conteudo identico; entao a checagem aqui exige valores DIFERENTES entre
 * alvos, alem de diferentes do residuo inicial.
 */
static void mts_mdio_probe(struct mts_priv *mp)
{
	static const struct { u8 devad; u16 reg; const char *nome; } alvos[] = {
		{ 0x01, 0x0002, "PMA/PMD ID1" },
		{ 0x01, 0x0003, "PMA/PMD ID2" },
		{ 0x01, 0x0000, "PMA/PMD Control1" },
		{ 0x01, 0x0001, "PMA/PMD Status1" },
		{ 0x03, 0x0002, "PCS ID1" },
	};
	u16 vals[ARRAY_SIZE(alvos)];
	u16 residuo = mts_read(mp, MTS_MDIO) >> 16;
	int i, j, ok = 0, distintos = 0;

	dev_info(&mp->pdev->dev, "MDIO: residuo inicial 0x%04x\n", residuo);

	for (i = 0; i < ARRAY_SIZE(alvos); i++) {
		if (mts_mdio_read(mp, alvos[i].devad, alvos[i].reg, &vals[i])) {
			dev_info(&mp->pdev->dev, "MDIO %s: timeout\n", alvos[i].nome);
			vals[i] = 0xffff;
			continue;
		}
		dev_info(&mp->pdev->dev, "MDIO devad=%#04x reg=%#06x (%s) = 0x%04x\n",
			 alvos[i].devad, alvos[i].reg, alvos[i].nome, vals[i]);
		if (vals[i] != residuo && vals[i] != 0x0000 && vals[i] != 0xffff)
			ok++;
	}

	for (i = 0; i < ARRAY_SIZE(alvos); i++) {
		bool novo = true;

		for (j = 0; j < i; j++)
			if (vals[j] == vals[i])
				novo = false;
		if (novo)
			distintos++;
	}

	if (ok && distintos > 1)
		dev_info(&mp->pdev->dev,
			 "MDIO: PHY RESPONDE (%d alvos com dado proprio, %d valores distintos)\n",
			 ok, distintos);
	else
		dev_warn(&mp->pdev->dev,
			 "MDIO: SEM leitura valida (%d distintos) — transacao nao completou\n",
			 distintos);
}

/* ------------------------------------------------------------------ */
/* Aneis de DMA  (layout de MTS_INIT_SEQUENCE_dc5a31f0.md secao 4)     */
/* ------------------------------------------------------------------ */

static void mts_free_rings(struct mts_priv *mp)
{
	struct device *d = &mp->pdev->dev;

	if (mp->rx_buf) {
		dma_free_coherent(d, MTS_RX_BUF_TOTAL, mp->rx_buf, mp->rx_buf_dma);
		mp->rx_buf = NULL;
	}
	if (mp->rx_ring) {
		dma_free_coherent(d, MTS_RING_BYTES, mp->rx_ring, mp->rx_ring_dma);
		mp->rx_ring = NULL;
	}
	if (mp->tx_ring) {
		dma_free_coherent(d, MTS_RING_BYTES, mp->tx_ring, mp->tx_ring_dma);
		mp->tx_ring = NULL;
	}
	if (mp->tx_skb) {
		kfree(mp->tx_skb);
		mp->tx_skb = NULL;
	}
	if (mp->tx_skb_dma) {
		kfree(mp->tx_skb_dma);
		mp->tx_skb_dma = NULL;
	}
	if (mp->tx_skb_len) {
		kfree(mp->tx_skb_len);
		mp->tx_skb_len = NULL;
	}
}

static int mts_alloc_rings(struct mts_priv *mp)
{
	struct device *d = &mp->pdev->dev;

	mp->tx_ring = dma_alloc_coherent(d, MTS_RING_BYTES, &mp->tx_ring_dma,
					 GFP_KERNEL);
	mp->rx_ring = dma_alloc_coherent(d, MTS_RING_BYTES, &mp->rx_ring_dma,
					 GFP_KERNEL);
	mp->rx_buf = dma_alloc_coherent(d, MTS_RX_BUF_TOTAL, &mp->rx_buf_dma,
					GFP_KERNEL);

	if (!mp->tx_ring || !mp->rx_ring || !mp->rx_buf) {
		mts_free_rings(mp);
		return -ENOMEM;
	}

	mp->tx_skb = kcalloc(MTS_RING_SIZE, sizeof(*mp->tx_skb), GFP_KERNEL);
	mp->tx_skb_dma = kcalloc(MTS_RING_SIZE, sizeof(*mp->tx_skb_dma), GFP_KERNEL);
	mp->tx_skb_len = kcalloc(MTS_RING_SIZE, sizeof(*mp->tx_skb_len), GFP_KERNEL);
	if (!mp->tx_skb || !mp->tx_skb_dma || !mp->tx_skb_len) {
		mts_free_rings(mp);
		return -ENOMEM;
	}

	dev_info(d, "aneis: TX va=%p dma=%pad | RX va=%p dma=%pad | bufs dma=%pad (%u KB)\n",
		 mp->tx_ring, &mp->tx_ring_dma, mp->rx_ring, &mp->rx_ring_dma,
		 &mp->rx_buf_dma, MTS_RX_BUF_TOTAL / 1024);
	return 0;
}

/*
 * Monta os descritores exatamente como fcn.dc5a31f0.
 *
 * Semantica do bit OWN (confirmada por dc5a2d00/dc5a5ae0): OWN==1 significa
 * "livre/pronto para o software agir" (ocioso ou concluido); OWN==0 significa
 * "em posse do hardware" (em transito). TX comeca ocioso, OWN=1, desc[2] |=
 * 0xffff0000. RX comeca em posse do hardware (OWN=0, aguardando pacote),
 * desc[1] = endereco fisico do buffer, WRAP no ultimo.
 */
static void mts_setup_rings(struct mts_priv *mp)
{
	u32 i;

	memset(mp->tx_ring, 0, MTS_RING_BYTES);
	for (i = 0; i < MTS_RING_SIZE; i++) {
		__le32 *d = mp->tx_ring + i * MTS_DESC_SIZE;

		d[0] = cpu_to_le32(MTS_DESC_OWN);
		d[2] = cpu_to_le32(le32_to_cpu(d[2]) | 0xffff0000);
	}

	memset(mp->rx_ring, 0, MTS_RING_BYTES);
	for (i = 0; i < MTS_RING_SIZE; i++) {
		__le32 *d = mp->rx_ring + i * MTS_DESC_SIZE;
		u32 ctl = MTS_DESC_OWN | MTS_RX_BUF_SIZE;

		if (i == MTS_RING_SIZE - 1)
			ctl |= MTS_DESC_WRAP;

		/* RX: inicializa com OWN=1 (buffer vazio, pronto para hardware) */
		d[0] = cpu_to_le32(ctl);
		d[1] = cpu_to_le32(mp->rx_buf_dma + i * MTS_RX_BUF_SIZE);
	}

	mp->tx_idx = 0;
	mp->tx_clean = 0;
	mp->rx_idx = 0;
	wmb();
}

/*
 * Programa os registradores de anel.
 *
 * 0x44/0x3c recebem o mesmo endereco (TX) e 0x48/0x40 o mesmo (RX): sao pares
 * base/ponteiro-corrente. Medicao ao vivo confirma — escritos iguais, leem
 * diferente, e o hardware avanca o de ponteiro sozinho.
 */
static void mts_program_rings(struct mts_priv *mp)
{
	mts_write(mp, MTS_TX_RING_BASE, lower_32_bits(mp->tx_ring_dma));
	mts_write(mp, MTS_TX_RING_PTR,  lower_32_bits(mp->tx_ring_dma));
	mts_write(mp, MTS_RX_RING_BASE, lower_32_bits(mp->rx_ring_dma));
	mts_write(mp, MTS_RX_RING_PTR,  lower_32_bits(mp->rx_ring_dma));

	dev_info(&mp->pdev->dev,
		 "aneis programados: TX base/ptr=0x%08x/0x%08x RX base/ptr=0x%08x/0x%08x\n",
		 mts_read(mp, MTS_TX_RING_BASE), mts_read(mp, MTS_TX_RING_PTR),
		 mts_read(mp, MTS_RX_RING_BASE), mts_read(mp, MTS_RX_RING_PTR));
}

/* ------------------------------------------------------------------ */
/* Glue region access (bpcie.glue @ 0xc8800000) para calibração PHY   */
/* ------------------------------------------------------------------ */

static inline u32 mts_glue_read(struct mts_priv *mp, u32 offset)
{
	if (!mp->regs_glue)
		return 0;
	return ioread32(mp->regs_glue + offset);
}

static inline void mts_glue_write(struct mts_priv *mp, u32 offset, u32 val)
{
	if (mp->regs_glue)
		iowrite32(val, mp->regs_glue + offset);
}

/* ------------------------------------------------------------------ */
/* PHY Calibration — tradução de fcn.ffffffffdc5a0ba0 (Orbis 12.52)   */
/* ------------------------------------------------------------------ */

static int mts_phy_wakeup(struct mts_priv *mp)
{
	u16 val;
	int ret;

	dev_info(&mp->pdev->dev, "PHY wakeup: tentando acordar PHY via Glue + MDIO...\n");

	/* FASE A: Pulso de liberação de Clock / Reset na região Pervasive do Glue (0x10a030) */
	u32 clk_pulse = mts_glue_read(mp, 0x10a030);
	dev_info(&mp->pdev->dev, "  Glue PERVASIVE_CLOCK_PULSE (0x10a030) antes: 0x%08x\n", clk_pulse);
	mts_glue_write(mp, 0x10a030, clk_pulse | 0x10);
	msleep(10);
	mts_glue_write(mp, 0x10a030, clk_pulse);
	dev_info(&mp->pdev->dev, "  Glue PERVASIVE_CLOCK_PULSE (0x10a030) depois: 0x%08x\n", mts_glue_read(mp, 0x10a030));

	/* FASE B: Varrer registradores de estado dos blocos na janela 0x140000 do Glue */
	dev_info(&mp->pdev->dev, "  Glue Janela 0x140000 (Power/Reset States):\n");
	for (u32 off = 0x140000; off <= 0x140020; off += 4) {
		dev_info(&mp->pdev->dev, "    Glue [0x%06x] = 0x%08x\n", off, mts_glue_read(mp, off));
	}

	/* FASE C: Varrer registradores da janela 0x180000 (Hold/Pulse de Periféricos Baikal) */
	dev_info(&mp->pdev->dev, "  Glue Janela 0x180000 (Peripheral Hold/Pulse):\n");
	dev_info(&mp->pdev->dev, "    SATA hold [0x18002c] = 0x%08x | pulse [0x18006c] = 0x%08x\n",
		 mts_glue_read(mp, 0x18002c), mts_glue_read(mp, 0x18006c));
	dev_info(&mp->pdev->dev, "    xHCI hold [0x180030] = 0x%08x | pulse [0x180070] = 0x%08x\n",
		 mts_glue_read(mp, 0x180030), mts_glue_read(mp, 0x180070));
	dev_info(&mp->pdev->dev, "    GBE  hold [0x180020] = 0x%08x | pulse [0x180074] = 0x%08x\n",
		 mts_glue_read(mp, 0x180020), mts_glue_read(mp, 0x180074));

	/* Testar pulso no controle da GBE (0x180074) */
	dev_info(&mp->pdev->dev, "  Enviando pulso de liberação de reset no Glue GBE pulse (0x180074)...\n");
	mts_glue_write(mp, 0x180074, 1);
	msleep(10);
	mts_glue_write(mp, 0x180074, 0);
	msleep(50);



	/* Ler status atual em devad=1, reg=0x0000 */
	ret = mts_mdio_read(mp, 1, 0x0000, &val);
	if (ret) {
		dev_err(&mp->pdev->dev, "  FALHA ao ler status inicial (ret=%d)\n", ret);
		return ret;
	}
	dev_info(&mp->pdev->dev, "  Status antes wakeup: 0x%04x\n", val);


	/* Tentar soft-reset (bit 15 em devad=1, reg=0x0000) */
	dev_info(&mp->pdev->dev, "  Enviando soft-reset ao PHY (devad=1, reg=0x0000, val=0x8000)...\n");
	mts_mdio_write(mp, 1, 0x0000, 0x8000);
	msleep(100);

	/* Desativar power-down/reset (limpar bits 15 e 11) */
	dev_info(&mp->pdev->dev, "  Limpando reset e power-down bits...\n");
	mts_mdio_write(mp, 1, 0x0000, 0x0000);
	msleep(500);

	/* Re-ler registrador de status para verificar se os dados mudaram */
	ret = mts_mdio_read(mp, 1, 0x0000, &val);
	dev_info(&mp->pdev->dev, "  Status depois wakeup (reg 0x0000): 0x%04x (ret=%d)\n", val, ret);

	u16 status1 = 0, id1 = 0, id2 = 0;
	mts_mdio_read(mp, 1, 0x0001, &status1);
	mts_mdio_read(mp, 1, 0x0002, &id1);
	mts_mdio_read(mp, 1, 0x0003, &id2);
	dev_info(&mp->pdev->dev, "  PHY Regs: Status1=0x%04x ID1=0x%04x ID2=0x%04x\n", status1, id1, id2);

	if (val != 0x0000 || id1 != 0x0000 || id2 != 0x0000) {
		dev_info(&mp->pdev->dev, "  ✅ PHY ACORDOU! (val=0x%04x ID=0x%04x:0x%04x)\n", val, id1, id2);
		return 0;
	} else {
		dev_warn(&mp->pdev->dev, "  ⚠️ PHY ainda retorna zeros (powered-down persiste)\n");
		return -ETIMEDOUT;
	}
}

static void mts_phy_calibration(struct mts_priv *mp)
{
	u16 dummy;
	u32 p0, p1, p2, p3, p4;
	u16 val16;
	u32 field;

	if (!enable_phy_calib) {
		dev_info(&mp->pdev->dev, "PHY calibration: desabilitada via module param\n");
		return;
	}

	if (mp->phy_calib_done) {
		dev_dbg(&mp->pdev->dev, "PHY calibration já executada\n");
		return;
	}

	dev_info(&mp->pdev->dev, "PHY calibration: iniciando...\n");

	/* Executar tentativa de wake-up do PHY */
	mts_phy_wakeup(mp);

	/* Diagnostic: Test MDIO Clause 45 vs Clause 22 (MII) */

	dev_info(&mp->pdev->dev, "MDIO diagnosis: testing Clause 45 vs Clause 22...\n");
	{
		u16 c45_val, c22_val;
		int ret_c45 = mts_mdio_read(mp, 0x01, 0x0000, &c45_val);
		int ret_c22 = mts_mdio_c22_read(mp, 0x00, 0x00, &c22_val);

		dev_info(&mp->pdev->dev, "  Clause 45: ret=%d val=0x%04x\n", ret_c45, ret_c45 ? 0xffff : c45_val);
		dev_info(&mp->pdev->dev, "  Clause 22: ret=%d val=0x%04x\n", ret_c22, ret_c22 ? 0xffff : c22_val);

		if (ret_c45 != 0 && ret_c22 == 0) {
			dev_info(&mp->pdev->dev, "  ✅ PHY responds to Clause 22 (MII), will use fallback\n");
		} else if (ret_c45 == 0 && ret_c22 != 0) {
			dev_info(&mp->pdev->dev, "  ✅ PHY responds to Clause 45, continuing normal path\n");
		} else if (ret_c45 == 0 && ret_c22 == 0) {
			dev_info(&mp->pdev->dev, "  ⚠️  Both Clause 45 and Clause 22 return data, PHY may work\n");
		} else {
			dev_warn(&mp->pdev->dev, "  ⚠️  PHY not responding to either Clause 45 or Clause 22!\n");
		}
	}

	/* ===== FASE 1: INIT ===== */
	/* BAR0[0x200] = 0 — desabilita I/O */
	mts_write(mp, 0x200, 0);

	/* BAR0[0x50] = BAR0[0x50] — read-modify-write para confirmar estado */
	mts_write(mp, 0x50, mts_read(mp, 0x50));

	/* ===== FASE 2: MDIO CLEAR ===== */
	/* MDIO read devad=2, reg=0x0000 */
	mts_mdio_read(mp, 2, 0x0000, &dummy);
	/* MDIO read devad=3, reg=0x0000 */
	mts_mdio_read(mp, 3, 0x0000, &dummy);

	/* ===== FASE 3: ENABLE PHY ===== */
	/* BAR0[0xac] = 9 — ativação do PHY */
	mts_write(mp, 0xac, 9);

	/* ===== FASE 4: CALIBRAÇÃO MDIO (loop complexo baseado em BAR2) ===== */
	/* Lê parâmetros de BAR2 (glue/pervasive) */
	p0 = mts_glue_read(mp, MTS_GLUE_CALIB_3);  /* 0x6c */
	p1 = mts_glue_read(mp, MTS_GLUE_CALIB_2);  /* 0x68 */
	p2 = mts_glue_read(mp, MTS_GLUE_CALIB_1);  /* 0x60 */
	p3 = mts_glue_read(mp, MTS_GLUE_CALIB_0);  /* 0x5c */
	p4 = mts_glue_read(mp, MTS_GLUE_CALIB_4);  /* 0x100 */


	dev_info(&mp->pdev->dev,
		 "PHY calibration: BAR2 params: 0x6c=0x%08x 0x68=0x%08x 0x60=0x%08x 0x5c=0x%08x 0x100=0x%08x\n",
		 p0, p1, p2, p3, p4);

	/* Grupo 1: baseado em 0x6c e 0x68 */
	if ((p0 & 0x80800000) == 0x80800000) {
		/* 0x201e devad=1 */
		field = (p1 & 0x3f) << 8;
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x201e, field);

		/* 0x211f devad=1 */
		field = (p1 >> 6) & 7;
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x211f, field);

		/* 0x161e, 0x171e, 0x181e, 0x191e devad=1 — com lookup table */
		/* O código original usa lookup table em -0x234f24c0; usamos fallback simples */
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x161e, 0x8001);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x171e, 0x0081);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x181e, 0x8001);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x191e, 0x0081);

		/* Segundo grupo com 0x207e, 0x217e, 0x267e, 0x277e, 0x291e, 0x2a1e */
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x207e, 0x8001);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x217e, 0x0081);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x267e, 0x8001);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x277e, 0x0081);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x291e, 0x8001);
		mts_mdio_write_packed(mp, (0x01 << 16) | 0x2a1e, 0x0081);

		/* Grupo baseado em 0x60 (p2) e 0x100 (p4) */
		/* 0x174001e, 0x175001e - usando endereços empacotados do Orbis */
		mts_mdio_write_packed(mp, 0x174001e, 0x8001);
		mts_mdio_write_packed(mp, 0x175001e, 0x8001);

		/* 0x172001e baseado em 0x5c e 0x60 */
		field = (p3 >> 12) & 0x3f00;
		mts_mdio_read_packed(mp, 0x172001e, &val16);
		val16 = (val16 & 0xffffc0ff) | field;
		mts_mdio_write_packed(mp, 0x172001e, val16);

		mts_mdio_read_packed(mp, 0x172001e, &val16);
		val16 = (val16 & 0xffffffc0) | ((p2 >> 7) & 0x3f);
		mts_mdio_write_packed(mp, 0x172001e, val16);

		/* 0x173001e baseado em 0x60 e 0x100 */
		field = (p2 >> 18) & 0x3f00;
		mts_mdio_read_packed(mp, 0x173001e, &val16);
		val16 = (val16 & 0xffffc0ff) | field;
		mts_mdio_write_packed(mp, 0x173001e, val16);

		mts_mdio_read_packed(mp, 0x173001e, &val16);
		val16 = (val16 & 0xffffffc0) | ((p4 >> 13) & 0x3f);
		mts_mdio_write_packed(mp, 0x173001e, val16);

		/* Registradores 0x12001e, 0x16001e, 0x17001e, 0x18001e, 0x19001e, 0x20001e, 0x21001e, 0x22001e */
		field = (p3 >> 26) * 0x401;
		mts_mdio_write_packed(mp, 0x12001e, field);

		field = (p3 >> 26) < 0x3c ? ((p3 >> 26) * 0x400 + 0xc00) : 0xfc00;
		mts_mdio_write_packed(mp, 0x16001e, field | (p3 >> 26));

		field = (p2 >> 13) & 0x3f;
		mts_mdio_write_packed(mp, 0x17001e, field * 0x101);

		field = ((p2 >> 13) & 0x3f) < 0x3c ? (((p2 >> 13) & 0x3f) + 3) << 8 | field : (0x3c + 3) << 8 | field;
		mts_mdio_write_packed(mp, 0x18001e, field);

		field = p4 & 0x3f;
		mts_mdio_write_packed(mp, 0x19001e, field * 0x101);

		field = (p4 & 0x3f) < 0x3c ? ((p4 & 0x3f) + 3) << 8 | (p4 & 0x3f) : (0x3c + 3) << 8 | (p4 & 0x3f);
		mts_mdio_write_packed(mp, 0x20001e, field);

		field = (p4 >> 19) & 0x3f;
		mts_mdio_write_packed(mp, 0x21001e, field * 0x101);

		field = ((p4 >> 19) & 0x3f) < 0x3c ? (((p4 >> 19) & 0x3f) + 3) << 8 | field : (0x3c + 3) << 8 | field;
		mts_mdio_write_packed(mp, 0x22001e, field);

		/* Registradores fixos */
		mts_mdio_write_packed(mp, 0x96001e, 0x8000);
		mts_mdio_write_packed(mp, 0x37001e, 0x33);

		/* 0x39001e */
		mts_mdio_read_packed(mp, 0x39001e, &val16);
		val16 &= 0xb7ff;
		mts_mdio_write_packed(mp, 0x39001e, val16);

		/* 0x107001f */
		mts_mdio_read_packed(mp, 0x107001f, &val16);
		val16 &= 0xefff;
		mts_mdio_write_packed(mp, 0x107001f, val16);

		/* 0x171001e */
		mts_mdio_read_packed(mp, 0x171001e, &val16);
		val16 |= 0x180;
		mts_mdio_write_packed(mp, 0x171001e, val16);

		/* 0x39001e | 0x2000 */
		mts_mdio_read_packed(mp, 0x39001e, &val16);
		val16 |= 0x2000;
		mts_mdio_write_packed(mp, 0x39001e, val16);

		/* delay */
		mdelay(50);

		/* 0x39001e & 0xdfff */
		mts_mdio_read_packed(mp, 0x39001e, &val16);
		val16 &= 0xdfff;
		mts_mdio_write_packed(mp, 0x39001e, val16);

		/* 0x171001e & 0xfe7f */
		mts_mdio_read_packed(mp, 0x171001e, &val16);
		val16 &= 0xfe7f;
		mts_mdio_write_packed(mp, 0x171001e, val16);
	} /* fim do if (p0 & 0x80800000) */

	/* ===== CÓDIGO QUE SEMPRE RODA (após if-block, dc5a0ba0 linhas 196-528) ===== */

	/* Lê BAR0[0x04] para preservar bits não-mascarados */
	u32 link_save = mts_read(mp, MTS_LINK_STATUS);

	/* MDIO write 0x189001e = 0x110 (devad=0x01, reg=0x001e) */
	mts_mdio_write_packed(mp, 0x189001e, 0x110);

	/* Page ops sequence 1 */
	mts_mdio_page_read(mp, 0x1f, &val16);
	u16 saved_page1 = val16;
	mts_mdio_page_write(mp, 0x1f, 0x52b5);
	mts_mdio_page_write(mp, 0x11, 0xb90a);
	mts_mdio_page_write(mp, 0x12, 0x6f);
	mts_mdio_page_write(mp, 0x10, 0x8f82);
	mts_mdio_page_write(mp, 0x1f, saved_page1);

	/* Page ops sequence 2 */
	mts_mdio_page_read(mp, 0x1f, &val16);
	u16 saved_page2 = val16;
	mts_mdio_page_write(mp, 0x1f, 0x52b5);
	mts_mdio_page_write(mp, 0x11, 0xbaef);
	mts_mdio_page_write(mp, 0x12, 0x2e);
	mts_mdio_page_write(mp, 0x10, 0x968c);
	mts_mdio_page_write(mp, 0x1f, saved_page2);

	/* Page ops sequence 3 */
	mts_mdio_page_write(mp, 0x1f, 3);
	mts_mdio_page_write(mp, 0x1c, 0xc92);
	mts_mdio_page_write(mp, 0x1f, 0);

	/* BAR0[0x7c] = 25000000 */
	mts_write(mp, 0x7c, 25000000);

	/* MDIO write 0x122001e = 0xffff (devad=0x01, reg=0x001e) */
	mts_mdio_write_packed(mp, 0x122001e, 0xffff);

	/* Page ops sequence 4 */
	mts_mdio_page_read(mp, 0x1f, &val16);
	u16 saved_page3 = val16;
	mts_mdio_page_write(mp, 0x1f, 0x52b5);
	mts_mdio_page_write(mp, 0x11, 0x704d);
	mts_mdio_page_write(mp, 0x12, 0);
	mts_mdio_page_write(mp, 0x10, 0x9698);
	mts_mdio_page_write(mp, 0x1f, saved_page3);

	/* Page ops sequence 5 */
	mts_mdio_page_read(mp, 0x1f, &val16);
	u16 saved_page4 = val16;
	mts_mdio_page_write(mp, 0x1f, 0x52b5);
	mts_mdio_page_write(mp, 0x11, 0x344f);
	mts_mdio_page_write(mp, 0x12, 2);
	mts_mdio_page_write(mp, 0x10, 0x969a);
	mts_mdio_page_write(mp, 0x1f, saved_page4);

	/* MDIO write 0x268001f = 0x7f4 */
	mts_mdio_write_packed(mp, 0x268001f, 0x7f4);

	/* Page ops sequence 6 */
	mts_mdio_page_read(mp, 0x1f, &val16);
	u16 saved_page5 = val16;
	mts_mdio_page_write(mp, 0x1f, 0x52b5);
	mts_mdio_page_write(mp, 0x11, 4);
	mts_mdio_page_write(mp, 0x12, 0);
	mts_mdio_page_write(mp, 0x10, 0x9686);
	mts_mdio_page_write(mp, 0x1f, saved_page5);

	/* Page ops sequence 7 */
	mts_mdio_page_read(mp, 0x1f, &val16);
	u16 saved_page6 = val16;
	mts_mdio_page_write(mp, 0x1f, 0x52b5);
	mts_mdio_page_write(mp, 0x11, 0x671);
	mts_mdio_page_write(mp, 0x12, 6);
	mts_mdio_page_write(mp, 0x10, 0x8fae);
	mts_mdio_page_write(mp, 0x1f, saved_page6);

	/* Page 4 read-modify-write */
	mts_mdio_page_read(mp, 4, &val16);
	mts_mdio_page_write(mp, 4, val16 & 0xf3ff);

	/* BAR0[0x04] = (preserved & 0x7fffcfff) | 0x61 — ativa Full-Duplex (0x60) e Link UP (0x01) */
	dev_info(&mp->pdev->dev, "pre  0x04=0x%08x\n", mts_read(mp, MTS_LINK_STATUS));
	mts_write(mp, MTS_LINK_STATUS, (link_save & 0x7fffcfff) | 0x61);
	dev_info(&mp->pdev->dev, "post 0x04=0x%08x\n", mts_read(mp, MTS_LINK_STATUS));


	/* BAR0[0x78] &= ~1 */
	dev_info(&mp->pdev->dev, "pre  0x78=0x%08x\n", mts_read(mp, 0x78));
	mts_clear(mp, 0x78, 1);
	dev_info(&mp->pdev->dev, "post 0x78=0x%08x\n", mts_read(mp, 0x78));

	/* MDIO write 0x3c0007 = 0 */
	mts_mdio_write_packed(mp, 0x3c0007, 0);

	/* MDIO read-modify-write 0x33001e */
	mts_mdio_read_packed(mp, 0x33001e, &val16);
	dev_info(&mp->pdev->dev, "pre  MDIO 0x33001e=0x%04x\n", val16);
	mts_mdio_write_packed(mp, 0x33001e, val16 & 0xefff);

	/* Page 0 read-modify-write */
	mts_mdio_page_read(mp, 0, &val16);
	dev_info(&mp->pdev->dev, "pre  Page 0=0x%04x\n", val16);
	mts_mdio_page_write(mp, 0, val16 | 0x1200);

	/* MAC address para BAR0[0x14]/[0x18] */
	u32 mac_low = mp->dev->dev_addr[0] |
		      (mp->dev->dev_addr[1] << 8) |
		      (mp->dev->dev_addr[2] << 16) |
		      (mp->dev->dev_addr[3] << 24);
	u32 mac_high = mp->dev->dev_addr[4] |
		      (mp->dev->dev_addr[5] << 8);
	mts_write(mp, 0x14, mac_low);
	mts_write(mp, 0x18, mac_high);

	/* BAR0[0x0c] &= ~0x80 */
	dev_info(&mp->pdev->dev, "pre  0x0c=0x%08x\n", mts_read(mp, 0x0c));
	mts_clear(mp, 0x0c, 0x80);
	dev_info(&mp->pdev->dev, "post 0x0c=0x%08x\n", mts_read(mp, 0x0c));

	/* BAR0[0x74] = 0x2277 — já feito em mts_mac_enable, redundante seguro */
	mts_write(mp, 0x74, 0x2277);

	/* BAR0[0x08] |= 0x7597c00 — enable MAC features */
	dev_info(&mp->pdev->dev, "pre  0x08=0x%08x\n", mts_read(mp, 0x08));
	mts_set(mp, 0x08, 0x7597c00);
	dev_info(&mp->pdev->dev, "post 0x08=0x%08x\n", mts_read(mp, 0x08));

	/* BAR0[0x1d4] = 1 */
	dev_info(&mp->pdev->dev, "pre  0x1d4=0x%08x\n", mts_read(mp, 0x1d4));
	mts_write(mp, 0x1d4, 1);
	dev_info(&mp->pdev->dev, "post 0x1d4=0x%08x\n", mts_read(mp, 0x1d4));

	/* BAR0[0x10] = (val & 0xffffff6e) | 0x81 */
	u32 reg10 = mts_read(mp, 0x10);
	dev_info(&mp->pdev->dev, "pre  0x10=0x%08x\n", reg10);
	reg10 = (reg10 & 0xffffff6e) | 0x81;
	mts_write(mp, 0x10, reg10);
	dev_info(&mp->pdev->dev, "post 0x10=0x%08x\n", mts_read(mp, 0x10));

	/* BAR0[0x30] = 0x10100 — já feito */
	mts_write(mp, 0x30, 0x10100);

	/* ===== Calibration loop via 0x1bc-0x1d4 (dc5a0ba0 linhas 382-506) ===== */

	if (enable_phy_calib_table) {
		dev_info(&mp->pdev->dev, "PHY calibration table: executando loop indexado 0x1bc-0x1d4...\n");
		u32 calib_tbl[128];
		u32 calib_msk[128];
		int ci;

		memset(calib_tbl, 0, sizeof(calib_tbl));
		memset(calib_msk, 0, sizeof(calib_msk));


		/* Indices baseados no MAC (como no Orbis: 0x22 para single MAC, 0x26 para dual) */
		ci = 0x22; /* offset fixo, como decompilado */

		calib_tbl[ci + 2] = 0x6721;              /* 0x22+2=0x24 */
		calib_msk[ci + 2] = 0xffff;

		calib_tbl[ci | 9] = 0x003;                /* 0x2b: 3 bytes via memcpy */
		calib_msk[ci | 9] = 0xffff;

		calib_tbl[ci | 8] = 0x80004000;           /* high word de 0x8000400000000034 */
		calib_tbl[ci | 8 | 1] = 0x00000034;      /* low word */

		ci = ((ci | 8) + 0xe) | 2;                  /* offset ~0x36 */
		calib_tbl[ci] = 0x18000000;               /* high word */
		calib_tbl[ci + 1] = 0x40;                 /* low word */
		calib_msk[ci] = 0xffffffff;
		calib_msk[ci + 1] = 0xffff;

		/* Valores MAC inseridos em posições específicas (cada 6 bytes) */
		calib_tbl[ci + 6] = mac_low;
		calib_tbl[ci + 7] = mac_high >> 16;       /* bits altos na posição correta */

		/* DMA tagging — 0x142 como valor fixo (decompilado dc73ce90 check) */
		mts_write(mp, 0x1c4, 1);

		u32 loop_count = 0x22 + 0x20;             /* 0x42 iterações */
		u32 max_entries = ARRAY_SIZE(calib_tbl);
		if (loop_count > max_entries)
			loop_count = max_entries;

		mts_write(mp, 0x1c8, (loop_count * 0x100) | loop_count | mts_read(mp, 0x1c8));

		/* Loop principal de calibração */
		for (u32 ci2 = 0; ci2 < loop_count; ci2++) {
			u32 calib_val = 0;
			if (ci2 < ARRAY_SIZE(calib_tbl))
				calib_val = (calib_tbl[ci2] & 0xffff) |
					    ((calib_tbl[ci2] >> 16) & 0xffff0000);

			mts_write(mp, 0x1bc, calib_val);
			mts_write(mp, 0x1c4, 0);
			mts_write(mp, 0x1c0, ci2);
			mts_write(mp, 0x1c4, 1);
			mts_write(mp, 0x1c0, ci2 | 0x80);

			int timeout = 1000;
			while (timeout--) {
				if (mts_read(mp, 0x1d0) & 1)
					break;
				udelay(1);
			}
			if (!timeout)
				dev_dbg(&mp->pdev->dev, "calib[%u] timeout\n", ci2);
		}

		mts_write(mp, 0x1c4, 3);
		mts_set(mp, 0x1c8, 0xc0000000);

		dev_info(&mp->pdev->dev, "PHY calibration: loop %u iteracoes concluido\n", loop_count);
	} else {
		dev_info(&mp->pdev->dev, "PHY calibration table (0x1bc-0x1d4): desabilitada via module param (default)\n");
	}

	mp->phy_calib_done = true;

	dev_info(&mp->pdev->dev, "PHY calibration: concluída\n");
}

/* ------------------------------------------------------------------ */
/* Enable / stop do MAC                                                */
/* ------------------------------------------------------------------ */

/* fcn.dc5a3060 (stop) mexe nos mesmos 0x34/0x38/0x54 */
static void mts_mac_stop(struct mts_priv *mp)
{
	mts_write(mp, MTS_IMR, 0);
	mts_clear(mp, MTS_MAC_EN1, MTS_MAC_ENABLE);
	mts_clear(mp, MTS_MAC_EN2, MTS_MAC_ENABLE);
}

static void mts_mac_enable(struct mts_priv *mp)
{
	u32 a34, a38;

	mts_set(mp, MTS_MAC_EN1, MTS_MAC_ENABLE);
	mts_set(mp, MTS_MAC_EN2, MTS_MAC_ENABLE);

	a34 = mts_read(mp, MTS_MAC_EN1);
	a38 = mts_read(mp, MTS_MAC_EN2);

	/*
	 * Confirmado ao vivo: 0x34 nao retem o valor escrito (le 0) mas produz
	 * efeito; o estado aparece em 0x38 (escrito 1, le 8) e em 0x50/0x70.
	 * Nao tratar "0x34 == 0" como falha.
	 */
	dev_info(&mp->pdev->dev, "MAC enable: 0x34=0x%08x 0x38=0x%08x 0x50=0x%08x 0x70=0x%08x\n",
		 a34, a38, mts_read(mp, 0x50), mts_read(mp, 0x70));

	/* PHY Calibration (Orbis dc5a0ba0) — necessária para carrier detection */
	mts_phy_calibration(mp);

	/* Bisecção: confirma se a calibração altera o estado de EN1/EN2/0x50/0x70
	 * observado logo acima, antes de qualquer calibração rodar. */
	dev_info(&mp->pdev->dev,
		 "MAC enable (pos-calib): 0x34=0x%08x 0x38=0x%08x 0x50=0x%08x 0x70=0x%08x\n",
		 mts_read(mp, MTS_MAC_EN1), mts_read(mp, MTS_MAC_EN2),
		 mts_read(mp, 0x50), mts_read(mp, 0x70));
}

/* ------------------------------------------------------------------ */
/* Carrier / Link detection                                           */
/* ------------------------------------------------------------------ */

static void mts_link_check(struct mts_priv *mp)
{
	u32 val = mts_read(mp, MTS_LINK_STATUS);

	if (val == mp->link_last_raw)
		return;

	mp->link_last_raw = val;

	bool up = val & MTS_LINK_UP;
	unsigned int speed = 0;
	unsigned int duplex = 0;

	if (up) {
		switch (val & MTS_LINK_SPEED_MASK) {
		case MTS_LINK_SPEED_10:
			speed = SPEED_10;
			break;
		case MTS_LINK_SPEED_100:
			speed = SPEED_100;
			break;
		case MTS_LINK_SPEED_1000:
			speed = SPEED_1000;
			break;
		}
		duplex = (val & MTS_LINK_DUPLEX_FULL) ? DUPLEX_FULL : DUPLEX_HALF;
	}

	if (force_carrier) {
		if (!mp->link_up) {
			mp->link_up = true;
			dev_info(&mp->pdev->dev, "Link FORÇADO UP via module param force_carrier=1!\n");
			netif_carrier_on(mp->dev);
		}
	} else if (up != mp->link_up) {
		mp->link_up = up;
		if (up) {
			dev_info(&mp->pdev->dev, "Link UP: %u Mbps %s duplex\n",
				 speed, duplex == DUPLEX_FULL ? "Full" : "Half");
			netif_carrier_on(mp->dev);
		} else {
			dev_info(&mp->pdev->dev, "Link DOWN (val=0x%08x)\n", val);
			netif_carrier_off(mp->dev);
		}
	} else if (up && (speed != mp->link_speed || duplex != mp->link_duplex)) {
		dev_info(&mp->pdev->dev, "Link change: %u Mbps %s duplex\n",
			 speed, duplex == DUPLEX_FULL ? "Full" : "Half");
	}

	mp->link_speed = speed;
	mp->link_duplex = duplex;
}

/* ------------------------------------------------------------------ */
/* TX reclamation (completion)                                        */
/* ------------------------------------------------------------------ */

static void mts_tx_reclaim(struct mts_priv *mp)
{
	struct net_device *dev = mp->dev;
	u32 clean = mp->tx_clean;

	while (clean != mp->tx_idx) {
		__le32 *d = mp->tx_ring + clean * MTS_DESC_SIZE;
		u32 ctl = le32_to_cpu(d[0]);

		/* OWN==1: descritor ainda em posse do driver (não processado pelo hardware) */
		if (ctl & MTS_DESC_OWN)
			break;

		/* OWN==0: hardware completou a transmissão — libera o skb */
		if (mp->tx_skb[clean]) {
			struct sk_buff *skb = mp->tx_skb[clean];

			dev->stats.tx_packets++;
			dev->stats.tx_bytes += skb->len;

			dma_unmap_single(&mp->pdev->dev, mp->tx_skb_dma[clean],
					 skb->len, DMA_TO_DEVICE);
			dev_consume_skb_any(skb);
			mp->tx_skb[clean] = NULL;
		}

		/* Restaura o padrão ocioso (OWN=1) para reutilização */
		d[0] = cpu_to_le32(MTS_DESC_OWN);
		d[2] = cpu_to_le32(0xffff0000);

		clean = (clean + 1) & (MTS_RING_SIZE - 1);
	}

	if (clean != mp->tx_clean) {
		mp->tx_clean = clean;
		smp_mb();
		if (netif_queue_stopped(dev))
			netif_wake_queue(dev);
	}
}

static void mts_tx_drain_force(struct mts_priv *mp)
{
	u32 i;

	for (i = 0; i < MTS_RING_SIZE; i++) {
		if (mp->tx_skb[i]) {
			struct sk_buff *skb = mp->tx_skb[i];

			dma_unmap_single(&mp->pdev->dev, mp->tx_skb_dma[i],
					 skb->len, DMA_TO_DEVICE);
			dev_kfree_skb_any(skb);
			mp->tx_skb[i] = NULL;
		}
	}
	mp->tx_idx = 0;
	mp->tx_clean = 0;
}

/* ------------------------------------------------------------------ */
/* RX path                                                            */
/* ------------------------------------------------------------------ */

static int mts_rx_clean(struct mts_priv *mp, int budget)
{
	struct net_device *dev = mp->dev;
	int cleaned = 0;

	while (cleaned < budget) {
		__le32 *d = mp->rx_ring + mp->rx_idx * MTS_DESC_SIZE;
		u32 ctl = le32_to_cpu(d[0]);

		/* DEBUG: log condicional (apenas primeiros 10 OU a cada 1000 chamadas de poll) */
		if (mp->rx_debug_logs < 10 || (mp->rx_debug_logs % 1000) == 0) {
			dev_info(&mp->pdev->dev,
				"RX_CLEAN idx=%u ctl=0x%08x OWN=%d len=%u cleaned=%u\n",
				mp->rx_idx, ctl,
				(ctl & MTS_DESC_OWN) ? 1 : 0,
				ctl & MTS_DESC_LEN_MASK, mp->rx_debug_logs);
		}
		mp->rx_debug_logs++;

		/* OWN==0 = hardware preencheu (pacote pronto); OWN==1 = buffer vazio (driver) */
		if (ctl & MTS_DESC_OWN)
			break; /* buffer vazio — nada novo */

		/* Hardware devolveu o buffer — processa o pacote */
		u32 len = ctl & MTS_DESC_LEN_MASK;

		if (len > 0 && len <= MTS_RX_BUF_SIZE) {
			struct sk_buff *skb = napi_alloc_skb(&mp->napi, len + 2);
			if (likely(skb)) {
				skb_reserve(skb, 2); /* alinhamento IP header */
				memcpy(skb_put(skb, len),
				       mp->rx_buf + mp->rx_idx * MTS_RX_BUF_SIZE, len);
				skb->protocol = eth_type_trans(skb, dev);
				napi_gro_receive(&mp->napi, skb);
				dev->stats.rx_packets++;
				dev->stats.rx_bytes += len;
			} else {
				dev->stats.rx_dropped++;
			}
		} else {
			dev->stats.rx_errors++;
		}

		/* devolve descritor ao hardware: seta OWN (1), mantem WRAP se for o ultimo */
		u32 new_ctl = MTS_DESC_OWN | MTS_RX_BUF_SIZE; /* OWN=1 = buffer vazio para hardware */
		if (mp->rx_idx == MTS_RING_SIZE - 1)
			new_ctl |= MTS_DESC_WRAP;
		d[0] = cpu_to_le32(new_ctl);

		mp->rx_idx = (mp->rx_idx + 1) & (MTS_RING_SIZE - 1);
		cleaned++;
	}

	wmb();
	/* avisa o hardware: novos buffers vazios prontos (tail pointer = índice) */
	if (cleaned > 0)
		mts_write(mp, MTS_RX_RING_PTR, mp->rx_idx);
	return cleaned;
}

/* ------------------------------------------------------------------ */
/* NAPI poll                                                          */
/* ------------------------------------------------------------------ */

static int mts_poll(struct napi_struct *napi, int budget)
{
	struct mts_priv *mp = container_of(napi, struct mts_priv, napi);
	int rx_done = 0;

	if (mp->enable_tx)
		mts_tx_reclaim(mp);

	if (mp->enable_rx)
		rx_done = mts_rx_clean(mp, budget);

	if (mp->enable_carrier)
		mts_link_check(mp);

	if (rx_done < budget) {
		napi_complete_done(napi, rx_done);
		return rx_done;
	}
	return budget;
}

/* ------------------------------------------------------------------ */
/* Timer de polling por software                                      */
/* ------------------------------------------------------------------ */

static void mts_poll_timer(struct timer_list *t)
{
	struct mts_priv *mp = timer_container_of(mp, t, poll_timer);

	if (mp->napi_enabled && (mp->enable_rx || mp->enable_tx || mp->enable_carrier))
		napi_schedule(&mp->napi);

	mod_timer(&mp->poll_timer, jiffies + msecs_to_jiffies(mp->poll_interval_ms));
}

/* ------------------------------------------------------------------ */
/* TX path                                                            */
/* ------------------------------------------------------------------ */

static netdev_tx_t mts_start_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct mts_priv *mp = netdev_priv(dev);
	u32 idx = mp->tx_idx;
	__le32 *d = mp->tx_ring + idx * MTS_DESC_SIZE;
	u32 ctl = le32_to_cpu(d[0]);

	if (!mp->enable_tx) {
		dev->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	/* OWN==1 = livre para o driver preencher; OWN==0 = em posse do hardware */
	if (!(ctl & MTS_DESC_OWN)) {
		/* descritor ocupado pelo hardware — para a fila e avisa o kernel */
		netif_stop_queue(dev);
		return NETDEV_TX_BUSY;
	}

	/* mapeia o skb para DMA */
	dma_addr_t dma = dma_map_single(&mp->pdev->dev, skb->data, skb->len,
					DMA_TO_DEVICE);
	if (dma_mapping_error(&mp->pdev->dev, dma)) {
		dev->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	mp->tx_skb[idx] = skb;
	mp->tx_skb_dma[idx] = dma;
	mp->tx_skb_len[idx] = skb->len;

	/* monta descritor: endereco em d[1], ctl com SOP|EOP|len|WRAP */
	d[1] = cpu_to_le32(lower_32_bits(dma));
	d[2] = cpu_to_le32(0xffff0000);

	u32 new_ctl = skb->len | MTS_DESC_SOP | MTS_DESC_EOP;
	if (idx == MTS_RING_SIZE - 1)
		new_ctl |= MTS_DESC_WRAP;

	/* wmb antes de entregar ao hardware (limpa OWN -> 0) */
	wmb();
	d[0] = cpu_to_le32(new_ctl);

	mp->tx_idx = (idx + 1) & (MTS_RING_SIZE - 1);

	/* avisa o hardware: novo descritor pronto (tail pointer = apenas o índice) */
	mts_write(mp, MTS_TX_RING_PTR, mp->tx_idx);

	/* tenta reclamar TX completos de forma oportunista */
	mts_tx_reclaim(mp);

	/* se o proximo descritor nao estiver livre (OWN==0), para a fila */
	d = mp->tx_ring + mp->tx_idx * MTS_DESC_SIZE;
	if (!(le32_to_cpu(d[0]) & MTS_DESC_OWN))
		netif_stop_queue(dev);

	return NETDEV_TX_OK;
}

/* ------------------------------------------------------------------ */
/* TX timeout handler                                                 */
/* ------------------------------------------------------------------ */

static void mts_tx_timeout(struct net_device *dev, unsigned int txqueue)
{
	struct mts_priv *mp = netdev_priv(dev);

	dev_warn(&mp->pdev->dev, "TX timeout — drenando fila\n");
	mts_tx_drain_force(mp);
	netif_wake_queue(dev);
}

/* ------------------------------------------------------------------ */
/* Diagnostico                                                         */
/* ------------------------------------------------------------------ */

static void mts_dump_regs(struct mts_priv *mp)
{
	static const u32 interessantes[] = {
		0x00, 0x04, 0x08, 0x0c, 0x10, 0x14, 0x18, 0x1c, 0x2c, 0x30,
		0x34, 0x38, 0x3c, 0x40, 0x44, 0x48, 0x50, 0x54, 0x5c,
		0x64, 0x70, 0x74, 0x7c, 0x80, 0x98, 0x9c, 0xac, 0xb0, 0xb4,
	};
	int i;

	dev_info(&mp->pdev->dev, "--- dump da BAR0 (offsets com conteudo conhecido) ---\n");
	for (i = 0; i < ARRAY_SIZE(interessantes); i++)
		dev_info(&mp->pdev->dev, "  +0x%03x = 0x%08x\n",
			 interessantes[i], mts_read(mp, interessantes[i]));

	dev_info(&mp->pdev->dev, "  clock (0x7c) = %u Hz %s\n",
		 mts_read(mp, MTS_CLOCK),
		 mts_read(mp, MTS_CLOCK) == MTS_CLOCK_25MHZ ? "(25 MHz, esperado)" : "(INESPERADO)");

	/* contadores sao clear-on-read: ler ja zera */
	dev_info(&mp->pdev->dev, "  contadores: pkts=%u bytes=%u | pkts2=%u bytes2=%u\n",
		 mts_read(mp, MTS_CNT_PKTS), mts_read(mp, MTS_CNT_BYTES),
		 mts_read(mp, MTS_CNT_PKTS2), mts_read(mp, MTS_CNT_BYTES2));
}

/* ------------------------------------------------------------------ */
/* Diagnostico sysfs (mts_regs) — leitura ao vivo de registradores,    */
/* aneis e buffers RX. Exposto em /sys/bus/pci/devices/0000:00:14.1/   */
/* mts_regs e acessivel via /sys/class/net/eth0/device/mts_regs.       */
/* ------------------------------------------------------------------ */

static ssize_t mts_regs_show(struct device *dev,
			     struct device_attribute *attr, char *buf)
{
	struct net_device *netdev = dev_get_drvdata(dev);
	struct mts_priv *mp;
	int len = 0;
	int i;
	u16 phy_val;
	int ret;

	if (!netdev)
		return -ENODEV;
	mp = netdev_priv(netdev);
	if (!mp || !mp->regs)
		return -ENODEV;

	static const u32 regs_key[] = {
		0x00, 0x04, 0x34, 0x38, 0x50, 0x54, 0x5c, 0x70, 0x7c
	};

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "=== BAR0 Registradores-chave ===\n");
	for (i = 0; i < ARRAY_SIZE(regs_key); i++)
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  +0x%03x = 0x%08x\n",
				 regs_key[i], mts_read(mp, regs_key[i]));

	/* Labels claros para 0x34/0x38 (escrito=1, lido=0/8) */
	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n  Labels: 0x34=MAC_EN1 (wo)  0x38=MAC_EN2 (ro=8 when enabled)\n");

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== PHY Clause 45 (live, MMD=1 PMA/PMD + MMD=7 AN) ===\n");

	/* Helper: try read PHY reg, return "timeout" or formatted value */
	#define MTS_PHY_READ(devad, reg, label) \
		do { \
			ret = mts_mdio_read(mp, devad, reg, &phy_val); \
			if (ret) \
				len += scnprintf(buf + len, PAGE_SIZE - len, "  %s: timeout\n", label); \
			else \
				len += scnprintf(buf + len, PAGE_SIZE - len, "  %s: 0x%04x\n", label, phy_val); \
		} while (0)

	MTS_PHY_READ(0x01, 0x0000, "PMA/PMD Control1  (devad=0x01, reg=0x0000)");
	MTS_PHY_READ(0x01, 0x0001, "PMA/PMD Status1   (devad=0x01, reg=0x0001)");
	MTS_PHY_READ(0x01, 0x0002, "PMA/PMD ID1       (devad=0x01, reg=0x0002)");
	MTS_PHY_READ(0x01, 0x0003, "PMA/PMD ID2       (devad=0x01, reg=0x0003)");

	/* AN Status (devad=7, reg=0x0001) - bit2=link, bit5=AN complete */
	ret = mts_mdio_read(mp, 0x07, 0x0001, &phy_val);
	if (ret)
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  AN Status         (devad=0x07, reg=0x0001): timeout\n");
	else
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  AN Status         (devad=0x07, reg=0x0001): 0x%04x (link=%d AN_complete=%d)\n",
				 phy_val, (phy_val & 0x0004) ? 1 : 0, (phy_val & 0x0020) ? 1 : 0);

	/* 1000BASE-T AN Status (devad=7, reg=0x000a) - best effort */
	ret = mts_mdio_read(mp, 0x07, 0x000a, &phy_val);
	if (ret)
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  1000BASE-T AN St  (devad=0x07, reg=0x000a): timeout/N/A\n");
	else
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  1000BASE-T AN St  (devad=0x07, reg=0x000a): 0x%04x\n", phy_val);

	#undef MTS_PHY_READ

	/* BMCR (Clause 22, phy_addr=0x00, reg=0x00) — mesmo endereco usado no
	 * diagnostico de wakeup (mts_mdio_probe); tentativa de re-leitura
	 * pos-link, ja que Clause 45 nao deu sinal algum do PHY. */
	ret = mts_mdio_c22_read(mp, 0x00, 0x00, &phy_val);
	if (ret)
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  BMCR (C22 phy=0x00, reg=0x00): timeout (ret=%d)\n", ret);
	else
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  BMCR (C22 phy=0x00, reg=0x00): 0x%04x (reset=%d powerdown=%d duplex=%d)\n",
				 phy_val, (phy_val & 0x8000) ? 1 : 0,
				 (phy_val & 0x0800) ? 1 : 0, (phy_val & 0x0100) ? 1 : 0);

	/* Scan Clause 22 phy_addr 0-31 for BMCR (reg=0x00) */
	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== PHY Clause 22 BMCR scan (phy_addr 0-31) ===\n");
	for (i = 0; i < 32; i++) {
		ret = mts_mdio_c22_read(mp, i, 0x00, &phy_val);
		if (ret == 0 && phy_val != 0x0000 && phy_val != 0xffff) {
			len += scnprintf(buf + len, PAGE_SIZE - len,
					 "  phy_addr=%02d: 0x%04x (reset=%d powerdown=%d duplex=%d speed_msb=%d)\n",
					 i, phy_val,
					 (phy_val & 0x8000) ? 1 : 0,
					 (phy_val & 0x0800) ? 1 : 0,
					 (phy_val & 0x0100) ? 1 : 0,
					 (phy_val & 0x2000) ? 1 : 0);
		} else if (ret == 0) {
			len += scnprintf(buf + len, PAGE_SIZE - len,
					 "  phy_addr=%02d: 0x%04x (ret=0, likely residual)\n", i, phy_val);
		} else {
			len += scnprintf(buf + len, PAGE_SIZE - len,
					 "  phy_addr=%02d: timeout (ret=%d)\n", i, ret);
		}
	}

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== Contadores HW (clear-on-read) ===\n");
	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "  MTS_CNT_PKTS  (0x100) = %u\n",
			 mts_read(mp, MTS_CNT_PKTS));
	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "  MTS_CNT_BYTES (0x104) = %u\n",
			 mts_read(mp, MTS_CNT_BYTES));
	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "  MTS_CNT_PKTS2 (0x128) = %u\n",
			 mts_read(mp, MTS_CNT_PKTS2));
	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "  MTS_CNT_BYTES2(0x12c) = %u\n",
			 mts_read(mp, MTS_CNT_BYTES2));

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== Estado dos aneis (SW) ===\n");
	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "  tx_idx=%u  tx_clean=%u  rx_idx=%u  irq_count=%lu\n",
			 mp->tx_idx, mp->tx_clean, mp->rx_idx, mp->irq_count);

	if (!mp->tx_ring || !mp->rx_ring)
		return len;

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== Descritores TX (0-3) ===\n");
	for (i = 0; i < 4 && i < MTS_RING_SIZE; i++) {
		__le32 *d = mp->tx_ring + i * MTS_DESC_SIZE;
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  TX[%03u] ctl=0x%08x addr=0x%08x d2=0x%08x d3=0x%08x\n",
				 i, le32_to_cpu(d[0]), le32_to_cpu(d[1]),
				 le32_to_cpu(d[2]), le32_to_cpu(d[3]));
	}

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== Descritores RX (0-3) ===\n");
	for (i = 0; i < 4 && i < MTS_RING_SIZE; i++) {
		__le32 *d = mp->rx_ring + i * MTS_DESC_SIZE;
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  RX[%03u] ctl=0x%08x addr=0x%08x\n",
				 i, le32_to_cpu(d[0]), le32_to_cpu(d[1]));
	}

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== Descritores RX ao redor de rx_idx=%u ===\n",
			 mp->rx_idx);
	for (i = -3; i <= 3; i++) {
		int idx = (mp->rx_idx + i) & (MTS_RING_SIZE - 1);
		__le32 *d = mp->rx_ring + idx * MTS_DESC_SIZE;
		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  RX[%03u] ctl=0x%08x addr=0x%08x %s\n",
				 idx, le32_to_cpu(d[0]), le32_to_cpu(d[1]),
				 (idx == mp->rx_idx) ? "<--- ATUAL" : "");
	}

	if (!mp->rx_buf)
		return len;

	len += scnprintf(buf + len, PAGE_SIZE - len,
			 "\n=== Hexdump buffers RX (64B cada) ===\n");
	for (i = -1; i <= 1; i++) {
		int idx = (mp->rx_idx + i) & (MTS_RING_SIZE - 1);
		u8 *buf_ptr = mp->rx_buf + idx * MTS_RX_BUF_SIZE;
		int j;

		len += scnprintf(buf + len, PAGE_SIZE - len,
				 "  Buffer RX[%03u]:\n", idx);
		for (j = 0; j < 64; j += 16) {
			int k;

			len += scnprintf(buf + len, PAGE_SIZE - len,
					 "    %04x: ", j);
			for (k = 0; k < 16; k++)
				len += scnprintf(buf + len, PAGE_SIZE - len,
						 "%02x ", buf_ptr[j + k]);
			len += scnprintf(buf + len, PAGE_SIZE - len, " |");
			for (k = 0; k < 16; k++) {
				char c = buf_ptr[j + k];

				len += scnprintf(buf + len, PAGE_SIZE - len, "%c",
						 (c >= 32 && c <= 126) ? c : '.');
			}
			len += scnprintf(buf + len, PAGE_SIZE - len, "|\n");
		}
	}

	return len;
}

static DEVICE_ATTR_RO(mts_regs);

/* ------------------------------------------------------------------ */
/* MAC address — mesma fonte que o sky2 usa no Aeolia: SPM da funcao   */
/* MEM do southbridge (00:14.6 no Baikal).                             */
/* ------------------------------------------------------------------ */

static void mts_get_mac_address(struct mts_priv *mp, u8 *addr)
{
	unsigned int mem_devfn = PCI_DEVFN(PCI_SLOT(mp->pdev->devfn),
					   BAIKAL_FUNC_ID_MEM);
	struct pci_dev *mem_dev;
	phys_addr_t bp_base;
	void __iomem *bp;

	eth_random_addr(addr);

	mem_dev = pci_get_slot(mp->pdev->bus, mem_devfn);
	if (!mem_dev) {
		dev_warn(&mp->pdev->dev, "funcao MEM ausente; MAC aleatorio\n");
		return;
	}

	bp_base = pci_resource_start(mem_dev, 5) + BPCIE_SPM_BP_BASE;
	if (!request_mem_region(bp_base, BPCIE_SPM_BP_SIZE, "mts.spm.bp")) {
		dev_warn(&mp->pdev->dev, "SPM ocupada; MAC aleatorio\n");
		goto put;
	}

	bp = ioremap(bp_base, BPCIE_SPM_BP_SIZE);
	if (bp) {
		u8 tmp[ETH_ALEN];

		memcpy_fromio(tmp, bp, ETH_ALEN);
		if (is_valid_ether_addr(tmp)) {
			memcpy(addr, tmp, ETH_ALEN);
			dev_info(&mp->pdev->dev, "MAC lido da SPM: %pM\n", addr);
		} else {
			dev_warn(&mp->pdev->dev, "SPM com MAC invalido (%pM); usando aleatorio\n", tmp);
		}
		iounmap(bp);
	}
	release_mem_region(bp_base, BPCIE_SPM_BP_SIZE);
put:
	pci_dev_put(mem_dev);
}

/* ------------------------------------------------------------------ */
/* Interrupt handler (placeholder — status register nao localizado)   */
/* ------------------------------------------------------------------ */

static irqreturn_t mts_interrupt(int irq, void *dev_id)
{
	struct net_device *dev = dev_id;
	struct mts_priv *mp = netdev_priv(dev);

	/*
	 * O registrador de STATUS de interrupcao ainda nao foi localizado na RE
	 * — so a mascara (0x54) esta identificada. Ate isso ser mapeado, o
	 * handler apenas contabiliza e devolve HANDLED para nao travar a linha.
	 */

	/* Phase 2: IRQ storm guard — conta quantas IRQs chegam dentro da
	 * janela de irq_storm_threshold_ms; só dispara apos passar de
	 * irq_storm_max_count NA MESMA janela (nao a cada duas IRQs
	 * proximas, que seria falso-positivo em trafego normal). */
	if (irq_storm_threshold_ms > 0) {
		unsigned long now = jiffies;
		unsigned long window = msecs_to_jiffies(irq_storm_threshold_ms);

		if (time_after(now, mp->irq_storm_jiffies + window)) {
			/* nova janela: reinicia contador */
			mp->irq_storm_jiffies = now;
			mp->irq_window_count = 1;
		} else {
			mp->irq_window_count++;
			if (mp->irq_window_count > irq_storm_max_count) {
				/* storm detectado: desabilita IRQ e volta para polling */
				dev_warn(&mp->pdev->dev,
					 "IRQ storm (%u em %d ms) — desabilitando IRQ, voltando para polling\n",
					 mp->irq_window_count, irq_storm_threshold_ms);
				disable_irq_nosync(irq);
				mp->enable_carrier = false; /* link check via polling apenas */
				return IRQ_HANDLED;
			}
		}
	}

	mp->irq_count++;
	return IRQ_HANDLED;
}

/* ------------------------------------------------------------------ */
/* netdev                                                              */
/* ------------------------------------------------------------------ */

static int mts_open(struct net_device *dev)
{
	struct mts_priv *mp = netdev_priv(dev);

	/* re-le module params (permite mudar via sysfs sem rmmod) */
	mp->enable_carrier = enable_carrier;
	mp->enable_rx = enable_rx;
	mp->enable_tx = enable_tx;

	dev_info(&mp->pdev->dev, "open (stage=%d) carrier=%d rx=%d tx=%d\n",
		 stage, mp->enable_carrier, mp->enable_rx, mp->enable_tx);

	mp->link_last_raw = ~0U; /* força primeira leitura a disparar mudança */
	mp->link_up = true;      /* inverte para que a primeira leitura (link down=0) sempre gere notificação */
	mp->link_speed = 0;
	mp->link_duplex = 0;

	netif_carrier_off(dev);

	if (mp->enable_carrier || mp->enable_rx || mp->enable_tx) {
		/* NAPI */
		netif_napi_add(dev, &mp->napi, mts_poll);
		mp->napi_enabled = true;
		napi_enable(&mp->napi);

		/* Timer de polling */
		mp->poll_interval_ms = poll_interval_ms;
		timer_setup(&mp->poll_timer, mts_poll_timer, 0);
		mod_timer(&mp->poll_timer, jiffies + msecs_to_jiffies(mp->poll_interval_ms));

		if (mp->enable_tx)
			netif_start_queue(dev);
	}

	return 0;
}

static int mts_stop(struct net_device *dev)
{
	struct mts_priv *mp = netdev_priv(dev);

	if (mp->napi_enabled) {
		timer_delete_sync(&mp->poll_timer);
		napi_disable(&mp->napi);
		netif_napi_del(&mp->napi);
		mp->napi_enabled = false;
	}

	mts_mac_stop(mp);

	if (mp->enable_tx)
		mts_tx_drain_force(mp);

	return 0;
}

static const struct net_device_ops mts_netdev_ops = {
	.ndo_open		= mts_open,
	.ndo_stop		= mts_stop,
	.ndo_start_xmit		= mts_start_xmit,
	.ndo_set_mac_address	= eth_mac_addr,
	.ndo_validate_addr	= eth_validate_addr,
	.ndo_tx_timeout		= mts_tx_timeout,
};

/* ------------------------------------------------------------------ */
/* probe / remove                                                      */
/* ------------------------------------------------------------------ */

static int mts_probe(struct pci_dev *pdev, const struct pci_device_id *ent)
{
	struct net_device *dev;
	struct mts_priv *mp;
	u8 mac[ETH_ALEN];
	int err;

	err = pci_enable_device(pdev);
	if (err)
		return err;

	err = pci_request_regions(pdev, DRV_NAME);
	if (err)
		goto disable;

	dev = alloc_etherdev(sizeof(*mp));
	if (!dev) {
		err = -ENOMEM;
		goto release;
	}
	SET_NETDEV_DEV(dev, &pdev->dev);

	mp = netdev_priv(dev);
	mp->pdev = pdev;
	mp->dev = dev;

	/*
	 * pci_resource_len() e nao um tamanho fixo: a BAR0 do Baikal tem 4 KB.
	 * Foi justamente o ioremap fixo de 0x4000 do sky2 que gerava o
	 * "resource sanity check ... spans more than 0000:00:14.1".
	 */
	mp->regs = pci_iomap(pdev, 0, pci_resource_len(pdev, 0));
	if (!mp->regs) {
		err = -ENOMEM;
		goto freedev;
	}

	/* Mapeia região do Glue (BAR2 de 00:14.4) em 0xc8800000 com 2 MB para cobrir registradores Pervasive (0x10a030 e 0x180000) */
	mp->glue_phys = 0xc8800000ULL;
	mp->regs_glue = ioremap(mp->glue_phys, 0x200000);

	if (mp->regs_glue) {
		dev_info(&pdev->dev, "Glue (00:14.4) ioremapped em %pa -> %px (2 MB)\n",
			 &mp->glue_phys, mp->regs_glue);
	} else {
		dev_warn(&pdev->dev, "Falha ao mapear glue @ 0xc8800000\n");
	}

	dev_info(&pdev->dev, "%s %s: BAR0 %pa len 0x%llx, stage=%d\n",
		 DRV_NAME, DRV_VERSION, &pdev->resource[0].start,
		 (unsigned long long)pci_resource_len(pdev, 0), stage);

	pci_set_drvdata(pdev, dev);

	if (stage >= 1) {
		mts_dump_regs(mp);
		mts_mdio_probe(mp);
	}

	if (stage >= 2) {
		if (force_mac_reset)
			mts_mac_stop(mp);

		err = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
		if (err) {
			dev_err(&pdev->dev, "sem mascara DMA de 32 bits\n");
			goto unmap;
		}
		err = mts_alloc_rings(mp);
		if (err)
			goto unmap;
		mts_setup_rings(mp);
		mts_program_rings(mp);

		err = device_create_file(&pdev->dev, &dev_attr_mts_regs);
		if (err)
			dev_warn(&pdev->dev,
				 "falha ao criar sysfs mts_regs: %d\n", err);
	}

	if (stage >= 3) {
		mts_mac_enable(mp);
		mts_write(mp, MTS_IMR, irq_mask);
		dev_info(&pdev->dev, "IMR (0x54) = 0x%08x (irq_mask=0x%x)\n",
			 mts_read(mp, MTS_IMR), irq_mask);
	}

	if (stage < 4) {
		dev_info(&pdev->dev,
			 "parando no stage %d — netdev NAO registrado (use stage=4 para ir ate o fim)\n",
			 stage);
		return 0;
	}

	/* --- stage 4: so aqui o dispositivo ganha permissao de mestrar o
	 * barramento, ja com os aneis apontando para memoria do Linux --- */
	pci_set_master(pdev);

	if (bpcie_assign_irqs(pdev, 1) <= 0) {
		dev_err(&pdev->dev, "falha ao alocar IRQ via bpcie\n");
		err = -ENODEV;
		goto freerings;
	}

	err = request_irq(pdev->irq, mts_interrupt, 0, DRV_NAME, dev);
	if (err) {
		dev_err(&pdev->dev, "request_irq falhou: %d\n", err);
		goto freeirqs;
	}

	mts_get_mac_address(mp, mac);
	eth_hw_addr_set(dev, mac);

	/* module params sao lidos em open(); aqui so guardamos defaults */
	mp->enable_carrier = enable_carrier;
	mp->enable_rx = enable_rx;
	mp->enable_tx = enable_tx;

	dev->netdev_ops = &mts_netdev_ops;
	dev->watchdog_timeo = 5 * HZ;

	err = register_netdev(dev);
	if (err) {
		dev_err(&pdev->dev, "register_netdev falhou: %d\n", err);
		goto freeirq;
	}

	dev_info(&pdev->dev, "%s registrado como %s, MAC %pM\n",
		 DRV_NAME, dev->name, dev->dev_addr);
	return 0;

freeirq:
	free_irq(pdev->irq, dev);
freeirqs:
	bpcie_free_irqs(pdev->irq, 1);
freerings:
	pci_clear_master(pdev);
	mts_free_rings(mp);
unmap:
	if (mp->regs_glue)
		iounmap(mp->regs_glue);
	pci_iounmap(pdev, mp->regs);
freedev:
	free_netdev(dev);
release:
	pci_release_regions(pdev);
disable:
	pci_disable_device(pdev);
	return err;
}

static void mts_remove(struct pci_dev *pdev)
{
	struct net_device *dev = pci_get_drvdata(pdev);
	struct mts_priv *mp;

	if (!dev)
		return;
	mp = netdev_priv(dev);

	/* Remover sysfs ANTES de unregister_netdev para evitar deadlock */
	if (stage >= 2)
		device_remove_file(&pdev->dev, &dev_attr_mts_regs);

	if (dev->reg_state == NETREG_REGISTERED) {
		unregister_netdev(dev);
		free_irq(pdev->irq, dev);
		bpcie_free_irqs(pdev->irq, 1);
		pci_clear_master(pdev);
	}

	if (stage >= 3)
		mts_mac_stop(mp);

	mts_free_rings(mp);
	if (mp->regs_glue)
		iounmap(mp->regs_glue);
	pci_iounmap(pdev, mp->regs);
	free_netdev(dev);
	pci_release_regions(pdev);
	pci_disable_device(pdev);
}

static const struct pci_device_id mts_id_table[] = {
	{ PCI_DEVICE(PCI_VENDOR_ID_SONY, PCI_DEVICE_ID_SONY_BAIKAL_GBE) },
	{ 0 }
};
MODULE_DEVICE_TABLE(pci, mts_id_table);

static struct pci_driver mts_driver = {
	.name		= DRV_NAME,
	.id_table	= mts_id_table,
	.probe		= mts_probe,
	.remove		= mts_remove,
};

module_pci_driver(mts_driver);

MODULE_DESCRIPTION("Sony Baikal GBE (MTS) network driver");
MODULE_LICENSE("GPL");
MODULE_VERSION(DRV_VERSION);