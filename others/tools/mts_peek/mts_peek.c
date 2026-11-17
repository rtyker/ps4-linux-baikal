// SPDX-License-Identifier: GPL-2.0
/*
 * mts_peek - look at the Baikal gigabit Ethernet (PCI 104d:90d8) the way the
 * previous boot stage (Orbis) left it, and optionally clear the one PHY bit
 * that blocks the link after a kexec.
 *
 * Why this exists: PLAN_ETH0_BAIKAL.md (others/docs). Every access below follows
 * a routine of the Orbis 12.52 GBE driver that was decompiled and checked; the
 * evidence is in others/rea/ethernet/decompiled/rea_20261117/.
 *
 * What it touches:
 *   - PCI config: reads COMMAND; pci_enable_device_mem() may set the memory
 *     decode bit if it is clear. It never sets bus mastering and never touches
 *     MSI/INTx, so the device cannot start DMA because of this module.
 *   - BAR0 reads of a fixed list of offsets. The clear-on-read counters
 *     (0x100-0x12c) are not in the list.
 *   - BAR0+0x00 (MDIO command/data) writes, which is how any MDIO read is
 *     done. These are the same command words the firmware uses (F1-F4).
 *   - ONE PHY register write (Clause 45 0x0147.1e, clear bit 4), only with
 *     clear_residue=1 and only when every gate below passes.
 *   It does not touch the glue block (no hold/pulse), the ICC, the rings, the
 *   MAC enable registers or the interrupt mask.
 *
 * It has no MODULE_DEVICE_TABLE, so nothing loads it automatically, and it
 * refuses to run if another driver is bound to the device.
 *
 * Output: lines starting with "mts_peek:" in dmesg. Load it once per boot.
 */

#define pr_fmt(fmt) "mts_peek: " fmt

#include <linux/delay.h>
#include <linux/iopoll.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/sched/signal.h>

#define DRV_VERSION		"0.1"

#define GBE_VENDOR		0x104d
#define GBE_DEVICE		0x90d8

/* BAR0 registers. Names only where the firmware routines confirm the use. */
#define R_MDIO			0x00	/* MDIO command (low half) / data (high half) */
#define R_LINK			0x04	/* bit 0: link up, read by gbe_phy_ctrl */
#define R_MAC_EN1		0x34	/* MAC core 1 enable, bit 0 (mac_enable) */
#define R_MAC_EN2		0x38	/* MAC core 2 enable, bit 0 (mac_enable) */
#define R_IMR			0x54	/* a set bit MASKS its source (mac_stop) */

#define MDIO_DONE		BIT(15)
#define MDIO_POLL_US		10000	/* the firmware polls 10000 x DELAY(1) */

/* mac_stop writes this to the IMR; every bit set means "masked". */
#define IMR_ALL_MASKED		0x007ffffa

/* PHY identity both reference projects report for this console family. */
#define PHY_ID1_EXPECTED	0x03a2
#define PHY_ID2_EXPECTED	0x9441

/* Clause 45 location of the shutdown residue (Orbis writes 0x0010 there). */
#define RESIDUE_DEVAD		0x1e
#define RESIDUE_REG		0x0147
#define RESIDUE_BIT		0x0010	/* plain int on purpose: the register is 16 bits */

static bool clear_residue;
module_param(clear_residue, bool, 0444);
MODULE_PARM_DESC(clear_residue,
		 "Clear bit 4 of Clause 45 0x0147.1e once, if all safety gates pass (default 0 = read only)");

static unsigned int watch_s;
module_param(watch_s, uint, 0444);
MODULE_PARM_DESC(watch_s,
		 "After the reads, keep sampling BMSR and BAR0+0x04 for this many seconds, printing changes (default 0, max 600)");

static struct pci_dev *gbe;
static void __iomem *bar0;
static bool device_enabled;

/* ---------------------------------------------------------------------- */
/* MDIO, exactly as the firmware does it (dc5a24d0, dc5a2680, dc5a2840,     */
/* dc5a2950): write 0x8000 to clear DONE, write the command, wait for bit   */
/* 15 of the low half to become 1.                                          */
/* ---------------------------------------------------------------------- */

