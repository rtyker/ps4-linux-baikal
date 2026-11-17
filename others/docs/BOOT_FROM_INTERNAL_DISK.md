# Alternative path: boot the kernel from the PS4's INTERNAL disk

**Status (2026-11-17): CONFIRMED.** The boot with tag `20261117-dp-diag2` came from the internal disk: `/proc/cmdline` carries `bootsrc=internal` (which only the internal `bootargs.txt` has), the kernel is the one built for that tag (`#1 ... Nov 17 08:29:07`), and the internal `vram.txt` was honored (it was changed from 4096 to 1024 over FTP, and the next boot showed VRAM 1024 MiB and RAM 6911 MiB). The USB drive had none of the four boot files at that point. Earlier boots with 4096 had read `vram.txt` from the USB drive.

## Idea

The payload (`ps4-linux-payloads/linux/main-aio.c`) looks for each boot file **independently**, in this order:

1. `/mnt/usb0/<file>`
2. `/mnt/usb1/<file>`
3. `/data/linux/boot/<file>`  ← **the internal-disk folder used here**
4. `/user/system/boot/<file>`

If the USB drive does not have a file, the payload uses the one on the internal disk. That way the kernel and the initramfs come from the PS4's own drive (Orbis), without depending on the USB drive. **The rootfs stays on the USB drive** (`root=LABEL=psxitarch`): the USB drive still has to be plugged in.

## Files the payload reads

| File | Required | Notes |
|---|---|---|
| `bzImage` | yes | the kernel |
| `initramfs.cpio.gz` | yes | the name must be exactly this (the old `.zip` on the internal disk does not match) |
| `bootargs.txt` | no | without it the payload uses a default command line **without** `root=LABEL=psxitarch` |
| `vram.txt` | no | value in MB; the default is 1024. It takes priority over the payload that was loaded |

## Official script for this path: `distro/deploy-boot-ftp-7.0.sh`

```bash
./distro/deploy-boot-ftp-7.0.sh <TAG> [--vram MB] [--no-marker] [--dry-run] [--allow-usb-conflict]
```

It does not touch `deploy-boot-7.0.sh` (which keeps writing to the USB drive). What it does: checks that FTP is answering (it only exists in Orbis); refuses to continue if the USB drive has boot files (the USB drive wins); downloads whatever is already on the PS4 to `~/ps4-boot-internal-backup-<date>/`; uploads everything as `.part`, verifies the MD5 by downloading it back, and only then renames to the final name; checks the final names again; writes `active-tag.txt` with the tag; appends `bootsrc=internal` to the bootargs (use `--no-marker` to skip it). The PS4's `vram.txt` is **only touched with `--vram MB`** (the repository's `vram.txt` is 1024 while the PS4's is 4096, so there is no default value). Tested on 2026-11-17: `--dry-run` and one real run with tag `20261117-dp-diag2` (idempotent, same MD5 as what was already uploaded). The GoldHEN FTP server accepts upload, rename (including over an existing file) and DELE: tested.

## Equivalent manual procedure (GoldHEN FTP, port 2121, PS4 in Orbis mode)

```bash
F=ftp://192.168.6.130:2121/data/linux/boot
curl --ftp-create-dirs -T bzImage           $F/bzImage
curl --ftp-create-dirs -T initramfs.cpio.gz $F/initramfs.cpio.gz
curl --ftp-create-dirs -T bootargs.txt      $F/bootargs.txt
curl --ftp-create-dirs -T vram.txt          $F/vram.txt
# verify: download it back and compare the md5 with the local file
curl -o /tmp/chk $F/bzImage && md5sum /tmp/chk bzImage
```

1. **Move, do not copy:** to avoid any ambiguity, **remove** these 4 files from the USB drive's BOOT partition (the USB drive has priority over the internal disk). Do this only after checking the MD5 of the internal copies and keeping a local backup.
2. **Proof marker:** put `bootsrc=internal` at the end of the internal `bootargs.txt`. The kernel ignores the parameter and it shows up in `/proc/cmdline`; if it does, the bootargs came from the internal disk.
3. FTP only exists in Orbis (`192.168.6.130`); after the `kexec` ports 9090 and 2121 are gone.

## What was done on 2026-11-17

- Tag in use: `20261117-dp-diag2` (kernel with the DisplayPort diagnostic patch, `vram.txt=4096`).
- Uploaded and verified (MD5 sent = MD5 downloaded): `bzImage` `2db126505d26`, `initramfs.cpio.gz` `9ba2bddd3097`, `bootargs.txt` `58a51d785b3f` (with `bootsrc=internal`), `vram.txt` `102e7bda3ff4`.
- `/data/linux/boot/` was empty beforehand.
- The 4 files were **removed** from the USB drive (BOOT), and a `BOOT-MOVIDO.txt` note was left there. Local backup: `~/ps4-boot-usb-backup-20261117/`.
- Record: `test_history` (phase "Boot pelo disco interno").

## Caveats

- **`distro/deploy-boot-7.0.sh` conflicts with this path:** it writes `bzImage`, `initramfs.cpio.gz`, `bootargs.txt` and `vram.txt` to the USB drive, which then takes priority again. To switch tags on this path, upload the new files over FTP and do **not** use `deploy-boot` (or remove the 4 files from the USB drive afterwards).
- **Old files on the internal disk** in `/user/system/boot/` (a `bzImage` from 2026-01-06, `initramfs.cpio.zip`, and a 3.7 GB `psxitarch.tar.xz`): they would only be used if a file were missing from `/data/linux/boot/`. Marked for removal later (BACKLOG, item 7b); they were not touched.
- **Rollback:** copy the 4 files from the backup (`~/ps4-boot-usb-backup-20261117/`) back to the USB drive's BOOT partition, or run `deploy-boot-7.0.sh <TAG>` with the drive plugged into the PC. Once the files are on the USB drive, it has priority again.
- **What this path does NOT solve:** the rootfs is still on the USB drive, so the USB drive's I/O failures (BACKLOG, item 5) still affect the boot. Removing the USB drive entirely needs a rootfs on the internal disk, which does not fit today (see the survey in `BACKLOG.md`: the internal disk has no free space, and the only large partition is the Orbis data partition).
