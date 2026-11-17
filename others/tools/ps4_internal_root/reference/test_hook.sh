#!/bin/bash
# Simulates the control flow of hooks_ps4-internal-root on the host, with stub commands, and checks that:
#   - the hook uses only commands that exist in the initramfs (the PATH is restricted to those),
#   - every failure path returns 0, leaves "root" untouched and tears the mappings down,
#   - the happy paths set root, rootfstype, the command-line cache, rwopt and fastboot as intended,
#   - the key never appears in any command line, log or output.
# It changes nothing outside a temporary folder. Run:  bash test_hook.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/hooks_ps4-internal-root}"      # override with HOOK=/path to test an edited copy
SH="$(command -v dash || command -v sh)"
PASS=0
FAIL=0

# Real tools that exist in the project's initramfs (checked against its file list on 2026-11-17).
ALLOWED="cat dd mkdir rm sleep head sync stat readlink basename cut sed xxd sha256sum mknod ash"

new_world() {
    W="$(mktemp -d)"
    mkdir -p "$W/bin" "$W/key" "$W/etc/ps4root" "$W/dev/disk/by-partuuid" "$W/dev/mapper" \
             "$W/sys/class/block/sda27" "$W/tmp" "$W/fixtures"
    for t in $ALLOWED; do
        p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$W/bin/$t"
    done
    UUID_PART="d3b99be5-f699-11e8-8092-2ccc443f695f"
    head -c 32 /dev/urandom > "$W/key/eap_hdd_key.bin"
    KEYHEX="$(xxd -p -c 64 "$W/key/eap_hdd_key.bin")"
    : > "$W/dev/sda27"
    ln -s "$W/dev/sda27" "$W/dev/disk/by-partuuid/$UUID_PART"
    echo 1882449920 > "$W/sys/class/block/sda27/size"
    mkdir -p "$W/sys/class/block/ps4root"; echo 32 > "$W/sys/class/block/ps4root/size"
    printf '0 32 linear /dev/mapper/ps4hdd 1000\n' > "$W/etc/ps4root/rootfs.table"
    TSHA="$(sha256sum "$W/etc/ps4root/rootfs.table" | cut -c1-64)"
    cat > "$W/etc/ps4root/meta" <<EOF
PS4ROOT_IMAGE_PATH=/data/linux/rootfs-16g.img
PS4ROOT_IMAGE_BYTES=16384
PS4ROOT_PARTUUID=$UUID_PART
PS4ROOT_CRYPT_SECTORS=1882449920
PS4ROOT_IV_OFFSET=111669149696
PS4ROOT_TABLE_SHA256=$TSHA
PS4ROOT_EXT4_UUID=11111111-2222-3333-4444-555555555555
EOF
    head -c 70000 /dev/zero > "$W/fixtures/ufs.bin"
    printf '\031\001\124\031' | dd of="$W/fixtures/ufs.bin" bs=1 seek=66908 conv=notrunc 2>/dev/null
    head -c 4096 /dev/zero > "$W/fixtures/ext4.bin"
    printf '\123\357' | dd of="$W/fixtures/ext4.bin" bs=1 seek=1080 conv=notrunc 2>/dev/null
    echo "root=LABEL=psxitarch" > "$W/tmp/cmdline"
    : > "$W/dmsetup.log"; : > "$W/kmsg"

    cat > "$W/bin/dmsetup" <<'STUB'
#!/bin/sh
# stub: logs the arguments (never the standard input), validates the table shape, creates fake nodes.
# The stub is a separate process, so it may use the host's full PATH; only the hook is restricted.
PATH=/usr/bin:/bin
echo "ARGV: $*" >> "$STUB_W/dmsetup.log"
ro=0; name=""; cmd=""
for a in "$@"; do
    case "$a" in
        -r) ro=1 ;;
        --noudevsync|-f) ;;
        create|remove|mknodes) cmd="$a" ;;
        *) [ -n "$cmd" ] && [ -z "$name" ] && name="$a" ;;
    esac
