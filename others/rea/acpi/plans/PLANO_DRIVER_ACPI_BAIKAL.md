# Plano — Baikal ACPI (00:14.0) e HPET/WDT da glue (00:14.4) — revisado 2026-11-13

> **Dispositivo ACPI:** Sony Baikal ACPI · **PCI:** `104d:90d7` (`00:14.0`) · **Subsystem:** `104d:90df`
> **Dispositivo do timer:** Baikal **glue** `104d:90db` (`00:14.4`), subfunção ICC **22**
>
> **Status:** a decisão anterior ("sem driver necessário", commit `53233c3`) foi **anulada por revisão
> crítica** em 2026-11-13. O HPET/WDT do Baikal **existe** (evidência de código no kernel Orbis e no
> header `drivers/ps4/baikal.h`); **não existe driver Linux público** que o exponha. O item do backlog
> foi **reaberto**.

---

## 0. Resumo da revisão crítica (2026-11-13, após `53233c3`)

| Afirmação do commit `53233c3` | Veredito | Evidência que a refuta / confirma |
|---|---|---|
| "FACP decodificada: PM1A_EVENT em 0x1000" | **Verdadeiro, método errado** | O FACP tem **corpo ACPI 1.0 legado** (PM1a_EVT=0x1000 em 0x38, PM1a_CNT=0x1004 em 0x40, PM_TMR=0x1008 em 0x4C, GPE0=0x1014 em 0x50). O decoder anterior usava offsets GAS (ACPI 2.0+) e imprimiu `PM1A_EVT addr=0x0`; a conclusão veio do `/proc/ioports`, não da tabela. |
| "FACP: nenhum bloco de timer HPET declarado" | **Evidência vazia** | O FADT **não tem campo HPET em nenhuma revisão da especificação** (HPET é tabela ACPI separada, assinatura `HPET`). A ausência é tautológica e não prova nada. |
| "DSDT/SSDT: nenhum dispositivo HPET/WDT → não há HPET/WDT" | **Não se segue** | O Orbis **não** expõe esse timer via ACPI: expõe via **PCI + ICC** (subfunção 22 da glue). A DSDT de 396 B é coerente com isso. |
| "Sistema ao vivo: sem `/dev/watchdog`, sem `/dev/hpet`" | **Evidência nula** | `CONFIG_HPET` e `CONFIG_WATCHDOG` estão **desligados** em todas as configs do projeto (`# CONFIG_HPET is not set`, `# CONFIG_WATCHDOG is not set`). **Esses devices não poderiam existir** mesmo com o hardware presente. |
| "Banco REA: nenhuma entrada de HPET/WDT/0x109000" | **Verdadeiro, irrelevante** | Verdadeiro (o banco nunca teve leitura ao vivo desse bloco), mas ausência de leitura não é ausência de hardware. |
| "Tabela `decompiled_functions`: nenhuma função de timer/watchdog" | **Verdadeiro, escopo curto** | O dump do Orbis (`kmem_dump_1252.bin`) **tem** código de HPET e a string `"Baikal Timer/WDT"` — apenas não estava catalogado. |
| "Não há evidência de um controlador HPET/WDT separado no Baikal" | **FALSO** | `drivers/ps4/baikal.h`: `BPCIE_SUBFUNC_HPET = 22, //Baikal Timer/WDT`, `BPCIE_HPET_BASE = 0x109000`, `BPCIE_HPET_SIZE = 0x400` e a rotina `stop_hpet_timers()` com **layout de registradores HPET padrão**. No Orbis: `cmp $0x104d` / `cmp $0x90db` / `cmp $0x4` / `cmpw $0x16` (=22) → `"Baikal Timer/WDT"`. |
| "sleep/wake via ICC" (função já coberta) | **Não demonstrado** | `bpcie_icc_suspend()` e `bpcie_icc_resume()` em `ps4-bpcie-icc.c:605-611` são **stubs vazios**. Só power button e shutdown estão realmente implementados. |
| Decisão: "encerrar como sem driver necessário" | **ANULADA** | O HPET/WDT existe e não tem driver. Item **reaberto** (ver §5). |

---

## 1. Evidência ao vivo (2026-11-13, leitura somente)

