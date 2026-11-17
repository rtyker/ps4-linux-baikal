// SPDX-License-Identifier: GPL-2.0
/*
 * mtsx - Baikal gigabit Ethernet MAC (PCI 104d:90d8), polled mode.
 *
 * STATUS: compiled and host-tested (test_desc.c), never run on hardware. This
 * is the driver for Phase C of others/docs/PLAN_ETH0_BAIKAL.md; nothing here
 * may be loaded before Phases A and B (others/tools/mts_peek) showed what the
 * console looks like after the kexec.
 *
 * Where the behavior comes from: the Orbis 12.52 driver, decompiled with REA
 * (others/rea/ethernet/decompiled/rea_20261117/). The plan calls those facts
 * F1-F20. Where the firmware says nothing, the measurements published by
 * Gcsman110 (ps4-mts-linux-driver) and meerzulee (linux-psx) are cited as [P];
 * they are not verified on this console.
 *
 * Design:
 *  - It adopts the MAC the way Orbis left it after the kexec: configured and
 *    stopped. It replays no cold init, no PHY calibration and no glue reset
 *    (F18: Orbis's own attach does none either).
 *  - The first "ip link set up" publishes one DMA generation: it clears the
 *    shutdown residue (F5, F6, F8), allocates and arms the rings, and enables
 *    the cores. After that the module cannot be unloaded and the device cannot
 *    be unbound: a stop acknowledgment does not prove that DMA drained [P].
 *    Every experiment that gets this far starts from a cold boot.
 *  - There are no interrupts. A 1 ms timer schedules NAPI, and the poll does
 *    what the Orbis interrupt handler does (F20): acknowledge 0x50, reclaim TX,
 *    ring the doorbells, drain RX. The interrupt mask stays as Orbis left it.
 *  - There is no MODULE_DEVICE_TABLE: only an explicit insmod loads this.
 */

#define pr_fmt(fmt) "mtsx: " fmt

#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/etherdevice.h>
#include <linux/ethtool.h>
#include <linux/hrtimer.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/netdevice.h>
#include <linux/pci.h>
#include <linux/skbuff.h>
#include <linux/spinlock.h>

#include "mtsx_desc.h"

#define DRV_NAME		"mtsx"
#define DRV_VERSION		"0.1"

#define GBE_VENDOR		0x104d
#define GBE_DEVICE		0x90d8

/* BAR0 registers. Meaning as established in the plan (F1-F20). */
#define R_MDIO			0x00	/* MDIO command (low half) and data (high half) */
#define R_LINK			0x04	/* bit 0: link up */
#define R_MAC_HI		0x14	/* MAC address bytes 0-1, as programmed by Orbis */
#define R_MAC_LO		0x18	/* MAC address bytes 2-5 */
#define R_TXCTL			0x34	/* TX core: bit 0 run, bit 1 reset, bit 2 doorbell */
#define R_RXCTL			0x38	/* RX core: same bits */
#define R_TXCUR			0x3c	/* TX ring current pointer (hardware advances it) */
#define R_RXCUR			0x40
#define R_TXBASE		0x44
#define R_RXBASE		0x48
#define R_ISR			0x50	/* status, write-1-to-clear (F20) */
#define R_IMR			0x54	/* a set bit MASKS its source (F6, F7) */

#define CTL_RUN			BIT(0)
#define CTL_RESET		BIT(1)
#define CTL_POLL		BIT(2)

#define LINK_UP			BIT(0)
/* [P] Gcsman110: bits 3:2 = speed (0: 10, 1: 100, 2: 1000 Mbit/s), bit 4 = full duplex. */
#define LINK_SPEED(v)		(((v) >> 2) & 3)
#define LINK_FDX		BIT(4)

#define ISR_RXFLOW		(BIT(1) | BIT(5))	/* F20: RX loop, then the RX doorbell */
#define ISR_FATAL		0x00500000u		/* F20: bits 20 and 22 */
#define ISR_ERRORS		0x007be600u		/* F20: logged by Orbis */

#define IMR_STOPPED		0x007ffffau		/* what mac_stop writes (F7) */
#define IMR_OPERATING		0x00001018u		/* operating mask set by Orbis attach (F17) */

#define MDIO_DONE		BIT(15)
#define MDIO_POLL_US		10000

/* The MediaTek PHY both reference projects report on this console family. */
#define PHY_ID1			0x03a2
#define PHY_ID2			0x9441

/* Clause 45 location of the shutdown residue (Orbis writes 0x0010 there). */
#define RESIDUE_DEVAD		0x1e
#define RESIDUE_REG		0x0147
#define RESIDUE_BIT		0x0010