done
case "$cmd" in
    create)
        [ "$ro" = 1 ] && echo "RO create $name" >> "$STUB_W/dmsetup.log" || echo "RW create $name" >> "$STUB_W/dmsetup.log"
        if [ "$name" = ps4hdd ]; then
            [ "${STUB_FAIL_CRYPT:-0}" = 1 ] && exit 1
            IFS= read -r line
            echo "$line" | grep -Eq '^0 [0-9]+ crypt aes-xts-plain64 [0-9a-f]{64} [0-9]+ [^ ]*/dev/disk/by-partuuid/[0-9a-f-]+ 0$' \
                && echo "TABLE_SHAPE_OK" >> "$STUB_W/dmsetup.log" || echo "TABLE_SHAPE_BAD" >> "$STUB_W/dmsetup.log"
            cp "$STUB_W/fixtures/${STUB_UFS:-ufs.bin}" "$STUB_W/dev/mapper/ps4hdd"
        else
            [ "${STUB_FAIL_LINEAR:-0}" = 1 ] && exit 1
            cat > /dev/null
            cp "$STUB_W/fixtures/${STUB_EXT4:-ext4.bin}" "$STUB_W/dev/mapper/ps4root"
        fi ;;
    remove) echo "remove $name" >> "$STUB_W/dmsetup.log"; rm -f "$STUB_W/dev/mapper/$name" ;;
    mknodes) ;;
esac
exit 0
STUB
    cat > "$W/bin/blkid" <<'STUB'
#!/bin/sh
echo "${STUB_UUID:-11111111-2222-3333-4444-555555555555}"
STUB
    cat > "$W/bin/mount" <<'STUB'
#!/bin/sh
[ "${STUB_FAIL_MOUNT:-0}" = 1 ] && exit 1
exit 0
STUB
    cat > "$W/bin/umount" <<'STUB'
#!/bin/sh
exit 0
STUB
    chmod +x "$W/bin/dmsetup" "$W/bin/blkid" "$W/bin/mount" "$W/bin/umount"

    # test copy of the hook: absolute paths moved under $W, block-device tests turned into existence tests
    sed -e "s|/key|$W/key|g" -e "s|/etc/ps4root|$W/etc/ps4root|g" \
        -e "s|/dev/disk/by-partuuid|$W/dev/disk/by-partuuid|g" -e "s|/dev/mapper|$W/dev/mapper|g" \
        -e "s|/sys/class/block|$W/sys/class/block|g" -e "s|/tmp/cmdline|$W/tmp/cmdline|g" \
        -e "s|/tmp/ps4root_trial|$W/tmp/ps4root_trial|g" -e "s|/dev/kmsg|$W/kmsg|g" \
        -e 's|\[ -b |[ -e |g' "$HOOK" > "$W/hook.sh"
}

# run_case NAME EXPECT(ok|keep) [VAR=value ...]   (extra env for the stubs and for getarg: MODE=...)
run_case() {
    local name="$1" expect="$2"; shift 2
    local out rc
    out="$(env -i PATH="$W/bin" STUB_W="$W" "$@" "$SH" -c '
        getarg() { printf "%s" "$MODE"; }
        poll_device() { [ -e "$1" ]; }
        root="LABEL=psxitarch"; unset rwopt fastboot rootfstype
        . "'"$W"'/hook.sh"
        run_hook; rc=$?
        echo "RESULT rc=$rc root=$root rootfstype=${rootfstype:-} rwopt=${rwopt:-} fastboot=${fastboot:-}"
    ' 2>&1)"
    rc=0
    echo "$out" | grep -q "RESULT rc=0 " || { rc=1; echo "   (run_hook did not return 0 / the shell died)"; }
    case "$expect" in
        ok)   echo "$out" | grep -q "root=$W/dev/mapper/ps4root " || rc=1 ;;
        keep) echo "$out" | grep -q "root=LABEL=psxitarch " || rc=1 ;;
    esac
    # the key must never appear in any output or log
    if echo "$out" | grep -q "$KEYHEX" || grep -q "$KEYHEX" "$W/dmsetup.log" "$W/kmsg" 2>/dev/null; then
        rc=1; echo "   KEY LEAKED"
    fi
    LAST_OUT="$out"
    if [ $rc -eq 0 ]; then PASS=$((PASS+1)); echo "PASS  $name"; else FAIL=$((FAIL+1)); echo "FAIL  $name"; echo "$out" | sed 's/^/      /'; fi
}

check() {   # check DESCRIPTION CONDITION-COMMAND...
    local d="$1"; shift
    if "$@"; then PASS=$((PASS+1)); echo "PASS  $d"; else FAIL=$((FAIL+1)); echo "FAIL  $d"; fi
}

[ -f "$HOOK" ] || { echo "hook file not found: $HOOK"; exit 2; }