static int mdio_cmd(u32 cmd)
{
	u32 v;

	writel(MDIO_DONE, bar0 + R_MDIO);
	writel(cmd, bar0 + R_MDIO);
	return readl_poll_timeout_atomic(bar0 + R_MDIO, v, v & MDIO_DONE, 1,
					 MDIO_POLL_US);
}

static int c22_read(u8 reg, u16 *val)
{
	int ret = mdio_cmd(((u32)(reg & 0x1f) << 8) | 0x4000);

	if (ret)
		return ret;
	*val = readl(bar0 + R_MDIO) >> 16;
	return 0;
}

static int c45_addr_phase(u8 devad, u16 reg)
{
	return mdio_cmd(((u32)reg << 16) | ((u32)(devad & 0x1f) << 8) | 0x20);
}

static int c45_read(u8 devad, u16 reg, u16 *val)
{
	int ret = c45_addr_phase(devad, reg);

	if (ret)
		return ret;
	ret = mdio_cmd(((u32)(devad & 0x1f) << 8) | 0xe0);
	if (ret)
		return ret;
	*val = readl(bar0 + R_MDIO) >> 16;
	return 0;
}

static int c45_write(u8 devad, u16 reg, u16 val)
{
	int ret = c45_addr_phase(devad, reg);

	if (ret)
		return ret;
	return mdio_cmd(((u32)(devad & 0x1f) << 8) | ((u32)val << 16) | 0x60);
}

/* ---------------------------------------------------------------------- */
/* Dumps                                                                   */
/* ---------------------------------------------------------------------- */

static void dump_bar0(const char *when)
{
	static const u16 offs[] = {
		0x00, 0x04, 0x08, 0x0c, 0x10, 0x14, 0x18, 0x30, 0x34, 0x38,
		0x3c, 0x40, 0x44, 0x48, 0x50, 0x54, 0x5c, 0x74, 0x7c, 0xac,
	};
	unsigned int i;

	pr_info("BAR0 %s:\n", when);
	for (i = 0; i < ARRAY_SIZE(offs); i++)
		pr_info("  +0x%03x = 0x%08x\n", offs[i], readl(bar0 + offs[i]));
}

static void print_c22(u8 reg, const char *name)
{
	u16 v;
	int ret = c22_read(reg, &v);

	if (ret)
		pr_info("  C22 reg %2u %-7s = ---- (error %d)\n", reg, name, ret);
	else
		pr_info("  C22 reg %2u %-7s = 0x%04x\n", reg, name, v);
}

static void print_c45(u8 devad, u16 reg)
{
	u16 v;
	int ret = c45_read(devad, reg, &v);

	if (ret)
		pr_info("  C45 %04x.%02x = ---- (error %d)\n", reg, devad, ret);
	else
		pr_info("  C45 %04x.%02x = 0x%04x\n", reg, devad, v);
}

static void dump_phy(void)
{
	static const struct {
		u8 devad;
		u16 reg;
	} c45[] = {
		{ 0x1e, 0x0147 },	/* the residue */
		{ 0x1e, 0x00a2 },	/* read twice by gbe_phy_ctrl */
		{ 0x1e, 0x0033 },
		{ 0x1e, 0x0037 },
		{ 0x1e, 0x0039 },
		{ 0x1e, 0x0096 },
		{ 0x1f, 0x0107 },
		{ 0x1e, 0x0171 },
	};
	unsigned int i;

	pr_info("PHY, Clause 22 (BMSR is read twice: the link bit latches low):\n");
	print_c22(0, "BMCR");
	print_c22(1, "BMSR");
	print_c22(1, "BMSR");
	print_c22(2, "PHYID1");
	print_c22(3, "PHYID2");
	print_c22(4, "ANAR");
	print_c22(5, "ANLPAR");
	print_c22(9, "GBCR");

	pr_info("PHY, Clause 45:\n");
	for (i = 0; i < ARRAY_SIZE(c45); i++)
		print_c45(c45[i].devad, c45[i].reg);
}

/* ---------------------------------------------------------------------- */
/* Residue clear                                                            */
/* ---------------------------------------------------------------------- */

