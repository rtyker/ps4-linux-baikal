// SPDX-License-Identifier: GPL-2.0
/*
 * Host test for mtsx_desc.h.
 *
 * Part 1 pins the bit patterns to the values the Orbis 12.52 driver produces.
 * Part 2 runs a model of the hardware's ownership protocol against the same
 * helpers, to check ring wrap and free-space arithmetic for 255 and 256 TX
 * descriptors. The model is our reading of the firmware, so Part 2 checks the
 * driver's bookkeeping, not the hardware.
 *
 * Build and run: ./check.sh
 */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef uint32_t u32;

#include "mtsx_desc.h"

/* ---- Part 1: patterns ---------------------------------------------------- */

static void test_patterns(void)
{
	u32 w[4];

	/* F9: an idle TX descriptor is 0x80000000 with word2 |= 0xffff0000 */
	mtsx_tx_idle_image(w);
	assert(w[0] == 0x80000000u && w[2] == 0xffff0000u && w[1] == 0 && w[3] == 0);

	/* F14: one 60-byte frame: len | FIRST | LAST, bit 31 clear, word2 = 0 */
	mtsx_tx_image(w, 0x01234000u, 60, false);
	assert(w[0] == 0x3000003cu);
	assert(w[1] == 0x01234000u && w[2] == 0 && w[3] == 0);
	assert(!(w[0] & MTSX_W0_DRV));

	/* F14: WRAP goes on the last descriptor in use */
	mtsx_tx_image(w, 0x01234000u, 1514, true);
	assert(w[0] == (0x70000000u | 1514u));

	/* the TX length field is 16 bits wide */
	mtsx_tx_image(w, 0, 0x12345, false);
	assert((w[0] & MTSX_TX_LEN_MASK) == 0x2345u);

	/* F9/F15: an armed RX descriptor is the buffer size, bit 31 clear */
	assert(mtsx_rx_arm_w0(0) == 0x600u);
	assert(mtsx_rx_arm_w0(254) == 0x600u);
	assert(mtsx_rx_arm_w0(255) == 0x40000600u);
	assert(!(mtsx_rx_arm_w0(7) & MTSX_W0_DRV));

	/* F16: ready iff word0 > 0x80000000 (unsigned) */
	assert(!mtsx_rx_ready(0x80000000u));		/* idle */
	assert(!mtsx_rx_ready(0x00000600u));		/* armed, hardware owns it */
	assert(!mtsx_rx_ready(0x40000600u));		/* armed with WRAP */
	assert(mtsx_rx_ready(0x80000001u));
	assert(mtsx_rx_ready(0x8000003cu));		/* 60-byte frame */
	assert(mtsx_rx_ready(0xc00005eau));		/* 1514-byte frame with WRAP still set */
	assert(mtsx_rx_len(0x800005eau) == 1514u);
	assert(mtsx_rx_len(0x8001a5eau) == 0x5eau);	/* status bits do not leak into the length */

	/* F10: done = bit 31 set and word2 not the idle marker */
	assert(!mtsx_tx_done(0x80000000u, 0xffff0000u));	/* never used */
	assert(!mtsx_tx_done(0x3000003cu, 0));			/* hardware owns it */
	assert(mtsx_tx_done(0xb000003cu, 0));			/* completed */
	assert(!mtsx_tx_done(0x3000003cu, 0xffff0000u));
	assert(mtsx_tx_recycled_w2(0x00000123u) == 0xffff0123u);
	assert(!mtsx_tx_done(0xb000003cu, mtsx_tx_recycled_w2(0)));	/* recycled: not done again */
}

/* ---- Part 2: ownership model --------------------------------------------- */

struct ring {
	u32 d[MTSX_HW_RING][4];
};

/* Hardware TX engine: consumes descriptors the driver gave it, in ring order. */
static unsigned int hw_tx_consume(struct ring *tx, unsigned int *cur, unsigned int max)
{
	unsigned int n = 0;

	while (n < max && !(tx->d[*cur][0] & MTSX_W0_DRV)) {
		u32 w0 = tx->d[*cur][0];

		tx->d[*cur][0] = w0 | MTSX_W0_DRV;	/* hand bit 31 back */
		*cur = (w0 & MTSX_W0_WRAP) ? 0 : *cur + 1;
		n++;
	}
	return n;
}

/* Hardware RX engine: one frame into the next armed descriptor; false if none is armed. */
static bool hw_rx_deliver(struct ring *rx, unsigned int *cur, u32 len)
{
	u32 w0 = rx->d[*cur][0];

	if (w0 & MTSX_W0_DRV)
		return false;			/* no buffer: the frame is lost */
	rx->d[*cur][0] = MTSX_W0_DRV | len;	/* completion overwrites word0 */
	*cur = (w0 & MTSX_W0_WRAP) ? 0 : *cur + 1;
	return true;
}

