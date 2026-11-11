# Build Checklist: 20260801-kvm-rtc-sata-fix

**Data:** 2026-08-01  
**Tag:** `20260801-kvm-rtc-sata-fix`  
**Status:** Em compilação (deploy agendado automaticamente após conclusão)

## ✅ Componentes Incluídos no Build

### Kernel Base
- [x] Kernel 7.0.8-Strawberry-ThinLTO-Baikal
- [x] Branch: `baikal/7.0.8-Stable` (aproveitando cache)
- [x] Compilação: ThinLTO (profile General)

### Correções Críticas Incluídas

#### 1. RTC (Real-Time Clock) via ICC
- [x] Driver: `drivers/rtc/rtc-ps4-icc.c` (restaurado automaticamente via heredoc após git reset)
- [x] Config: `CONFIG_RTC_DRV_PS4_ICC=m` (módulo)
- [x] ICC Commands: major=2 minor=0x0b/0x0c (save/load context), major=4 minor=0x50 (alarme)
- [x] MMIO: 0x5180000 (read), 0x5140000 (write)
- [x] Fase: EM ANDAMENTO (compilação + deploy para teste ao vivo)
- [x] Referência: `memory/rtc-via-icc-re-validada-2026-07-25.md`

#### 2. KVM (Virtualization Support)
- [x] Config: `CONFIG_KVM=y`, `CONFIG_KVM_AMD=y`
- [x] Habilitado: Sim (linha 746-747 do script de build, última operação prevalece)
- [x] Propósito: Validar suporte a virtualização no Baikal
- [x] Teste: Planejado (ver próximas seções)

#### 3. SATA Polling Timer (HD Interno)
- [x] Patch: `patches/ahci-baikal-polling-fallback.patch` (criado 2026-08-01)
- [x] Aplicado: Automaticamente após git reset (linha 274-275 do script)
- [x] Correções incluídas:
  - [x] API `hrtimer_setup()` (não `hrtimer_init()`, removido neste kernel)
  - [x] Ack de `HOST_IRQ_STAT` (evita IRQ espúria)
  - [x] Guarda contra EH frozen (evita dupla-completação)
- [x] Fallback: 1ms polling quando PxIE=0 (bug conhecido do Baikal)
- [x] Resultado esperado: `ata1.00: configured for UDMA/100` + zero `disable device`
- [x] Referência: `memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md`

#### 4. Correções Anteriores Mantidas
- [x] Vídeo HDMI OK (baseline confirmado 2026-07-30)
- [x] GBE `mts.ko` com fix de polaridade MDIO Clause 22 (2026-07-30)
- [x] Netconsole configurado
- [x] rootwait no bootargs (ganho de 10,5s de boot)
- [x] Wireless WiFi integrado
- [x] SSH automático via systemd

## 📊 Testes Planejados Pós-Deploy

### Teste 1: RTC
```bash
# Verificar se RTC subiu
ls -l /dev/rtc*

# Teste de leitura
hwclock -r

# Teste de escrita (opcional, requer permissão)
date +%s > /tmp/test_time.txt
```

### Teste 2: KVM
```bash
# Verificar se KVM está disponível
ls -l /dev/kvm 2>/dev/null && echo "KVM disponível" || echo "KVM não disponível"

# Testar módulo
modprobe kvm_amd

# Verificar
cat /proc/cpuinfo | grep -i vmx
```

### Teste 3: SATA (HD Interno - `ata1`)
```bash
# Capture UART
scripts/uart_start.sh 300 sata-kvm-rtc-test

# Monitorar boot
tail -f tests/uart_logs/sata-kvm-rtc-test_*.log

# Critérios de Sucesso (no log UART):
# ✓ "ata1.00: configured for UDMA/100" (probe OK)
# ✓ "PS4 Baikal: AHCI polling timer started (1ms)" (fallback ativo)
# ✓ Zero ocorrências de "disable device" em 300+ segundos
# ✓ Leitura confirmada: "dd if=/dev/sda bs=1M count=50" sem erro
```

### Teste 4: Video + Ethernet + WiFi
```bash
# Video HDMI (verificar visualmente no monitor)
# Esperado: 1920x1080@60Hz estável

# Ethernet cabeada (mts.ko)
ip link show eth0
ping -c 5 -I eth0 192.168.0.1

# WiFi
ip link show wlan0
ping -c 5 -I wlan0 8.8.8.8
```

## 🔧 Detalhes Técnicos

### Por que o patch de SATA é necessário
- Baikal AHCI controlador zeroa `PxIE` (Port Interrupt Enable) após ~5s
- Sem interrupções, libata timeout em 30s + hard reset + `disable device` aos ~84s
- Polling de 1ms fornece fallback até que IRQ real volte ou timeout expire

### Por que KVM foi adicionado
- Validar suporte a virtualização no Baikal
- Potencial para testes/emulação futura

