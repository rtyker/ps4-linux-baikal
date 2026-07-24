/* SPDX-License-Identifier: GPL-2.0 */
/*
 * mts.h — mapa de registradores da GBE Baikal (MTS).
 *
 * Cada offset abaixo tem procedência declarada:
 *   [RE]     vem da decompilação do kernel Orbis 12.52
 *   [MEDIDO] vem da varredura completa da BAR0 ao vivo (Fase 13, 1024/1024
 *            dwords, 3 passadas, em consolidado/ps4_hardware_memory.db,
 *            tabela bar0_register_map)
 *   [?]      função ainda desconhecida — NÃO escrever
 */

#ifndef _MTS_H
#define _MTS_H

#include <linux/types.h>
#include <linux/netdevice.h>
#include <linux/pci.h>

/* ---------------- registradores da BAR0 (4 KB) ---------------- */

/* MDIO Clause 45 — comando e status no mesmo registrador.  [RE dc5a2680] */
#define MTS_MDIO			0x00
#define MTS_MDIO_CLEAR_BUSY	0x8000
#define MTS_MDIO_OP_ADDR	0x20	/* fase de endereço */
#define MTS_MDIO_OP_READ	0xe0	/* fase de leitura */
#define MTS_MDIO_READY		0x8000	/* bit 15 do half baixo */
#define MTS_MDIO_RETRIES	10000	/* mesmo limite do original */

/* Escritos pela rotina de init do Orbis; valores conferidos ao vivo.
 * [RE dc5a0ba0] + [MEDIDO] */
#define MTS_REG_10		0x10	/* [MEDIDO] 0x00000085 */
#define MTS_REG_14		0x14	/* [MEDIDO] 0x00002ccc */
#define MTS_REG_18		0x18	/* [MEDIDO] 0x443f695f */
#define MTS_REG_30		0x30	/* [RE] escreve 0x10100 — [MEDIDO] confere */

/* Enable dos dois MAC cores — read-modify-write com OR 1.  [RE dc5a31f0]
 *
 * Confirmado ao vivo (Fase 14): a escrita produz efeito real e persistente.
 * 0x34 NÃO retém o valor (lê 0); o estado observável aparece em 0x38 (escrito
 * 1, lê 8), 0x50 e 0x70. Não interpretar "0x34 == 0" como falha. */
#define MTS_MAC_EN1		0x34
#define MTS_MAC_EN2		0x38
#define MTS_MAC_ENABLE		BIT(0)

/* Pares base/ponteiro dos anéis. O init escreve o MESMO endereço físico nos
 * dois de cada par; o hardware avança o de ponteiro conforme consome.
 * [RE dc5a31f0] + [MEDIDO: escritos iguais, leem diferente] */
#define MTS_TX_RING_PTR		0x3c	/* ponteiro corrente TX */
#define MTS_RX_RING_PTR		0x40	/* ponteiro corrente RX */
#define MTS_TX_RING_BASE	0x44	/* base do anel TX */
#define MTS_RX_RING_BASE	0x48	/* base do anel RX */

#define MTS_REG_50		0x50	/* [MEDIDO] 0x02 -> 0x42 após o enable */

/* Máscara de interrupção. [RE dc5a31f0 escreve softc[0x3098];
 * dc5a5ec0 faz read-modify-write com & 0xffffefff, limpando o bit 12] */
#define MTS_IMR			0x54
/* O valor que o Orbis usa vem do softc e ainda não foi determinado.
 * Começar com tudo mascarado é o único default seguro: nada de interrupção
 * até o registrador de STATUS ser localizado na RE. */
#define MTS_IMR_DEFAULT		0x00000000

#define MTS_REG_5C		0x5c	/* [MEDIDO] 0x00100054 -> 0x00101000 */
#define MTS_REG_70		0x70	/* [MEDIDO] 0x00014000 -> 0x00014003 */
#define MTS_REG_74		0x74	/* [RE] escreve 0x2277 — [MEDIDO] confere */

/* Clock de referência do MAC, em Hz.  [RE dc5a0ba0 escreve 25000000]
 * [MEDIDO] 0x017d7840 = 25000000 — prova de que o MAC está clocado. */
#define MTS_CLOCK		0x7c
#define MTS_CLOCK_25MHZ		25000000

#define MTS_REG_AC		0xac	/* [RE] escreve 9 — [MEDIDO] confere */

