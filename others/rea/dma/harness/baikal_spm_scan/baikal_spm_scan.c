// SPDX-License-Identifier: GPL-2.0
/*
 * baikal_spm_scan - READ-ONLY map of the SPM/DDR3 as the DMAC sees it.
 *
 * Reads the SPM through the baikal-dmac dmaengine channel, 1 MiB at a time,
 * starting at the address the DMAC sees the SPM at (0xC0000000), and prints
 * runs of 1 MiB blocks that behave the same way:
 *   ZERO    all bytes 0x00
 *   FF      all bytes 0xFF (what a PCI read of nothing returns)
 *   DATA    anything else (live data: something may be using that memory)
 *   ERROR   the DMAC reported an error (INT_FLAG) and aborted the transfer
 *   NOWRITE the transfer "completed" but the poisoned buffer was not touched
 *
 * Nothing is written to the SPM. The buffer is poisoned with 0xA5 before each
 * read so a transfer that did not run cannot pass for zeros.
 * The scan stops probing block by block after a few errors in a row and
 * samples sparsely instead, so an unmapped region costs a handful of resets.
 *
 * Needs baikal_dmac loaded. If baikal-memory holds DMAC1, release it first
 * (echo 0 > /sys/bus/pci/devices/0000:00:14.6/dma/use_dma) so this gets DMAC1.
 */
#include <linux/module.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/completion.h>
#include <linux/pci.h>
#include <linux/sizes.h>
#include <linux/string.h>
#include <linux/crc32.h>

static unsigned long base = 0xC0000000UL;
module_param(base, ulong, 0444);
MODULE_PARM_DESC(base, "address the DMAC sees the SPM at (default 0xC0000000)");

static unsigned int mb = 1024;
module_param(mb, uint, 0444);
MODULE_PARM_DESC(mb, "how many MiB to scan (default 1024)");

static bool cpu_probe = true;
module_param(cpu_probe, bool, 0444);
MODULE_PARM_DESC(cpu_probe, "also read 4 KiB through the BAR2 (CPU) at sample blocks and compare with DMA");

static bool wtest;
module_param(wtest, bool, 0444);
MODULE_PARM_DESC(wtest, "write/readback/restore 4 KiB through DMA at blocks below WTEST_MAX_BLK (default off)");

/* Hard limit for the write test: the scan saw zeros only below block 188 */
#define WTEST_MAX_BLK	187

#define BLK		SZ_1M
#define ERR_STOP	6	/* consecutive errors before sampling sparsely */
#define SPARSE_STEP	32	/* MiB between samples once the errors start */

struct xctx {
	struct completion done;
	enum dmaengine_tx_result res;
};

static bool filt(struct dma_chan *c, void *p)
{
	struct device *d = c->device->dev;
	struct pci_dev *pdev;

	if (!d || !dev_is_pci(d))
		return false;
	pdev = to_pci_dev(d);
	return pdev->vendor == 0x104d && pdev->device == 0x90dc;
}

static void xcb(void *p, const struct dmaengine_result *r)
{
	struct xctx *c = p;

	c->res = r ? r->result : DMA_TRANS_NOERROR;
	complete(&c->done);
}

static int xfer(struct dma_chan *ch, dma_addr_t dst, dma_addr_t src, size_t len)
{
	struct dma_async_tx_descriptor *tx;
	struct xctx c;
	dma_cookie_t ck;

	init_completion(&c.done);
	c.res = DMA_TRANS_NOERROR;
	tx = dmaengine_prep_dma_memcpy(ch, dst, src, len, DMA_CTRL_ACK | DMA_PREP_INTERRUPT);
	if (!tx)
		return -EIO;
	tx->callback_result = xcb;
	tx->callback_param = &c;
	ck = dmaengine_submit(tx);
	if (dma_submit_error(ck))
		return -EIO;
	dma_async_issue_pending(ch);
	if (!wait_for_completion_timeout(&c.done, msecs_to_jiffies(3000))) {
		dmaengine_terminate_sync(ch);
		return -ETIMEDOUT;
	}
	return c.res == DMA_TRANS_NOERROR ? 0 : -EIO;
}

enum { C_ZERO, C_FF, C_DATA, C_ERROR, C_NOWRITE, C_TIMEOUT };
static const char *const cname[] = { "ZERO", "FF", "DATA", "ERROR", "NOWRITE", "TIMEOUT" };

static int classify(const u8 *buf, int rc)
{
	if (rc == -ETIMEDOUT)
		return C_TIMEOUT;
	if (rc)
		return C_ERROR;
	if (!memchr_inv(buf, 0xA5, BLK))
		return C_NOWRITE;
	if (!memchr_inv(buf, 0x00, BLK))
		return C_ZERO;
	if (!memchr_inv(buf, 0xFF, BLK))
		return C_FF;
	return C_DATA;
}

static struct dma_chan *chan;
static void *buf;
static dma_addr_t buf_dma;

/* per-block fingerprint, to tell distinct memory from an address that wraps around */
#define MAXB	2048
static u32 b_crc[MAXB];
static u32 b_zero[MAXB];
static u32 b_ff[MAXB];
static u8 b_ok[MAXB];

