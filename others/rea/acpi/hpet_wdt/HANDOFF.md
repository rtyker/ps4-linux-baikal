# HANDOFF — HPET / Watchdog do Baikal (glue 00:14.4, subfunção ICC 22)

> ## ⛔ REVISÃO de 2026-11-17 (feita por outro agente, a pedido do usuário) — LEIA ANTES DO RESTO
> **HPET/WDT está PAUSADO por decisão do usuário.** `CONFIG_CLKSRC_BAIKAL_HPET` foi **redesligado** no `00-build-kernel-7.0.sh` (o §5 Passo 1 abaixo mandava ligá-lo; **não repita**). Pontos deste documento que estavam errados ou perigosos:
> 1. **"O driver se auto-desabilita se o contador não incrementa" (§7) é FALSO.** Em `baikal-hpet.c`, contador parado só gera `dev_warn("MAIN_COUNTER not incrementing")` e o driver **continua e registra o clocksource com rating 300**; CAP inesperado também só avisa ("but continuing"). Só não travou o relógio do sistema porque o bootargs tem `clocksource=tsc`. Antes de qualquer retomada, o probe deve **recusar (`-ENODEV`)** se o CAP ou o contador não baterem.
> 2. **"Causa raiz identificada" (seção de testes de 2026-11-17) é HIPÓTESE.** O código mapeia o início da BAR2 (`pcim_iomap_table(pdev)[2]`), mas o cabeçalho do mesmo arquivo diz BAR2 + `0x109000`; é coerente, mas ninguém leu `0x109000` com o driver corrigido.
> 3. **O teste usou "bind forçado"** de um driver num device que já tem dono (`baikal_pcie`), e **o deploy no HD foi feito à mão** ("script falhou em copiar"), fora do procedimento oficial. **Não sei qual kernel ficou ativo no HD**; conferir `active-tag.txt`, o `md5` do `bzImage` e o `config` da partição BOOT antes de qualquer outro teste.
> 4. O build do teste (`20261117-hpet-clocksource-test`) misturou `CLKSRC_MMIO=y` embutido, que o próprio script apontava como suspeito de 2 boots mortos em 2026-11-15, com outras variáveis.
> 5. Os `config`s estão desligados de novo; o "Status" abaixo volta a ser verdadeiro.


**Subsistema:** HPET (High Precision Event Timer) + Watchdog Timer  
**Dispositivo PCI:** Baikal PCIe Glue `104d:90db`, função 4 (`00:14.4`)  
**Subfunção ICC:** 22 (`BPCIE_SUBFUNC_HPET`)  
**Hardware:** PS4 Slim/Pro (CUH-2xxx/CUH-7xxx, Baikal B1)  
**Kernel alvo:** 7.0.8-Strawberry-ThinLTO-Baikal-+ (x86_64)  
**Status:** Patches **prontos e aplicados** no build; configs **desligados** por padrão até validação ao vivo isolada.  
**Acesso ao PS4:** SSH WiFi `root@192.168.6.128`, senha `ps4`.  

---

## 1. Resumo do estado (o que existe, o que falta)

| Item | Estado | Detalhes |
|------|--------|----------|
| **Evidência de hardware** | ✅ Confirmada | Header Sony (`drivers/ps4/baikal.h`), dump Orbis (strings + registro device), leitura ao vivo CAP register |
| **Leitura ao vivo (Fase 0)** | ✅ Feita 2026-11-13 | `0xc8909000` = `0x05f5e10000002301` (estável em 2 boots frios) |
| **Clocksource driver** | ✅ Patch pronto | `kernel/patches/clocksource-baikal-hpet.patch` → `drivers/clocksource/baikal-hpet.c` |
| **Watchdog driver** | ✅ Patch pronto | `kernel/patches/baikal-wdt.patch` → `drivers/watchdog/baikal_wdt.c` |
| **Build script** | ✅ Patches aplicados | `00-build-kernel-7.0.sh` aplica ambos pós-`git reset --hard` com `--check` + `exit 1` |
| **Configs no build** | ⚠️ **Desligados** | `CONFIG_CLKSRC_BAIKAL_HPET=n`, `CONFIG_WATCHDOG=n`, `CONFIG_WATCHDOG_CORE=n` |
| **Validação ao vivo** | ❌ **Pendente** | Nunca foi carregado no PS4 — risco de tela preta (histórico 2026-11-15) |

