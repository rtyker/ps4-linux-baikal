/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Descriptor words and ring arithmetic of the Baikal gigabit MAC.
 *
 * Every rule below comes from the Orbis 12.52 driver (decompiled with REA; see
 * F9, F10 and F14-F16 in others/docs/PLAN_ETH0_BAIKAL.md) and agrees with the
 * measurements of an independent implementation (Gcsman110, ps4-mts-linux-driver).
 *
 * The functions work on host-endian u32 words, so test_desc.c can run them on
 * the host. The driver converts at the memory edge with cpu_to_le32/le32_to_cpu.
 * The includer provides u32 and bool.
 */
#ifndef MTSX_DESC_H
#define MTSX_DESC_H

#define MTSX_HW_RING		256u		/* descriptors per ring */
#define MTSX_RING_BYTES		4096u		/* 256 descriptors of 4 words */
#define MTSX_DESC_WORDS		4u

/* word0 */
#define MTSX_W0_DRV		0x80000000u	/* bit 31 SET: the driver owns the descriptor */
#define MTSX_W0_WRAP		0x40000000u	/* last descriptor of the ring */
#define MTSX_W0_FIRST		0x20000000u	/* TX: first segment of a frame */
#define MTSX_W0_LAST		0x10000000u	/* TX: last segment of a frame */
#define MTSX_TX_LEN_MASK	0x0000ffffu	/* TX length: 16 bits */
#define MTSX_RX_LEN_MASK	0x000007ffu	/* RX length: 11 bits */
#define MTSX_RX_BUF		0x600u		/* RX buffer size (word0 of an armed one) */

/* word2 of a TX descriptor that holds no frame */
#define MTSX_W2_IDLE		0xffff0000u

/* The firmware accepts a frame only with at least 64 free TX descriptors. */
#define MTSX_TX_MIN_FREE	64u
#define MTSX_TX_WAKE_AT		80u

/* ---- TX (F9, F10, F14) ------------------------------------------------- */

/* A TX descriptor that no frame uses: driver-owned, word2 carries the idle marker. */
static inline void mtsx_tx_idle_image(u32 w[4])
{
	w[0] = MTSX_W0_DRV;
	w[1] = 0;
	w[2] = MTSX_W2_IDLE;
	w[3] = 0;
}

/*
 * A single-segment frame handed to the hardware. word0 has bit 31 CLEAR, so the
 * driver must store words 1-3 first, issue a barrier, and store word0 last:
 * the clear bit 31 is what gives the descriptor away.
 */
static inline void mtsx_tx_image(u32 w[4], u32 dma, u32 len, bool wrap)
{
	w[0] = (len & MTSX_TX_LEN_MASK) | MTSX_W0_FIRST | MTSX_W0_LAST |
	       (wrap ? MTSX_W0_WRAP : 0);
	w[1] = dma;
	w[2] = 0;
	w[3] = 0;
}

/*
 * The hardware has finished with a TX descriptor when it handed bit 31 back and
 * word2 no longer carries the idle marker. Both conditions are the firmware's
 * (dc5a2ce0).
 */
static inline bool mtsx_tx_done(u32 w0, u32 w2)
{
	return (w0 & MTSX_W0_DRV) && (w2 & 0xffff0000u) != MTSX_W2_IDLE;
}

/* What the firmware does to word2 after it processed a completion. */
static inline u32 mtsx_tx_recycled_w2(u32 w2)
{
	return w2 | MTSX_W2_IDLE;
}

/* ---- RX (F9, F15, F16) ------------------------------------------------- */

/*
 * An armed RX descriptor: buffer size in word0, bit 31 clear (the hardware owns
 * it), WRAP on the last one. word1 holds the buffer's DMA address and word2 is 0.
 */
static inline u32 mtsx_rx_arm_w0(unsigned int idx)
{
	return MTSX_RX_BUF | (idx == MTSX_HW_RING - 1 ? MTSX_W0_WRAP : 0);
}

/*
 * A received frame is bit 31 set AND something in the low bits. An idle
 * descriptor is exactly 0x80000000 (dc5a2a50 compares unsigned > 0x80000000).
 */
static inline bool mtsx_rx_ready(u32 w0)
{
	return w0 > MTSX_W0_DRV;
}

static inline u32 mtsx_rx_len(u32 w0)
{
	return w0 & MTSX_RX_LEN_MASK;
}

/* ---- TX ring accounting ------------------------------------------------- */

/*
 * The TX ring uses `used` of the 256 descriptors (255 by default: with 256 the
 * other implementation saw the engine stop on the last descriptor). head and
 * tail are free-running counters; the descriptor index is the counter modulo
 * `used`, and WRAP goes on the last descriptor in use.
 */
static inline unsigned int mtsx_tx_index(u32 counter, unsigned int used)
{
	return counter % used;
}

static inline bool mtsx_tx_wrap(unsigned int idx, unsigned int used)
{
	return idx == used - 1;
}

static inline unsigned int mtsx_tx_free(u32 head, u32 tail, unsigned int used)
{
	return used - (head - tail);
}

#endif /* MTSX_DESC_H */