static void test_tx(unsigned int used, unsigned int seed)
{
	struct ring tx;
	u32 head = 0, tail = 0;
	unsigned int hw_cur = 0, sent = 0, reclaimed = 0, i;
	u32 expect_token = 1;
	u32 tokens[MTSX_HW_RING];
	bool stopped = false;

	srand(seed);
	for (i = 0; i < MTSX_HW_RING; i++)
		mtsx_tx_idle_image(tx.d[i]);

	for (i = 0; i < 200000; i++) {
		unsigned int free = mtsx_tx_free(head, tail, used);

		assert(free <= used);			/* never negative, never more than the ring */

		/* driver: submit one frame when the firmware's rule allows it */
		if (!stopped && (rand() % 3)) {
			if (free < MTSX_TX_MIN_FREE) {
				stopped = true;
			} else {
				unsigned int idx = mtsx_tx_index(head, used);
				u32 w[4];

				/* the slot must really be free: idle or recycled, bit 31 set */
				assert(tx.d[idx][0] & MTSX_W0_DRV);
				mtsx_tx_image(w, 0x1000u + idx * 0x800u, 60 + (rand() % 1455),
					      mtsx_tx_wrap(idx, used));
				tx.d[idx][1] = w[1];
				tx.d[idx][2] = w[2];
				tx.d[idx][3] = w[3];
				tokens[idx] = head + 1;		/* identifies this submission */
				tx.d[idx][0] = w[0];		/* last store: bit 31 clear */
				head++;
				sent++;
				if (mtsx_tx_free(head, tail, used) < MTSX_TX_MIN_FREE)
					stopped = true;
			}
		}

		/* hardware: finishes a random burst */
		if (rand() % 4 == 0)
			hw_tx_consume(&tx, &hw_cur, 1 + rand() % 8);

		/* driver: reclaim in order, exactly as the firmware's loop does */
		while (tail != head) {
			unsigned int idx = mtsx_tx_index(tail, used);

			if (!mtsx_tx_done(tx.d[idx][0], tx.d[idx][2]))
				break;
			assert(tokens[idx] == tail + 1);	/* completed in submission order */
			tx.d[idx][2] = mtsx_tx_recycled_w2(tx.d[idx][2]);
			tail++;
			reclaimed++;
			expect_token++;
		}
		if (stopped && mtsx_tx_free(head, tail, used) >= MTSX_TX_WAKE_AT)
			stopped = false;
	}

	/* drain what is left */
	while (tail != head) {
		unsigned int idx = mtsx_tx_index(tail, used);

		hw_tx_consume(&tx, &hw_cur, MTSX_HW_RING);
		assert(mtsx_tx_done(tx.d[idx][0], tx.d[idx][2]));
		tx.d[idx][2] = mtsx_tx_recycled_w2(tx.d[idx][2]);
		tail++;
		reclaimed++;
	}
	assert(sent == reclaimed);
	assert(head == tail);
	assert(sent > used * 10);			/* the test really wrapped the ring many times */
	printf("tx used=%u: %u frames, ring wrapped %u times, in order, none lost\n",
	       used, sent, sent / used);
}

static void test_rx(unsigned int seed)
{
	struct ring rx;
	unsigned int hw_cur = 0, drv_idx = 0, i, delivered = 0, lost = 0, got = 0;
	u32 next_len = 60;

	srand(seed);
	for (i = 0; i < MTSX_HW_RING; i++) {
		rx.d[i][0] = mtsx_rx_arm_w0(i);
		rx.d[i][1] = 0x2000u + i * MTSX_RX_BUF;
		rx.d[i][2] = 0;
	}

	for (i = 0; i < 300000; i++) {
		unsigned int burst = rand() % 12;

		/* hardware: a burst of frames, with a length that identifies each one */
		while (burst--) {
			u32 len = 60 + (next_len % 1455);

			if (hw_rx_deliver(&rx, &hw_cur, len)) {
				delivered++;
				next_len++;
			} else {
				lost++;
			}
		}

		/*
		 * driver: drain, then re-arm every descriptor it consumed. Every 5000
		 * rounds it stalls for 100 rounds, so the ring fills up and the hardware
		 * has to drop frames: that path must keep the order of what it did deliver.
		 */
		if ((i % 5000) < 100)
			continue;
		for (burst = rand() % 40; burst; burst--) {
			u32 w0 = rx.d[drv_idx][0];
			u32 len;

			if (!mtsx_rx_ready(w0))
				break;
			len = mtsx_rx_len(w0);
			assert(len == 60 + ((60 + got) % 1455));	/* frames arrive in order */
			got++;
			rx.d[drv_idx][2] = 0;
			rx.d[drv_idx][1] = 0x2000u + drv_idx * MTSX_RX_BUF;
			rx.d[drv_idx][0] = mtsx_rx_arm_w0(drv_idx);	/* last store */
			drv_idx = (drv_idx + 1) % MTSX_HW_RING;
		}
	}
	/* drain the rest */
	while (mtsx_rx_ready(rx.d[drv_idx][0])) {
		assert(mtsx_rx_len(rx.d[drv_idx][0]) == 60 + ((60 + got) % 1455));
		got++;
		rx.d[drv_idx][0] = mtsx_rx_arm_w0(drv_idx);
		drv_idx = (drv_idx + 1) % MTSX_HW_RING;
	}
	assert(got == delivered);
	assert(delivered > MTSX_HW_RING * 10);
	assert(lost > 0);				/* the full-ring path really ran */
	printf("rx: %u frames delivered and received in order, %u lost while the ring was full\n",
	       delivered, lost);
}

int main(void)
{
	test_patterns();
	test_tx(255, 1);
	test_tx(256, 2);
	test_tx(192, 3);
	test_rx(4);
	printf("all tests passed\n");
	return 0;
}
