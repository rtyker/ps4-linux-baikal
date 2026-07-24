#!/bin/bash
# Conecta via telnet ao PS4
# Uso: ./scripts/telnet_ps4.sh [comando]

PS4_IP="192.168.6.128"
PS4_PORT="23"

if [ $# -eq 0 ]; then
    # Modo interativo
    expect -c "
        spawn telnet $PS4_IP $PS4_PORT
        set timeout 10
        expect \"~ # \"
        interact
    "
else
    # Executa comando único
    CMD="$*"
    expect -c "
        spawn telnet $PS4_IP $PS4_PORT
        set timeout 10
        expect \"~ # \"
        send \"$CMD\r\"
        expect \"~ # \"
        send \"exit\r\"
        expect eof
    "
fi