**O que bloqueia a ativação:** Em 2026-11-15, habilitar `CONFIG_WATCHDOG=y` (core embutido) junto com `CLKSRC_MMIO=y` (selecionado pelo HPET) coincidiu com **2 boots mortos** — UART para em `kexec: About to relocate and jump to kernel`. Nunca se provou causalidade, mas a regra do projeto é: **testar isolado, um por vez, sempre como módulo (`=m`)**, nunca `=y`.

---

## 2. Hardware confirmado

| Item | Valor |
|------|-------|
| Dispositivo PCI | `104d:90db` (Baikal PCIe Glue), função 4 (`00:14.4`) |
| Subfunção ICC | 22 (`BPCIE_SUBFUNC_HPET`) |
| Base MMIO | `BAR2 + 0x109000` = `0xc8909000` (BAR2 base `0xc8800000`, tamanho 2 MiB) |
| Tamanho do bloco | `0x400` bytes (`BPCIE_HPET_SIZE`) |
| CAP/TIMCAP (offset 0x00) | `0x05f5e10000002301` — **estável em 2 boots** |
| REV_ID | 1 |
| NUM_TIM_CAP | 3 (→ 4 timers: 0, 1, 2, 3) |
| LEG_RT_CAP | 1 |
| Vendor ID (bits 16-31) | `0x0000` (atípico — **não usar como validação de presença**) |
| General Config (offset 0x10) | **HIGH_RISK_POWER_OFF** — não ler/escrever até driver validado |
| Timer N Config (offset 0x100 + 0x20·N) | **HIGH_RISK_POWER_OFF** — não ler/escrever até driver validado |

**Offsets validados como SAFE no banco REA:**
- `0x109000` (CAP/TIMCAP) — `safe_to_read=1` (id 1339)
- `0x109010` (GENERAL_CONFIG) — `HIGH_RISK_POWER_OFF`, `safe_to_read=0` (id 1340)

---

## 3. Patches existentes (já no repo)

### Clocksource
- **Arquivo:** `kernel/patches/clocksource-baikal-hpet.patch`
- **Gera:** `drivers/clocksource/baikal-hpet.c`
- **Kconfig:** `CONFIG_CLKSRC_BAIKAL_HPET` (module, `depends on X86 && PCI`, `select CLKSRC_MMIO`)
- **Função:** usa `MAIN_COUNTER` (64-bit free-running) como clocksource, rating 300

### Watchdog (opcional)
- **Arquivo:** `kernel/patches/baikal-wdt.patch`
- **Gera:** `drivers/watchdog/baikal_wdt.c`
- **Kconfig:** `CONFIG_BAIKAL_WDT` (module, `depends on X86 && PCI && WATCHDOG_CORE`)
- **Função:** Timer 0 em modo one-shot com `INT_ENB_CNF`, `nowayout=0`, timeout default 30s
- **⚠️ Escreve em:** `GENERAL_CONFIG` (bit 0) e `TIMER_0_CONFIG` (bit 2) — **só habilitar após validação de leitura**

Ambos são **um único `pci_driver` da glue** (`104d:90db` função 4), porque o bloco HPET vive na BAR2 da glue.

---

## 4. Restrições CRÍTICAS (violação = PS4 desliga)

1. **Nunca varredura sequencial/bloco na BAR2 da glue** (`0xc8800000`–`0xc89fffff`). Risco `HIGH_RISK_POWER_OFF` registrado como `BAR2_SEQUENTIAL_BLOCK_READ`. Apenas acessos **pontuais** de 8 bytes (ou 4 bytes alinhados) em offsets validados.
2. **Offsets validados SAFE:** só `0x109000` (CAP). `0x109010` (GENERAL_CONFIG) é `HIGH_RISK_POWER_OFF`.
3. **Nenhuma escrita** antes do driver estar completo, testado em 2 boots frios, e revisado.
4. **Leitura via `/dev/mem`** (validações) ou `ioremap` + `readq` no driver. `/dev/mem` existe, `CONFIG_STRICT_DEVMEM` não está setado.

---

## 5. Próximos passos (ordem obrigatória)

### Passo 1 — Ativar só o clocksource (baixo risco, só leitura)
```bash
# No 00-build-kernel-7.0.sh, editar a linha ~1050 (procure por "DESLIGADO por padrão"):
# scripts/config --disable CONFIG_CLKSRC_BAIKAL_HPET
# → scripts/config --module CONFIG_CLKSRC_BAIKAL_HPET

# MANTER desligado (linhas ~1054-1057):
# scripts/config --disable CONFIG_WATCHDOG
# scripts/config --disable CONFIG_WATCHDOG_CORE
```
1. Build: `sudo ./kernel/00-build-kernel-7.0.sh 20261117-hpet-clocksource-test`
2. Deploy boot: `sudo ./distro/deploy-boot-7.0.sh 20261117-hpet-clocksource-test`
3. No PS4:
   ```bash
   insmod baikal-hpet.ko
   dmesg -T | grep -i baikal
   cat /sys/devices/system/clocksource/clocksource0/current_clocksource
   # deve mostrar "baikal-hpet"
   # validar que o contador incrementa (não "HPET never increments")
   ```