| Item | Medido | Fonte |
|---|---|---|
| BAR0 (MMIO) | `fdf8000000`, 32 MiB, 64-bit | `lspci -vv -s 00:14.0`, `/sys/.../resource` |
| BAR2 (I/O) | `0x1000`, 1 KiB | idem |
| Driver ligado ao dispositivo | nenhum (`ls` em `driver` não existe) | sysfs |
| Claims em `/proc/ioports` | `ACPI PM1a_EVT_BLK` (1000), `PM1a_CNT_BLK` (1004), `PM_TMR` (1008), `GPE0_BLK` (1014) | já reclamados pelo núcleo ACPI |
| Tabelas ACPI | `DSDT`, `FACP`, `FACS`, `IVRS`, `MCFG`, `SSDT` presentes (sem tabela `HPET`) | `/sys/firmware/acpi/tables/` |
| DSDT | **396 bytes** (`OEM "SIE" / "ORBIS"`). Só `_PR` com `C000..C007`, `_S0/_S3/_S5`, `WKST`. Praticamente nenhum objeto de dispositivo | `others/rea/acpi/scans/dsdt_orbis_decompilada_20261113.dsl` |
| Power button | **já registrado**: `input: Power Button` (bpcie) | `dmesg`, `/proc/bus/input/devices` |
| `/dev/hpet`, `/dev/watchdog` | inexistentes — **irrelevante**: `CONFIG_HPET`/`CONFIG_WATCHDOG` desligados | config do kernel |
| Função Aeolia/Baikal | enum `BAIKAL_FUNC_ID_ACPI = 0` (`drivers/ps4/baikal.h`), mesma ordem do `aeolia.h` | árvore do kernel + web |

> **Nota:** o `sshd` do PS4 (`192.168.6.128`) esteve instável nesta rodada (reset no `kex`), mas
> recuperou e respondeu a `ping` + SSH. A leitura pontual da Fase 0 foi executada com sucesso ao vivo
> (ver §5).

---

## 2. Correções ao plano original (mantidas)

1. **Não é `platform_driver`.** O dispositivo é PCI (`104d:90d7`). O probe é `pci_driver`.
2. **BAR errado.** O plano dizia "BAR0 MMIO + BAR1 I/O". Não existe BAR1 útil: a I/O está em **BAR2**.
3. **PM1a/PM_TMR/GPE0 já são do núcleo ACPI.** Um driver próprio que lesse `0x1000+` brigaria com `ACPI PM1a_*` e `GPE0_BLK`. Não criar driver de PM por cima disso.
4. **Power button já existe.** `ps4-apcie-pwrbutton.c` / `icc_pwrbutton_init()` (chamado em `ps4-bpcie-icc.c:541`) já registra `KEY_POWER` via ICC.
5. **Não há objetos ACPI para parsear.** A DSDT tem 396 bytes. A "Opção B" (ACPI tables + `_PRW`/`_PSW`) não se sustenta.
6. **Thermal e sleep/wake:** não há evidência de sensor térmico na DSDT. **Sleep/wake não está implementado** — `bpcie_icc_suspend()`/`bpcie_icc_resume()` são stubs vazios.

---

## 3. Evidência de que o HPET/WDT do Baikal existe

### 3.1 Header do driver (`drivers/ps4/baikal.h`, idêntico nos 3 kernels públicos)

```c
enum bpcie_subfunc {
    ...
    BPCIE_SUBFUNC_HPET   = 22,  //Baikal Timer/WDT
    ...
};
#define BPCIE_HPET_BASE    0x109000
#define BPCIE_HPET_SIZE    0x400
```

E a rotina que já existia no cabeçalho (código morto no Linux — só uma chamada comentada em
`ps4-bpcie-icc.c:133`), usando o **layout de registradores padrão do HPET**:

```c
static inline void stop_hpet_timers(struct bpcie_dev *sc) {
    *(volatile u64 *)(sc->bar2 + BPCIE_HPET_BASE + 0x10) &= ~(1UL << 0);   // General Configuration
    u64 NUM_TIM_CAP = *(volatile u64 *)(sc->bar2 + BPCIE_HPET_BASE) & 0x1F00; // CAP/TIMCAP
    for (u64 N = 0; N <= NUM_TIM_CAP; N++)
        *(volatile u64 *)(sc->bar2 + BPCIE_HPET_BASE + (0x20*N) + 0x100) &= ~(1UL << 2); // TN_CONFIG
    cpu_stop();
}
```