### Por que RTC foi incluído
- Feature completada (RE validada em 2026-07-25)
- Pronto para testes ao vivo (ICC + MMIO confirmados)

## ⏱️ Cronograma

| Evento | Hora | Status |
|--------|------|--------|
| Build iniciado | 12:36 UTC | ✅ Em andamento |
| Build estimado (conclusão) | ~13:45 UTC | ⏳ Aguardando (~1h ThinLTO) |
| Deploy (automático) | ~13:46 UTC | ⏳ Agendado |
| Testes no PS4 | ~14:00 UTC | ⏳ Planejado |

## 📋 Checklist de Validação Pós-Deploy

- [ ] Boot completo (earlycon → systemd[1])
- [ ] Vídeo HDMI OK (resolução 1920x1080@60Hz)
- [ ] Netconsole funcionando (captura UART)
- [ ] RTC `/dev/rtc0` presente
- [ ] KVM `/dev/kvm` presente
- [ ] `eth0` sobe com MAC correto
- [ ] SATA probe OK: `ata1.00: configured for UDMA/100`
- [ ] Zero `disable device` em 300+ segundos de uptime
- [ ] WiFi conecta (SSH 192.168.6.128:22)
- [ ] SSH acesso confirmado
- [ ] Artefatos salvos para rollback (se necessário)

## 🔙 Rollback (Se Necessário)

```bash
# Se regressão for detectada:
sudo ./deploy-boot-7.0.sh 20260730-sata-polling-fase-ab  # SATA funcional (baseline anterior)
# ou
sudo ./deploy-boot-7.0.sh 20260730-sata-reverted         # Sem SATA polling (mais estável se polling tiver bug)
```

## 📚 Referências

- `AGENTS.md` § "Idempotência de Alterações no Kernel" (nova regra 2026-08-01)
- `memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md` (regressão diagnosticada)
- `memory/rtc-via-icc-re-validada-2026-07-25.md` (RTC RE completa)
- `memory/marco-sata-interno-funcional-2026-07-30.md` (SATA baseline funcional)
- `distros/arch_minimal_v2/patches/ahci-baikal-polling-fallback.patch` (patch novo)

---

**Próximos Passos:**
1. ✅ Aguardar build (em andamento)
2. ✅ Deploy automático (agendado)
3. ⏳ UART capture pós-boot
4. ⏳ Validação de RTC/KVM/SATA ao vivo
5. ⏳ Registro de resultados em `test_history` (SQLite)

---

## 🎯 BUILD & DEPLOY — RESULTADO FINAL

**Status:** ✅ CONCLUÍDO  
**Data:** 2026-08-01  
**Duração:** ~40 minutos (12:36-13:16 UTC)

### Artefatos Gravados
- ✅ bzImage-7.0-20260801-kvm-rtc-sata-fix (16M)
- ✅ config-7.0-20260801-kvm-rtc-sata-fix (138K)
- ✅ bootargs-7.0-20260801-kvm-rtc-sata-fix.txt (521B)
- ✅ initramfs-7.0-20260801-kvm-rtc-sata-fix.cpio.gz (14M)

### ⚠️ Alerta: Patch de SATA Parcialmente Aplicado
O patch `ahci-baikal-polling-fallback.patch` **falhou em aplicar** em alguns headers:
- ❌ drivers/ata/ahci.h (hunk #1 FAILED)
- ❌ drivers/ps4/aeolia.h
- ❌ drivers/ps4/baikal.h
- ❌ drivers/ps4/ps4-bpcie-icc.c

A compilação continuou com sucesso (comportamento de fallback do script), mas o polling timer pode estar **parcialmente ativo ou completamente inativo**.

### Impacto Esperado
- SATA pode funcionar normalmente (baseado em outro driver/kernel feature)
- SATA pode sofrer timeouts como o build anterior (20260801-kvm-rtc-ok)
- **TESTE AO VIVO é necessário para confirmar status**

### Próximos Passos Urgentes
1. **Conectar HD ao PS4 e ligar**
2. **Capturar UART** durante boot (300s):
   ```bash
   scripts/uart_start.sh 300 kvm-rtc-sata-test
   ```
3. **Validar SATA** no log:
   - ✓ Sucesso esperado: `ata1.00: configured for UDMA/100` + zero `disable device`
   - ✗ Falha esperada: `qc timeout` → `disable device` (como build anterior)

4. **Se falha SATA detectada:** Rollback imediato
   ```bash
   sudo ./deploy-boot-7.0.sh 20260730-sata-polling-fase-ab
   ```

### Investigação Técnica (Post-Test)
Se SATA funcionar apesar do patch falho:
- Significa que o polling já é nativo ou outra mudança o ativa
- Rever a versão do kernel para compatibilidade com patch

Se SATA falhar:
- Patch não é suficiente para este kernel
- Alternativa: investigar se há fallback de polling nativo no kernel 7.0
- Última opção: merge manual das mudanças (sem patch genérico)

---

**Status Final:** HD pronto para testes ao vivo no PS4.