/* Registradores de calibração do PHY tocados por dc5a0ba0.  [RE]
 * Não usados ainda; listados para não serem redescobertos. */
#define MTS_PHY_140		0x140
#define MTS_PHY_144		0x144
#define MTS_PHY_1BC		0x1bc
#define MTS_PHY_1C0		0x1c0
#define MTS_PHY_1C4		0x1c4
#define MTS_PHY_1C8		0x1c8
#define MTS_PHY_1D0		0x1d0
#define MTS_PHY_1D4		0x1d4
#define MTS_PHY_200		0x200

/* Offsets Glue (pervasive 00:14.4) lidos pela calibração PHY (dc5a0ba0) */
#define MTS_GLUE_CALIB_0	0x5c
#define MTS_GLUE_CALIB_1	0x60
#define MTS_GLUE_CALIB_2	0x68
#define MTS_GLUE_CALIB_3	0x6c
#define MTS_GLUE_CALIB_4	0x100


/* Contadores de estatística — CLEAR-ON-READ. [MEDIDO: não-zero na 1ª leitura,
 * zero nas seguintes; 0x100/0x104 deram 554 pacotes / 289.664 bytes] */
#define MTS_CNT_PKTS		0x100
#define MTS_CNT_BYTES		0x104
#define MTS_CNT_PKTS2		0x128
#define MTS_CNT_BYTES2		0x12c

/* ---------------- descritores ---------------- */

#define MTS_RING_SIZE		256		/* [RE] softc[0x3060] = 0x100 */
#define MTS_DESC_SIZE		16		/* dwords: ctl, addr, x, y */
#define MTS_RING_BYTES		(MTS_RING_SIZE * MTS_DESC_SIZE)	/* 0x1000 */

#define MTS_DESC_OWN		BIT(31)		/* pertence ao hardware */
#define MTS_DESC_WRAP		BIT(30)		/* último descritor do anel */
#define MTS_DESC_SOP		BIT(29)		/* start of packet (TX) */
#define MTS_DESC_EOP		BIT(28)		/* end of packet (TX) */
#define MTS_DESC_LEN_MASK	0x7ff

#define MTS_RX_BUF_SIZE		0x600		/* 1536 bytes por buffer */
#define MTS_RX_BUF_TOTAL	(MTS_RING_SIZE * MTS_RX_BUF_SIZE) /* 384 KB */

/* Status de link em BAR0+0x04. [RE fcn.ffffffffdc5a2bd0] */
#define MTS_LINK_STATUS		0x04
#define MTS_LINK_UP		BIT(0)
#define MTS_LINK_SPEED_MASK	(0x3 << 2)
#define MTS_LINK_SPEED_10	(0x0 << 2)
#define MTS_LINK_SPEED_100	(0x1 << 2)
#define MTS_LINK_SPEED_1000	(0x2 << 2)
#define MTS_LINK_DUPLEX_FULL	BIT(6)

/* ---------------- estado do driver ---------------- */

struct mts_priv {
	struct pci_dev		*pdev;
	struct net_device	*dev;
	void __iomem		*regs;		/* BAR0 */

	/* BAR2 (glue/pervasive) — para parâmetros de calibração PHY */
	void __iomem		*regs_glue;	/* ioremap(0xc8800000) */
	phys_addr_t		glue_phys;

	void			*tx_ring;
	dma_addr_t		tx_ring_dma;
	void			*rx_ring;
	dma_addr_t		rx_ring_dma;
	void			*rx_buf;
	dma_addr_t		rx_buf_dma;

	u32			tx_idx;
	u32			rx_idx;
	u32			tx_clean;
	unsigned long		irq_count;

	/* NAPI + polling por software */
	struct napi_struct	napi;
	struct timer_list	poll_timer;
	bool			napi_enabled;
	unsigned int		poll_interval_ms;

	/* Carrier detection */
	u32			link_last_raw;
	bool			link_up;
	unsigned int		link_speed;
	unsigned int		link_duplex;
	bool			enable_carrier;
	bool			enable_rx;
	bool			enable_tx;

	/* TX tracking */
	struct sk_buff		**tx_skb;
	dma_addr_t		*tx_skb_dma;
	size_t			*tx_skb_len;

	/* PHY calibration */
	bool			phy_calib_done;

	/* RX debug log throttling */
	u32			rx_debug_logs;
};

#endif /* _MTS_H */