`+0x00` = CAPABILITY/TIMCAP, `+0x10` = GENERAL CONFIG, `+0x100 + 0x20*N` = TIMER N CONFIG — é o mapa
de registradores do HPET padrão (Intel/Microsoft). O bloco está em `BAR2 + 0x109000` da **glue**
(`00:14.4`, base `0xc8800000` → endereço `0xc8909000`), janela de `0x400` bytes.

### 3.2 Kernel Orbis (`others/rea/dumps/kmem_dump_1252.bin`, base `0xffffffffc0000000`)

Strings no dump:

```
Baikal High Precision Event Timer      @0xffffffffc07f5690
Aeolia High Precision Event Timer      @0xffffffffc07f564c
Belize High Precision Event Timer      @0xffffffffc07f566e
Baikal Timer/WDT                       @0xffffffffc07b740f
pci/hpet_pci  /  acpi/hpet  /  hpet_identify  /  "HPET never increments, disabling"
```

Desmontagem (referências `LEA` rip-relativas localizadas por varredura do dump):

**(a) Nome do device de timer por SoC** — `0xffffffffc03fe75d..0xffffffffc03fe784`: escolhe
`"Aeolia|Baikal|Belize High Precision Event Timer"` conforme o modelo do SoC.

**(b) Registro do device "Baikal Timer/WDT"** — `0xffffffffc02275be..0xffffffffc02275f6`:

```asm
cmp  $0x104d,%eax        ; vendor Sony
cmp  $0x90db,%edx        ; device = glue do Baikal
cmp  $0x4,%ebx           ; função PCI 4 (00:14.4)
cmpw $0x16,0x120(%rcx)   ; subfunção 22 = BPCIE_SUBFUNC_HPET
lea  0x58fe1c(%rip),%rsi # 0xffffffffc07b740f  -> "Baikal Timer/WDT"
```

Isto é a **assinatura exata** de `BPCIE_SUBFUNC_HPET = 22` sobre a glue `104d:90db` func 4 — a mesma
numeração do header do driver. O Orbis registra um device chamado **"Baikal Timer/WDT"**.

**(c) Driver de HPET do Orbis** — `hpet_identify` em `0xffffffffc03fc1fa`, com as mensagens
`"HPET never increments, disabling"`, `"pci/hpet_pci"`, `"acpi/hpet"`.

> O HPET do Orbis é exposto por **PCI/ICC**, não por ACPI — por isso a DSDT de 396 B e a ausência de
> tabela `HPET` são **coerentes** com a existência do hardware, e não a contradizem.

### 3.3 Consequência