#define MTSX_TX_BUF		2048u	/* per-descriptor TX bounce buffer */
#define LINK_EVERY_TICKS	250u	/* the link is checked about every 250 ms */

static bool clear_residue = true;
module_param(clear_residue, bool, 0444);
MODULE_PARM_DESC(clear_residue,
		 "Clear the shutdown residue (0x0147.1e bit 4) before enabling the MAC, behind four gates (default 1)");

static unsigned int tx_used = 255;
module_param(tx_used, uint, 0444);
MODULE_PARM_DESC(tx_used,
		 "TX descriptors in use, 128-256 (default 255: the other implementation saw the engine stop on index 255 of 256)");

static unsigned int poll_us = 1000;
module_param(poll_us, uint, 0444);
MODULE_PARM_DESC(poll_us, "Poll period in microseconds while the interface is up, 100-10000 (default 1000)");

struct mtsx_priv {
	struct pci_dev *pdev;
	struct net_device *ndev;
	void __iomem *regs;
	struct napi_struct napi;
	struct hrtimer timer;
	spinlock_t lock;		/* TX ring state and the doorbells */
	spinlock_t mdio_lock;		/* an MDIO read is two commands and must not interleave */

	/* One DMA generation, allocated at the first open and never freed. */
	__le32 *tx_ring;
	__le32 *rx_ring;
	u8 *tx_buf;
	u8 *rx_buf;
	dma_addr_t tx_ring_dma;
	dma_addr_t rx_ring_dma;
	dma_addr_t tx_buf_dma;
	dma_addr_t rx_buf_dma;

	unsigned int used;		/* TX descriptors in use */
	u32 tx_head;			/* free-running counters */
	u32 tx_tail;
	unsigned int rx_idx;
	unsigned int tick;
	ktime_t period_up;
	ktime_t period_down;
	ktime_t period;

	bool published;
	bool up;
	bool fatal;
};

/* ---------------------------------------------------------------------- */
/* MDIO, exactly as the firmware does it (F1-F4)                            */
/* ---------------------------------------------------------------------- */

static int mdio_cmd(struct mtsx_priv *mp, u32 cmd)
{
	u32 v;

	writel(MDIO_DONE, mp->regs + R_MDIO);
	writel(cmd, mp->regs + R_MDIO);
	return readl_poll_timeout_atomic(mp->regs + R_MDIO, v, v & MDIO_DONE, 1, MDIO_POLL_US);
}

static int c22_read(struct mtsx_priv *mp, u8 reg, u16 *val)
{
	unsigned long flags;
	int ret;

	spin_lock_irqsave(&mp->mdio_lock, flags);
	ret = mdio_cmd(mp, ((u32)(reg & 0x1f) << 8) | 0x4000);
	if (!ret)
		*val = readl(mp->regs + R_MDIO) >> 16;
	spin_unlock_irqrestore(&mp->mdio_lock, flags);
	return ret;
}

static int c45_addr(struct mtsx_priv *mp, u8 devad, u16 reg)
{
	return mdio_cmd(mp, ((u32)reg << 16) | ((u32)(devad & 0x1f) << 8) | 0x20);
}

static int c45_read(struct mtsx_priv *mp, u8 devad, u16 reg, u16 *val)
{
	unsigned long flags;
	int ret;

	spin_lock_irqsave(&mp->mdio_lock, flags);
	ret = c45_addr(mp, devad, reg);
	if (!ret)
		ret = mdio_cmd(mp, ((u32)(devad & 0x1f) << 8) | 0xe0);
	if (!ret)
		*val = readl(mp->regs + R_MDIO) >> 16;
	spin_unlock_irqrestore(&mp->mdio_lock, flags);
	return ret;
}

static int c45_write(struct mtsx_priv *mp, u8 devad, u16 reg, u16 val)
{
	unsigned long flags;
	int ret;

	spin_lock_irqsave(&mp->mdio_lock, flags);
	ret = c45_addr(mp, devad, reg);
	if (!ret)
		ret = mdio_cmd(mp, ((u32)(devad & 0x1f) << 8) | ((u32)val << 16) | 0x60);
	spin_unlock_irqrestore(&mp->mdio_lock, flags);
	return ret;
}

/* ---------------------------------------------------------------------- */
/* Doorbells and link                                                       */
/* ---------------------------------------------------------------------- */

/*
 * TX doorbell: bit 2 of 0x34 (F13). The firmware does a plain read-modify-write
 * of |= 4. This variant puts a real 0 -> 1 edge on the bit even if it reads back
 * as 1 [P]; in the healthy state it reads 0 and the two are identical. Bit 1
 * (reset) is masked out of the read-back so a doorbell can never reset the core.
 */
