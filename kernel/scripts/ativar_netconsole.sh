#!/bin/bash
# scripts/ativar_netconsole.sh — Configura e ativa o netconsole no PS4 remotamente

# Configurações padrão
PS4_IP="192.168.6.128"
REMOTE_PORT="6666"
LOCAL_PORT="6665"

echo "=== Ativação do Netconsole no PS4 ==="

# 1. Obter informações de rota e rede do host PC
echo "[+] Detectando interface e rota de rede local para $PS4_IP..."
ROUTE_INFO=$(ip route get "$PS4_IP" 2>/dev/null)
if [ -z "$ROUTE_INFO" ]; then
    echo "[-] ERRO: Não foi possível obter rota de rede para $PS4_IP. O PS4 está ligado e na mesma rede?"
    exit 1
fi

LOCAL_DEV=$(echo "$ROUTE_INFO" | grep -oP 'dev \K\S+')
LOCAL_IP=$(echo "$ROUTE_INFO" | grep -oP 'src \K\S+')
LOCAL_MAC=$(ip link show "$LOCAL_DEV" | grep -oP 'link/ether \K\S+')

if [ -z "$LOCAL_IP" ] || [ -z "$LOCAL_MAC" ]; then
    echo "[-] ERRO: Não foi possível determinar IP/MAC locais."
    exit 1
fi

echo "    - Interface local: $LOCAL_DEV"
echo "    - IP local: $LOCAL_IP"
echo "    - MAC local: $LOCAL_MAC"

# 2. Configurar o PS4 remotamente via SSH
echo "[+] Enviando comandos de configuração para o PS4..."
SSH_CMD="sshpass -p 'ps4' ssh -o StrictHostKeyChecking=no root@$PS4_IP"

# Comando remoto a ser executado no PS4
REMOTE_SCRIPT="
    # Descobrir a interface do PS4 que possui o IP correto
    PS4_DEV=\$(ip -o addr show | grep '$PS4_IP/' | awk '{print \$2}' | head -n1)
    if [ -z \"\$PS4_DEV\" ]; then
        echo \"[-] ERRO no PS4: Interface para o IP $PS4_IP não encontrada.\"
        exit 1
    fi
    echo \"    [PS4] Usando interface: \$PS4_DEV\"

    # Criar target no configfs se não existir
    TARGET_DIR=\"/sys/kernel/config/netconsole/target1\"
    mkdir -p \"\$TARGET_DIR\"

    # Desabilitar temporariamente para poder configurar
    echo 0 > \"\$TARGET_DIR/enabled\"

    # Escrever parâmetros
    echo \"\$PS4_IP\" > \"\$TARGET_DIR/local_ip\"
    echo \"\$PS4_DEV\" > \"\$TARGET_DIR/dev_name\"
    echo \"$LOCAL_IP\" > \"\$TARGET_DIR/remote_ip\"
    echo \"$LOCAL_MAC\" > \"\$TARGET_DIR/remote_mac\"
    echo \"$REMOTE_PORT\" > \"\$TARGET_DIR/remote_port\"
    echo \"$LOCAL_PORT\" > \"\$TARGET_DIR/local_port\"

    # Reativar netconsole
    echo 1 > \"\$TARGET_DIR/enabled\"

    # Ajustar loglevel do printk para capturar mensagens de debug
    echo 8 > /proc/sys/kernel/printk

    echo \"[+] Netconsole configurado e ativado no PS4 com sucesso!\"
"

eval "$SSH_CMD" \""$REMOTE_SCRIPT"\"

if [ $? -eq 0 ]; then
    echo "[+] Concluído com sucesso!"
    echo "-------------------------------------------------------"
    echo "Para assistir os logs do Kernel ao vivo, execute:"
    echo "  tail -f netconsole_ps4.log"
    echo "-------------------------------------------------------"
else
    echo "[-] Falha ao configurar netconsole no PS4. Verifique a conexão SSH."
fi
