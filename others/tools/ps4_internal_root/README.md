# ps4_internal_root: tools for putting the Linux root filesystem on the PS4's internal disk

These tools belong to the runbook [`others/docs/PLAN_INTERNAL_ROOTFS.md`](../../docs/PLAN_INTERNAL_ROOTFS.md). **Read the runbook first; do not use these tools on their own.** They are outside the official build (`others/` is for diagnostics and research).

All tools are Python 3 with the standard library only. None of them writes to a disk: they read, hash, verify or write a file you name.

| File | What it does |
|---|---|
| `gen_pattern_image.py` | Streams a patterned image (index + nonce in every 512-byte sector) to stdout, for an FTP upload |
| `fibmap_table.py` | Turns the `FIBMAP` block list of a file into a dm-linear table |
| `verify_pattern_image.py` | Checks that every sector of an image carries the right index and nonce, through a table or directly |
| `region_hash.py` | SHA-256 of the start of a device, ignoring the image's own blocks (proves the rest did not change) |
| `list_initramfs_segments.py` | Lists an initramfs segment by segment, like the kernel unpacks it |
| `append_boot_fragment.py` | Appends the key, table and meta to a copy of an initramfs (refuses to write inside a git tree) |
| `reference/hooks_ps4-internal-root` | Tested reference version of the mkinitcpio runtime hook |
| `reference/install_ps4-internal-root` | The matching mkinitcpio install file |
| `reference/test_hook.sh` | Simulates the hook on the host with stub commands (30 checks) |

Tests done on 2026-11-17 (all on the host, none on the console): see section 8 of the runbook. The tools have not run on UFS2 yet; Phase 3 of the runbook does that.

**The drive key is secret.** Never put it in git, in `distro/boot_referencia/`, in a log, or in a message. `append_boot_fragment.py` writes its output with mode 600 and refuses a path inside a git working tree.