new_world; run_case "mode not requested: nothing happens" keep MODE=
check "  ...no dmsetup call" test ! -s "$W/dmsetup.log"; rm -rf "$W"

new_world; run_case "internal: happy path" ok MODE=internal
check "  ...both mappings created read-write" sh -c "grep -q 'RW create ps4hdd' '$W/dmsetup.log' && grep -q 'RW create ps4root' '$W/dmsetup.log'"
check "  ...crypt table has the expected shape (read from stdin)" grep -q TABLE_SHAPE_OK "$W/dmsetup.log"
check "  ...the key file was removed" test ! -e "$W/key"
check "  ...the command-line cache now points at the internal root" grep -q "^root=$W/dev/mapper/ps4root\$" "$W/tmp/cmdline"
check "  ...rwopt and fastboot untouched in read-write mode" sh -c "echo '$LAST_OUT' | grep -q 'rwopt= fastboot='"
rm -rf "$W"

new_world; run_case "internal-ro: happy path" ok MODE=internal-ro
check "  ...both mappings created read-only" sh -c "grep -q 'RO create ps4hdd' '$W/dmsetup.log' && grep -q 'RO create ps4root' '$W/dmsetup.log'"
check "  ...rwopt=ro and fastboot=1" sh -c "echo '$LAST_OUT' | grep -q 'rwopt=ro fastboot=1'"
rm -rf "$W"

new_world; rm -f "$W/key/eap_hdd_key.bin"; run_case "failure: no key" keep MODE=internal; rm -rf "$W"
new_world; rm -f "$W/etc/ps4root/rootfs.table"; run_case "failure: no table" keep MODE=internal; rm -rf "$W"
new_world; rm -f "$W/etc/ps4root/meta"; run_case "failure: no meta" keep MODE=internal; rm -rf "$W"
new_world; sed -i '/PS4ROOT_EXT4_UUID/d' "$W/etc/ps4root/meta"; run_case "failure: meta lacks a variable" keep MODE=internal; rm -rf "$W"
new_world; echo "0 32 linear /dev/mapper/ps4hdd 2000" > "$W/etc/ps4root/rootfs.table"; run_case "failure: table checksum mismatch" keep MODE=internal
check "  ...no mapping was created" sh -c "! grep -q ' create ' '$W/dmsetup.log' && ! grep -q 'RW create\|RO create' '$W/dmsetup.log'"; rm -rf "$W"
new_world; rm -f "$W/dev/disk/by-partuuid/$UUID_PART"; run_case "failure: internal partition not found" keep MODE=internal; rm -rf "$W"
new_world; echo 1000 > "$W/sys/class/block/sda27/size"; run_case "failure: partition size differs" keep MODE=internal; rm -rf "$W"
new_world; run_case "failure: dm-crypt creation fails" keep MODE=internal STUB_FAIL_CRYPT=1
check "  ...the key file was still removed" test ! -e "$W/key"; rm -rf "$W"
new_world; head -c 70000 /dev/zero > "$W/fixtures/ufs_bad.bin"; run_case "failure: UFS2 magic wrong (bad key or iv_offset)" keep MODE=internal STUB_UFS=ufs_bad.bin
check "  ...the mappings were removed" grep -q "remove ps4hdd" "$W/dmsetup.log"; rm -rf "$W"
new_world; run_case "failure: dm-linear creation fails" keep MODE=internal STUB_FAIL_LINEAR=1
check "  ...ps4hdd was removed again" grep -q "remove ps4hdd" "$W/dmsetup.log"; rm -rf "$W"
new_world; echo 9999 > "$W/sys/class/block/ps4root/size"; run_case "failure: image size differs" keep MODE=internal; rm -rf "$W"
new_world; head -c 4096 /dev/zero > "$W/fixtures/ext4_bad.bin"; run_case "failure: no ext4 magic on the image" keep MODE=internal STUB_EXT4=ext4_bad.bin; rm -rf "$W"
new_world; run_case "failure: ext4 UUID differs" keep MODE=internal STUB_UUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee; rm -rf "$W"
new_world; run_case "failure: trial mount fails" keep MODE=internal STUB_FAIL_MOUNT=1
check "  ...both mappings were removed" sh -c "grep -q 'remove ps4root' '$W/dmsetup.log' && grep -q 'remove ps4hdd' '$W/dmsetup.log'"; rm -rf "$W"

echo
echo "hook simulation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
