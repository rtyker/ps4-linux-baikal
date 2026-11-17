# Release notes

## 2026-11-17 — Swap on the Baikal SPM/DDR3, moved by DMA (`baikal-spm-blk`)

**Headline feature:** the PS4 Pro's Baikal southbridge carries a block of DDR3 (the SPM) that the
CPU can only reach one 32-bit word at a time (~4 MB/s). This release adds a block device,
`/dev/baikal_spm0`, backed by that memory and moved by the southbridge's own DMA controller
(`baikal-dmac`), so it can be used as **swap at hundreds of MB/s**.

Kernel tag `20261117-checkpoint` (7.0.8-Strawberry-ThinLTO-Baikal). Validated on a real console.

### Before and after (all numbers measured on the console)

| Measurement | Before (CPU, word by word) | After (DMA) | Gain |
|---|---|---|---|
| Read 64 KiB, median of 10 | 16,144.6 µs (~4.1 MB/s) | 192.6 µs (~340 MB/s) | ~84x |
| Read 4 MiB | 1.029 s (4.1 MB/s) | 7.7 ms (547 MB/s) | ~133x |
| Read 1 MiB, hot, 10 runs | — | 545–638 MB/s | — |
| Block device, 64 MiB `O_DIRECT` | — | write 645 MB/s, read ~1.0 GB/s | — |
| Block device, 4 KiB blocks, 16 MiB | — | 111 MB/s | — |
| Real swap traffic (random pages) | ~4.4 MB/s (30 MiB in 6.85 s, DMA off) | ~88 MB/s (140 MiB in 1.58 s) | ~20x |
| Swap on the SPM at all | not available (zram only) | 180 MiB device, priority 50 (below zram's 100) | new |

Read figures from `baikal-memory` include the `copy_to_user`; they are not raw DMAC throughput.
The SPM answers up to **188 MiB** on the tested console, so the device is 180 MiB (the driver probes
the region at load time and refuses the device if the memory does not answer).

### What changed in `swap_test.sh`

`others/tests/dma/swap_test.sh` now exercises the real kernel swap path instead of just copying blocks:

- worker processes are confined by a cgroup (`MemoryMax`) so the kernel is forced to page through `/dev/baikal_spm0`;
- every 1 MiB block is filled from a seed and **verified by CRC** after being paged out and back in (3 random passes);
- three scenarios: 1 process, 3 concurrent processes, and DMA disabled (`use_dma=0`) to prove the CPU fallback is correct;
- it checks `pswpin`/`pswpout`, that the data really went through the DMA counters, and that `dma_errors` and fallbacks stay at 0;
- it restores the device (zeroed) and unloads the module on exit, even on failure.

Result on the console: **10/10 PASS**, 144 MiB swapped out and 403 MiB swapped back in, 0 corrupted blocks.
The companion `blk_test.sh` (8/8 PASS) and the `baikal-memory` battery (46/46 PASS) also pass.

### Design notes

- No allocation in the I/O path (swap must make progress under memory pressure); any DMA failure, timeout or abort
  only sends that chunk to the CPU, without disabling the DMA.
- A real bug found while testing faults: the DMAC reports an aborted transfer only through `callback_result`,
  and the old code returned stale bounce-buffer data. Fixed and covered by fault-injection tests.
- Packaging: `distro/baikal-spm-swap.service` + `distro/scripts/install-spm-swap.sh` (`--no-enable` available).

### Credits

This work was **inspired by Debarshi's PS4 Pro "Belize" DDR3 patch**, which first showed that this memory can be
exposed as a swap disk and that replacing CPU access with DMA lifts throughput from ~10.6 MB/s to ~504 MB/s
(their numbers, on their hardware). Original write-ups:

- <https://dev.to/debarshis/ps4-pro-belize-ddr3-170m> (v1)
- <https://dev.to/debarshis/ddr3-memory-engine-architecture-dg2> (architecture)
- <https://dev.to/debarshis/ps4-pro-belize-ddr3-patch-v2-4pb2> (v2, DMA)
- Coverage: <https://ps4linux.com/ps4-pro-ddr3-patch-linux-debarshi/>

No code from that patch is used: it targets Belize, and this project is an independent implementation for Baikal
(different DMAC, different address map), written from the hardware behavior measured here. The idea and the
public measurements are theirs. Thank you.

### Known limits

- Capacity is 188 MiB on the tested console; an older measurement said 256 MB and the two disagree without explanation.
- Auto-start at boot is confirmed: after a reboot the service is `active` and `/dev/baikal_spm0` (180 MiB, priority 50) is listed next to zram.
- **DP-2 (link at 2.7 Gbps) is in this tag but did not fix the DisplayPort `clock recovery` failures**
  (stress test: 4–6 failures per mode switch; the image still comes up). It is not a validated fix.