static void fingerprint(unsigned int i)
{
	const u8 *p = buf;
	u32 z = 0, f = 0, k;

	for (k = 0; k < BLK; k++) {
		z += p[k] == 0x00;
		f += p[k] == 0xFF;
	}
	b_crc[i] = crc32_le(0, buf, BLK);
	b_zero[i] = z;
	b_ff[i] = f;
	b_ok[i] = 1;
}

static void print_block(unsigned int i)
{
	if (i >= MAXB || !b_ok[i])
		return;
	pr_info("spm_scan: block %4u  crc=%08x  zero=%6u  ff=%6u  of %u bytes", i, b_crc[i],
		b_zero[i], b_ff[i], BLK);
}

static void flush_run(int cls, unsigned int from, unsigned int to, u64 first8)
{
	if (cls < 0)
		return;
	pr_info("spm_scan: %4u-%4u MiB  %-7s (%u MiB)", from, to, cname[cls], to - from + 1);
	if (cls == C_DATA)
		pr_info("spm_scan:        first 8 bytes of the first block: %016llx", first8);
}

static const char *cls4k(const u8 *p, bool *poison)
{
	*poison = !memchr_inv(p, 0xA5, SZ_4K);
	if (!memchr_inv(p, 0x00, SZ_4K))
		return "zero";
	if (!memchr_inv(p, 0xFF, SZ_4K))
		return "FF";
	return "data";
}

/* CPU read (through BAR2) against DMA read of the same 4 KiB, at a few blocks */
static void cpu_vs_dma(void)
{
	static const unsigned int smp[] = { 0, 100, 187, 188, 189, 200, 255, 256, 257, 512, 1023 };
	struct pci_dev *spm = pci_get_device(0x104d, 0x90dd, NULL);
	u8 *cpu_copy = kmalloc(SZ_4K, GFP_KERNEL);
	resource_size_t start;
	unsigned int s;

	if (!spm || !cpu_copy) {
		pr_info("spm_scan: cpu_probe skipped (no SPM device or no memory)\n");
		goto out;
	}
	start = pci_resource_start(spm, 2);
	pr_info("spm_scan: BAR2 of 00:14.6 at %pa, size %llu MiB\n", &start,
		(unsigned long long)(pci_resource_len(spm, 2) >> 20));
	for (s = 0; s < ARRAY_SIZE(smp); s++) {
		void __iomem *m;
		bool pc, pd;
		const char *c, *d;
		int rc;

		if ((u64)smp[s] << 20 >= pci_resource_len(spm, 2))
			continue;
		m = ioremap(start + ((u64)smp[s] << 20), SZ_4K);
		if (!m)
			continue;
		memcpy_fromio(cpu_copy, m, SZ_4K);
		iounmap(m);
		c = cls4k(cpu_copy, &pc);
		memset(buf, 0xA5, SZ_4K);
		rc = xfer(chan, buf_dma, (dma_addr_t)(base + ((unsigned long)smp[s] << 20)), SZ_4K);
		d = rc ? "ERROR" : cls4k(buf, &pd);
		pr_info("spm_scan: block %4u  4 KiB at its start: CPU=%-4s DMA=%-5s%s", smp[s], c, d,
			(!rc && !strcmp(c, d)) ? "" : "   <-- views differ");
	}
out:
	kfree(cpu_copy);
	if (spm)
		pci_dev_put(spm);
}

/*
 * Write a random 4 KiB pattern through DMA at the start and at the end of a few blocks, read it back
 * through DMA, then restore zeros. Only blocks below WTEST_MAX_BLK, and only if the 4 KiB was zero.
 */
static void write_test(void)
{
	static const unsigned int blks[] = { 4, 16, 64, 100, 150, 180, 186, 187 };
	u8 *pat = buf, *rb = buf + SZ_8K, *zr = buf + SZ_16K;
	unsigned int s, e;
	int ok = 0, bad = 0;

	memset(zr, 0, SZ_4K);
	get_random_bytes(pat, SZ_4K);
	for (s = 0; s < ARRAY_SIZE(blks); s++) {
		for (e = 0; e < 2; e++) {
			unsigned long off = ((unsigned long)blks[s] << 20) + (e ? BLK - SZ_4K : 0);
			dma_addr_t spm = (dma_addr_t)(base + off);
			bool same = false, was_zero;
			int r1, r2, r3;

			if (blks[s] > WTEST_MAX_BLK)
				continue;
			memset(rb, 0xA5, SZ_4K);
			r1 = xfer(chan, buf_dma + SZ_8K, spm, SZ_4K);		/* read before */
			was_zero = !r1 && !memchr_inv(rb, 0x00, SZ_4K);
			if (!was_zero) {
				pr_info("spm_scan: wtest block %4u %s: not zero before (rc=%d), skipped\n",
					blks[s], e ? "end  " : "start", r1);
				continue;
			}
			r1 = xfer(chan, spm, buf_dma, SZ_4K);			/* write pattern */
			memset(rb, 0xA5, SZ_4K);
			r2 = xfer(chan, buf_dma + SZ_8K, spm, SZ_4K);		/* read back */
			same = !r1 && !r2 && !memcmp(pat, rb, SZ_4K);
			r3 = xfer(chan, spm, buf_dma + SZ_16K, SZ_4K);		/* restore zeros */
			memset(rb, 0xA5, SZ_4K);
			r3 |= xfer(chan, buf_dma + SZ_8K, spm, SZ_4K);
			pr_info("spm_scan: wtest block %4u %s: write+readback %s; restored to zero: %s (rc %d/%d/%d)\n",
				blks[s], e ? "end  " : "start", same ? "OK  " : "FAIL",
				(!r3 && !memchr_inv(rb, 0x00, SZ_4K)) ? "yes" : "NO", r1, r2, r3);
			same ? ok++ : bad++;
		}
	}
	pr_info("spm_scan: wtest summary: %d OK, %d FAIL\n", ok, bad);
}

