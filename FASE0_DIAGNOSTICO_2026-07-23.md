# FASE 0 — Diagnóstico Telnet — 2026-07-23 (noite)

## Status do Console

**Estado:** Console respondendo via telnet (`192.168.6.128:23`)  
**Carga:** 15.72, 13.41, 11.37 (bastante alta no momento do teste)  
**Uptime:** 2:10 quando testado

## Problemas Identificados

### ❌ Módulo `mts` Preso em "Unloading"

```bash
~ # lsmod | grep mts
mts 36864 -1 - Unloading 0xffffffffa0800000 (O-)
```

**Sintomas:**
- Qualquer comando que toque no subsistema de rede (ex: `ifconfig`) congela/não retorna
- `rmmod mts -f` falha com "Resource busy"
- Isso indica que uma tentativa anterior de descarregar o módulo ficou pendernte no kernel

**Causa provável:**
- Última iteração de testes deixou o driver em estado instável
- `rmmod` foi executado mas o kernel não conseguiu descarregar completamente
- IRQ/device em estado zombie

### ✅ Comandos Funcionando

- `uptime` ✅
- `ls` ✅  
- `echo` ✅
- `lsmod` ✅

### ❌ Comandos Congelando

- `ifconfig` ❌ (não retorna)
- `ip addr show` ❌ (não retorna)
- Qualquer acesso a `/sys/class/net/eth0/` (presumido, não testado)

## Próxima Ação Necessária

**OBRIGATÓRIO:** Power cycle completo do PS4
1. Desligar fisicamente da tomada
2. Aguardar 30 segundos
3. Ligar novamente
4. Aguardar boot completo
5. Reabrir GoldHEN/Payload Server
6. Conectar telnet de novo

## Testes Planejados após Power Cycle

Uma vez com console limpo, executar:

```bash
# Fase 0A: Verificar interfaces sem carregar mts
ip addr show
ifconfig -a

# Fase 0B: Carregar driver limpo
rmmod mts 2>/dev/null; true
insmod /tmp/mts.ko stage=4

# Fase 0C: Testar isolamento de interface
ping -I eth0 -c 5 192.168.6.100

# Fase 0D: Coletar stats
ifconfig eth0
ifconfig wlan0
cat /sys/class/net/eth0/device/mts_regs | head -20
```

## Rastreamento

**Arquivo gerado:** Este arquivo (`FASE0_DIAGNOSTICO_2026-07-23.md`)  
**Status:** Bloqueado à espera de power cycle do usuário  
**Prox versão planejada:** FASE0_RESULTADO_POS_POWERCYCLE.md (após restart)