static void mtsx_tx_doorbell(struct mtsx_priv *mp)
{
	u32 ctl = readl(mp->regs + R_TXCTL) & ~CTL_RESET;

	writel(ctl & ~CTL_POLL, mp->regs + R_TXCTL);
	writel(ctl | CTL_POLL, mp->regs + R_TXCTL);
}

/* RX doorbell: plain 0x38 |= 4, as the firmware's interrupt handler does (F20). */
static void mtsx_rx_doorbell(struct mtsx_priv *mp)
{
	u32 ctl = readl(mp->regs + R_RXCTL) & ~CTL_RESET;

	writel(ctl | CTL_POLL, mp->regs + R_RXCTL);
}

static void mtsx_dump_state(struct mtsx_priv *mp, const char *when)
{
	/* Reads only. The counters at 0x100-0x12c clear on read and are never read. */
	netdev_info(mp->ndev,
		    "%s: link=0x%08x txctl=0x%08x rxctl=0x%08x isr=0x%08x imr=0x%08x txcur=0x%08x rxcur=0x%08x\n",
		    when, readl(mp->regs + R_LINK), readl(mp->regs + R_TXCTL),
		    readl(mp->regs + R_RXCTL), readl(mp->regs + R_ISR), readl(mp->regs + R_IMR),
		    readl(mp->regs + R_TXCUR), readl(mp->regs + R_RXCUR));
}

static void mtsx_link_check(struct mtsx_priv *mp)
{
	struct net_device *ndev = mp->ndev;
	u32 v = readl(mp->regs + R_LINK);
	bool up = (v & LINK_UP) && mp->up;
	u16 b1 = 0, b2 = 0;

	if (up == netif_carrier_ok(ndev))
		return;

	/* The first BMSR read returns the latched value, the second the current one. */
	if (c22_read(mp, 1, &b1) || c22_read(mp, 1, &b2)) {
		b1 = 0xffff;
		b2 = 0xffff;
	}

	if (up) {
		netif_carrier_on(ndev);
		netdev_info(ndev, "link up (0x04=0x%08x, speed code %u, %s duplex [P]; BMSR %04x/%04x)\n",
			    v, LINK_SPEED(v), (v & LINK_FDX) ? "full" : "half", b1, b2);
	} else {
		netif_carrier_off(ndev);
		netdev_info(ndev, "link down (0x04=0x%08x, BMSR %04x/%04x)\n", v, b1, b2);
	}
}

/* ---------------------------------------------------------------------- */
/* Shutdown residue (F5, F6, F8)                                            */
/* ---------------------------------------------------------------------- */

/*
 * Orbis writes 0x0010 to Clause 45 0x0147.1e as the last act of every stop
 * path, and nothing clears it on the way up. A power cycle does; a kexec does
 * not. With the bit set the link stays down and nothing is transmitted [P].
 * One read-modify-write clears it, and only if every gate passes. The MAC is
 * still stopped here, so refusing is always safe.
 */
static int mtsx_clear_residue(struct mtsx_priv *mp)
{
	struct device *dev = &mp->pdev->dev;
	u16 id1 = 0, id2 = 0, cur = 0, after = 0;
	int ret;

	ret = c22_read(mp, 2, &id1);
	if (!ret)
		ret = c22_read(mp, 3, &id2);
	if (ret || id1 != PHY_ID1 || id2 != PHY_ID2) {
		dev_err(dev, "residue gate phy_id: FAIL (read %s, got %04x/%04x, want %04x/%04x); not enabling\n",
			ret ? "failed" : "ok", id1, id2, PHY_ID1, PHY_ID2);
		return -ENODEV;
	}
	if (readl(mp->regs + R_TXCTL) || readl(mp->regs + R_RXCTL)) {
		dev_err(dev, "residue gate mac_stopped: FAIL; not enabling\n");
		return -EBUSY;
	}
	/* Accept either the full stop mask (IMR_STOPPED) or the operating mask (IMR_OPERATING).
	 * The firmware's mac_stop uses the full mask, but the attach sets the operating
	 * mask before stopping. MAC cores stopped (gate above) is the real indicator. */
	u32 imr = readl(mp->regs + R_IMR);
	if (imr != IMR_STOPPED && imr != IMR_OPERATING) {
		dev_err(dev, "residue gate irq_masked: FAIL (IMR=0x%08x, want 0x%08x or 0x%08x); not enabling\n",
			imr, IMR_STOPPED, IMR_OPERATING);
		return -EBUSY;
	}
	ret = c45_read(mp, RESIDUE_DEVAD, RESIDUE_REG, &cur);
	if (ret) {
		dev_err(dev, "residue read failed (%d); not enabling\n", ret);
		return -EIO;
	}
	if (!(cur & RESIDUE_BIT)) {
		dev_info(dev, "residue: 0x0147.1e = 0x%04x, bit 4 already clear\n", cur);
		return 0;
	}

	ret = c45_write(mp, RESIDUE_DEVAD, RESIDUE_REG, cur & ~RESIDUE_BIT);
	/* The firmware waits DELAY(1000) after this write, before anything else. */
	usleep_range(1000, 2000);
	if (!ret)
		ret = c45_read(mp, RESIDUE_DEVAD, RESIDUE_REG, &after);
	dev_info(dev, "residue: 0x0147.1e 0x%04x -> 0x%04x (result %d)\n", cur, after, ret);
	if (ret || (after & RESIDUE_BIT)) {
		dev_err(dev, "residue did not clear; not enabling\n");
		return -EIO;
	}
	return 0;
}

