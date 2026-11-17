# mtsx: Baikal Ethernet driver for the state Orbis leaves after the kexec

**Status: compiled with `W=1` without warnings, `checkpatch --strict` clean, host-tested. Never run on hardware.** Written on 2026-11-17 while the console was busy with the internal-rootfs plan. This is the driver for Phase C of [`others/docs/PLAN_ETH0_BAIKAL.md`](../../docs/PLAN_ETH0_BAIKAL.md). Do not load it before Phases A and B (`others/tools/mts_peek`) have shown what the console looks like after the kexec.

## Why a new module and not a fix of `mts.c`

`kernel/drivers_mts/mts.c` loads on every boot (D14 of the plan) and has 14 defects (D1-D14) across the bring-up and the data path. Changing what it writes would reach every boot of the console as soon as a build picks it up. `mtsx` is a separate module: it has no `MODULE_DEVICE_TABLE`, so nothing loads it but an explicit `insmod`, and `mts.c` stays untouched. If the user decides to fix `mts.c` or to adopt one of the external GPL drivers instead (decision E4), nothing here is in the way.

## What it does

- **Adopts the MAC as Orbis left it:** configured and stopped. No cold init, no PHY calibration, no glue reset, no ICC call (F18: Orbis's own attach does none of these).
- **The first `ip link set up` publishes one DMA generation**, in this order: gates, clear the shutdown residue (F5, F6, F8), allocate and arm the rings, acknowledge stale status, program the ring registers (F9), `pci_set_master`, enable both cores, RX doorbell. After that the module cannot be unloaded (it holds a reference), sysfs unbind is suppressed, and "down" is administrative only (the cores keep running and the poll discards): a stop acknowledgment does not prove that DMA drained [P].
- **No interrupts.** A 1 ms `hrtimer` schedules NAPI. The poll does what the Orbis interrupt handler does (F20): read `0x50` and write it back (write-1-to-clear), reclaim TX, ring the TX doorbell again if descriptors are outstanding, drain RX, ring the RX doorbell (`0x38 |= 4`), stop TX on the fatal bits `0x500000`. The interrupt mask stays as Orbis left it.
- Link: `BAR0+0x04` bit 0 (what Orbis's PHY thread reads, F11), checked about every 250 ms and on the link-change status bit; BMSR is logged on each change.
- MAC address: bytes 0-1 from `0x14`, bytes 2-5 from `0x18`, as programmed by Orbis (it reads `2c:cc:44:3f:69:5f` in our 2026-11-12 log).

## What it writes to the hardware

| When | Writes |
|---|---|
| Probe | Nothing but PCI COMMAND (`pci_enable_device_mem`) |
| First open | MDIO command register for the gate reads; one Clause 45 write to `0x0147.1e` (only if bit 4 is set and every gate passes); `0x50` (ack), `0x44`/`0x3c`/`0x48`/`0x40` (ring registers), PCI bus master, `0x34 = 1`, `0x38 = 1`, `0x38 \|= 4` |
| Running | `0x50` (ack), `0x34` doorbell (`ctl & ~4`, then `ctl \| 4`, bit 1 masked out), `0x38 \|= 4`, MDIO reads for the link log |
| Shutdown | the first steps of Orbis's `mac_stop` (F7): IMR `0x7ffffa`, `0x34 = 2` and `0x38 = 2` with bounded waits, bus master off. Memory is not touched |

It never touches the glue block, the ICC, the counters at `0x100`-`0x12c`, `0x200` or `0x1c8`, and it writes the IMR only at shutdown.

The four gates before the PHY write (as in `mts_peek`): PHY ID `03a2/9441`, both cores stopped, IMR has every bit of `0x007ffffa` set, `0x0147.1e` readable. If a gate fails, open fails and nothing was enabled, so a retry costs no power cycle. `clear_residue=0` skips the whole step.

## How it avoids the defects of `mts.c` (plan section 2.4)

| Defect | In `mtsx` |
|---|---|
| D1, D2 MDIO write opcode, packed address | F1-F4 encodings, copied from the decompiled routines |
| D3 residue never cleared | cleared, gated |
| D4 link wait on the wrong register | `BAR0+0x04` bit 0 and BMSR, as `gbe_phy_ctrl` |
| D5 BMCR overwritten | BMCR is never written |
| D6 block reset in the middle of bring-up | no glue access at all |
| D7 PHY probe on MMD 1/3 | Clause 22 and MMD 30 only |
| D8 RX handed over with bit 31 set | armed with bit 31 clear, size `0x600`, WRAP on 255 (F9, F15) |
| D9 TX completion inverted | done = bit 31 set and word2 not idle; word2 = 0 on submit; bit 31 cleared last (F10, F14) |
| D10 IMR polarity | IMR untouched (`0x7ffffa` as left); no interrupts |
| D11 doorbell | `0x34` bit 2 (F13) |
| D12 255 of 256 TX descriptors | `tx_used=255` by default [P]; WRAP on index 254 |
| D13 write to `BAR0+0x1c8` | none |

## Not implemented (known gaps)

- Interrupts (MSI): polled only.
- Receive filter and multicast hash: whatever Orbis programmed stays. IPv4 unicast and broadcast should work; IPv6 neighbor discovery may not.
- Checksum, VLAN and TSO offloads; BQL; ethtool speed/duplex (the register `0x04` decode in the log is [P], not verified here).
- Recovery from the fatal bits: the firmware pulses `0x9c` bit 6 and rebuilds the TX ring (F20); here TX just stops and the log says why.
- A `fw_bringup`-style switch inside `mts.c`: not needed, the new module replaces it.

## Unknowns that Phase C must measure

1. Does the RX length include the FCS? (The driver accepts 60..1536 and drops the rest.)
2. Does the hardware pad short TX frames? (The driver pads to 60 anyway.)
3. 255 versus 256 TX descriptors (`tx_used=256` to test).
4. What the status bits of a completed descriptor mean (ignored for now).
5. Behavior of `ip link set down` / `up` while the cores keep running.
6. Does the PS4 Pro behave like the Slim consoles of the two reference projects? (H4 of the plan.)

## Files

| File | What |
|---|---|
| `mtsx.c` | the driver |
| `mtsx_desc.h` | descriptor words and ring arithmetic, pure functions shared by the driver and the host test |
| `test_desc.c`, `check.sh` | host test: bit patterns pinned to the firmware's values, plus a model of the ownership protocol run over 255, 256 and 192 TX descriptors and the RX ring, including the full-ring path. `./check.sh` (with ASan and UBSan) |
| `Kbuild`, `build.sh` | out-of-tree build, same mechanism as `others/tools/mts_peek/build.sh` and `others/scripts/build_mts_module.sh` |

The model in `test_desc.c` is our reading of the firmware, so it checks the driver's bookkeeping, not the hardware.

## Use (Phase C of the plan; only when the user says the console is free)

Preconditions: cold boot into Orbis, payload, kernel booted with `module_blacklist=mts`, Phases A and B done, cable on a live partner, host NIC `enp60s0` at `192.168.0.1/24`. One variable per boot.

```bash
sudo others/tools/mtsx/build.sh
scp others/tools/mtsx/mtsx.ko root@192.168.6.128:/dev/shm/
ssh root@192.168.6.128 'insmod /dev/shm/mtsx.ko; dmesg | grep mtsx'     # probe: reads only
ssh root@192.168.6.128 'ip addr add 192.168.0.2/24 dev eth0; ip link set eth0 up; dmesg | grep mtsx'
ping -c 5 192.168.0.2        # from the host; then hash-checked transfers both ways
```

Never test the wired path over the WiFi subnet. `rmmod mtsx` fails by design after the first open.

## Credits

The shutdown-residue finding, the doorbell edge, the 255-descriptor workaround and the ISR-level details were published by Gabriel Stewart ([Gcsman110/ps4-mts-linux-driver](https://github.com/Gcsman110/ps4-mts-linux-driver), GPL-2.0-only) and meerzulee ([linux-psx](https://github.com/meerzulee/linux-psx), GPL-2.0-only). The plan cites them as [P] where our own firmware analysis does not cover a point. No code was copied; everything here was written from our own decompilation (F1-F20) and then cross-checked against their documentation. If this driver is promoted to the kernel tree, credit them in the release notes.