O hardware HPET/WDT do Baikal **existe** e é **conhecido publicamente** (header do driver + código do
Orbis), mas **nenhum driver Linux o expõe** — ver §7 (pesquisa web). O backlog original ("desenvolver
driver para o ACPI/timer do Baikal") é **legítimo**, e a parte de ACPI puro (`00:14.0`) continua sem
driver — o que é correto e distinto do HPET/WDT (que vive na glue `00:14.4`).

---

## 4. O que **não** é evidência (erros de raciocínio a não repetir)

1. **FADT sem HPET** — o FADT nunca teve campo HPET. Não usar como argumento.
2. **`/dev/hpet` / `/dev/watchdog` ausentes** — `CONFIG_HPET` e `CONFIG_WATCHDOG` desligados: os devices
   são impossíveis por construção, independentemente do hardware.
3. **Ausência de dispositivo HPET nas tabelas ACPI** — o Orbis não usava ACPI para esse timer.
4. **"Já coberto: sleep/wake via ICC"** — as funções são stubs vazios; não há implementação.
5. **Ausência de registro no banco RE** — o banco registra o que *foi lido*, não o que *existe*.

---

## 5. Fases

### Fase 0 — Leitura somente

**Concluído:**
- [x] Consulta ao banco (`hardware_registers`, `readonly_verification`): nenhuma leitura prévia de
      `0x109000` (o bloco HPET nunca foi lido ao vivo neste projeto).
- [x] Tabelas dumpadas e decompiladas com `iasl` (DSDT 396 B, SSDT 492 B) + FACP/IVRS/MCFG binários.
- [x] FACP decodificada corretamente (corpo ACPI 1.0 legado) — PM1a_EVT `0x1000`, PM1a_CNT `0x1004`,
      PM_TMR `0x1008`, GPE0 `0x1014`, PM1b/PM2/GPE1 ausentes.
- [x] RE estática do dump do Orbis: strings + xrefs + desmontagem (§3.2).
- [x] Pesquisa web: nenhum driver Linux público de HPET/WDT/ACPI para Baikal (§7).

**Concluído (2026-11-13, leitura ao vivo autorizada):**
- [x] **Leitura pontual de 8 bytes** em `BAR2(00:14.4) + 0x109000` = `0xc8909000` (registro CAP/TIMCAP
      do HPET). **Resultado:** `0x05f5e10000002301`.
      - REV_ID (bits 0-7): `1`
      - NUM_TIM_CAP (bits 8-12): `3` (controlador com 3+ timers)
      - LEG_RT_CAP (bit 13): `1` (legacy route capable)
      - vendor ID (bits 16-31): `0x0000` (**não-padrão** — esperado algo não-zero; peculiaridade da
        implementação Baikal/Sony, não invalida a existência do controlador)
      - bits 32-63: `0x05f5e100` (não-zero, fora do padrão HPET que reserva esses bits)
      - **PS4 permaneceu ligado** — leitura pontual é segura; nenhuma escrita foi feita.
      - Registrado em `readonly_verification` (id 893) e `hardware_registers` (id 1339/1340).

**Conclusão da leitura:** algo **responde** em `0xc8909000` com campos exatamente do CAP register do
HPET (REV_ID, NUM_TIM_CAP, LEG_RT_CAP). O vendor ID `0x0000` é atípico, mas os demais campos são
compatíveis com um controlador de timer. **Não foi feita nenhuma escrita** neste bloco.

### Fase 1 — Decisão (corrigida em 2026-11-13)

**Decisão vigente:**

- **ACPI `00:14.0` (`104d:90d7`)** → **sem driver** (mantido). O núcleo ACPI já possui PM1a/PM_TMR/GPE0;
  não há objeto ACPI a parsear; power button e shutdown já têm implementação.
- **HPET/WDT da glue `00:14.4` (`104d:90db`, subfunção ICC 22)** → **item REABERTO, leitura feita**.
  O hardware existe e foi confirmado ao vivo (§3, Fase 0): `0xc8909000` = `0x05f5e10000002301` com
  campos de CAP register do HPET. Não há driver Linux público (§7). **Nada deve ser escrito** nesse
  bloco até validar contra o Orbis em 2 boots.

### Fase 2 — Validação em 2º boot (CONCLUÍDA 2026-11-13)

**Resultado:** leitura de `0xc8909000` após reboot = `0x05f5e10000002301` — **IDÊNTICA** à 1ª leitura.
Valor estável confirmado. **Nenhuma escrita** foi feita. Registro atualizado em `readonly_verification` (id 893).

---

### Fase 3 — Especificação de Implementação do Driver (PARA OUTRO AGENTE)

Esta seção é a **especificação completa** para que outro agente implemente o driver. Não inicie antes
de ler e entender todo o documento.

#### 3.1 Objetivo
Expor o HPET/WDT do Baikal (glue `00:14.4`, subfunção ICC 22) ao Linux via:
- **Clocksource** (`drivers/clocksource/baikal-hpet.c`) — timer de alta precisão para o subsistema de tempo
- **Watchdog opcional** (`drivers/watchdog/baikal_wdt.c`) — se `CONFIG_WATCHDOG` for ligado

Ambos como **um único `pci_driver` da glue** (`104d:90db`), porque o bloco HPET vive na BAR2 da glue.

#### 3.2 Hardware confirmado

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
| General Config (offset 0x10) | **NÃO LER/ESCREVER** — marcado `HIGH_RISK_POWER_OFF` no banco |
| Timer N Config (offset 0x100 + 0x20*N) | **NÃO LER/ESCREVER** até driver pronto |

#### 3.3 Mapeamento de registradores HPET (padrão Intel/Microsoft)

| Offset | Registro | Bits relevantes |
|--------|----------|-----------------|
| +0x00 | CAPABILITY / TIMCAP | RO — lido: `0x05f5e10000002301` |
| +0x10 | GENERAL_CONFIG | RW — **bit 0 = ENABLE_CNF** — **NÃO TOCAR** até driver pronto |
| +0x20 | GENERAL_INT_STATUS | RO |
| +0x100 + 0x20*N | TIMER_N_CONFIG | RW — **bit 2 = TIMER_INT_ENB_CNF** — **NÃO TOCAR** |
| +0x108 + 0x20*N | TIMER_N_COMPARATOR | RW |
| +0x110 + 0x20*N | TIMER_N_FSB | RW (se 64-bit) |
| +0xF0 | MAIN_COUNTER | RO — contador principal |

#### 3.4 Restrições CRÍTICAS (violação = PS4 desliga)

1. **Nunca varredura sequencial/bloco na BAR2 da glue** (`0xc8800000`–`0xc89fffff`). Risco
   `HIGH_RISK_POWER_OFF` registrado como `BAR2_SEQUENTIAL_BLOCK_READ`. Apenas acessos **pontuais**
   de 8 bytes (ou 4 bytes alinhados) em offsets validados.
2. **Offsets validados como SAFE no banco:**
   - `0x109000` (CAP/TIMCAP) — `safe_to_read=1` (id 1339)
   - `0x10a000`, `0x10a004`, `0x10a008`, `0x10a00c`, `0x10a030`, `0x10a034`, `0x10a038`, `0x10a03c`, `0x180004` — others offsets da glue já lidos
   - `0x109010` (GENERAL_CONFIG) — **`HIGH_RISK_POWER_OFF`, safe_to_read=0** (id 1340)
3. **Nenhuma escrita** antes do driver estar completo, testado em 2 boots, e revisado.
4. **Leitura via `/dev/mem`** (como feito nas validações) ou `ioremap` + `readq` no driver.
   `/dev/mem` existe, `CONFIG_STRICT_DEVMEM` não está setado.

#### 3.5 Estrutura do driver (recomendada)

```c
// drivers/clocksource/baikal-hpet.c  (ou drivers/watchdog/baikal_wdt.c unificado)
#include <linux/pci.h>
#include <linux/clocksource.h>
#include <linux/watchdog.h>   // se watchdog
#include <linux/io.h>
#include <linux/delay.h>

#define BAIKAL_HPET_VENDOR   0x104d
#define BAIKAL_HPET_DEVICE   0x90db
#define BAIKAL_HPET_BAR      2
#define BAIKAL_HPET_OFFSET   0x109000
#define BAIKAL_HPET_SIZE     0x400

#define HPET_CAP             0x00
#define HPET_GEN_CONFIG      0x10
#define HPET_TIMER_CONFIG(n) (0x100 + 0x20 * (n))
#define HPET_TIMER_COMP(n)   (0x108 + 0x20 * (n))
#define HPET_MAIN_COUNTER    0xF0

struct baikal_hpet {
    void __iomem *base;
    struct clocksource cs;
    struct watchdog_device wdd;  // opcional
    u64 cap;
    int num_timers;
};

// PCI probe: valida vendor/device, mapeia BAR2 + 0x109000, lê CAP,
// valida REV_ID==1, NUM_TIM_CAP>=3, LEG_RT_CAP==1.
// NÃO escreve GENERAL_CONFIG no probe.

// clocksource: usa MAIN_COUNTER (64-bit, free-running) como clocksource
// rating alto (ex: 300), read() retorna readq(base + HPET_MAIN_COUNTER).

// watchdog (se habilitado): usa Timer 0 em modo one-shot, INT_ENB_CNF,
// GENERAL_CONFIG enable, nowayout=0, timeout default 30s.

// remove: desabilita GENERAL_CONFIG (bit 0 = 0), desabilita timers,
// iounmap, pci_release_regions.
```

#### 3.6 Configs de kernel necessárias (em `00-build-kernel-7.0.sh`)

```bash
scripts/config --enable CONFIG_CLOCKSOURCE_WATCHDOG   # se watchdog
scripts/config --enable CONFIG_HPET                   # ou CONFIG_HPET_TIMER
scripts/config --enable CONFIG_WATCHDOG               # se watchdog
scripts/config --module CONFIG_BAIKAL_HPET            # driver como módulo
```

#### 3.7 Passos de validação obrigatórios (antes de considerar "pronto")

1. **Compile isolado:** `make drivers/clocksource/baikal-hpet.o` (ou watchdog) — sem erros.
2. **Boot 1:** `insmod baikal-hpet.ko`, `dmesg` mostra probe + clocksource registrado,
   `/sys/devices/system/clocksource/clocksource0/current_clocksource` = `baikal-hpet`.
3. **Boot 2 (reboot frio):** mesmo comportamento, valor CAP idêntico (`0x05f5e10000002301`).
4. **Teste clocksource:** `cat /sys/devices/system/clocksource/clocksource0/current_clocksource`
   não muda com carga; `clocksource -l` lista o driver.
5. **Teste watchdog (se implementado):** `echo 1 > /dev/watchdog` não reinicia o PS4;
   `wdctl` mostra status.
6. **Nenhuma escrita em GENERAL_CONFIG** até etapa 5 passar.

#### 3.8 Referências de código existentes no projeto

| Arquivo | O que contém |
|---------|--------------|
| `kernel/kernel_build_7.0/drivers/ps4/baikal.h` | `BPCIE_HPET_BASE`, `BPCIE_HPET_SIZE`, `stop_hpet_timers()` (layout HPET padrão) |
| `kernel/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c` | `bpcie_icc_cmd()` — padrão de retry ICC (100x50ms) se precisar falar com firmware |
| `others/rea/dumps/kmem_dump_1252.bin` | Orbis: strings `"Baikal Timer/WDT"`, `"Baikal High Precision Event Timer"`, driver `hpet_identify`/`hpet_pci` |
| `others/rea/acpi/decompiled/` | `orbis_baikal_timer_wdt_register` (0xc02275ec), `orbis_hpet_device_name_by_soc` (0xc03fe77d), `orbis_hpet_identify` (0xc03fc1fa) |

#### 3.9 Checklist de "pronto para merge"

- [ ] Driver compila isolado (`make M=drivers/clocksource baikal-hpet.o`)
- [ ] Probe PCI da glue `104d:90db` função 4 funciona
- [ ] Clocksource registrado e selecionado automaticamente
- [ ] Valor CAP lido no probe = `0x05f5e10000002301` (logado no dmesg)
- [ ] 2 boots frios consecutivos estáveis
- [ ] Nenhuma escrita em `0xc8909010` (GENERAL_CONFIG) no código
- [ ] `CONFIG_HPET`/`CONFIG_WATCHDOG` ligados no build script
- [ ] Patch gerado via `git diff HEAD` (padrão AGENTS.md) em `kernel/patches/baikal-hpet.patch`
- [ ] `00-build-kernel-7.0.sh` aplica patch com `git apply --check` + `exit 1` se falhar

---

## 6. Riscos

| Risco | Mitigação |
|---|---|
| Escrita no bloco de timer pode travar o barramento PCIe (lição de 2026-07-21) | Só leitura até validar; nunca escrever no caminho de boot |
| Varredura sequencial na BAR2 da glue → desligamento instantâneo | Acesso **pontual** apenas; nunca varredura/bloco |
| Watchdog armado reinicia o PS4 sem aviso | Não armar por padrão; `nowayout=0` |
| Duplicar o núcleo ACPI | Não ler `0x1000+` e não registrar PM |

---

## 7. Fontes

**Web (pesquisa de 2026-11-13; `websearch` do harness retornou HTTP 402 — contornado via API do GitHub
e DuckDuckGo HTML)**

- [fail0verflow/ps4-linux, `drivers/ps4/`](https://github.com/fail0verflow/ps4-linux/tree/master/drivers/ps4):
  upstream Orbis/Aeolia. `drivers/ps4/` contém só `ps4-apcie*.c` — **sem** driver HPET/WDT/ACPI.
- [whitehax0r/ps4-linux-baikal](https://github.com/whitehax0r/ps4-linux-baikal) (kernel 5.4.213 Baikal):
  `drivers/ps4/baikal.h` **idêntico** ao local (`BPCIE_HPET_BASE 0x109000`, `stop_hpet_timers()`);
  `drivers/ps4/Makefile` só compila `ps4-apcie*.c` + `ps4-bpcie*.c` — **sem** driver de timer.
- [DFAUS-git/ps4-baikal-5.4.247-kernel](https://github.com/DFAUS-git/ps4-baikal-5.4.247-kernel): idem.
- [noob404yt/baikal-5.4.213-mt7668-dns-vpn](https://github.com/noob404yt/baikal-5.4.213-mt7668-dns-vpn): idem.
- [crashniels/linux @ `ps4-linux-6.15.y-baikal`](https://github.com/crashniels/linux/tree/ps4-linux-6.15.y-baikal)
  (PS4 Linux 6.15, o mais moderno público): `drivers/ps4/` igual ao anterior; `drivers/watchdog/` **sem**
  driver Baikal; `drivers/acpi/` **sem** driver PS4/Baikal.
- [odiecay/android-tv-ps4, `kernel/baikal/README.md`](https://github.com/odiecay/android-tv-ps4/blob/main/releases/release-1.0/kernel/baikal/README.md):
  southbridge Baikal em 6.15 (`crashniels/linux` + `linux-psx`) — cobre serial/ICC/ACPI-IRQ/USB/IOMMU,
  **não** menciona HPET/WDT.
- [X-F1REBALL-X/PS4-Linux](https://github.com/X-F1REBALL-X/PS4-Linux): kernel Baikal 7.0.8, sem info de
  ACPI/HPET/WDT.
- [postmarketOS MR 5194](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/5194):
  estrutura `drivers/ps4/`.
- Busca por `"Baikal High Precision Event Timer"` e por `"Timer/WDT"` na web: **sem resultado público**
  (as strings são do kernel Orbis, não publicadas).

**Projeto**
- `kernel/kernel_build_7.0/drivers/ps4/baikal.h` (enums + `BPCIE_HPET_BASE` + `stop_hpet_timers()`).
- `kernel/kernel_build_7.0/drivers/ps4/ps4-apcie-pwrbutton.c` (`KEY_POWER` via ICC).
- `kernel/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c` (`icc_shutdown` → `pm_power_off`;
  `bpcie_icc_suspend/resume` vazios).
- `others/rea/acpi/scans/dsdt_orbis_decompilada_20261113.dsl`,
  `others/rea/acpi/scans/facp_orbis_bruta_20261113.aml`.
- `others/rea/dumps/kmem_dump_1252.bin` (dump do kernel Orbis, base `0xffffffffc0000000`).

---

## 8. Resumo da decisão (2026-11-13, revisão final)

1. **ACPI `00:14.0`** → segue **sem driver**: PM1a/PM_TMR/GPE0 são do núcleo ACPI; não há objeto ACPI;
   power button (`KEY_POWER` via ICC) e shutdown (`icc_shutdown` → `pm_power_off`) já existem.
   **Sleep/wake não está implementado** (stubs vazios) — se for desejado, é trabalho novo.
2. **HPET/WDT da glue `00:14.4` (subfunção ICC 22)** → **existe** e **não tem driver Linux**:
   - header do driver: `BPCIE_HPET_BASE = 0x109000`, `BPCIE_HPET_SIZE = 0x400`, `stop_hpet_timers()` com
     layout HPET padrão;
   - kernel Orbis: device `"Baikal Timer/WDT"` registrado para `104d:90db` func 4 subfunção `0x16`, e
     driver de HPET com nome por SoC (`"Baikal High Precision Event Timer"`);
   - nenhum kernel Linux público (5.4, 6.15, 7.0) expõe esse bloco.
3. **Próximo passo decisivo e de baixo risco**: leitura **pontual** de 8 bytes em
   `BAR2(00:14.4) + 0x109000` (`0xc8909000`), com autorização explícita, conferindo o
   `vendor ID = 0xA808` do HPET. Sem essa leitura, o driver fica em fase de plano (não se escreve nada).
