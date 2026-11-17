# mts_peek: read-only look at the Baikal Ethernet, plus one optional PHY write

**Status: compiled, never run on hardware.** Written on 2026-11-17 while the console was busy with the internal-rootfs plan. Nothing here has been loaded on the PS4. This is the tool for Phases A and B of [`others/docs/PLAN_ETH0_BAIKAL.md`](../../docs/PLAN_ETH0_BAIKAL.md); read the plan first.

## What it does

Finds PCI `104d:90d8` (`0000:00:14.1`), maps BAR0 and logs, as lines starting with `mts_peek:` in `dmesg`:

- the BAR0 registers of a fixed list (never the clear-on-read counters at `0x100`-`0x12c`);
- PHY registers by Clause 22 (BMCR, BMSR twice, PHY ID, ANAR, ANLPAR, GBCR) and by Clause 45 (`0147.1e`, `00a2.1e`, `0033.1e`, `0037.1e`, `0039.1e`, `0096.1e`, `0107.1f`, `0171.1e`);
- with `clear_residue=1`: after four gates, one write that clears bit 4 of Clause 45 `0x0147.1e` (the shutdown residue Orbis leaves), then BMSR and `BAR0+0x04` at 1, 10, 50, 100, 500 and 1000 ms;
- with `watch_s=N`: keeps sampling BMSR and `BAR0+0x04` for N seconds (max 600) and prints only the changes. Use it to see a link come up when the cable is plugged in later. `insmod` blocks for that long.

Every MDIO command word is the one the Orbis 12.52 driver uses (write `0x8000`, write the command, wait for bit 15). The evidence is in [`others/rea/ethernet/decompiled/rea_20261117/`](../../rea/ethernet/decompiled/rea_20261117/).

## What it touches

| Target | Access |
|---|---|
| PCI COMMAND | read; `pci_enable_device_mem()` sets the memory-decode bit only if it is clear. Never sets bus mastering, never touches MSI or INTx |
| BAR0 | reads of the list above; writes only to `+0x00` (the MDIO command register), as every MDIO read needs |
| PHY | reads; with `clear_residue=1` and all gates passed, one Clause 45 write to `0x0147.1e` |
| Glue block, ICC, rings, MAC enable (`0x34`/`0x38`), IMR (`0x54`) | not touched |

It has no `MODULE_DEVICE_TABLE`, so udev never loads it, and it refuses to run if another driver is bound to the device (so it never runs together with `mts`).

The four gates for `clear_residue=1`, each logged as `gate <name>: ok|FAIL`:

1. PHY ID reads `0x03a2` / `0x9441` (the MediaTek PHY both reference projects report);
2. `BAR0+0x34` and `+0x38` bit 0 are clear (MAC stopped);
3. `BAR0+0x54` has every bit of `0x007ffffa` set (all interrupt sources masked);
4. `0x0147.1e` reads with bit 4 set.

If any gate fails, nothing is written and the log says which one. Do not add a way around the gates: if they fail, stop and report what was read.

## Build

```bash
sudo others/tools/mts_peek/build.sh        # W=1 sudo -E ... for extra warnings
```

Same mechanism and toolchain flags as `others/scripts/build_mts_module.sh`, but the module stays outside the kernel tree. The module only loads on the kernel built from `kernel/kernel_build_7.0`. Before using it, check that the tree and the deployed tag are the same build: `Module.symvers` and `bzImage-7.0-<TAG>` should have the same timestamp (they did on 2026-11-17: tag `20261117-dp-diag2`, 08:29:41 / 08:29:42). On the console, `uname -r` must equal the `vermagic` that `build.sh` prints (`7.0.8-Strawberry-ThinLTO-Baikal-+`). The kernel has no module versioning or signature checks, so only vermagic is compared.

## Use (Phases A and B of the plan; only when the user says the console is free)

Preconditions: `mts` blocked from loading (kernel parameter `module_blacklist=mts`; see the plan, E3/P0-3), cable plugged into a live link partner, `lsmod | grep -w mts` empty.

```bash
# Phase A: read only
scp others/tools/mts_peek/mts_peek.ko root@192.168.6.128:/dev/shm/
ssh root@192.168.6.128 'insmod /dev/shm/mts_peek.ko; dmesg | grep mts_peek'

# Phase B: the single PHY write, in a boot where Phase A passed
ssh root@192.168.6.128 'rmmod mts_peek; insmod /dev/shm/mts_peek.ko clear_residue=1 watch_s=30; dmesg | grep mts_peek'
```

Compare the output with section 9 of the plan (expected values from the prior art) and record it in `test_history`. Load it once per boot and unload it with `rmmod mts_peek`; the file lives in RAM (`/dev/shm`) so nothing is written to the USB root drive.
