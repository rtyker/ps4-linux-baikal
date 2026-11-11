# 🚀 Teste #6 — Habilitação de RX/TX por Padrão (2026-07-23)

**Data:** 2026-07-23  
**Status:** 📝 Planejado

---

## 1. O que foi Feito

**Alteração em `drivers_mts/mts.c` (linhas 78-84):**

```diff
-static bool enable_rx = false;
-MODULE_PARM_DESC(enable_rx, "Habilita recepção RX (default false)");
+static bool enable_rx = true;
+MODULE_PARM_DESC(enable_rx, "Habilita recepção RX (default true)");

-static bool enable_tx = false;
-MODULE_PARM_DESC(enable_tx, "Habilita transmissão TX (default false)");
+static bool enable_tx = true;
+MODULE_PARM_DESC(enable_tx, "Habilita transmissão TX (default true)");
```

**Justificativa:**
- O Teste #5 confirmou que o link Ethernet sobe (carrier=1, `Link UP: 1000 Mbps`).
- RX e TX já estão **100% implementados** no driver (`mts_rx_clean()`, `mts_start_xmit()`, NAPI, timer de polling).
- Estavam apenas **desabilitados por padrão** como medida de segurança durante o desenvolvimento.
- Agora é seguro ativá-los por padrão para testar DHCP e conectividade TCP/IP.

---

## 2. Próximas Ações (após rebuild do kernel)

### 2.1 Teste de DHCP
```bash
# No PS4, via SSH:
dhclient eth0
ip addr show eth0
```

**Sucesso esperado:**
```
eth0: <BROADCAST,RUNNING,MULTICAST> mtu 1500
  inet 192.168.0.X/24 brd 192.168.0.255 scope global dynamic eth0
```

### 2.2 Teste de Ping
```bash
ping -c 4 192.168.0.1      # seu gateway/roteador
ping -c 4 8.8.8.8          # Google DNS (se houver rota externa)
```

**Sucesso esperado:**
```
PING 192.168.0.1 (192.168.0.1) 56(84) bytes of data.
64 bytes from 192.168.0.1: icmp_seq=1 ttl=64 time=X.XXX ms
```

### 2.3 Log do Kernel (dmesg)
```bash
# Procurar por:
# - "Link UP"
# - "mts_rx_clean"
# - "rx_packets"/"rx_bytes"
# - Sem "rx_errors"/"tx_dropped"
dmesg | tail -50
```

---

## 3. Possíveis Problemas & Fallbacks

Se **DHCP/ping falhar**, o problema pode estar em:

| Sintoma | Possível Causa | Próximo Passo |
|---------|----------------|---------------|
| `Link UP` mas sem resposta de ARP | MAC não tá enviando frames (TX falho) | Verificar ponteiros TX (0x3c/0x40 em BAR0) |
| `Link UP` mas DHCP timeout | MAC não tá recebendo frames (RX falho) | Verificar buffer RX e flags OWN nos descritores |
| Muitos `rx_errors` | Descritores com tamanho errado | Revisar `mts_rx_clean()` e `MTS_RX_BUF_SIZE` |
| TX parado após alguns pacotes | Anel TX lotado, reclamação não funciona | Revisar `mts_tx_reclaim()` e descritor wrap |
| Kernel Panic ao enviar | Descritor TX com endereço DMA inválido | Verificar `dma_map_single()` e `dma_sync_single_for_device()` |

---

## 4. Linha de Investigação Aberta

**Registrador de STATUS** ainda não foi identificado:
- O registrador IMR (0x54) está mascarado em 0x00 (sem interrupções).
- Não sabemos qual registrador sinala "RX pronto" ou "TX completo".
- Se DHCP falhar, a próxima etapa será RE do kernel Orbis 12.52 (`consolidado/dumps_orbis/kmem_dump_1252.bin`) para achar a rotina de read do registrador de status.

---

## 5. Git & Build

**Commit esperado após este teste:**
```bash
git add drivers_mts/mts.c
git commit -m "feat(mts): habilita RX/TX por padrão para teste de conectividade DHCP/IP"
```

**Build:**
```bash
cd /mnt/hdauxiliar/temp/kernel_build_7.0
./00-build-kernel-7.0.sh
```

---

## 6. Marco Esperado

Se RX/TX funcionar:
- **Git tag:** `v7.0-20260723-rxtx-enabled-dhcp-ok`
- **Resumo:** "Ethernet Gigabit funcional com RX/TX, DHCP e IP ativos"

