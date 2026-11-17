# Plan: Linux root filesystem on the PS4's internal disk (no USB drive)

**Status (2026-11-17): proposal only. Nothing in this plan has been executed.**
Created after the kernel boot from the internal disk was confirmed (see [`BOOT_FROM_INTERNAL_DISK.md`](BOOT_FROM_INTERNAL_DISK.md)).

## Goal

Boot the whole system from the PS4's internal disk: kernel and initramfs (already done), **and** the root filesystem, so the unreliable USB drive is no longer needed. Constraints: do not repartition the internal disk, do not lose the console's Orbis data, and do not let Linux write to the Orbis UFS2 filesystem.

## Where we are

| Item | State | Evidence |
|---|---|---|
| Kernel + initramfs on the internal disk | **Done**, confirmed on 2026-11-17 | `bootsrc=internal` in `/proc/cmdline`; files in `sda27/data/linux/boot/` |
| Orbis `/data` location | `data/` folder of `sda27` (encrypted UFS2 "user" partition); `/user` is the root of `sda27` | Read-only mount from Linux; MD5 of `bzImage` matches |
| Root filesystem | Still on the USB drive (`root=LABEL=psxitarch`, SSD behind a JMS578 bridge with I/O errors) | `dmesg` |
| Free space in `sda27` | 330 GiB of 884 GiB | `df` on the read-only mount |
| Internal disk | TOSHIBA MQ04ABF100 (HDD), SMART `PASSED`, 1 reallocated sector, SATA link limited to 3 Gbps | `smartctl`, `dmesg` |
| Partition table | GPT with no free space (0.7 MiB at the end, a 256 MiB gap at the start that looks reserved) | `sfdisk -d` (read-only) |

## Prior art (found on 2026-11-17)

