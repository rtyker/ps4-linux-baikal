# Runbook: Linux root filesystem on the PS4's internal disk (no USB drive)

**Status (2026-11-17): the plan and its host-side tools are written and tested. NOTHING in Phases 2-7 has been executed on the console.**

Audience: another coding agent that will carry this out. **Follow it to the letter. Where it says STOP, stop and report to the user; do not improvise a workaround.** If this document and a measurement disagree, the measurement wins: stop, record it, tell the user.

## 0. How to use this document

### 0.1 Evidence tags
- **[V]** verified in this repository or on this console on 2026-11-17 (the evidence is named, so you can re-check it).
- **[P]** reported by prior art on the web (section 12). Not verified here.
- **[U]** unknown. It must be measured in the phase that names it. Never assume it.

### 0.2 Notation
- **[HOST]** = commands run on the PC, from the repository root `/mnt/hdauxiliar/ps4-linux-baikal`.
- **[PS4]** = commands run on the console while it runs Linux from the USB root: `sshpass -p ps4 ssh root@192.168.6.128 '<command>'` (or an interactive session). Scripts and temporary files go in `/dev/shm` (RAM).
- **[ORBIS]** = the console is in Orbis mode (GoldHEN loaded, FTP on port 2121). Linux is not running then.
- Variables used below (set them in every shell you open):
  ```bash
  TOOLS=/mnt/hdauxiliar/ps4-linux-baikal/others/tools/ps4_internal_root
  WORK=$HOME/ps4-internal-root/20261117        # created in step P2-1, mode 700, outside git
  FTP=ftp://192.168.6.130:2121
  ```
- `<NONCE>` = the 32 hex characters stored in `$WORK/nonce.txt`.

### 0.3 Project rules you must obey (they come from `AGENTS.md`, the single source of rules)
1. **Talk to the user in Portuguese. Write every new file, comment and commit body in American English.** Do not translate old files unless asked.
2. **Never state something as fact without measuring it.** Say "I don't know" when you did not verify. Ask before risky hardware actions.
3. **Mount points:** never mount anything directly on `/mnt`. Use a dedicated sub-folder (`/mnt/ps4_rootfs_7.0`, `/mnt/ps4_boot_7.0`, `/mnt/ps4_internal_root`, ...).
4. **Kernel and image builds only through the official scripts** (`kernel/00-build-kernel-7.0.sh`, `distro/01-build-image-7.0.sh`, `distro/rebuild-initramfs-7.0.sh`). **This plan needs no kernel change** [V: `CONFIG_BLK_DEV_DM=y`, `CONFIG_DM_CRYPT=y`, `CONFIG_UFS_FS=y`, `CONFIG_EXT4_FS=y`, `CONFIG_CRYPTO_XTS=y`, `CONFIG_CRYPTO_AES=y` are built in; `fs/ufs/inode.c` has `.bmap = ufs_bmap`]. If you think a kernel change is needed, STOP and ask.
5. **Editing:** use the Edit tool; if you must script an edit, use Python with an `assert` on every replacement. No `sed -i` on multi-line blocks, no heredoc injection into source files.
6. **Record every step:** one row per test in `others/rea/ps4_hardware_memory.db`, table `test_history` (columns `timestamp, phase, test_name, target_component, action_taken, status, complementary_info`), and update `others/docs/BACKLOG.md` item `7c`. Commit locally with a clear message. **Never push unless the user asks.**
7. **The console is a PS4 Pro with a Baikal southbridge** (not a Slim). Old documents that say otherwise are wrong.
8. **The USB root drive (`/dev/sdb`, a Kingston SSD behind a JMS578 bridge) has known I/O errors. The user told us to ignore them.** Do not investigate them. Because of them: keep temporary files in `/dev/shm`, keep commands short, and if the console hangs ask the user to power-cycle it.
9. **The user performs every physical action** (power cycle, plugging drives, loading the payload, cable changes). Ask in Portuguese, then wait for the confirmation.
10. At the end of every phase ask the user for the go-ahead (a "gate") before starting the next one.

### 0.4 Reading list before you start
`AGENTS.md` (sections "Regras de Conduta", "REGRA CRÍTICA - Montagem de dispositivos", the build/deploy rules, "Topologia de Rede", "Envio de payload"), `others/docs/BOOT_FROM_INTERNAL_DISK.md`, `others/docs/MONTAGEM_HD_INTERNO.md`, the header of `distro/monta_particao.sh`, `distro/deploy-boot-ftp-7.0.sh`, `distro/rebuild-initramfs-7.0.sh`, and section 8 of this file.

## 1. Goal and non-goals

**Goal:** the console boots the whole system from its own disk. The kernel and initramfs already do [V: `bootsrc=internal` in `/proc/cmdline`, 2026-11-17]. This plan puts the **root filesystem** there too, so the unreliable USB drive is no longer needed.

**Hard constraints:**
- Do **not** repartition the internal disk. Do **not** lose or alter Orbis data (games, saves, trophies, system data).
- Linux **never** mounts the Orbis UFS2 partition read-write and never uses the kernel's experimental UFS write path [V: `CONFIG_UFS_FS_WRITE=y` is compiled in and its Kconfig help calls it "DANGEROUS"; we do not use it].
- Do not touch the old files in `/user/system/boot/` on the console (an old kernel and a 3.7 GB tarball): the user will remove them later (BACKLOG item 7b).

### 1.1 Overview of the phases

| Phase | What happens | Console mode | What it writes | Gate |
|---|---|---|---|---|
| 0 | The user answers D1-D6 | any | nothing | G0 |
| 1 | Host tools and the reference hook (**done**) | - | repository files only | - |
| 2 | Orbis creates the patterned image by FTP | [ORBIS] | the image file, made by Orbis | G2 |
| 3 | Linux learns where the image lives and proves the map (read-only) | Linux (USB root) | nothing on the internal disk | G3 |
| 4 | ext4 is created inside the image and tested; reverse proof; Orbis health check | Linux (USB root) | only inside the image's blocks | G4 |
| 5 | The current system is copied into the image | Linux (USB root) | only inside the image's blocks | G5 |
| 6 | Initramfs hook, build, FTP deploy, three boot tests | [ORBIS] then Linux (internal root) | boot files in `/data/linux/boot/`; the image | G6 |
| 7 | Acceptance (10 cold boots, power-off, Orbis check, speed) and documentation | Linux (internal root) | docs | G7 |
| 8 | A bigger image (optional, later) | all | as above | - |

Each switch between [ORBIS] and Linux costs a power cycle by the user. Group your work so that each trip is worth it.

## 2. Facts you will rely on

