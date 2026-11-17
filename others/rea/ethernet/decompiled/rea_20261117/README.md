# Orbis 12.52 GBE driver: REA pseudocode of 2026-11-17

Sixteen functions of the Orbis GBE (`mts`) driver, decompiled with REA to re-check the Ethernet plan. The plan that uses them is `others/docs/PLAN_ETH0_BAIKAL.md` (section 2.2). Each file starts with a header naming the function, our reading of its role, the source dump, the analyzed slice and the REA evidence ID.

This is decompiler output, not source code. The names `FUN_*`, `func_*`, `param_*` and `*Var*` are Ghidra's. The role line in each header is our interpretation and can be wrong; the pseudocode under it is what the tool produced.

| File | Address | Role (our reading) |
|---|---|---|
| `dc5a24d0_mdio_c45_write.txt` | `0xffffffffdc5a24d0` | Clause 45 write: address phase opcode `0x20`, data phase opcode `0x60` |
| `dc5a2680_mdio_c45_read.txt` | `0xffffffffdc5a2680` | Clause 45 read: address phase `0x20`, read phase `0xe0`, data in bits 31:16 |
| `dc59fe10_gbe_teardown.txt` | `0xffffffffdc59fe10` | Teardown: stops the MAC, then writes `0x0010` to `0x0147.1e` (the shutdown residue) |
| `dc5a0b10_dev_method_stop_residue.txt` | `0xffffffffdc5a0b10` | Device method: `mac_stop`, residue write, `DELAY(1000)` |
| `dc5a0750_dev_method_threads_stop_residue.txt` | `0xffffffffdc5a0750` | Device method: stops the worker threads, then the same as above |
| `dc5a3060_mac_stop.txt` | `0xffffffffdc5a3060` | `mac_stop`: IMR `0x7ffffa`, `0x34`/`0x38` = 2 with polling, rings back to the driver |
| `dc5a31f0_mac_enable.txt` | `0xffffffffdc5a31f0` | `mac_enable`: ring layout and ownership, ring registers, `0x34 \|= 1`, `0x38 \|= 1`, IMR |
| `dc5a2ce0_tx_reclaim.txt` | `0xffffffffdc5a2ce0` | TX completion: bit 31 set means the hardware is done |
| `dc5a44c0_gbe_phy_ctrl.txt` | `0xffffffffdc5a44c0` | PHY thread: waits for link on Clause 22 BMSR bit 2; autonegotiation restart |
| `dc5a2840_mdio_c22_read.txt` | `0xffffffffdc5a2840` | Clause 22 read: `(reg & 0x1f) << 8 \| 0x4000`, no PHY-address field |
| `dc5a2950_mdio_c22_write.txt` | `0xffffffffdc5a2950` | Clause 22 write: `(reg & 0x1f) << 8 \| 0x2000 \| value << 16` |
| `dc5a3df0_tx_start.txt` | `0xffffffffdc5a3df0` | Transmit start: descriptor builder per frame, then the doorbell `BAR0+0x34 \|= 4` once |
| `dc5a5ae0_tx_encap.txt` | `0xffffffffdc5a5ae0` | TX descriptor builder: word layout, bit 31 cleared last |
| `dc5a2dd0_rx_frame_and_rearm.txt` | `0xffffffffdc5a2dd0` | RX per frame: length `word0 & 0x7ff`, copy out, re-arm with bit 31 cleared |
| `dc5a2a50_rx_loop.txt` | `0xffffffffdc5a2a50` | RX loop: a frame is `word0 > 0x80000000` |
| `dc5a1d30_interrupt_handler.txt` | `0xffffffffdc5a1d30` | Interrupt handler: status register `0x50` is write-1-to-clear; TX reclaim + TX doorbell, RX loop + RX doorbell `0x38 \|= 4`, fatal bits `0x500000` |

## How to reproduce

REA's Ghidra provider timed out (330 s) analyzing the whole 32 MiB dump, so the analysis runs on a 192 KiB slice that holds the GBE driver.

1. Cut the slice (the dump's virtual base is `0xffffffffdc350000`; the slice starts at `0xffffffffdc590000`, 576 pages later):

   ```bash
   dd if=others/rea/dumps/kmem_dump_1252.bin of=/path/to/kmem1252_gbe_dc590000.bin bs=4096 skip=576 count=48
   sha256sum /path/to/kmem1252_gbe_dc590000.bin
   # 99301a318f580f3993b93d504e2b3e80f6f6d76059bab3b808d68b84f27da488
   ```

2. Open it in REA: `open_binary` with `format: raw-binary`, `architecture: x86_64`, `entry_point: 0xffffffffdc590000`, `provider_id: ghidra`.
3. Call `procedure_pseudo_code` with each address of the table. The evidence ID in each header is deterministic for the same slice, tool version and analysis profile.

Calls into other parts of the kernel (locks, `DELAY`, `printf`) point outside the slice and appear as `func_0x...`.
