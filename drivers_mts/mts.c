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
 * BRING-UP EM ESTÁGIOS  (module param `stage`, default 1)
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

	dev_info(d, "aneis: TX va=%p dma=%pad | RX va=%p dma=%pad | bufs dma=%pad (%u KB)\n",
		 mp->tx_ring, &mp->tx_ring_dma, mp->rx_ring, &mp->rx_ring_dma,
		 &mp->rx_buf_dma, MTS_RX_BUF_TOTAL / 1024);
	return 0;
}

/*
 * Monta os descritores exatamente como fcn.dc5a31f0.
 *
 * TX: desc[0] = OWN (entregue ao hardware), desc[2] |= 0xffff0000.
 * RX: desc[0] = OWN | tamanho, desc[1] = endereco fisico do buffer,
 *     WRAP no ultimo, e no fim OWN e LIMPO (descritor pertence ao driver).
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

		d[0] = cpu_to_le32(ctl);
		d[1] = cpu_to_le32(mp->rx_buf_dma + i * MTS_RX_BUF_SIZE);
		/* o original limpa OWN depois de montar: o descritor comeca
		 * pertencendo ao driver, nao ao hardware */
		d[0] = cpu_to_le32(ctl & ~MTS_DESC_OWN);
	}

	mp->tx_idx = 0;
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
}

/* ------------------------------------------------------------------ */
/* Diagnostico                                                         */
/* ------------------------------------------------------------------ */

static void mts_dump_regs(struct mts_priv *mp)
{
	static const u32 interessantes[] = {
		0x00, 0x08, 0x0c, 0x10, 0x14, 0x18, 0x1c, 0x2c, 0x30,
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
/* netdev                                                              */
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
	mp->irq_count++;
	return IRQ_HANDLED;
}

static int mts_open(struct net_device *dev)
{
	struct mts_priv *mp = netdev_priv(dev);

	dev_info(&mp->pdev->dev, "open (stage=%d)\n", stage);
	netif_carrier_off(dev);
	return 0;
}

static int mts_stop(struct net_device *dev)
{
	struct mts_priv *mp = netdev_priv(dev);

	mts_mac_stop(mp);
	return 0;
}

static netdev_tx_t mts_start_xmit(struct sk_buff *skb, struct net_device *dev)
{
	/*
	 * TX ainda nao implementado: falta mapear o registrador de doorbell e o
	 * layout completo do descritor de transmissao. Descartar e contabilizar
	 * e preferivel a escrever em registrador adivinhado.
	 */
	dev->stats.tx_dropped++;
	dev_kfree_skb_any(skb);
	return NETDEV_TX_OK;
}

static const struct net_device_ops mts_netdev_ops = {
	.ndo_open		= mts_open,
	.ndo_stop		= mts_stop,
	.ndo_start_xmit		= mts_start_xmit,
	.ndo_set_mac_address	= eth_mac_addr,
	.ndo_validate_addr	= eth_validate_addr,
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
	}

	if (stage >= 3) {
		mts_mac_enable(mp);
		mts_write(mp, MTS_IMR, MTS_IMR_DEFAULT);
		dev_info(&pdev->dev, "IMR (0x54) = 0x%08x\n", mts_read(mp, MTS_IMR));
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

	if (dev->reg_state == NETREG_REGISTERED) {
		unregister_netdev(dev);
		free_irq(pdev->irq, dev);
		bpcie_free_irqs(pdev->irq, 1);
		pci_clear_master(pdev);
	}

	if (stage >= 3)
		mts_mac_stop(mp);

	mts_free_rings(mp);
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