4. **Reboot frio** e repetir — CAP no dmesg deve ser `0x05f5e10000002301` idêntico.

**Critério de aceite:** 2 boots frios consecutivos estáveis, clocksource registrado e incrementando, **zero escritas em GENERAL_CONFIG**.

### Passo 2 — Ativar watchdog (após Passo 1 passar)
```bash
# No 00-build-kernel-7.0.sh, DEPOIS da linha do clocksource (após ~1050):
# scripts/config --enable CONFIG_WATCHDOG
# scripts/config --enable CONFIG_WATCHDOG_CORE
# scripts/config --module CONFIG_BAIKAL_WDT
# (as linhas ~1054-1057 têm --disable; comente ou substitua por --enable/--module)
```
1. Build nova tag
2. Deploy boot
3. No PS4:
   ```bash
   insmod baikal-hpet.ko
   insmod baikal_wdt.ko
   dmesg -T | grep -i baikal
   wdctl /dev/watchdog
   # teste curto: echo 1 > /dev/watchdog  (não deve reiniciar)
   ```
4. **Reboot frio** e validar.

**Critério de aceite:** watchdog carrega, `wdctl` mostra status, teste de ping no device não reinicia o console.

---

## 6. Comandos de referência para teste no PS4

```bash
# 1. Verificar se módulos existem no rootfs
sshpass -p ps4 ssh root@192.168.6.128 "find /lib/modules -name 'baikal*hpet*' -o -name 'baikal*wdt*'"

# 2. Carregar clocksource
sshpass -p ps4 ssh root@192.168.6.128 "insmod /lib/modules/.../baikal-hpet.ko; dmesg -T | tail -20"

# 3. Verificar clocksource ativo
sshpass -p ps4 ssh root@192.168.6.128 "cat /sys/devices/system/clocksource/clocksource0/current_clocksource"

# 4. Verificar contador incrementando (rodar 2x com 1s de intervalo)
sshpass -p ps4 ssh root@192.168.6.128 "cat /sys/devices/system/clocksource/clocksource0/current_clocksource; sleep 1; cat /sys/devices/system/clocksource/clocksource0/current_clocksource"

# 5. Carregar watchdog (só após Passo 1 validado)
sshpass -p ps4 ssh root@192.168.6.128 "insmod /lib/modules/.../baikal_wdt.ko; dmesg -T | tail -10"

# 6. Testar watchdog
sshpass -p ps4 ssh root@192.168.6.128 "wdctl /dev/watchdog"
sshpass -p ps4 ssh root@192.168.6.128 "echo 1 > /dev/watchdog; sleep 2; echo 'ainda vivo'"

# 7. UART (se precisar capturar boot)
# Host: ./others/scripts/uart_start.sh 120 hpet-test
# ... power cycle PS4 ...
# Host: tail -f others/tests/uart_logs/hpet-test_*.log
# Host: ./others/scripts/uart_stop.sh
```

---

## 7. Rollback / recuperação

| Situação | Ação |
|----------|------|
| Boot morto (UART para no kexec) | `sudo ./distro/deploy-boot-7.0.sh 20261116-dma-final` (último boot bom conhecido) |
| Watchdog reiniciou o PS4 | O `nowayout=0` permite fechar `/dev/watchdog` antes do timeout; se travou, power cycle + rollback acima |
| Clocksource não incrementa | `dmesg` deve mostrar `"HPET never increments, disabling"` — driver se auto-desabilita; rollback acima |

---

## 8. Referências no repositório

| Documento | Local |
|-----------|-------|
| Plano completo (este) | `others/rea/acpi/hpet_wdt/PLANO_DRIVER_ACPI_BAIKAL.md` |
| Patch clocksource | `kernel/patches/clocksource-baikal-hpet.patch` |
| Patch watchdog | `kernel/patches/baikal-wdt.patch` |
| Build script | `kernel/00-build-kernel-7.0.sh` (linhas 153, 562, **1046-1062**) |
| Header Sony (baikal.h) | `kernel/kernel_build_7.0/drivers/ps4/baikal.h` |
| Dump Orbis | `others/rea/dumps/kmem_dump_1252.bin` |
| Decompiladas Orbis | `others/rea/acpi/decompiled/` (`orbis_baikal_timer_wdt_register`, `orbis_hpet_*`) |
| Banco REA | `others/rea/ps4_hardware_memory.db` (tabelas `hardware_registers` ids 1339/1340, `readonly_verification` id 893) |
| BACKLOG (item HPET/WDT) | `others/docs/BACKLOG.md` (seção "Baikal ACPI / HPET/WDT") |