/* One line: time since the write, BMSR (latched, then current), BAR0+0x04. */
static void sample(ktime_t t0, const char *tag)
{
	char first[8] = "----", second[8] = "----";
	u16 b1 = 0, b2 = 0;
	bool ok1 = !c22_read(1, &b1);
	bool ok2 = !c22_read(1, &b2);
	u32 link = readl(bar0 + R_LINK);

	if (ok1)
		snprintf(first, sizeof(first), "%04x", b1);
	if (ok2)
		snprintf(second, sizeof(second), "%04x", b2);

	pr_info("  %-10s t+%4lldms BMSR %s/%s (link bit %c)  0x04 = 0x%08x (link bit %u)\n",
		tag, ktime_to_ms(ktime_sub(ktime_get(), t0)), first, second,
		ok2 ? ((b2 & BIT(2)) ? '1' : '0') : '?', link, link & 1);
}

/* Every gate must pass before the single PHY write. Returns true if it may go. */
static bool residue_gates_ok(u16 *cur)
{
	u16 id1 = 0, id2 = 0;
	u32 en1 = readl(bar0 + R_MAC_EN1), en2 = readl(bar0 + R_MAC_EN2);
	u32 imr = readl(bar0 + R_IMR);
	bool ok = true;
	int r;

	r = c22_read(2, &id1);
	if (!r)
		r = c22_read(3, &id2);
	if (r || id1 != PHY_ID1_EXPECTED || id2 != PHY_ID2_EXPECTED) {
		pr_info("gate phy_id: FAIL (read %s, got %04x/%04x, want %04x/%04x)\n",
			r ? "failed" : "ok", id1, id2, PHY_ID1_EXPECTED, PHY_ID2_EXPECTED);
		ok = false;
	} else {
		pr_info("gate phy_id: ok (%04x/%04x)\n", id1, id2);
	}

	if ((en1 & 1) || (en2 & 1)) {
		pr_info("gate mac_stopped: FAIL (0x34=0x%08x 0x38=0x%08x)\n", en1, en2);
		ok = false;
	} else {
		pr_info("gate mac_stopped: ok\n");
	}

	if ((imr & IMR_ALL_MASKED) != IMR_ALL_MASKED) {
		pr_info("gate irq_masked: FAIL (IMR=0x%08x, want bits 0x%08x set)\n",
			imr, IMR_ALL_MASKED);
		ok = false;
	} else {
		pr_info("gate irq_masked: ok (IMR=0x%08x)\n", imr);
	}

	r = c45_read(RESIDUE_DEVAD, RESIDUE_REG, cur);
	if (r) {
		pr_info("gate residue_read: FAIL (error %d)\n", r);
		ok = false;
	} else if (!(*cur & RESIDUE_BIT)) {
		pr_info("gate residue_set: bit 4 is already clear (0x%04x), nothing to do\n", *cur);
		ok = false;
	} else {
		pr_info("gate residue_set: ok (0x%04x)\n", *cur);
	}
	return ok;
}

static void do_clear_residue(void)
{
	static const unsigned int sample_ms[] = { 1, 10, 50, 100, 500, 1000 };
	u16 cur = 0, after = 0;
	unsigned int i;
	ktime_t t0;
	char tag[16];
	int r;

	pr_info("clear_residue=1: checking the gates\n");
	if (!residue_gates_ok(&cur)) {
		pr_info("no write was done\n");
		return;
	}

	t0 = ktime_get();
	r = c45_write(RESIDUE_DEVAD, RESIDUE_REG, cur & ~RESIDUE_BIT);
	pr_info("WROTE C45 %04x.%02x = 0x%04x (was 0x%04x), result %d\n",
		RESIDUE_REG, RESIDUE_DEVAD, cur & ~RESIDUE_BIT, cur, r);
	if (r)
		return;

	r = c45_read(RESIDUE_DEVAD, RESIDUE_REG, &after);
	pr_info("read back C45 %04x.%02x = 0x%04x (%s)\n", RESIDUE_REG, RESIDUE_DEVAD, after,
		r ? "read failed" : ((after & RESIDUE_BIT) ? "BIT STILL SET" : "bit 4 clear"));

	for (i = 0; i < ARRAY_SIZE(sample_ms); i++) {
		s64 elapsed = ktime_to_ms(ktime_sub(ktime_get(), t0));

		if (sample_ms[i] > elapsed)
			msleep(sample_ms[i] - elapsed);
		snprintf(tag, sizeof(tag), "after-%u", sample_ms[i]);
		sample(t0, tag);
	}
}