- **[meerzulee/linux-psx, issue #5](https://github.com/meerzulee/linux-psx/issues/5) — Baikal Slim (CUH-2002A), reported on one console.** Root booted from a 32 GiB ext4 image at `/data/linux/psxitarch.img` with no USB storage attached. The image was **created by Orbis** (zeros uploaded over GoldHEN FTP), so Linux never wrote the UFS2 filesystem. Linux, booted from USB, mounted the crypt mapping and UFS2 **read-only**, built a FIBMAP block map (1100 extents, 4 KiB blocks, no holes) and verified that every mapped block read as zero. At boot, an initramfs step (enabled by `ps4root=internal`) opens dm-crypt, checks the UFS2 magic, loads the dm-linear table with `dmsetup`, checks the ext4 UUID and mounts ext4 read-write. Root mounted at 14.7 s; 1 GiB write at 253 MB/s (on an SSD); one clean power-off, after which Orbis booted with no UFS errors or database rebuild. The key came from the loader (`/key/eap_hdd_key.bin`, ps4-linux-loader v25.1, per the report). Not tested: repeated cold boots, long uptime, power loss during writes, the stock HDD, Orbis updates.
- **[blue0x1/ps4-multiboot](https://github.com/blue0x1/ps4-multiboot) — Belize (PS4 Pro) is its only tested platform; Baikal is "experimental".** One image per distro at `/user/home/<name>-ps4.img`, nothing repartitioned. Same mechanism: `cryptsetup` plain `aes-xts-plain64`, 256-bit key from `/key/eap_hdd_key.bin`, `--skip 111669149696` on Belize/Baikal (0 on Aeolia), UFS2 mounted read-only, `blockmap` (FIBMAP, see [`initramfs/blockmap.c`](https://raw.githubusercontent.com/blue0x1/ps4-multiboot/main/initramfs/blockmap.c)) to build a dm-linear table. Difference: it creates the image **from Linux**, remounting UFS2 read-write once to zero-fill the new file ("the only time Linux writes the PS4's filesystem"). It keeps 10 GiB free for Orbis and refuses to format an existing image that is neither ext4 nor all zeros.
- **[Juniorleao06/ps4-linux-internal-drive](https://github.com/Juniorleao06/ps4-linux-internal-drive) — Baikal Slim, one console.** 50 GiB ext4 image at `/ps4hdd/home/ps4linux.img`, kernel named `7.0.8-Strawberry-ThinLTO-Baikal-+` (from `rmuxnet/ps4-linux-12xx`). The page does not describe the mechanism.
- **Older tutorials** (`install-linux-hdd.sh`, `/user/home/linux.img`, e.g. [dionkill](https://dionkill.github.io/ps4-linux-tutorial/internal-installation.html), [zfentom](https://zfentom.github.io/playstation-linux-tutorial/ps4/internal-installation)) targeted Aeolia/Belize and explicitly say **not** to use them on Baikal.

## Chosen technique: image file + block map + dm-linear (no UFS2 writes from Linux)

```
internal disk  ->  sda27 (raw)  ->  dm-crypt (aes-xts-plain64, IV offset 111669149696)
                                      |
                                      +-> UFS2 (mounted READ-ONLY only to compute the block map)
                                      |
                                      +-> dm-linear "ps4root" = exactly the blocks of /data/linux/rootfs.img
                                              -> ext4 (read-write) = Linux root
```

The image file is created **by Orbis** (FTP upload of zeros), so Orbis's own filesystem code allocates every block. Linux only reads UFS2 metadata to learn where the file's blocks are, and then writes only inside those blocks through dm-linear. UFS2 metadata is never changed by Linux. This avoids the kernel's experimental UFS write support (`CONFIG_UFS_FS_WRITE`, marked "DANGEROUS").

**Verified locally (2026-11-17), no hardware changes:**
- Our kernel's UFS driver implements `bmap` (`fs/ufs/inode.c`: `.bmap = ufs_bmap`), so `FIBMAP` works on UFS2.
- `dm-linear` is built into the device-mapper core (`dm-mod`: `dm-linear.o`; `CONFIG_BLK_DEV_DM=y`); `CONFIG_DM_CRYPT=y`; `CONFIG_DM_SNAPSHOT=y`.
- The dm-crypt parameters for `sda27` are already in production use by `distro/monta_particao.sh` (IV offset `111669149696`, the same value ps4-multiboot uses).
- The GoldHEN FTP server accepts upload, rename (also over an existing file) and DELE.
- The dm-crypt + dm-snapshot stack worked for a RAM-backed write simulation on `sda25` with the real partition hash unchanged (`others/tests/internal_partition_write_sim.sh`).

## Gaps to close

1. **Drive key at boot.** Our payload source (`ps4-linux-payloads`, `ps4-linux-loader` commit `741b0ef`) has **no** EAP key code; the upstream repository now returns 404, and the "loader v25.1 places the key in the initramfs" claim comes from a single report. Options:
   - **A (preferred):** append the key as a small cpio fragment (`/key/eap_hdd_key.bin`) **only to the copy of the initramfs uploaded to the internal disk** (`deploy-boot-ftp-7.0.sh`), at deploy time, from `~/ps4-keys/`. It then lives inside `sda27` (itself encrypted with that key). It is never written to git, `boot_referencia/`, the USB drive, or any backup folder. (The project rule "the key never goes into git or into the image" still holds for the built artifacts.)
   - **B:** adopt a loader version that injects the key itself, after verifying that it really does.
2. **initramfs hook.** Our initramfs is built by mkinitcpio. Add a hook (through the official build, `distro/01-build-image-7.0.sh` / `rebuild-initramfs-7.0.sh`) that, when `ps4root=internal` is on the command line: waits for the internal disk on `ata1` (by sysfs path, not `sdX` order), opens the dm-crypt mapping of `sda27` (it must allow writes, because the ext4 writes pass through it; the UFS2 filesystem itself is never mounted at boot), checks the UFS2 magic by reading the raw superblock (`0x19540119` at byte `0x1055C`), loads the stored dm-linear table, checks the ext4 UUID, and mounts root. **On any failure, fall back to the USB root (`LABEL=psxitarch`)** instead of a dead rescue shell.
3. **Where the table lives.** Store the dm-linear table (and its SHA-256, the image size, the ext4 UUID) next to the boot files in `/data/linux/boot/`, uploaded by the FTP deploy script. The hook refuses to map if any check fails.

## Phases (each one ends with an explicit go/no-go)

### Phase 0 — Decisions (user)
- Final image size (suggestion: 64 GiB to start; leave **at least 10 GiB** free in `sda27` for Orbis; it does not report the space Linux uses).
- Key option A or B.
- Fallback behavior when the internal root fails (proposed: boot the USB root).

### Phase 1 — Small test image created by Orbis (no Linux writes)
- Upload an 8 GiB file of zeros over FTP: `head -c 8G /dev/zero | curl -T - ftp://192.168.6.130:2121/data/linux/rootfs-test.img`. Measure the upload speed (WiFi).
- Acceptance: file size exact; Orbis keeps working normally.

### Phase 2 — Block map, read-only (Linux booted from USB)
- With `sda27` mounted read-only: compute the FIBMAP block map of `rootfs-test.img` (a small `blockmap` tool or `filefrag -v`, whichever works on UFS2), build the dm-linear table over the existing dm-crypt mapping, and create `ps4root-test` **read-only**.
- Acceptance: no holes; the dm-linear device reads back all zeros; its size equals the file size.

### Phase 3 — Write test through dm-linear (still from USB root)
- Create the dm-linear device read-write; `mkfs.ext4`; write and read back known data; `fsck.ext4 -n`.
- **Key proof that the map is correct:** after unmapping, read the file **through the UFS2 read-only mount** and confirm the bytes written through dm-linear are there (for example, the ext4 superblock magic at offset 1080 and a test file's content). Writes landed only in the file's own blocks.
- Then boot Orbis and confirm: no "repair storage" or database rebuild prompt, games and saves intact.
- Acceptance: all checks pass; Orbis is unaffected.

### Phase 4 — Boot with the internal root
- Initramfs hook + key option + stored table; boot with `ps4root=internal` and `bootsrc=internal`.
- Acceptance: `findmnt /` shows `/dev/mapper/ps4root ext4 rw`; 10 consecutive cold boots; clean power-off; Orbis still healthy afterwards; the USB fallback works when the internal root is deliberately made unavailable.

### Phase 5 — Full-size image and migration
- Create the final image the same way (Orbis-allocated), map it, `mkfs.ext4`, copy the current USB root (`rsync -aHAX`), switch `bootargs` to `ps4root=internal`.
- Acceptance: system runs from the internal disk with the USB drive unplugged; long-uptime and I/O tests; then decide whether the USB drive is retired.

## Safety rules

1. Linux **never** mounts `sda27` read-write and never runs a UFS2 write path. The image is created only by Orbis (FTP).
2. The dm-linear table is a fixed promise about where the file lives. If the file is deleted, moved, truncated or rewritten from Orbis (FTP delete, "Initialize PS4", a storage cleanup), the next Linux boot could overwrite Orbis data. Mitigations: the hook verifies the ext4 UUID and the table checksum before mounting; never delete or replace the image while its table is installed; document this in the boot README on the internal disk.
3. Keep the USB boot path as rollback until Phase 5 is fully accepted.
4. One change per boot; record every step in `test_history`.

## Risks and unknowns

- **Performance:** the prior Baikal report used a SATA SSD (253 MB/s write). Ours is a 2.5" HDD; sequential and random speeds are unmeasured.
- **Internal SATA stability over long runs:** the current boots show `ata1` clean, but the project has a history of SATA problems on this disk.
- **Orbis behavior** after the image exists (updates, storage management, rebuild database): not verified by anyone for long periods.
- **Key handling:** option A puts the key in an initramfs file inside the encrypted partition; anyone able to read that file already has Orbis-level access.
- **FTP upload time** of a large image over WiFi.

## Rollback

- Remove `ps4root=internal` from `bootargs.txt` (FTP) to boot the USB root again; or put the boot files back on the USB drive (backup in `~/ps4-boot-usb-backup-20261117/`).
- To remove the internal root entirely: delete the image and its table from `/data/linux/` over FTP (only after removing `ps4root=internal`).

## Sources

- [meerzulee/linux-psx issue #5](https://github.com/meerzulee/linux-psx/issues/5)
- [blue0x1/ps4-multiboot](https://github.com/blue0x1/ps4-multiboot), [initramfs init](https://raw.githubusercontent.com/blue0x1/ps4-multiboot/main/initramfs/init), [blockmap.c](https://raw.githubusercontent.com/blue0x1/ps4-multiboot/main/initramfs/blockmap.c)
- [Juniorleao06/ps4-linux-internal-drive](https://github.com/Juniorleao06/ps4-linux-internal-drive)
- [Internal HDD installation (dionkill)](https://dionkill.github.io/ps4-linux-tutorial/internal-installation.html), [(zfentom)](https://zfentom.github.io/playstation-linux-tutorial/ps4/internal-installation)
- [loreps/initramfsps4](https://github.com/loreps/initramfsps4-loreps-v.) (the loader is expected to provide `/key/eap_hdd_key.bin`)