static int __init spm_scan_init(void)
{
	unsigned int i, step, errs = 0;
	int cls, run_cls = -1;
	unsigned int run_from = 0, run_to = 0;
	u64 run_first8 = 0;
	dma_cap_mask_t mask;
	int counts[6] = { 0 };

	dma_cap_zero(mask);
	dma_cap_set(DMA_MEMCPY, mask);
	chan = dma_request_channel(mask, filt, NULL);
	if (!chan) {
		pr_err("spm_scan: no baikal-dmac channel free (release baikal-memory's first)\n");
		return -ENODEV;
	}
	buf = dma_alloc_coherent(chan->device->dev, BLK, &buf_dma, GFP_KERNEL);
	if (!buf || upper_32_bits(buf_dma + BLK)) {
		pr_err("spm_scan: coherent buffer unavailable or above 4 GiB\n");
		if (buf)
			dma_free_coherent(chan->device->dev, BLK, buf, buf_dma);
		dma_release_channel(chan);
		return -ENOMEM;
	}
	pr_info("spm_scan: channel %s, base 0x%lx, %u MiB, read-only\n",
		dma_chan_name(chan), base, mb);

	for (i = 0; i < mb; i += step) {
		int rc;

		step = errs >= ERR_STOP ? SPARSE_STEP : 1;
		memset(buf, 0xA5, BLK);
		rc = xfer(chan, buf_dma, (dma_addr_t)(base + ((unsigned long)i << 20)), BLK);
		cls = classify(buf, rc);
		counts[cls]++;
		if (i < MAXB && !rc)
			fingerprint(i);
		errs = (cls == C_ERROR || cls == C_TIMEOUT) ? errs + 1 : 0;

		if (cls != run_cls) {
			flush_run(run_cls, run_from, run_to, run_first8);
			run_cls = cls;
			run_from = i;
			run_first8 = cls == C_DATA ? *(u64 *)buf : 0;
		}
		run_to = i + step - 1;
	}
	flush_run(run_cls, run_from, run_to, run_first8);
	pr_info("spm_scan: summary ZERO=%d FF=%d DATA=%d ERROR=%d NOWRITE=%d TIMEOUT=%d (blocks probed)\n",
		counts[C_ZERO], counts[C_FF], counts[C_DATA], counts[C_ERROR],
		counts[C_NOWRITE], counts[C_TIMEOUT]);

	/* sample blocks around the interesting boundaries */
	{
		static const unsigned int smp[] = { 0, 187, 188, 189, 255, 256, 257, 443, 444,
						    511, 512, 513, 767, 768, 1022, 1023 };
		unsigned int s, j, n_ok = 0, n_uniq = 0, n_alias = 0, n_cmp = 0;

		for (s = 0; s < ARRAY_SIZE(smp); s++)
			print_block(smp[s]);

		/* distinct fingerprints, and how many blocks equal the one 256 MiB earlier */
		for (i = 0; i < mb && i < MAXB; i++) {
			bool seen = false;

			if (!b_ok[i])
				continue;
			n_ok++;
			for (j = 0; j < i; j++)
				if (b_ok[j] && b_crc[j] == b_crc[i]) {
					seen = true;
					break;
				}
			if (!seen)
				n_uniq++;
			if (i >= 256 && b_ok[i - 256]) {
				n_cmp++;
				if (b_crc[i] == b_crc[i - 256])
					n_alias++;
			}
		}
		pr_info("spm_scan: %u blocks fingerprinted, %u distinct CRCs; blocks equal to the one 256 MiB earlier: %u of %u compared\n",
			n_ok, n_uniq, n_alias, n_cmp);
	}
	if (cpu_probe)
		cpu_vs_dma();
	if (wtest)
		write_test();
	return 0;
}

static void __exit spm_scan_exit(void)
{
	if (buf)
		dma_free_coherent(chan->device->dev, BLK, buf, buf_dma);
	if (chan)
		dma_release_channel(chan);
}

module_init(spm_scan_init);
module_exit(spm_scan_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Read-only DMA map of the Baikal SPM/DDR3");