/* ---------------------------------------------------------------------- */
/* TX                                                                       */
/* ---------------------------------------------------------------------- */

/* Caller holds mp->lock. Reclaims in order, exactly as the firmware's loop does (F10). */
static void mtsx_tx_reclaim(struct mtsx_priv *mp)
{
	while (mp->tx_tail != mp->tx_head) {
		unsigned int idx = mtsx_tx_index(mp->tx_tail, mp->used);
		__le32 *d = mp->tx_ring + idx * MTSX_DESC_WORDS;
		u32 w0 = le32_to_cpu(READ_ONCE(d[0]));
		u32 w2 = le32_to_cpu(READ_ONCE(d[2]));

		if (!mtsx_tx_done(w0, w2))
			break;
		dma_rmb();
		d[2] = cpu_to_le32(mtsx_tx_recycled_w2(w2));
		mp->tx_tail++;
	}
}

static netdev_tx_t mtsx_xmit(struct sk_buff *skb, struct net_device *ndev)
{
	struct mtsx_priv *mp = netdev_priv(ndev);
	unsigned int idx, free;
	unsigned long flags;
	__le32 *d;
	u32 w[4];
	u32 len;

	/* The device is not known to pad short frames, and an Ethernet sender must [P]. */
	if (skb_put_padto(skb, ETH_ZLEN)) {
		ndev->stats.tx_dropped++;
		return NETDEV_TX_OK;
	}
	len = skb->len;
	if (unlikely(len > MTSX_TX_BUF)) {
		ndev->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	spin_lock_irqsave(&mp->lock, flags);
	free = mtsx_tx_free(mp->tx_head, mp->tx_tail, mp->used);
	if (free < MTSX_TX_MIN_FREE || mp->fatal) {
		/* The firmware refuses a frame with fewer than 64 free descriptors (F14). */
		netif_stop_queue(ndev);
		spin_unlock_irqrestore(&mp->lock, flags);
		return NETDEV_TX_BUSY;
	}

	idx = mtsx_tx_index(mp->tx_head, mp->used);
	d = mp->tx_ring + idx * MTSX_DESC_WORDS;
	memcpy(mp->tx_buf + idx * MTSX_TX_BUF, skb->data, len);
	mtsx_tx_image(w, lower_32_bits(mp->tx_buf_dma + idx * MTSX_TX_BUF), len,
		      mtsx_tx_wrap(idx, mp->used));

	/* Words 1-3 first, then the store of word0 that clears bit 31 hands it over (F14). */
	d[1] = cpu_to_le32(w[1]);
	d[2] = cpu_to_le32(w[2]);
	d[3] = cpu_to_le32(w[3]);
	dma_wmb();
	WRITE_ONCE(d[0], cpu_to_le32(w[0]));
	mp->tx_head++;

	wmb();	/* the descriptor must be visible before the doorbell */
	mtsx_tx_doorbell(mp);

	if (mtsx_tx_free(mp->tx_head, mp->tx_tail, mp->used) < MTSX_TX_MIN_FREE)
		netif_stop_queue(ndev);
	spin_unlock_irqrestore(&mp->lock, flags);

	ndev->stats.tx_packets++;
	ndev->stats.tx_bytes += len;
	dev_consume_skb_any(skb);	/* the frame was copied to the bounce buffer */
	return NETDEV_TX_OK;
}

static void mtsx_tx_timeout(struct net_device *ndev, unsigned int txqueue)
{
	struct mtsx_priv *mp = netdev_priv(ndev);
	unsigned long flags;

	netdev_err(ndev, "TX timeout: head=%u tail=%u free=%u\n", mp->tx_head, mp->tx_tail,
		   mtsx_tx_free(mp->tx_head, mp->tx_tail, mp->used));
	mtsx_dump_state(mp, "tx-timeout");
	spin_lock_irqsave(&mp->lock, flags);
	mtsx_tx_doorbell(mp);
	spin_unlock_irqrestore(&mp->lock, flags);
}

/* ---------------------------------------------------------------------- */
/* RX                                                                       */
/* ---------------------------------------------------------------------- */

/* Returns the number of descriptors handled (at most budget). */
static int mtsx_rx(struct mtsx_priv *mp, int budget)
{
	struct net_device *ndev = mp->ndev;
	int handled;

	for (handled = 0; handled < budget; handled++) {
		unsigned int idx = mp->rx_idx;
		__le32 *d = mp->rx_ring + idx * MTSX_DESC_WORDS;
		u32 w0 = le32_to_cpu(READ_ONCE(d[0]));
		unsigned int len;

		if (!mtsx_rx_ready(w0))
			break;
		dma_rmb();	/* read the descriptor before the payload it describes */
		len = mtsx_rx_len(w0);

		if (mp->up) {
			if (len >= ETH_ZLEN && len <= MTSX_RX_BUF) {
				struct sk_buff *skb = napi_alloc_skb(&mp->napi, len);

				if (skb) {
					skb_put_data(skb, mp->rx_buf + idx * MTSX_RX_BUF, len);
					skb->protocol = eth_type_trans(skb, ndev);
					ndev->stats.rx_packets++;
					ndev->stats.rx_bytes += len;
					napi_gro_receive(&mp->napi, skb);
				} else {
					ndev->stats.rx_dropped++;
				}
			} else {
				ndev->stats.rx_length_errors++;
			}
		}

		/*
		 * Re-arm in full, as the firmware does (F15): word1 and word2 again,
		 * then the store of word0 that clears bit 31 gives the buffer back.
		 */
		d[1] = cpu_to_le32(lower_32_bits(mp->rx_buf_dma + idx * MTSX_RX_BUF));
		d[2] = 0;
		dma_wmb();
		WRITE_ONCE(d[0], cpu_to_le32(mtsx_rx_arm_w0(idx)));
		mp->rx_idx = (idx + 1) % MTSX_HW_RING;
	}
	return handled;
}

/* ---------------------------------------------------------------------- */
/* Poll: what the Orbis interrupt handler does (F20), driven by a timer     */
/* ---------------------------------------------------------------------- */

static int mtsx_poll(struct napi_struct *napi, int budget)
{
	struct mtsx_priv *mp = container_of(napi, struct mtsx_priv, napi);
	struct net_device *ndev = mp->ndev;
	unsigned long flags;
	bool outstanding;
	u32 isr;
	int work;

	isr = readl(mp->regs + R_ISR);
	if (isr)
		writel(isr, mp->regs + R_ISR);		/* write-1-to-clear */

	spin_lock_irqsave(&mp->lock, flags);
	mtsx_tx_reclaim(mp);
	outstanding = mp->tx_tail != mp->tx_head;
	if (outstanding)
		mtsx_tx_doorbell(mp);			/* never rely on one doorbell surviving */
	if (mp->up && !mp->fatal && netif_queue_stopped(ndev) &&
	    mtsx_tx_free(mp->tx_head, mp->tx_tail, mp->used) >= MTSX_TX_WAKE_AT)
		netif_wake_queue(ndev);
	spin_unlock_irqrestore(&mp->lock, flags);

	work = mtsx_rx(mp, budget);
	if (work || (isr & ISR_RXFLOW))
		mtsx_rx_doorbell(mp);

	if (isr & ISR_FATAL) {
		if (!mp->fatal) {
			mp->fatal = true;
			netif_stop_queue(ndev);
			netdev_err(ndev, "fatal DMA error bits 0x%08x; TX stopped (the firmware rebuilds the TX ring here: not implemented)\n",
				   isr & ISR_FATAL);
			mtsx_dump_state(mp, "fatal");
		}
	} else if ((isr & ISR_ERRORS) && net_ratelimit()) {
		netdev_info(ndev, "status error bits 0x%08x (logged by Orbis too, meaning unknown)\n",
			    isr & ISR_ERRORS);
	}

	if ((++mp->tick % LINK_EVERY_TICKS) == 0 || (isr & BIT(2)))
		mtsx_link_check(mp);

	if (work < budget)
		napi_complete_done(napi, work);
	return work;
}

static enum hrtimer_restart mtsx_timer(struct hrtimer *t)
{
	struct mtsx_priv *mp = container_of(t, struct mtsx_priv, timer);

	napi_schedule(&mp->napi);
	hrtimer_forward_now(t, READ_ONCE(mp->period));
	return HRTIMER_RESTART;
}

/* ---------------------------------------------------------------------- */
/* Publishing the DMA generation                                            */
/* ---------------------------------------------------------------------- */

static void mtsx_free_dma(struct mtsx_priv *mp)
{
	struct device *dev = &mp->pdev->dev;

	if (mp->rx_buf)
		dma_free_coherent(dev, MTSX_HW_RING * MTSX_RX_BUF, mp->rx_buf, mp->rx_buf_dma);
	if (mp->tx_buf)
		dma_free_coherent(dev, MTSX_HW_RING * MTSX_TX_BUF, mp->tx_buf, mp->tx_buf_dma);
	if (mp->rx_ring)
		dma_free_coherent(dev, MTSX_RING_BYTES, mp->rx_ring, mp->rx_ring_dma);
	if (mp->tx_ring)
		dma_free_coherent(dev, MTSX_RING_BYTES, mp->tx_ring, mp->tx_ring_dma);
	mp->rx_buf = NULL;
	mp->tx_buf = NULL;
	mp->rx_ring = NULL;
	mp->tx_ring = NULL;
}

static int mtsx_alloc_dma(struct mtsx_priv *mp)
{
	struct device *dev = &mp->pdev->dev;

	mp->tx_ring = dma_alloc_coherent(dev, MTSX_RING_BYTES, &mp->tx_ring_dma, GFP_KERNEL);
	mp->rx_ring = dma_alloc_coherent(dev, MTSX_RING_BYTES, &mp->rx_ring_dma, GFP_KERNEL);
	mp->tx_buf = dma_alloc_coherent(dev, MTSX_HW_RING * MTSX_TX_BUF,
					&mp->tx_buf_dma, GFP_KERNEL);
	mp->rx_buf = dma_alloc_coherent(dev, MTSX_HW_RING * MTSX_RX_BUF,
					&mp->rx_buf_dma, GFP_KERNEL);
	if (!mp->tx_ring || !mp->rx_ring || !mp->tx_buf || !mp->rx_buf) {
		mtsx_free_dma(mp);
		return -ENOMEM;
	}
	/* The hardware takes 32-bit addresses (the mask was set at probe). */
	if (upper_32_bits(mp->tx_ring_dma) || upper_32_bits(mp->rx_ring_dma) ||
	    upper_32_bits(mp->tx_buf_dma + MTSX_HW_RING * MTSX_TX_BUF) ||
	    upper_32_bits(mp->rx_buf_dma + MTSX_HW_RING * MTSX_RX_BUF)) {
		mtsx_free_dma(mp);
		return -EIO;
	}
	return 0;
}

static void mtsx_init_rings(struct mtsx_priv *mp)
{
	unsigned int i;
	u32 w[4];

	for (i = 0; i < MTSX_HW_RING; i++) {
		__le32 *d = mp->tx_ring + i * MTSX_DESC_WORDS;
		unsigned int k;

		mtsx_tx_idle_image(w);
		for (k = 0; k < MTSX_DESC_WORDS; k++)
			d[k] = cpu_to_le32(w[k]);
	}
	for (i = 0; i < MTSX_HW_RING; i++) {
		__le32 *d = mp->rx_ring + i * MTSX_DESC_WORDS;

		d[1] = cpu_to_le32(lower_32_bits(mp->rx_buf_dma + i * MTSX_RX_BUF));
		d[2] = 0;
		d[3] = 0;
		d[0] = cpu_to_le32(mtsx_rx_arm_w0(i));	/* bit 31 clear: the hardware owns it */
	}
	mp->tx_head = 0;
	mp->tx_tail = 0;
	mp->rx_idx = 0;
}

/* The first open. Everything before the MAC is enabled can be undone. */
static int mtsx_publish(struct mtsx_priv *mp)
{
	struct device *dev = &mp->pdev->dev;
	int ret;

	/* F9: the MAC must be exactly as the previous stage left it, stopped. */
	if (readl(mp->regs + R_TXCTL) || readl(mp->regs + R_RXCTL)) {
		dev_err(dev, "MAC cores are not stopped (0x34=0x%08x 0x38=0x%08x); refusing\n",
			readl(mp->regs + R_TXCTL), readl(mp->regs + R_RXCTL));
		return -EBUSY;
	}

	if (clear_residue) {
		ret = mtsx_clear_residue(mp);
		if (ret)
			return ret;
	}

	ret = mtsx_alloc_dma(mp);
	if (ret) {
		dev_err(dev, "cannot allocate the DMA generation: %d\n", ret);
		return ret;
	}
	mtsx_init_rings(mp);
	wmb();	/* descriptors in memory before the hardware is pointed at them */

	/* Cold-init step 2 [P]: read 0x50 and write it straight back (clears stale events). */
	writel(readl(mp->regs + R_ISR), mp->regs + R_ISR);

	/* F9: base and current pointer both get the ring base, for TX and for RX. */
	writel(lower_32_bits(mp->tx_ring_dma), mp->regs + R_TXBASE);
	writel(lower_32_bits(mp->tx_ring_dma), mp->regs + R_TXCUR);
	writel(lower_32_bits(mp->rx_ring_dma), mp->regs + R_RXBASE);
	writel(lower_32_bits(mp->rx_ring_dma), mp->regs + R_RXCUR);

	pci_set_master(mp->pdev);

	/*
	 * F9: the cores are enabled with |= 1. Both read 0 here (checked above), so this
	 * is a plain write of 1; a stale bit 3 would have made the old driver's
	 * read-modify-write write 0x09, which was rejected.
	 */
	writel(CTL_RUN, mp->regs + R_TXCTL);
	writel(CTL_RUN, mp->regs + R_RXCTL);
	/* The IMR stays as Orbis left it (all masked): this driver polls. */
	mtsx_rx_doorbell(mp);

	/* From here the hardware may DMA into the generation: it must never be freed. */
	__module_get(THIS_MODULE);
	mp->published = true;
	napi_enable(&mp->napi);
	hrtimer_start(&mp->timer, mp->period_up, HRTIMER_MODE_REL_SOFT);
	mtsx_dump_state(mp, "published");
	return 0;
}

/* ---------------------------------------------------------------------- */
/* net_device and ethtool operations                                        */
/* ---------------------------------------------------------------------- */

static int mtsx_open(struct net_device *ndev)
{
	struct mtsx_priv *mp = netdev_priv(ndev);
	int ret;

	if (!mp->published) {
		ret = mtsx_publish(mp);
		if (ret)
			return ret;
	}

	mp->up = true;
	WRITE_ONCE(mp->period, mp->period_up);
	netif_start_queue(ndev);
	mtsx_link_check(mp);
	return 0;
}

/*
 * "Down" is administrative only: the cores keep running and the poll keeps
 * reclaiming and discarding, so the hardware never sees a stopped ring that
 * the driver has forgotten.
 */
static int mtsx_stop(struct net_device *ndev)
{
	struct mtsx_priv *mp = netdev_priv(ndev);

	mp->up = false;
	WRITE_ONCE(mp->period, mp->period_down);
	netif_stop_queue(ndev);
	netif_carrier_off(ndev);
	return 0;
}

static void mtsx_get_drvinfo(struct net_device *ndev, struct ethtool_drvinfo *info)
{
	struct mtsx_priv *mp = netdev_priv(ndev);

	strscpy(info->driver, DRV_NAME, sizeof(info->driver));
	strscpy(info->version, DRV_VERSION, sizeof(info->version));
	strscpy(info->bus_info, pci_name(mp->pdev), sizeof(info->bus_info));
}

static const struct ethtool_ops mtsx_ethtool_ops = {
	.get_drvinfo	= mtsx_get_drvinfo,
	.get_link	= ethtool_op_get_link,
};

static const struct net_device_ops mtsx_netdev_ops = {
	.ndo_open		= mtsx_open,
	.ndo_stop		= mtsx_stop,
	.ndo_start_xmit		= mtsx_xmit,
	.ndo_tx_timeout		= mtsx_tx_timeout,
	.ndo_validate_addr	= eth_validate_addr,
};

/* ---------------------------------------------------------------------- */
/* PCI                                                                      */
/* ---------------------------------------------------------------------- */

static int mtsx_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct net_device *ndev;
	struct mtsx_priv *mp;
	u32 hi, lo;
	u8 mac[ETH_ALEN];
	int ret;

	ret = pci_enable_device_mem(pdev);
	if (ret)
		return ret;
	ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
	if (ret)
		goto err_disable;

	ndev = alloc_etherdev(sizeof(*mp));
	if (!ndev) {
		ret = -ENOMEM;
		goto err_disable;
	}
	SET_NETDEV_DEV(ndev, &pdev->dev);
	mp = netdev_priv(ndev);
	mp->pdev = pdev;
	mp->ndev = ndev;
	spin_lock_init(&mp->lock);
	spin_lock_init(&mp->mdio_lock);
	pci_set_drvdata(pdev, mp);

	mp->regs = pci_iomap(pdev, 0, pci_resource_len(pdev, 0));
	if (!mp->regs) {
		ret = -ENOMEM;
		goto err_free;
	}

	mp->used = clamp(tx_used, 128u, MTSX_HW_RING);
	mp->period_up = ns_to_ktime((u64)clamp(poll_us, 100u, 10000u) * NSEC_PER_USEC);
	mp->period_down = ns_to_ktime(10 * NSEC_PER_MSEC);
	mp->period = mp->period_down;

	/* The address Orbis programmed: bytes 0-1 in 0x14, bytes 2-5 in 0x18. */
	hi = readl(mp->regs + R_MAC_HI);
	lo = readl(mp->regs + R_MAC_LO);
	mac[0] = hi >> 8;
	mac[1] = hi;
	mac[2] = lo >> 24;
	mac[3] = lo >> 16;
	mac[4] = lo >> 8;
	mac[5] = lo;
	if (is_valid_ether_addr(mac)) {
		eth_hw_addr_set(ndev, mac);
	} else {
		eth_hw_addr_random(ndev);
		dev_warn(&pdev->dev, "no valid MAC address in 0x14/0x18 (%08x %08x), using a random one\n",
			 hi, lo);
	}

	ndev->netdev_ops = &mtsx_netdev_ops;
	ndev->ethtool_ops = &mtsx_ethtool_ops;
	ndev->watchdog_timeo = 5 * HZ;
	ndev->min_mtu = ETH_MIN_MTU;
	ndev->max_mtu = ETH_DATA_LEN;	/* 14 + 1500 fits the 0x600 RX buffer */
	netif_napi_add(ndev, &mp->napi, mtsx_poll);
	hrtimer_setup(&mp->timer, mtsx_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_SOFT);
	netif_carrier_off(ndev);

	ret = register_netdev(ndev);
	if (ret)
		goto err_unmap;

	/* Nothing has been written to the hardware yet: only reads above and below. */
	mtsx_dump_state(mp, "probed");
	netdev_info(ndev, "v%s, tx_used=%u: bring it up to publish the DMA generation (one per boot)\n",
		    DRV_VERSION, mp->used);
	return 0;

err_unmap:
	netif_napi_del(&mp->napi);
	pci_iounmap(pdev, mp->regs);
err_free:
	free_netdev(ndev);
err_disable:
	pci_disable_device(pdev);
	return ret;
}