static void do_watch(void)
{
	ktime_t t0 = ktime_get();
	u32 last_link = ~0u;
	int last_bmsr = -1;
	unsigned int secs = min_t(unsigned int, watch_s, 600);
	s64 end_ms = (s64)secs * 1000;

	pr_info("watching BMSR and BAR0+0x04 for %u s (only changes are printed)\n", secs);
	while (ktime_to_ms(ktime_sub(ktime_get(), t0)) < end_ms) {
		u16 b = 0;
		u32 link = readl(bar0 + R_LINK);
		int r;

		/* The first read returns the latched value, the second the current one. */
		c22_read(1, &b);
		r = c22_read(1, &b);
		if (!r && (int)b != last_bmsr) {
			pr_info("  t+%5lldms BMSR = 0x%04x (link bit %u)\n",
				ktime_to_ms(ktime_sub(ktime_get(), t0)), b, (b >> 2) & 1);
			last_bmsr = b;
		}
		if (link != last_link) {
			pr_info("  t+%5lldms 0x04 = 0x%08x (link bit %u)\n",
				ktime_to_ms(ktime_sub(ktime_get(), t0)), link, link & 1);
			last_link = link;
		}
		if (msleep_interruptible(100) || signal_pending(current)) {
			pr_info("watch interrupted\n");
			break;
		}
	}
}

/* ---------------------------------------------------------------------- */
/* Module                                                                   */
/* ---------------------------------------------------------------------- */

static int __init mts_peek_init(void)
{
	u16 cmd_before = 0, cmd_after = 0;
	int ret;

	pr_info("v%s, clear_residue=%d watch_s=%u\n", DRV_VERSION, clear_residue, watch_s);

	gbe = pci_get_device(GBE_VENDOR, GBE_DEVICE, NULL);
	if (!gbe) {
		pr_err("no PCI device %04x:%04x\n", GBE_VENDOR, GBE_DEVICE);
		return -ENODEV;
	}
	if (gbe->driver) {
		pr_err("%s is bound to driver %s, refusing to touch it\n",
		       pci_name(gbe), gbe->driver->name);
		ret = -EBUSY;
		goto put;
	}

	pci_read_config_word(gbe, PCI_COMMAND, &cmd_before);
	ret = pci_enable_device_mem(gbe);
	if (ret) {
		pr_err("pci_enable_device_mem failed: %d\n", ret);
		goto put;
	}
	device_enabled = true;
	pci_read_config_word(gbe, PCI_COMMAND, &cmd_after);
	pr_info("%s PCI COMMAND 0x%04x -> 0x%04x (memory decode %s, bus master %s)\n",
		pci_name(gbe), cmd_before, cmd_after,
		(cmd_after & PCI_COMMAND_MEMORY) ? "on" : "OFF",
		(cmd_after & PCI_COMMAND_MASTER) ? "ON (inherited)" : "off");

	bar0 = pci_iomap(gbe, 0, pci_resource_len(gbe, 0));
	if (!bar0) {
		pr_err("cannot map BAR0\n");
		ret = -ENOMEM;
		goto disable;
	}
	pr_info("BAR0 %pR\n", &gbe->resource[0]);

	dump_bar0("before any MDIO access");
	dump_phy();
	dump_bar0("after the MDIO reads");

	if (clear_residue)
		do_clear_residue();
	if (watch_s)
		do_watch();

	pr_info("done\n");
	return 0;

disable:
	pci_disable_device(gbe);
	device_enabled = false;
put:
	pci_dev_put(gbe);
	gbe = NULL;
	return ret;
}

static void __exit mts_peek_exit(void)
{
	bool mac_running;

	if (!gbe)
		return;
	mac_running = (readl(bar0 + R_MAC_EN1) | readl(bar0 + R_MAC_EN2)) & 1;
	pci_iounmap(gbe, bar0);
	/* pci_disable_device() clears bus mastering; never do that to a running MAC. */
	if (device_enabled && !mac_running)
		pci_disable_device(gbe);
	pci_dev_put(gbe);
	pr_info("unloaded\n");
}

module_init(mts_peek_init);
module_exit(mts_peek_exit);

MODULE_DESCRIPTION("Read-only diagnostic for the Baikal GBE (104d:90d8), optional shutdown-residue clear");
MODULE_LICENSE("GPL");
MODULE_VERSION(DRV_VERSION);
