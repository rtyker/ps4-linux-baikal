#!/bin/bash
# Deploy mts.ko to PS4 via SSH
# Usage: ./others/scripts/deploy_mts.sh [push|test]
#
# push does rmmod + insmod on the console. After a driver instance has enabled the MAC
# or published DMA rings, unloading it is forbidden (others/docs/PLAN_ETH0_BAIKAL.md,
# prohibition 3), so push refuses when mts is already loaded unless MTS_ALLOW_RMMOD=1.

set -e

PS4_IP="192.168.6.128"
PS4_PORT="22"
PS4_USER="root"
PS4_PASS="ps4"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MTS_KO="$SCRIPT_DIR/../../kernel/drivers_mts/build/mts.ko"   # moved from drivers_mts/ on 2026-11-11
REMOTE_KO="/tmp/mts.ko"

# Check dependencies
if ! command -v sshpass &>/dev/null; then
    echo "ERROR: sshpass not found. Install with: sudo pacman -S sshpass"
    exit 1
fi

SSH_CMD="sshpass -p $PS4_PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $PS4_USER@$PS4_IP"
SCP_CMD="sshpass -p $PS4_PASS scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

push_module() {
    if [ "${MTS_ALLOW_RMMOD:-0}" != "1" ] && $SSH_CMD "lsmod | grep -q '^mts '"; then
        echo "ERROR: mts is already loaded on the console; push would rmmod it."
        echo "       Unloading a driver that enabled the MAC is forbidden (PLAN_ETH0_BAIKAL.md, prohibition 3)."
        echo "       Reboot instead, or set MTS_ALLOW_RMMOD=1 if you know the MAC was never enabled."
        exit 1
    fi

    echo "Pushing mts.ko to PS4..."

    # Start HTTP server in background
    cd "$(dirname "$MTS_KO")"
    python3 -m http.server 8000 > /tmp/http_server.log 2>&1 &
    HTTP_PID=$!
    sleep 1

    # Verify server
    if ! curl -s http://127.0.0.1:8000/mts.ko -o /dev/null; then
        kill $HTTP_PID 2>/dev/null
        echo "ERROR: HTTP server failed to start"
        exit 1
    fi

    # Deploy via SCP (more robust than wget for large files)
    echo "  Copying mts.ko via SCP..."
    $SCP_CMD "$MTS_KO" "$PS4_USER@$PS4_IP:$REMOTE_KO"

    # Unload old module and load new one
    echo "  Loading module..."
    $SSH_CMD "rmmod mts 2>/dev/null; sleep 1; insmod $REMOTE_KO stage=4; echo 'Module loaded successfully'"

    kill $HTTP_PID 2>/dev/null
    echo "Push complete"
}

test_module() {
    echo "Testing mts.ko on PS4 (eth0 on 192.168.0.2)..."

    $SSH_CMD "
        echo '=== mts_regs ==='
        cat /sys/bus/pci/devices/0000:00:14.1/mts_regs 2>/dev/null || echo '(mts_regs not available)'
        echo ''
        echo '=== Setting up eth0 ==='
        ifconfig eth0 192.168.0.2 netmask 255.255.255.0 up
        echo ''
        echo '=== Ping test (5 packets) ==='
        ping -I eth0 -c 5 192.168.0.1
        echo ''
        echo '=== mts_regs after test ==='
        cat /sys/bus/pci/devices/0000:00:14.1/mts_regs 2>/dev/null || echo '(mts_regs not available)'
        echo ''
        echo '=== RX logs ==='
        dmesg | grep RX_CLEAN | head -30
        echo ''
        echo '=== ifconfig eth0 ==='
        ifconfig eth0 | grep RX
        echo ''
        echo '=== dmesg tail ==='
        dmesg | tail -40
    "
}

case "${1:-push}" in
    push)
        push_module
        ;;
    test)
        test_module
        ;;
    *)
        echo "Usage: $0 [push|test]"
        exit 1
        ;;
esac
