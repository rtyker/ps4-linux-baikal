# bridge_icc — read the MN864729 (DP→HDMI bridge) registers from userspace

Read-only tools that talk to the Panasonic MN864729 bridge through the same ICC
command (`0x10/0`, I2C command queue) that `ps4_bridge.c` uses, by way of the
`/dev/icc` ioctl (`others/tools/icc_cmd`). No kernel build is needed.

| Script | What it does |
|---|---|
| `bridge_dump.sh` | Dumps every block the driver writes (`0x1000`, `0x10c0`, `0x1e00`, `0x6000`, `0x60f0`, `0x6a00`, `0x7000-0x70ff`, `0x7200`, `0x7400`, `0x7600-0x76ff`, `0x7a80`) as `ADDR VALUE` lines, 16 bytes per ICC call |
| `bridge_watch.sh N reg...` | Samples the given registers N times (for live status bits) |

## Usage (console, as root)

```bash
scp others/tools/icc_cmd/icc_cmd others/tools/bridge_icc/*.sh root@<PS4>:/tmp/
ssh root@<PS4> '/tmp/icc_cmd selftest'                       # must answer first
ssh root@<PS4> 'sh /tmp/bridge_dump.sh > /tmp/bridge.txt'    # ~52 ICC calls
ssh root@<PS4> 'sh /tmp/bridge_watch.sh 10 7008 705f 60f8 60f9'
```

## Wire format (taken from `cq_read`/`cq_writereg`/`cq_exec` in `ps4_bridge.c`)

Request (`icc_cmd raw 0x10 0 <hex> --reply 48 --yes`), **one hex argument**:

```
04 | len_lo len_hi | n_cmds | major len minor count | entry...
read  N bytes at AAAA:  04 0c 00 01  01 08 01 01  NN AA AA 00
write 1 byte  at AAAA:  04 0c 00 01  02 08 02 01  01 AA AA VV
```

Reply: `res1 res2 unk1 unk2 count` (`res1 res2` must be `00 00`), then the echo
`NN AA AA`, then the data (data starts at reply byte 8). Verified on 2026-11-18:
`0x7005` (TSYSCTRL) reads `0x80`, the value the driver writes.

## Rules

- **Read-only by default.** The scripts only send `CMD_READ`. A write is a
  separate, deliberate `icc_cmd raw` call, one register, with a value of known
  origin (the driver's own), and with someone watching the monitor.
- **Pass the payload as ONE argument.** `icc_cmd` reads only `argv[4]`; a split
  payload is silently truncated. On 2026-11-18 this sent an 8-byte queue whose
  header said 12; the MCU rejected it (`res1=06 res2=10`) and nothing changed,
  but check the length (`24` hex chars for the formats above) before sending.
- The ioctl takes the same mutex as the drivers; do not run it during a modeset.
