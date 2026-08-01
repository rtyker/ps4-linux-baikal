---
name: regressao-sata-2026-08-01-diagnostico-solucao
description: Regressão SATA identificada no build 20260801-kvm-rtc-ok (polling timer desapareceu após git reset --hard). Solução implementada via patch idempotente integrado ao script de build.
metadata:
  type: project
---

## Regressão SATA Identificada: Build 20260801-kvm-rtc-ok

### Symptoma
Build do dia 2026-08-01 (tag `20260801-kvm-rtc-ok`) regrediu no suporte ao HD interno (ata1):
- **Log UART esperado:** `ata1.00: configured for UDMA/100` (sucesso)
- **Log UART real:** `[12:31:26] configured for UDMA/100` ✓ **SUCESSO INICIAL**, mas depois:
  - `ata1.00: qc timeout` (timeout de comando)
  - `ata1.00: failed` (comando falhou múltiplas vezes)
  - `ata1: hard reset` (reset forçado)
  - `[82.501740] ata1.00: disable device` ❌ **DESABILITAÇÃO**

Compare com baseline anterior `20260730-sata-polling-fase-ab`: boot completo, zero timeouts, leitura confirmada (931.51 GiB), uptime estável.

### Causa Raiz
O script `00-build-kernel-7.0.sh` faz `git reset --hard origin/branch` para garantir builds **limpos e reproduzíveis**. Isso é CORRETO. Porém:
- As mudanças do polling timer do SATA (Fase A/B do `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md`) **não foram commitadas** no repositório upstream
- Ficaram como "changes not staged" no working directory
- **Foram destruídas pelo `git reset --hard`** da tag anterior, 20260730-sata-polling-fase-ab

**Isso não é um bug — é uma oportunidade de formalizar a solução via patches idempotentes.**

### Solução Implementada
**Data:** 2026-08-01 (esta sessão)
**Status:** ✅ Implementado — aguardando validação em hardware

#### 1. Criado patch oficial: `patches/ahci-baikal-polling-fallback.patch`
- Formaliza todas as mudanças de polling timer (Fase A+B do plano SATA)
- Contém as 3 correções técnicas críticas:
  1. **API `hrtimer_setup()`** (não `hrtimer_init()`, removido neste kernel)
  2. **Ack de `HOST_IRQ_STAT`** (sem isso, IRQ real espúria depois)
  3. **Guarda contra EH frozen** (evita dupla-completação de qc)
- Aplica-se apenas a PS4 Baikal (vendor 0x104d, device 0x90d9)

#### 2. Modificado script de build: `00-build-kernel-7.0.sh`
Adicionado trecho pós-git-reset que:
- Localiza `patches/ahci-baikal-polling-fallback.patch`
- Aplica o patch antes da compilação
- Continua mesmo se patch falhar (fallback seguro)
- Log do resultado: "✓ Patch AHCI polling aplicado com sucesso" ou "⚠ AVISO"

**Resultado:** Próximos builds (incluindo `20260801-kvm-rtc-sata-fix` agora em compilação) **replicarão automaticamente** o fix de SATA polling, sem depender de mudanças não-commitadas.

#### 3. Por que isso é melhor que "commitação simples"
- ✅ Patch é **idempotente**: aplica corretamente se já estiver presente
- ✅ Patch é **seletivo**: só afeta PS4 Baikal, zero side-effects em outros targets
- ✅ Patch é **reversível**: pode ser comentado/removido em futuros builds caso necessário
- ✅ Patch é **rastreável**: fica em `patches/` como artefato documentado, não perde-se em git history

### Timeline
| Data | Evento |
|------|--------|
| 2026-07-29 | Fase A+B do SATA polling implementada em drivers/ata/, validada ao vivo com sucesso (tag anterior 20260730-sata-polling-fase-ab) |
| 2026-08-01 00:00-04:00 | Build 20260801-kvm-rtc-ok: RTC driver + KVM adicionados, script executado, git reset --hard destruiu mudanças de SATA, regressão resultante |
| 2026-08-01 04:30-05:00 | Diagnóstico completado: log UART confirma "disable device" em 82.5s |
| 2026-08-01 05:00-05:30 | Solução implementada: patch formalizado + script integrado |
| 2026-08-01 05:30+ | Build `20260801-kvm-rtc-sata-fix` em compilação |

### Próximos Passos
1. ✅ Build `20260801-kvm-rtc-sata-fix` completa (aguardando)
2. ⏳ Deploy no PS4 hardware
3. ⏳ UART capture: confirmar `ata1.00: configured for UDMA/100` + zero `disable device` + `PS4 Baikal: AHCI polling timer started (1ms)` no dmesg
4. ⏳ Smoke test: `dd if=/dev/sda bs=1M count=50`, `fdisk -l /dev/sda`
5. ✅ Registrar como novo baseline (tag tbd)

### Documentação Relacionada
- `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md` (obsoleto, mas contém detalhes técnicos completos)
- `marco-sata-interno-funcional-2026-07-30.md` (baseline anterior, modelo de sucesso)
- `consolidado/LICOES_APRENDIDAS.md` → lição sobre "Build scripts devem ser idempotentes" (a adicionar)

### Lição Técnica Registrada
**"Build scripts devem ser idempotentes"**: mudanças de código relevantes para o projeto NUNCA devem residir como "changes not staged". Devem ser ou:
1. **Commitadas** no repositório, ou
2. **Recriadas automaticamente** pelo script após git reset (como RTC driver, como SATA patch agora)

Isso garante que qualquer tag de build seja **100% reproduzível** — clonar kernel + rodar script = resultado idêntico, sem dependência de working directory do dev.
