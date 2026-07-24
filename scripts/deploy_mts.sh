#!/bin/bash
# Deploy mts.ko to PS4 via telnet
# Usage: ./scripts/deploy_mts.sh [push|pull|test]

set -e

PS4_IP="192.168.6.128"
PS4_PORT="23"
MTS_KO="/mnt/t/downloads/PS4/linux_in_ps4/drivers_mts/build/mts.ko"
REMOTE_KO="/tmp/mts.ko"

push_module() {
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
    
    # Deploy via telnet
    expect -c "
        spawn telnet $PS4_IP $PS4_PORT
        set timeout 15
        expect \"~ # \"
        send \"rmmod mts 2>/dev/null; sleep 1\r\"
        expect \"~ # \"
        send \"wget http://192.168.6.100:8000/mts.ko -O $REMOTE_KO\r\"
        expect \"~ # \"
        send \"insmod $REMOTE_KO stage=4\r\"
        expect \"~ # \"
        send \"echo 'Module loaded successfully'\r\"
        expect \"~ # \"
        send \"exit\r\"
        expect eof
    "
    
    kill $HTTP_PID 2>/dev/null
    echo "Push complete"
}

pull_module() {
    echo "Pulling mts.ko from PS4 (not implemented - PS4 doesn't have the built module)"
    exit 1
}

test_module() {
    echo "Testing mts.ko on PS4 (eth0 on 192.168.0.2)..."
    
    expect -c "
        spawn telnet $PS4_IP $PS4_PORT
        set timeout 20
        expect \"~ # \"
        send \"cat /sys/bus/pci/devices/0000:00:14.1/mts_regs\r\"
        expect \"~ # \"
        send \"ifconfig eth0 192.168.0.2 netmask 255.255.255.0 up\r\"
        expect \"~ # \"
        send \"ping -I eth0 -c 5 192.168.0.1 &\r\"
        expect \"~ # \"
        send \"sleep 4\r\"
        expect \"~ # \"
        send \"cat /sys/bus/pci/devices/0000:00:14.1/mts_regs\r\"
        expect \"~ # \"
        send \"dmesg | grep RX_CLEAN | head -30\r\"
        expect \"~ # \"
        send \"ifconfig eth0 | grep RX\r\"
        expect \"~ # \"
        send \"dmesg | tail -40\r\"
        expect \"~ # \"
        send \"exit\r\"
        expect eof
    "
}

case "${1:-push}" in
    push)
        push_module
        ;;
    pull)
        pull_module
        ;;
    test)
        test_module
        ;;
    *)
        echo "Usage: $0 [push|pull|test]"
        exit 1
        ;;
esac