| # | Fact | Tag | Evidence / how to re-check |
|---|---|---|---|
| 1 | The console's `/data` is the folder `data/` of partition `sda27`; `/user` is the root of `sda27`. So `/data/linux/boot/` is physically `sda27:/data/linux/boot/` | V | `ls /mnt/ps4_internal/sda27/data/linux/boot/` shows our files; the MD5 of `bzImage` matches the FTP upload |
| 2 | `sda27` is the Orbis "user" partition: encrypted with dm-crypt `aes-xts-plain64` (256-bit key = the 32-byte EAP key), UFS2 inside, 897.6 GiB, about 330 GiB free | V | `sfdisk -d /dev/sda`, `dmsetup table ps4_sda27`, `df -h /mnt/ps4_internal/sda27` |
| 3 | `sda27`: start sector 57147392, size **1882449920** sectors, PARTUUID **`d3b99be5-f699-11e8-8092-2ccc443f695f`**, dm-crypt `iv_offset` **111669149696** (= (27-1) << 32) | V | `sfdisk -d`, `blkid`, `distro/monta_particao.sh` |
| 4 | The UFS2 superblock magic `0x19540119` is at byte offset `0x1055C` (66908) of the decrypted device. Stored little-endian, the bytes are `19 01 54 19` (derived from the endianness; confirmed in step P3-6) | V / derived | `AGENTS.md`; `distro/monta_particao.sh` |
| 5 | The key file on the host is `~/ps4-keys/eap_hdd_key.bin`: exactly 32 raw bytes. On the USB rootfs it is `/etc/ps4-keys/eap_hdd_key.bin` | V | `ls -l` (never print the content) |
| 6 | Orbis: `192.168.6.130` (FTP `2121`, GoldHEN, only while in Orbis mode). Linux: `192.168.6.128` (SSH `root` / `ps4`). **Never probe port 9090.** | V | `AGENTS.md`; used all session |
| 7 | The GoldHEN FTP server accepts upload (`STOR`), rename (`RNFR`/`RNTO`, also over an existing file) and `DELE` | V | tested 2026-11-17; used by `distro/deploy-boot-ftp-7.0.sh` |
| 8 | The payload reads `bzImage`, `initramfs.cpio.gz`, `bootargs.txt`, `vram.txt` one file at a time from `/mnt/usb0`, `/mnt/usb1`, `/data/linux/boot/`, `/user/system/boot/` (first hit wins) | V | `ps4-linux-payloads/linux/main-aio.c`, lines 379-405 |
| 9 | The initramfs is built by mkinitcpio: a 1356-byte plain cpio followed by a gzip cpio. It has **no `dmsetup`, no `cryptsetup` and no `tr`**. It has `xxd`, `blkid`, `dd`, `cat`, `cut`, `sed`, `readlink`, `basename`, `sha256sum`, `mount`, `umount`, `e2fsck`, `fsck`, `mkdir`, `rm`, `sleep` as separate binaries | V | `python3 -I $TOOLS/list_initramfs_segments.py distro/boot_referencia/initramfs-7.0-20261117-dp-diag2.cpio.gz --all` |
| 10 | The kernel unpacks concatenated initramfs segments (plain or gzip), skips zero padding, and requires a plain segment to start at a 4-byte aligned offset | V | `kernel/kernel_build_7.0/init/initramfs.c`, `unpack_to_rootfs` (lines 511-566) |
| 11 | mkinitcpio's `init` sources `/hooks/<name>` and calls `run_hook` in HOOKS order inside the same shell; afterwards it calls `resolve_device "$root"` and the mount handler. A hook can change the variable `root`. **But `fsck_root` reads `root` from the cache `/tmp/cmdline`, not from the variable**, so the hook must rewrite that cache too. `rwopt` and `rootfstype` are plain variables; a non-empty `fastboot` skips fsck | V | `init` and `init_functions` extracted from the initramfs |
| 12 | `dmsetup create NAME` reads the table from standard input when no table argument is given, so a key never has to appear in a command line | V | used on 2026-11-17: `dmsetup table --showkeys X \| dmsetup create Y` |
| 13 | dm-crypt + a RAM-backed dm-snapshot + `vfat` worked for write tests with the real partition's hash unchanged | V | `others/tests/internal_partition_write_sim.sh`; `test_history` id 121 |
| 14 | `FIBMAP` + block map + dm-linear is how two independent projects boot a root image from the Orbis user partition without USB; one of them on a Baikal Slim | P | section 12 |
| 15 | `dmsetup table` prints devices as `major:minor`, not as paths | V | standard dmsetup behavior; the guard in section 7 uses it |
| 16 | The host tools of section 8 work on ext4 and detect wrong maps; the hook's control flow passes 30 simulated checks | V | section 8 |
| 17 | The UFS2 block size that `FIGETBSZ`/`FIBMAP` use on our kernel (4096? 2048? 32768?) | **U** | step P3-2 prints it |
| 18 | That `FIBMAP` on UFS2 returns block numbers that, times the block size, are byte offsets from the start of the decrypted device (the prior art says yes) | **U** | steps P3-5 and P3-6 prove it with the pattern image |
| 19 | FTP upload speed, over WiFi and over a cable in Orbis mode | **U** | step P2-3 |
| 20 | That `APPE` (append) works on the GoldHEN FTP server, needed to resume a broken multi-hour upload | **U** | step P2-4 |
| 21 | That `DM_DISABLE_UDEV=1 dmsetup --noudevsync` creates correct `/dev/mapper` nodes inside our initramfs (no device-mapper udev rules there) | **U** | Phase 6 |
| 22 | That `rsync` exists on the console's USB rootfs | **U** | step P5-2 |
| 23 | How Orbis behaves, over weeks, with a big private file in `/data/linux/` (updates, "rebuild database", storage clean-up) | **U** | nobody has reported long-term results |
| 24 | The speed of the internal 2.5" HDD (TOSHIBA MQ04ABF100), slower than the SSDs of the prior art | **U** | Phase 7 |

## 3. The mechanism

```
internal HDD -> sda27 (raw) -> dm-crypt "ps4hdd"  (aes-xts-plain64, 32-byte key, iv_offset 111669149696)
                                  |
                                  +--> UFS2 (Orbis files). Mounted READ-ONLY, and only to learn where the image lives.
                                  |
                                  +--> dm-linear "ps4root" = exactly the blocks of /data/linux/rootfs-16g.img
                                            |
                                            +--> ext4 (label ps4internal) = the Linux root, mounted read-write
```

- **The image file is created by Orbis** (FTP upload). Orbis's own code allocates every block. Linux never writes UFS2 metadata.
- **Linux only reads** UFS2 metadata (through `FIBMAP`) to learn where each block of the file is. It stores that list as a dm-linear table.
- From then on Linux writes only inside those blocks, through `ps4root`.
- The image is **not zeros**. Every 512-byte sector carries its own index plus a random nonce. Reading all sectors back through the table and finding the right index and nonce in every one proves that the table points at exactly this file's blocks, in order. A zero-filled image cannot prove that, because zeros look the same everywhere. This is stronger than the prior art's check.
- The table, the key and a metadata file are appended to the initramfs as an extra cpio segment **at upload time only**. The key never enters git or `distro/boot_referencia/`.
- **Fallback:** if anything in the hook fails, it leaves `root=LABEL=psxitarch` untouched and the system boots from the USB drive as today.