---

## 9. Checklist de "pronto para merge" (copiado do plano §3.9)

- [ ] Driver compila isolado (`make M=drivers/clocksource baikal-hpet.o`)
- [ ] Probe PCI da glue `104d:90db` função 4 funciona
- [ ] Clocksource registrado e selecionado automaticamente
- [ ] Valor CAP lido no probe = `0x05f5e10000002301` (logado no dmesg)
- [ ] 2 boots frios consecutivos estáveis
- [ ] Nenhuma escrita em `0xc8909010` (GENERAL_CONFIG) no código
- [ ] `CONFIG_CLKSRC_BAIKAL_HPET` ligado no build script (como módulo)
- [ ] Patch gerado via `git diff HEAD` (padrão AGENTS.md) — **já existe**
- [ ] `00-build-kernel-7.0.sh` aplica patch com `git apply --check` + `exit 1` se falhar — **já faz**

**Para watchdog (após clocksource validado):**
- [ ] `CONFIG_WATCHDOG` + `CONFIG_WATCHDOG_CORE` + `CONFIG_BAIKAL_WDT` como módulos
- [ ] `wdctl /dev/watchdog` funcional
- [ ] 2 boots frios com ambos carregados

---

## Testes executados — 2026-11-17 (Passo 1: Clocksource)

### Build: tag `20261117-hpet-clocksource-test`
- `CONFIG_CLKSRC_BAIKAL_HPET=m` habilitado no build script
- `CONFIG_WATCHDOG=n`, `CONFIG_WATCHDOG_CORE=n` mantidos desligados
- Build OK (8m24s, ccache 63.9% hit), deploy manual no HD (script falhou em copiar, feito manual)

### Teste ao vivo no PS4 (2026-11-17 08:08)

| Passo | Resultado |
|-------|-----------|
| 1. `modprobe baikal-hpet` (bind forçado) | ✅ Driver carrega, probe roda |
| 2. Leitura CAP register | ❌ **Lê `0x0088500000511148`** (errado) — esperado `0x05f5e10000002301` |
| 3. MAIN_COUNTER incrementa? | ❌ **Não** — `0xffe00004ffffffff` → mesmo valor após 1ms |
| 4. Clocksource registrado | ⚠️ Sim (rating 300), mas **não funcional** (contador parado) |

### Causa raiz identificada

O driver mapeia `pcim_iomap_table(pdev)[2]` → **início da BAR2** (offset 0). Mas o bloco HPET está em **BAR2 + `0x109000`** (offset dentro da BAR2 da glue).

O dispositivo `00:14.4` já tem driver `baikal_pcie` que mapeou a BAR2 completa. O `baikal-hpet` está lendo registradores da glue (offset 0), não o HPET (offset `0x109000`).

### Correção necessária no driver (`drivers/clocksource/baikal-hpet.c`)

```c
// Linha ~140, em baikal_hpet_probe():
// ATUAL (errado):
bhp->base = pcim_iomap_table(pdev)[2];

// CORRETO:
bhp->base = pcim_iomap_table(pdev)[2] + 0x109000;
```

Também ajustar validação: o `BAR2` da glue tem 2 MiB; o HPET ocupa `0x400` bytes a partir de `0x109000`.

### Próximo passo quando retomar

1. Editar `kernel/kernel_build_7.0/drivers/clocksource/baikal-hpet.c` (somar `0x109000`)
2. Compilar isolado: `make M=drivers/clocksource baikal-hpet.o`
3. Gerar patch: `git diff > kernel/patches/clocksource-baikal-hpet.patch`
4. Resetar árvore + `git apply --check`
5. Rebuild kernel tag `20261117-hpet-clocksource-fix`
6. Deploy + teste no PS4 (critério: CAP = `0x05f5e10000002301`, MAIN_COUNTER incrementa)

---

> **Nota para o próximo agente:** os patches **já estão prontos e aplicados no build**. O driver tem bug de offset (lê BAR2+0 em vez de BAR2+0x109000). Correção é trivial (uma linha). Testar isolado, como módulo, reboot frio entre etapas. Histórico de "boot morto com WATCHDOG=y" (2026-11-15) mantém regra: testar clocksource primeiro, só depois watchdog.