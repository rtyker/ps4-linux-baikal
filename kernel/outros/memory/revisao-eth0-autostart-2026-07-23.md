---
name: revisao-eth0-autostart-2026-07-23
description: Revisão — eth0 autostart está INCOMPLETO no próximo build (systemd-networkd não habilitado)
metadata:
  type: project
---

## 🔍 Revisão: eth0 Autostart — Status INCOMPLETO

**Solicitação:** Revisar se próximo build release está configurado para eth0 subir automaticamente.

**Resultado:** ⚠️ **PARCIALMENTE CONFIGURADO — Há uma falha crítica.**

---

## ✅ O Que Está Configurado Corretamente

### 1. **mts.ko carrega automaticamente**
```bash
# Em 01-build-image-7.0.sh, linha ~283
echo "mts" > "$ROOTFS_DIR/etc/modules-load.d/mts.conf"
echo "options mts stage=4" > "$ROOTFS_DIR/etc/modprobe.d/mts.conf"
```
✅ Módulo `mts.ko` carrega com `stage=4` no boot (sem intervenção manual)

### 2. **Arquivo de configuração de rede estática existe**
```bash
# Em 01-build-image-7.0.sh, linhas ~198-207
cat > "$ROOTFS_DIR/etc/systemd/network/20-ethernet.network" << 'NETEOF'
[Match]
Name=eth0

[Network]
Address=192.168.0.2/24
Gateway=192.168.0.1
DNS=192.168.0.1
DNS=8.8.8.8
NETEOF
```
✅ Configuração estática de IP pronta (192.168.0.2/24)

### 3. **Bootargs com netconsole**
```bash
netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff
```
✅ Netconsole configurado esperando eth0 ativo em 192.168.0.2

### 4. **dhcpcd bloqueado para eth0**
```bash
# Em 01-build-image-7.0.sh, linha ~297
echo "denyinterfaces eth0" >> "$ROOTFS_DIR/etc/dhcpcd.conf"
```
✅ Impede conflito: dhcpcd só gerencia wlan0, eth0 é estático

---

## ❌ **FALHA CRÍTICA: systemd-networkd.service NÃO HABILITADO**

### O Problema
O script de build **menciona** `systemd-networkd` (linhas 198, 295) e **cria** o arquivo de configuração `/etc/systemd/network/20-ethernet.network`, MAS **NUNCA HABILITA** o serviço `systemd-networkd.service` no boot!

**Resultado:** Arquivo de config existe, mas nenhum serviço systemd está ativo para lê-lo e configurar a interface.

### Serviços Habilitados Atualmente (grep do script)
```bash
sshd.service                 ✅ SSH remoto
ssh-auto-startup.service    ✅ SSH auto
wpa_supplicant@wlan0        ✅ WiFi
dhcpcd                      ✅ DHCP (bloqueado para eth0)
systemd-networkd.service    ❌ FALTA ISSO!
```

---

## 🤔 Como eth0 "Sobe" Hoje?

Baseado no comportamento observado ao vivo (2026-07-23):
1. **mts.ko carrega** via `/etc/modules-load.d/mts.conf` ✅
2. **Interface eth0 é criada** pelo driver (após probe) ✅
3. **MAC é lido** pela SPM ✅
4. **DMA rings programam** ✅
5. **Interface fica UP** (status `UP`, mas `NO-CARRIER`) ✅
6. **IP estático configurado???** ⚠️ INCERTO

**Pergunta aberta:** A interface realmente está recebendo o IP 192.168.0.2, ou só está detectada mas sem IP?

---

## 🔧 Para CORRIGIR (Próximo Build)

### Solução: Habilitar systemd-networkd.service

Adicionar ao script `01-build-image-7.0.sh` (após as linhas 290-297):

```bash
# CORREÇÃO: Habilitar systemd-networkd para carregar configurações de rede estática (eth0)
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/systemd-networkd.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"

# (Opcional mas recomendado) Habilitar systemd-resolved para DNS
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
```

### Localização Exata no Script
Entre as linhas:
```
297  echo "denyinterfaces eth0" >> "$ROOTFS_DIR/etc/dhcpcd.conf"
298  [INSERIR AQUI ↓]
299  echo "=== Instalando módulos do kernel 7.0 ==="
```

### Validação Pós-Rebuild
Após rebuild, ao boot do PS4:
```bash
# Telnet para PS4 (via WiFi, não precisa eth0 ainda)
telnet 192.168.6.128 22

# Verificar eth0
ip link show eth0     # Deve estar UP
ip addr show eth0     # Deve mostrar 192.168.0.2/24
ping 192.168.0.1      # Deve responder (gateway)

# Verificar serviço
systemctl status systemd-networkd  # Deve estar "active (running)"
```

---

## 📋 Checklist de Estado

| Item | Status | Correção Necessária |
|------|--------|-------------------|
| mts.ko carrega | ✅ OK | Não |
| Config arquivo existe | ✅ OK | Não |
| systemd-networkd habilitado | ❌ FALHA | **SIM** |
| IP 192.168.0.2 sobe | ⚠️ INCERTO | **SIM** |
| Netconsole funciona | ⚠️ INCERTO | Depende de ✅ acima |

---

## ⚠️ Impacto da Falha

### Na Sessão Atual (2026-07-23)
- **eth0 sobe (interface UP)** — motorista mts.ko carrega ✅
- **MAC é lido corretamente** — driver inicializa ✅
- **DMA rings programam** — registradores escrevem ✅
- **IP 192.168.0.2 é atribuído** — ⚠️ **INCERTO** (systemd-networkd não está rodando)
- **Netconsole UDP funciona** — ⚠️ **INCERTO** (bootargs espera eth0 em 192.168.0.2)

### Próximo Build (Se Não Corrigir)
- Same issue: eth0 detectada, IP **talvez não** configurado
- Netconsole pode não funcionar (depende do IP)
- RX/TX ainda incompletos de qualquer forma

---

## 🎯 Recomendação Final

**ANTES DO PRÓXIMO BUILD RELEASE:**

1. Adicionar symlink de `systemd-networkd.service` (3 linhas)
2. Testar ao vivo: `ip addr show eth0` deve mostrar 192.168.0.2/24
3. Testar netconsole: `nc -lu 6666` no host deve capturar kernel logs ao vivo
4. Marcar como "v7.0-20260723-eth0-autostart-COMPLETO" quando validado

**Esforço:** ~5 min (3 linhas de código) + ~10 min teste (power cycle 1x)

---

## Referências

- Script de build: `/mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/01-build-image-7.0.sh`
- Configuração de rede: `/mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/boot_referencia/bootargs-7.0-20260723-mts-autoeth0.txt`
- Status atual: `memory/status-build-20260723.md`

---

**Revisão realizada:** 2026-07-23
**Status:** ⚠️ AÇÃO RECOMENDADA ANTES DO RELEASE