### 3.1 Consequences you must know
1. While a dm-linear device sits on top of `ps4hdd`, the UFS2 partition cannot be mounted (expected from the kernel's exclusive-open rule on block devices [P]; confirm in step P6-9). So when the console runs from the internal root, `ps4-automount.service` cannot mount `sda27`, and **Linux cannot browse the Orbis partition**. To inspect UFS2 (for example to recompute the table), boot from the USB root. **The USB boot path must therefore stay working: it is the rollback path.**
2. The table is a fixed promise about where the file lives. If Orbis (or anyone, by FTP) deletes, moves, truncates or rewrites the image, the next Linux boot could write ext4 data over whatever Orbis put in those blocks. The hook's checks (table checksum, ext4 magic, UUID) catch only gross mistakes. **Never delete or replace the image over FTP while its table is installed.**
3. The image cannot be resized later.

## 4. Absolute prohibitions (any one of these means STOP and tell the user)
1. Mounting `sda27`, `sda29`, `sda25` or any internal partition **read-write**, or `mount -o remount,rw` on them.
2. Running `mkfs.*`, `wipefs`, `dd of=`, `sfdisk`, `parted` or `cryptsetup` (any write) on `/dev/sda*`, on `/dev/mapper/ps4_sda*`, or on `/dev/mapper/ps4hdd`. `mkfs` is allowed **only** on `/dev/mapper/ps4root_test`, after the 5-point guard of section 7.
3. Deleting, renaming or overwriting `/data/linux/rootfs-*.img` over FTP once its table exists (unless the user decided to start over; then redo Phases 2-5).
4. Writing the drive key anywhere except: `~/ps4-keys/` and `/etc/ps4-keys/` on the USB rootfs (both already exist), the **temporary** key-bearing initramfs, and `/data/linux/boot/initramfs.cpio.gz` on the console. Never in git, in `distro/boot_referencia/`, on the USB BOOT partition, in logs, in `test_history`, or in chat.
5. Using `deploy-boot-7.0.sh` (it writes to the USB drive, which would take priority over the internal files).
6. Changing two things in one boot. One variable per boot.
7. Continuing after any mismatch. "Close enough" does not exist here.
8. Pushing to GitHub.

## 5. Decisions the user must make (Phase 0). Ask in Portuguese; record the answers in section 13.

| ID | Decision | Recommended default |
|---|---|---|
| D1 | Size of the first image, which is a real bootable one | **16 GiB** (the current rootfs uses 8.7 GiB; the image cannot be resized, so a larger one comes later in Phase 8; always leave at least 10 GiB free in `sda27` for Orbis) |
| D2 | How the key reaches the initramfs | **Option A:** append it to the copy of the initramfs uploaded to the console (section 9, Phase 6). Option B (a loader that injects the key) is not available: our payload source has no key code [V: no match for `eap`/`key` in `ps4-linux-payloads/linux/*.c`] |
| D3 | If the internal root fails | **Fall back to the USB root** (`root=LABEL=psxitarch` stays in `bootargs`) |
| D4 | How the image file is created | **Orbis FTP upload of the patterned file.** The alternative used by ps4-multiboot [P] is to remount UFS2 read-write once from Linux and zero-fill the file. **Do not use it unless the user approves it in writing**, because it is the one case where Linux writes UFS2 |
| D5 | Network path for the upload | **A LAN cable to the console while it is in Orbis mode**, if the user can do it [U: not measured]. Otherwise WiFi |
| D6 | The `ps4-automount.service` when running from the internal root | **Do not run it** in internal-root mode (step P6-5), because it cannot mount `sda27` there |

## 6. Names and artifacts

| What | Value | Notes |
|---|---|---|
| Host work folder | `~/ps4-internal-root/20261117/` (`$WORK`) | Holds `nonce.txt`, `rootfs.table`, `meta`, logs. Mode 700, outside git, never contains the key |
| Image (Orbis path) | `/data/linux/rootfs-16g.img` | = `/mnt/ps4_internal/sda27/data/linux/rootfs-16g.img` seen from Linux |
| Crypt mapper | `ps4hdd` | The table text names it `/dev/mapper/ps4hdd` |
| Linear devices | `ps4root_test` (Phases 3-5, by hand) and `ps4root` (the boot hook) | |
| ext4 label | `ps4internal` | **Not** `psxitarch`: two filesystems with the same label would make `LABEL=psxitarch` ambiguous |
| Files inside the initramfs fragment | `/key/eap_hdd_key.bin`, `/etc/ps4root/rootfs.table`, `/etc/ps4root/meta` | The hook removes `/key` as soon as the mappings exist |
| Kernel command-line switch | `ps4root=internal-ro` first, later `ps4root=internal` | `bootsrc=internal` is added by the deploy script |
| Tags | `20261117-ps4root1` (switch `internal-ro`), `20261117-ps4root2` (switch `internal`) | Same `bzImage`/`config` as `20261117-dp-diag2`; the initramfs has the hook |

`meta` file (plain `KEY=VALUE`, no spaces, no quotes). You create it in Phase 3 and finish it in Phase 4:
```
PS4ROOT_IMAGE_PATH=/data/linux/rootfs-16g.img
PS4ROOT_IMAGE_BYTES=17179869184
PS4ROOT_PARTUUID=d3b99be5-f699-11e8-8092-2ccc443f695f
PS4ROOT_CRYPT_SECTORS=1882449920
PS4ROOT_IV_OFFSET=111669149696
PS4ROOT_TABLE_SHA256=<64 hex characters, printed by fibmap_table.py as table_sha256=>
PS4ROOT_EXT4_UUID=<filled in after mkfs, step P4-4>
```

## 7. The 5-point guard before any `mkfs` or any write through `ps4root_test` (mandatory)

Run it **on the console** and require all five to pass. If one fails: STOP.

```bash
HDD_MM=$(dmsetup info -c --noheadings -o major,minor --separator : ps4hdd)
echo "1. name   : $(dmsetup info -c --noheadings -o name ps4root_test)"                                      # exactly: ps4root_test
echo "2. targets: $(dmsetup table ps4root_test | awk '{print $3}' | sort -u)"                               # exactly: linear
echo "3. devices: $(dmsetup table ps4root_test | awk '{print $4}' | sort -u)  (want: $HDD_MM)"             # only the ps4hdd major:minor
echo "4. bytes  : $(( $(cat /sys/class/block/$(basename $(readlink -f /dev/mapper/ps4root_test))/size) * 512 ))"   # 17179869184
echo "5. table  : $(sha256sum /dev/shm/rootfs.table | cut -c1-64)"                                          # equals PS4ROOT_TABLE_SHA256
```

## 8. Tools (already written and tested on 2026-11-17)

All of them are in `others/tools/ps4_internal_root/`. Python 3, standard library only; English comments. Never `pip install` anything.

| Tool | Purpose | How it was tested |
|---|---|---|
| `gen_pattern_image.py` | Streams the patterned image to stdout (`--size-gib` or `--size-mib`, `--nonce`, `--skip-bytes` to resume). 1.3 GB/s, so the network is the only bottleneck | 2 GiB in 1.6 s; the tail produced with `--skip-bytes` is byte-identical to the tail of the full stream; bad arguments are refused |
| `fibmap_table.py` | `FIBMAP` of a file -> dm-linear table (`start length linear DEVICE offset`, all in 512-byte sectors). Prints a summary with `table_sha256=` on stderr. Refuses holes, sizes that are not a multiple of the block size, and extents past `--device-sectors` (exit 2) | On the host's ext4: a 256 MiB pattern file gave 160 extents; the three refusals were confirmed; the printed `table_sha256` equals `sha256sum` of the saved table |
| `verify_pattern_image.py` | Checks every 512-byte sector's index and nonce, reading either through a table and the raw device (`--table T --device D`) or from a file/device at offset 0 (`--file F`). `--sample N` checks 1 of N sectors. Exit 1 on any mismatch | Full check OK on the host (524288 sectors read through the table from the raw root partition). **Negative tests, all detected:** a table shifted by one block, a wrong nonce, two swapped extents, a table with a gap |
| `region_hash.py` | SHA-256 of the first N bytes of a device, optionally treating the image's physical blocks as zero (`--exclude-table`). Proves that the *rest* of the Orbis partition did not change | Changing bytes inside an excluded range leaves the hash equal; changing a byte outside changes it; ranges that cross a chunk boundary work; overlapping ranges are refused |
| `list_initramfs_segments.py` | Lists an initramfs the way the kernel unpacks it (`--all`, `--find NAME`, `--extract PATH`) | On the real initramfs: 2 segments, plain at 0 and gzip at 10240 |
| `append_boot_fragment.py` | Appends the key + table + meta as a third plain segment on a 4096-byte boundary. Refuses to write inside a git tree, refuses a key that is not 32 bytes, creates the output with mode 600 | With a **dummy** key: 3 segments, the fragment at offset 15106048, the extracted key equals the dummy, the first 15102034 bytes identical to the original. The real key was never used |
| `reference/hooks_ps4-internal-root` | The tested reference version of the initramfs hook | `reference/test_hook.sh` |
| `reference/install_ps4-internal-root` | The mkinitcpio install file (adds `dmsetup` and registers the hook) | `bash -n` |
| `reference/test_hook.sh` | Runs the hook on the host with stub commands and a PATH restricted to the commands that exist in the initramfs. **30 checks pass:** every failure path returns 0, keeps `root`, tears the mappings down and removes `/key`; the happy paths set `root`, `rootfstype`, the `/tmp/cmdline` cache, `rwopt` and `fastboot`; the key never appears in an argument list, a log or an output. Mutation tests confirm that it catches `tr` (absent in the initramfs), `${VAR:?}` (would kill PID 1), a missing cache rewrite, and a key put on the dmsetup command line | `bash others/tools/ps4_internal_root/reference/test_hook.sh` (use `HOOK=/path` to test an edited copy) |

What the tests do **not** cover: UFS2 (the host only has ext4), the real console, the real key, and a real initramfs boot. Phases 3 and 6 cover those.

## 9. Phases

Every step has: the action, the expected result, and **STOP if**. After each phase: write the `test_history` row, update BACKLOG `7c`, commit locally, then **ask the user for the gate**. Each phase says which mode the console must be in.

### Phase 0 - Decisions (gate G0)
Ask D1-D6 (section 5). Write the answers in section 13. Do not start Phase 2 without them.

### Phase 1 - Tools on the host (DONE on 2026-11-17)
Committed. Re-run the tool tests only if you change a tool.

### Phase 2 - Create the patterned image with Orbis (console in [ORBIS])

**Preconditions:** `ping -c1 192.168.6.130` answers; `curl -s $FTP/data/linux/` lists the folder; `curl -s $FTP/data/linux/boot/` shows the four boot files (never touch them). `sda27` has at least 330 GiB free [V on 2026-11-17].

**P2-1 and P2-2 - work folder and nonce** [HOST]
```bash
mkdir -p -m 700 $WORK && cd $WORK
python3 -c 'import os; print(os.urandom(16).hex())' > nonce.txt
cat nonce.txt
```
Expected: 32 hex characters. STOP if not.

**P2-3 - measure the upload speed first** [HOST]
```bash
python3 -I $TOOLS/gen_pattern_image.py --size-mib 64 --nonce $(cat $WORK/nonce.txt) 2>/dev/null \
  | curl -sS -T - $FTP/data/linux/speedtest.bin -w 'upload speed: %{speed_upload} bytes/s\n'
curl -s -Q "-DELE speedtest.bin" $FTP/data/linux/ > /dev/null
```
Expected: a speed. Compute the time for the real image: `17179869184 / speed`. **Tell the user the estimate. If it is over 2 hours, ask whether to use a LAN cable (D5) before going on.** STOP if the upload fails.

**P2-4 - test whether resuming works (`APPE`)** [HOST]
```bash
python3 -I $TOOLS/gen_pattern_image.py --size-mib 64 --nonce $(cat $WORK/nonce.txt) 2>/dev/null \
  | head -c $((32*1024*1024)) | curl -sS -T - $FTP/data/linux/resume-test.bin
python3 -I $TOOLS/gen_pattern_image.py --size-mib 64 --nonce $(cat $WORK/nonce.txt) --skip-bytes $((32*1024*1024)) 2>/dev/null \
  | curl -sS -a -T - $FTP/data/linux/resume-test.bin
curl -sS -o $WORK/resume-test.bin $FTP/data/linux/resume-test.bin
python3 -I $TOOLS/verify_pattern_image.py --file $WORK/resume-test.bin --size-bytes $((64*1024*1024)) --nonce $(cat $WORK/nonce.txt)
curl -s -Q "-DELE resume-test.bin" $FTP/data/linux/ > /dev/null; rm -f $WORK/resume-test.bin
```
Expected: `OK: 131072 sectors checked (every sector)...`. If it fails or `curl -a` is refused, **resume is not available**: record that as the result, and tell the user that a broken upload must restart from zero (so the cable is recommended). This is information, not a STOP.

**P2-5 - upload the real image** [HOST] (run it detached and wait for its completion notice; do not poll in a loop)
```bash
python3 -I $TOOLS/gen_pattern_image.py --size-gib 16 --nonce $(cat $WORK/nonce.txt) 2>/dev/null \
  | curl -sS -T - --speed-limit 1024 --speed-time 120 $FTP/data/linux/rootfs-16g.img
echo "curl exit status: ${PIPESTATUS[1]}"
```
Expected: exit status 0. STOP if not: do **not** delete the partial file; report; resume only if P2-4 showed that it works.

**P2-6 - check the size** [HOST]
```bash
curl -s $FTP/data/linux/ | grep rootfs-16g.img
```
Expected: the size column is exactly `17179869184`. STOP on any other value.

**P2-7 - Orbis sanity (physical).** Ask the user to look at the console's storage screen and confirm that Orbis shows normal free space (about 16 GiB less) and no warning. STOP on any warning.

**Acceptance:** file present with the exact size; speed and resume result recorded. **Gate G2.**
**Rollback:** `curl -s -Q "-DELE rootfs-16g.img" $FTP/data/linux/ > /dev/null`. Nothing depends on the file yet.

### Phase 3 - Block map and full verification (console in Linux from the USB root, UFS2 read-only)

**Preconditions:** the user booted Linux from the USB root as usual; the internal `bootargs.txt` has **no** `ps4root=`; `ssh root@192.168.6.128` works; `mount | grep ps4_internal` shows `sda27` mounted `ro`; the file `/mnt/ps4_internal/sda27/data/linux/rootfs-16g.img` exists.

**P3-1 - copy the tools to the console's RAM** [HOST]
```bash
sshpass -p ps4 scp $TOOLS/*.py root@192.168.6.128:/dev/shm/
```

**P3-2 - print the block size (fact 17)** [PS4]
```bash
python3 -c "import fcntl,struct,os;fd=os.open('/mnt/ps4_internal/sda27/data/linux/rootfs-16g.img',os.O_RDONLY);print(struct.unpack('i',fcntl.ioctl(fd,2,struct.pack('i',0)))[0])"
```
Expected: a power of two between 512 and 32768. **Record it.** STOP if it is not a multiple of 512, or if the ioctl is refused.

**P3-3 - build the table** [PS4]
```bash
python3 -I /dev/shm/fibmap_table.py /mnt/ps4_internal/sda27/data/linux/rootfs-16g.img \
  --device /dev/mapper/ps4hdd --device-sectors 1882449920 --progress \
  > /dev/shm/rootfs.table 2> /dev/shm/fibmap.summary
tail -1 /dev/shm/fibmap.summary
```
Expected: exit 0 and a summary with `size_bytes=17179869184`, `total_sectors=33554432`, the number of extents, and `table_sha256=...`. STOP on exit 2 (hole, partial block, extent beyond the device): do not "fix" it, report it. Copy `rootfs.table` and `fibmap.summary` to `$WORK` [HOST] with `sshpass -p ps4 scp root@192.168.6.128:/dev/shm/rootfs.table root@192.168.6.128:/dev/shm/fibmap.summary $WORK/`. **Record the extent count** (the prior art had 1100 extents for 32 GiB; tens of thousands would be a fragmentation problem: tell the user before going on).

Now create `$WORK/meta` with the lines of section 6, using the table checksum from the summary (leave `PS4ROOT_EXT4_UUID=` empty for now).

**P3-4 - baseline of the Orbis data, BEFORE anything else touches it** [PS4]
```bash
find /mnt/ps4_internal/sda27 -xdev | wc -l > /dev/shm/files_before.txt          # may take several minutes
sha256sum /mnt/ps4_internal/sda27/data/linux/boot/* /mnt/ps4_internal/sda27/hdmeta.dat > /dev/shm/hash_before.txt
python3 -I /dev/shm/region_hash.py --device /dev/mapper/ps4_sda27 --bytes 1073741824 \
  --exclude-table /dev/shm/rootfs.table > /dev/shm/region_before.txt
cat /dev/shm/files_before.txt /dev/shm/region_before.txt
```

**P3-5 - full verification through the table** [PS4] (reads 16 GiB; about 2-6 minutes)
```bash
python3 -I /dev/shm/verify_pattern_image.py --table /dev/shm/rootfs.table --device /dev/mapper/ps4_sda27 \
  --size-bytes 17179869184 --nonce <NONCE>
```
Expected: `OK: 33554432 sectors checked (every sector), all carry the expected index and nonce`. **Any `MISMATCH`: STOP.** The table is wrong or the file was changed. Report the first mismatching sector. `--sample` is only for a quick look, never the final proof.

**P3-6 - prove the dm-linear path itself, read-only** [PS4]
```bash
systemctl stop ps4-automount.service
ls /dev/mapper                                  # expected: control (nothing else)
KEY=$(xxd -p -c 64 /etc/ps4-keys/eap_hdd_key.bin)
printf '%s\n' "0 1882449920 crypt aes-xts-plain64 $KEY 111669149696 /dev/disk/by-partuuid/d3b99be5-f699-11e8-8092-2ccc443f695f 0" \
  | DM_DISABLE_UDEV=1 dmsetup --noudevsync create -r ps4hdd
unset KEY
dd if=/dev/mapper/ps4hdd bs=1 skip=66908 count=4 2>/dev/null | xxd -p        # expected: 19015419
DM_DISABLE_UDEV=1 dmsetup --noudevsync create -r ps4root_test < /dev/shm/rootfs.table
echo $(( $(cat /sys/class/block/$(basename $(readlink -f /dev/mapper/ps4root_test))/size) * 512 ))   # expected: 17179869184
python3 -I /dev/shm/verify_pattern_image.py --file /dev/mapper/ps4root_test --size-bytes 17179869184 --nonce <NONCE>
dmsetup remove ps4root_test; dmsetup remove ps4hdd
systemctl start ps4-automount.service
mount | grep ps4_internal                       # the three read-only mounts are back
```
Expected values are in the comments. STOP if `ls /dev/mapper` shows anything else, if the magic differs (wrong key, `iv_offset` or partition), if the size differs, or on any mismatch. These command lines are the same ones the hook uses, so they also test fact 21.

**P3-7 - baseline again and compare** [PS4]
```bash
find /mnt/ps4_internal/sda27 -xdev | wc -l > /dev/shm/files_after.txt
sha256sum /mnt/ps4_internal/sda27/data/linux/boot/* /mnt/ps4_internal/sda27/hdmeta.dat > /dev/shm/hash_after.txt
python3 -I /dev/shm/region_hash.py --device /dev/mapper/ps4_sda27 --bytes 1073741824 \
  --exclude-table /dev/shm/rootfs.table > /dev/shm/region_after.txt
diff /dev/shm/files_before.txt /dev/shm/files_after.txt && diff /dev/shm/hash_before.txt /dev/shm/hash_after.txt \
  && diff /dev/shm/region_before.txt /dev/shm/region_after.txt && echo "BASELINE UNCHANGED"
```
Expected: `BASELINE UNCHANGED`. STOP on any difference.

**Acceptance:** P3-5 and P3-6 report `OK` for every sector and the baseline is unchanged. Store the block size, extent count and `table_sha256` in `test_history`. **Gate G3.**

### Phase 4 - ext4 and write tests through dm-linear (Linux from the USB root)
This is the first time Linux writes through the map. It can only write inside the image file's blocks.

**P4-1 - writable mappings** [PS4]
```bash
systemctl stop ps4-automount.service
ls /dev/mapper                                  # expected: control
KEY=$(xxd -p -c 64 /etc/ps4-keys/eap_hdd_key.bin)
printf '%s\n' "0 1882449920 crypt aes-xts-plain64 $KEY 111669149696 /dev/disk/by-partuuid/d3b99be5-f699-11e8-8092-2ccc443f695f 0" \
  | DM_DISABLE_UDEV=1 dmsetup --noudevsync create ps4hdd
unset KEY
DM_DISABLE_UDEV=1 dmsetup --noudevsync create ps4root_test < /dev/shm/rootfs.table
```

**P4-2 - run the 5-point guard of section 7.** All five must pass. STOP otherwise.

**P4-3 - last pattern check before it is overwritten** [PS4]
```bash
python3 -I /dev/shm/verify_pattern_image.py --file /dev/mapper/ps4root_test --size-bytes 17179869184 --nonce <NONCE>
```
Expected: `OK ... every sector`. STOP on any mismatch.

**P4-4 - create the filesystem** [PS4]
```bash
mkfs.ext4 -L ps4internal -m 1 -E lazy_itable_init=0,lazy_journal_init=0 /dev/mapper/ps4root_test
blkid -s UUID -o value /dev/mapper/ps4root_test
```
Copy the UUID into `PS4ROOT_EXT4_UUID=` of `$WORK/meta` [HOST].

**P4-5 to P4-7 - write, flush, verify** [PS4]
```bash
mkdir -p /mnt/ps4_internal_root
mount /dev/mapper/ps4root_test /mnt/ps4_internal_root
head -c 1G /dev/urandom > /dev/shm/rnd.bin
sha256sum /dev/shm/rnd.bin | cut -c1-64 > /dev/shm/rnd.sha
cp /dev/shm/rnd.bin /mnt/ps4_internal_root/rnd.bin && sync
echo 3 > /proc/sys/vm/drop_caches
sha256sum /mnt/ps4_internal_root/rnd.bin | cut -c1-64; cat /dev/shm/rnd.sha      # the two lines must be equal
umount /mnt/ps4_internal_root
fsck.ext4 -fn /dev/mapper/ps4root_test; echo "fsck exit status: $?"              # expected: 0
dd if=/dev/mapper/ps4root_test bs=1M count=4 status=none | sha256sum | cut -c1-64 > /dev/shm/head4m_via_dm.txt
```
STOP if the hashes differ or fsck is not 0.

**P4-8 and P4-9 - tear down and the reverse proof** [PS4]
```bash
dmsetup remove ps4root_test; dmsetup remove ps4hdd
systemctl start ps4-automount.service
dd if=/mnt/ps4_internal/sda27/data/linux/rootfs-16g.img bs=1M count=4 status=none | sha256sum | cut -c1-64
cat /dev/shm/head4m_via_dm.txt                   # must equal the line above
```
This is the key proof: the ext4 data that went in through dm-linear is now visible **through the UFS2 file**, so it landed inside the image file's own blocks. **If the two lines differ: STOP immediately and tell the user; run nothing else that writes.**

**P4-10 - the rest of the Orbis data is unchanged** [PS4]
```bash
find /mnt/ps4_internal/sda27 -xdev | wc -l > /dev/shm/files_after4.txt
sha256sum /mnt/ps4_internal/sda27/data/linux/boot/* /mnt/ps4_internal/sda27/hdmeta.dat > /dev/shm/hash_after4.txt
python3 -I /dev/shm/region_hash.py --device /dev/mapper/ps4_sda27 --bytes 1073741824 \
  --exclude-table /dev/shm/rootfs.table > /dev/shm/region_after4.txt
diff /dev/shm/files_before.txt /dev/shm/files_after4.txt && diff /dev/shm/hash_before.txt /dev/shm/hash_after4.txt \
  && diff /dev/shm/region_before.txt /dev/shm/region_after4.txt && echo "ORBIS DATA UNCHANGED"
```
Expected: `ORBIS DATA UNCHANGED` (the `find` count may differ by one if you left a file in the image's folder; explain any difference). STOP on an unexplained one.

**P4-11 - Orbis health gate (physical).** Ask the user to power-cycle into Orbis and check: no "rebuild database" or "repair the storage" prompt, the game library and saves look normal, and one game starts. STOP on any anomaly. The image can be deleted over FTP to undo everything (Orbis never knew about the ext4 data).

**Acceptance:** every comparison equal, Orbis healthy. **Gate G4.**

### Phase 5 - Put the system on the internal ext4 (Linux from the USB root)

**P5-1 - recreate the writable mappings** exactly as P4-1, run the guard of section 7, then
```bash
mount /dev/mapper/ps4root_test /mnt/ps4_internal_root
rm -f /mnt/ps4_internal_root/rnd.bin
command -v rsync || echo "rsync is missing (fact 22): use the tar pipe below"
```

**P5-2 - copy the running system** [PS4] (the USB root is flaky: if the copy reports read errors, run it again and compare; never accept a partial copy)
```bash
# with rsync
rsync -aHAXx --numeric-ids --info=progress2 \
  --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' --exclude='/tmp/*' \
  --exclude='/mnt/*' --exclude='/lost+found' --exclude='/var/cache/pacman/pkg/*' --exclude='/etc/ps4-keys/*' \
  / /mnt/ps4_internal_root/
# without rsync
tar -C / --one-file-system --numeric-owner --xattrs --acls -cpf - \
  --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./run --exclude=./tmp --exclude=./mnt \
  --exclude=./lost+found --exclude=./var/cache/pacman/pkg --exclude=./etc/ps4-keys . \
  | tar -C /mnt/ps4_internal_root --numeric-owner --xattrs --acls -xpf -
mkdir -p /mnt/ps4_internal_root/{proc,sys,dev,run,tmp,mnt}; chmod 1777 /mnt/ps4_internal_root/tmp
```
Expected: exit status 0. (`/etc/ps4-keys` is left out on purpose: in internal-root mode the key is not needed there.)

**P5-3 - fix `/etc/fstab` in the copy only** [PS4]. Print `cat /mnt/ps4_internal_root/etc/fstab`. The `/` line must become `/dev/mapper/ps4root / ext4 rw,noatime 0 0`, and any `psxitarch` entry must go. Make the edit with a small Python script (in `/dev/shm`) that asserts the old text occurs exactly once; show the user the diff. Expected: `grep psxitarch /mnt/ps4_internal_root/etc/fstab` prints nothing.

**P5-4 - check, then tear down** [PS4]
```bash
diff -r /etc /mnt/ps4_internal_root/etc | head -30          # only fstab (and ps4-keys) may differ
umount /mnt/ps4_internal_root
fsck.ext4 -fn /dev/mapper/ps4root_test; echo "fsck exit status: $?"        # expected: 0
dmsetup remove ps4root_test; dmsetup remove ps4hdd
systemctl start ps4-automount.service
```
STOP if fsck is not 0 or other files differ.

**Acceptance:** fsck clean; the fstab (and the missing keys) are the only differences. Re-run P4-10 to show Orbis data unchanged. **Gate G5.**

### Phase 6 - The initramfs hook, the build, the deploy, the boot tests

**P6-1 - bring the tested hook into the repository** [HOST]
```bash
mkdir -p distro/initcpio/hooks distro/initcpio/install
cp $TOOLS/reference/hooks_ps4-internal-root   distro/initcpio/hooks/ps4-internal-root
cp $TOOLS/reference/install_ps4-internal-root distro/initcpio/install/ps4-internal-root
bash $TOOLS/reference/test_hook.sh | tail -1           # expected: hook simulation: 30 passed, 0 failed
HOOK=distro/initcpio/hooks/ps4-internal-root bash $TOOLS/reference/test_hook.sh | tail -1   # same, on the copy
```
**Do not edit the hook unless a boot test proves a bug.** If you do edit it, rerun `test_hook.sh` first, and add a case for the bug.

**P6-2 - make the official build install it** [HOST]. In `distro/01-build-image-7.0.sh`, after the block that creates the `set-time-from-cmdline` hook (around line 868): copy the two files with `install -Dm755 "$SCRIPT_DIR/initcpio/hooks/ps4-internal-root" "$ROOTFS_DIR/etc/initcpio/hooks/ps4-internal-root"` and `install -Dm644 "$SCRIPT_DIR/initcpio/install/ps4-internal-root" "$ROOTFS_DIR/etc/initcpio/install/ps4-internal-root"`; change `BINARIES=()` to `BINARIES=(dmsetup)`; and put `ps4-internal-root` in `HOOKS` **right after `block`**. Use the Edit tool; show the user the diff.

**P6-3 - fast path for the existing USB rootfs** [HOST]. Identify the USB disk by label (`lsblk -o NAME,LABEL,SIZE`), then:
```bash
sudo mount /dev/<USB root partition> /mnt/ps4_rootfs_7.0          # the partition labeled psxitarch
sudo install -Dm755 distro/initcpio/hooks/ps4-internal-root   /mnt/ps4_rootfs_7.0/etc/initcpio/hooks/ps4-internal-root
sudo install -Dm644 distro/initcpio/install/ps4-internal-root /mnt/ps4_rootfs_7.0/etc/initcpio/install/ps4-internal-root
# edit /mnt/ps4_rootfs_7.0/etc/mkinitcpio.conf as in P6-2 (BINARIES=(dmsetup), hook after block); show the diff
cd distro/boot_referencia
cp bzImage-7.0-20261117-dp-diag2 bzImage-7.0-20261117-ps4root1
cp config-7.0-20261117-dp-diag2  config-7.0-20261117-ps4root1
sed 's/$/ ps4root=internal-ro/' bootargs-7.0-20261117-dp-diag2.txt > bootargs-7.0-20261117-ps4root1.txt
cd ../..
sudo ./distro/rebuild-initramfs-7.0.sh 20261117-ps4root1
python3 -I $TOOLS/list_initramfs_segments.py distro/boot_referencia/initramfs-7.0-20261117-ps4root1.cpio.gz --find ps4-internal-root
python3 -I $TOOLS/list_initramfs_segments.py distro/boot_referencia/initramfs-7.0-20261117-ps4root1.cpio.gz --find dmsetup
python3 -I $TOOLS/list_initramfs_segments.py distro/boot_referencia/initramfs-7.0-20261117-ps4root1.cpio.gz --find libdevmapper
sudo umount /mnt/ps4_rootfs_7.0
```
Expected: the hook, `dmsetup` and `libdevmapper` are listed. STOP if one is missing. **The initramfs in `distro/boot_referencia/` must stay key-free.**

**P6-4 - extend `distro/deploy-boot-ftp-7.0.sh`** with `--internal-root DIR` (DIR holds `rootfs.table` and `meta`) [HOST]. With the option the script must: create a `mktemp -d` folder (mode 700, outside the repository, removed by a `trap` on exit); build the key-bearing initramfs there with `append_boot_fragment.py --key $HOME/ps4-keys/eap_hdd_key.bin`; upload **that** file as `initramfs.cpio.gz` through the existing `.part`, MD5 and rename flow; and **create the backup folder with mode 700** (from now on the previous initramfs it backs up contains the key). English messages. Keep `--dry-run` working. Test: `--dry-run` shows the plan; a real run ends with every MD5 `OK`; the key appears in no output; after the run `ls -ld` of the backup folder shows `drwx------`.

**P6-5 - the `ps4-automount` condition** (decision D6). In the unit text of `distro/01-build-image-7.0.sh` (the `ps4-automount.service` block) and in the copy on the internal ext4 (mount it as in P5-1), add two lines to `[Unit]`: `ConditionKernelCommandLine=!ps4root=internal` and `ConditionKernelCommandLine=!ps4root=internal-ro`. Re-run `fsck.ext4 -fn` after.

**P6-6 - deploy tag `ps4root1`** [HOST, console in ORBIS]
```bash
./distro/deploy-boot-ftp-7.0.sh 20261117-ps4root1 --internal-root $WORK --vram 1024 --dry-run
./distro/deploy-boot-ftp-7.0.sh 20261117-ps4root1 --internal-root $WORK --vram 1024
```
Then download the uploaded initramfs once, confirm with `list_initramfs_segments.py` that it has **3 segments** (the third with `key/eap_hdd_key.bin`), and **delete the downloaded copy**.

**P6-7 - boot test 1, read-only** (`ps4root=internal-ro`; the USB root drive stays plugged in as the fallback). Ask the user to load the payload. Then [PS4]:
```bash
cat /proc/cmdline
findmnt -no SOURCE,OPTIONS /
dmsetup ls
dmesg | grep -i ps4-internal-root
```
Expected: root is `/dev/mapper/ps4root` mounted `ro`; the log lines say `OK: root is now /dev/mapper/ps4root (internal-ro)`. If the log says `FAILED: ...` and the console booted from the USB root, the fallback worked: read the reason, fix **one** thing in the repository (rerun `test_hook.sh`), rebuild with a new tag, redeploy, and boot again. If the console does not boot at all: the user power-cycles and loads the payload again; if it still fails, from Orbis run `./distro/deploy-boot-ftp-7.0.sh 20261117-dp-diag2` (plain initramfs) to restore the old boot.

**P6-8 - boot test 2, read-write.** Create tag `20261117-ps4root2` exactly as in P6-3 (copy `bzImage`, `config` and the new initramfs from `ps4root1`), but with `sed 's/ps4root=internal-ro/ps4root=internal/'` on the bootargs, deploy it as in P6-6, and boot. [PS4] check `findmnt /` shows `rw`, `systemctl is-system-running`, `systemctl --failed`, `swapon --show`, SSH, and write a test file.

**P6-9 - confirm the exclusive-open rule (fact for section 3.1).** [PS4], while running from the internal root:
```bash
mount -t ufs -o ro,ufstype=ufs2 /dev/mapper/ps4hdd /mnt/ps4_internal_root 2>&1 | head -2
```
Expected: it fails (device busy). If it succeeds, **STOP and tell the user**: two paths to the same blocks are open, which is dangerous. Unmount at once.

**P6-10 - boot test 3, no USB drive.** The user unplugs the USB root drive, power-cycles and loads the payload. Expected: the console reaches the same state. If it does not boot: plug the drive back and verify that the fallback works.

**Acceptance of Phase 6:** tests 1 to 3 pass, **and** the fallback is shown to work once (corrupt the table checksum in `meta` on purpose, redeploy, and see the USB root come up with `FAILED: table checksum mismatch` in `dmesg`; then restore the correct `meta`). **Gate G6.**

### Phase 7 - Acceptance and documentation
- 10 consecutive cold boots without the USB drive. After each: `findmnt /`, `dmesg | grep -c "I/O error, dev sda"` (must be 0), `systemctl --failed`. After the last: a clean `shutdown -h now` (blue light and fan must stop).
- The Orbis health check again (the user).
- Measure: `dd if=/dev/zero of=/root/w bs=1M count=1024 conv=fdatasync; rm /root/w` and a 1 GiB read on the internal root (fact 24), and compare with the USB root.
- Update `RELEASE_NOTES.md` and `README.md` (English), `AGENTS.md` (one short paragraph), and mark BACKLOG `7c` done. **Claim nothing the tests did not show.**

### Phase 8 - A bigger image (optional, later, only if the user wants it)
Repeat Phases 2-6 for a larger image (for example 100-200 GiB), copy the system with `rsync` from the 16 GiB root, switch `meta` and the table, and keep the 16 GiB image until the new one is accepted. Always leave at least 10 GiB free in `sda27` for Orbis.

## 10. Rollback summary

| Situation | Action |
|---|---|
| Any phase up to 5 | Nothing was booted from the internal root. Delete `/data/linux/rootfs-16g.img` over FTP (Orbis mode) if the user wants everything gone |
| A boot test fails and the console does not come up | The user power-cycles; from Orbis run `./distro/deploy-boot-ftp-7.0.sh 20261117-dp-diag2`: plain initramfs, no `ps4root=`, boots from the USB root as before |
| The internal image is damaged | The USB root is untouched; boot from it and redo Phase 5 |
| Total undo | Remove `ps4root=` from the console's `bootargs.txt`, delete the image and the key-bearing initramfs from `/data/linux/`, delete every `~/ps4-boot-internal-backup-*` folder made after Phase 6 (they hold the key), and delete `$WORK` |

## 11. Notes on the hook (details are in `others/tools/ps4_internal_root/reference/hooks_ps4-internal-root`)

What it does, in order: read `ps4root=` from the command line; require the key, table, meta and `dmsetup`; require every meta variable; check the table's SHA-256; wait for `/dev/disk/by-partuuid/<PARTUUID>`; check the partition size; create the dm-crypt mapping from a table fed on standard input (the key never appears in an argument list); remove `/key`; check the UFS2 magic; create the dm-linear mapping; check its size, the ext4 magic and the UUID; do a trial read-only mount; and only then set `root`, `rootfstype`, rewrite the `root=` line of `/tmp/cmdline`, and (in read-only mode) set `rwopt=ro` and `fastboot=1`. On any failure it removes both mappings and `/key` and leaves `root` untouched.

Known weak points to watch in the Phase 6 boots: whether `dmsetup` needs more libraries than mkinitcpio's `add_binary` picks (check with `--find libdevmapper`); whether `/dev/disk/by-partuuid/` appears in time (the hook waits up to 30 s); whether libdevmapper creates the `/dev/mapper` nodes with `DM_DISABLE_UDEV=1` (the hook runs `dmsetup mknodes` as a second chance); whether `blkid` reads a UUID from a dm device without the udev database (it reads the superblock directly, so it should).

## 12. Sources (prior art, all [P])

- meerzulee/linux-psx issue #5, root on `/data/linux/psxitarch.img`, Baikal Slim, no USB: https://github.com/meerzulee/linux-psx/issues/5
- blue0x1/ps4-multiboot (Belize tested; Baikal experimental): https://github.com/blue0x1/ps4-multiboot, [`initramfs/init`](https://raw.githubusercontent.com/blue0x1/ps4-multiboot/main/initramfs/init), [`initramfs/blockmap.c`](https://raw.githubusercontent.com/blue0x1/ps4-multiboot/main/initramfs/blockmap.c)
- Juniorleao06/ps4-linux-internal-drive (Baikal Slim, 50 GiB image, same kernel family as ours): https://github.com/Juniorleao06/ps4-linux-internal-drive
- Old tutorials for Aeolia/Belize that say not to use them on Baikal: https://dionkill.github.io/ps4-linux-tutorial/internal-installation.html , https://zfentom.github.io/playstation-linux-tutorial/ps4/internal-installation
- An initramfs that expects the loader to provide `/key/eap_hdd_key.bin`: https://github.com/loreps/initramfsps4-loreps-v.
- Kernel initramfs format: `Documentation/driver-api/early-userspace/buffer-format.rst` and `init/initramfs.c` in our tree.

What the prior art reported (not verified here): the root mounted at 14.7 s and a 1 GiB write ran at 253 MB/s on an SSD; one clean power-off left Orbis healthy; repeated cold boots, long uptime, power loss during writes, the stock HDD, and Orbis updates were not tested.

## 13. Decisions log (the executing agent fills this in after Phase 0)

| ID | Answer | Date | Who answered |
|---|---|---|---|
| D1 | | | |
| D2 | | | |
| D3 | | | |
| D4 | | | |
| D5 | | | |
| D6 | | | |

## 14. Progress log (append one line per finished step; never rewrite history)

| Date | Step | Result | test_history id |
|---|---|---|---|
| 2026-11-17 | Phase 1: host tools and the reference hook written and tested | OK | see BACKLOG 7c |

## 15. Template for a test_history row

```sql
INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
VALUES ('2026-11-DD', 'Internal rootfs: Phase N', 'step ids', 'sda27 image rootfs-16g.img / initramfs hook',
        'what was run (never include the key)', 'SUCCESS | FAILED | PARTIAL',
        'measured values: sizes, extent count, hashes (first 12 hex characters are enough), times, anything unexpected');
```