static void mtsx_remove(struct pci_dev *pdev)
{
	struct mtsx_priv *mp = pci_get_drvdata(pdev);

	/*
	 * Unreachable once published: the module holds a reference and sysfs unbind is
	 * suppressed. If it ever happens anyway, freeing memory the MAC still DMAs into
	 * would be worse than leaking it.
	 */
	if (mp->published) {
		dev_err(&pdev->dev, "remove after publishing the DMA generation; leaking it on purpose\n");
		return;
	}
	unregister_netdev(mp->ndev);
	netif_napi_del(&mp->napi);
	pci_iounmap(pdev, mp->regs);
	free_netdev(mp->ndev);
	pci_disable_device(pdev);
}

/* The first three steps of the firmware's mac_stop (F7); memory is not touched. */
static void mtsx_shutdown(struct pci_dev *pdev)
{
	struct mtsx_priv *mp = pci_get_drvdata(pdev);
	u32 v;

	if (!mp || !mp->published)
		return;
	writel(IMR_STOPPED, mp->regs + R_IMR);
	writel(CTL_RESET, mp->regs + R_TXCTL);
	readl_poll_timeout_atomic(mp->regs + R_TXCTL, v, !(v & CTL_RESET), 1, 100000);
	writel(CTL_RESET, mp->regs + R_RXCTL);
	readl_poll_timeout_atomic(mp->regs + R_RXCTL, v, !(v & CTL_RESET), 1, 100000);
	pci_clear_master(pdev);
}

/* No MODULE_DEVICE_TABLE on purpose: nothing may load this module by itself. */
static const struct pci_device_id mtsx_ids[] = {
	{ PCI_DEVICE(GBE_VENDOR, GBE_DEVICE) },
	{ }
};

static struct pci_driver mtsx_driver = {
	.name		= DRV_NAME,
	.id_table	= mtsx_ids,
	.probe		= mtsx_probe,
	.remove		= mtsx_remove,
	.shutdown	= mtsx_shutdown,
	.driver.suppress_bind_attrs = true,
};
module_pci_driver(mtsx_driver);

MODULE_DESCRIPTION("Baikal gigabit Ethernet MAC (104d:90d8), polled mode, adopts the state Orbis left");
MODULE_LICENSE("GPL");
MODULE_VERSION(DRV_VERSION);
