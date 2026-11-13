# Plano — Baikal ACPI / função 00:14.0 (revisado 2026-11-13)

> **Dispositivo:** Sony Baikal ACPI · **PCI:** `104d:90d7` (`00:14.0`) · **Subsystem:** `104d:90df`
> **Status:** o plano original (driver `platform_driver` com power button e thermal próprios) foi **revisado**. Boa parte do escopo já existe ou não se sustenta com a evidência medida. Ver "Correções".

---

## 1. Evidência ao vivo (2026-11-13, leitura somente)

| Item | Medido | Fonte |
|---|---|---|
| BAR0 (MMIO) | `fdf8000000`, 32 MiB, 64-bit | `lspci -vv -s 00:14.0`, `/sys/.../resource` |
| BAR2 (I/O) | `0x1000`, 1 KiB | idem |
| Driver ligado ao dispositivo | nenhum (`ls` em `driver` não existe) | sysfs |
| Claims em `/proc/ioports` | `ACPI PM1a_EVT_BLK` (1000), `PM1a_CNT_BLK` (1004), `PM_TMR` (1008), `GPE0_BLK` (1014) | já reclamados pelo núcleo ACPI |
| Tabelas ACPI | `DSDT`, `FACP`, `FACS`, `IVRS`, `MCFG`, `SSDT` presentes | `/sys/firmware/acpi/tables/` |
| DSDT | **396 bytes** (`OEM "SIE" / "ORBIS"`). Só `_PR` com `C000..C007`, `_S0/_S3/_S5`, `WKST`. Praticamente nenhum objeto de dispositivo | `outros/rea/acpi/scans/dsdt_orbis_decompilada_20261113.dsl` |
| Power button | **já registrado**: `input: Power Button` em `/devices/.../0000:00:14.4/input/input0` (bpcie) | `dmesg`, `/proc/bus/input/devices` |
| HPET / watchdog | `/dev/hpet` e `/dev/watchdog*` **inexistentes**. Nada em `dmesg` sobre hpet/wdt | `ls`, `dmesg` |
| Função Aeolia/Baikal | enum `BAIKAL_FUNC_ID_ACPI = 0` (`drivers/ps4/baikal.h`), mesma ordem do `aeolia.h` | árvore do kernel + web |

---

## 2. Correções ao plano original

1. **Não é `platform_driver`.** O dispositivo é PCI (`104d:90d7`). O probe é `pci_driver`.
2. **BAR errado.** O plano dizia "BAR0 MMIO + BAR1 I/O". Não existe BAR1 útil: a I/O está em **BAR2**.
3. **PM1a/PM_TMR/GPE0 já são do núcleo ACPI.** Um driver próprio que lesse `0x1000+` brigaria com `ACPI PM1a_*` e `GPE0_BLK`. Não criar driver de PM por cima disso.
4. **Power button já existe.** `ps4-apcie-pwrbutton.c` / `icc_pwrbutton_init()` (chamado em `ps4-bpcie-icc.c:541`) já registra `KEY_POWER` via ICC. A "Fase 2" do plano original está **fechada**.
5. **Não há objetos ACPI para parsear.** A DSDT tem 396 bytes. A "Opção B" (ACPI tables + `_PRW`/`_PSW`) não se sustenta.
6. **Thermal e sleep/wake:** não há evidência de sensor térmico na DSDT. Sleep S3/S5 depende de ICC (`icc_power_shutdown` já é tratado no código). A "Fase 3" e a "Fase 4" precisam de nova evidência antes de virar tarefa.

---

## 3. O que sobrou de real

O subfunção `BPCIE_SUBFUNC_ACPI = 1` e `BPCIE_SUBFUNC_HPET = 22` ("Baikal Timer/WDT") em `drivers/ps4/baikal.h`. O bloco HPET está em **BAR2 `+0x109000`, tamanho `0x400`**, marcado como "not confirmed" no próprio header. O WDT **não está exposto** no Linux (sem `/dev/watchdog`).

**Único candidato de driver:** watchdog/timer Baikal (`baikal-wdt`), **se** a leitura confirmar que o bloco responde.

---

## 4. Fases

### Fase 0 — Leitura somente (sem risco)

**Resultados (2026-11-13):**
- [x] Consulta ao banco (`hardware_registers`, `readonly_verification`, colunas `reg_name`/`reg_offset`): **nenhuma entrada de HPET, WDT ou `0x109000`**. Não há leitura prévia do bloco.
- [x] Tabelas dumpadas via sysfs e decompiladas com `iasl`:
  - **DSDT** (396 bytes, `SIE / ORBIS`): só `_PR_.C000..C007` com `_CST` e registradores de C-state (`SystemIO 0x1771`). Nenhum dispositivo. Salva em `scans/dsdt_orbis_decompilada_20261113.dsl`.
  - **SSDT** (492 bytes, `AMD / POWERNOW`): só `_PR_.C000..C007` com `_CST`. Salva em `scans/ssdt_orbis_decompilada_20261113.dsl`.
  - **MCFG** (60 bytes), **IVRS** (84 bytes), **FACP** (244 bytes): salvas como binárias brutas em `scans/*_orbis_bruta_20261113.aml`. FACP decodificada: PM1A_EVENT em 0x1000 (confere com /proc/ioports), sem bloco de timer HPET.
- **Conclusão:** nenhuma das tabelas declara dispositivo ACPI para `00:14.0`. Confirma a correção 5 deste plano.

**Pendente (adiado por risco):**
- [ ] Ler `BAR2 + 0x109000` do `00:14.4` (glue). **Não executado:** varredura sequencial na BAR2 da glue dispara desligamento instantâneo do PS4; offset `0x109000` não está entre os offsets validados como SAFE no banco. Requer autorização explícida e registro antes/depois no banco.
- [ ] Decodificar a FACP à mão, se for preciso confirmar `PM1a/GPE0` (já confirmados por `/proc/ioports`, então não é bloqueante). **Decodificada: PM1A_EVENT em 0x1000.**

### Fase 1 — Decisão (registrada 2026-11-13)

**Decisão: encerrar o item ACPI como "sem driver necessário".**

**Fundamentação:**
- DSDT (396 B): apenas processadores C000-C007, estados S0/S3/S5, métodos _PTS/_TTS/_WAK. **Nenhum dispositivo HPET ou WDT declarado.**
- SSDT (492 B): apenas _CST (C-states) da AMD POWERNOW. Sem dispositivo timer/watchdog.
- FACP (244 B): PM1A_EVENT em 0x1000 (confere com /proc/ioports). PM1B ausente. **Nenhum bloco de timer HPET declarado.**
- Banco `ps4_hardware_memory.db`: nenhuma entrada de HPET, WDT ou offset `0x109000` em `hardware_registers` ou `readonly_verification`.
- Tabela `decompiled_functions`: nenhuma função de timer/watchdog.
- Sistema ao vivo: sem `/dev/watchdog`, sem `/dev/hpet`.
- Leitura de `BAR2 + 0x109000` (glue, 00:14.4) está **adiada por risco** (varredura sequencial na BAR2 da glue dispara desligamento instantâneo do PS4; offset `0x109000` não está entre os offsets validados como SAFE no banco).
- Funcionalidade de energia já coberta: power button via `ps4-apcie-pwrbutton.c` / `icc_pwrbutton_init()`; shutdown via `icc_shutdown` atribuído a `pm_power_off`; sleep/wake via ICC.

**Conclusão:** não há evidência de um controlador HPET/WDT separado no Baikal que justifique um driver `baikal-wdt`. O item ACPI é encerrado sem driver.

### Fase 2 — Watchdog (não necessário)

**Não executado.** Conforme decisão da Fase 1, não há HPET/WDT a ser encapsulado. Nenhum arquivo `drivers/watchdog/baikal_wdt.c` será criado.

---

## 5. Riscos

| Risco | Mitigação |
|---|---|
| Escrita no bloco de timer pode travar o barramento PCIe (lição de 2026-07-21) | Só leitura até validar; nunca escrever no caminho de boot |
| Watchdog armado reinicia o PS4 sem aviso | Não armar por padrão; `nowayout=0` |
| Duplicar o núcleo ACPI | Não ler `0x1000+` e não registrar PM |

---

## 6. Fontes

**Web**
- [fail0verflow/ps4-linux, `drivers/ps4/aeolia.h`](https://github.com/fail0verflow/ps4-linux/blob/412b34111c0b0e646f94a258b23589d9e8fa10f9/drivers/ps4/aeolia.h): IDs e enum das funções Aeolia. Confirma `ACPI = 0x908f` e a ordem `ACPI, GBE, AHCI, SDHCI, PCIE, DMAC, MEM, XHCI`, a mesma do Baikal. A correspondência de função com o PCI ficou confirmada pela lista ao vivo (`.0` ACPI, `.1` GBE, `.4` PCIe, `.5` DMAC, `.6` MEM, `.7` XHCI).
- [Gcsman110/ps4-mts-linux-driver](https://github.com/Gcsman110/ps4-mts-linux-driver): cita `docs/baikal-gbe-register-map.md`. Não cobre ACPI nem HPET.
- [X-F1REBALL-X/PS4-Linux](https://github.com/X-F1REBALL-X/PS4-Linux): kernel Baikal 7.0.8. Não tem informação de ACPI, HPET ou WDT.
- [postmarketOS MR 5194](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/5194): mostra a estrutura `drivers/ps4/` (`aeolia.h`, `ps4-apcie.c`, `ps4-apcie-icc.c`).

**Projeto**
- `kernel/kernel_build_7.0/drivers/ps4/baikal.h`, `ps4-apcie-pwrbutton.c`, `ps4-bpcie-icc.c:541`.
- `outros/rea/acpi/scans/dsdt_orbis_decompilada_20261113.dsl`.

---

## 7. Resumo da decisão (2026-11-13)

O dispositivo Baikal ACPI (`00:14.0`, `104d:90d7`) existe no PCI e tem MMIO + I/O BARs, mas:

1. **Não há dispositivo HPET ou WDT nas tabelas ACPI** (DSDT/SSDT/FACP analisadas).
2. **Não há leitura prévia do bloco `0x109000` na glue BAR2** (adiada por risco de desligamento instantâneo).
3. **A funcionalidade de energia já está coberta por drivers existentes:**
   - Power button: `ps4-apcie-pwrbutton.c` + `icc_pwrbutton_init()` → `KEY_POWER` via ICC
   - Shutdown: `icc_shutdown` atribuído a `pm_power_off`
   - Sleep/wake: tratado pelo ICC
4. **Não há `/dev/watchdog` nem `/dev/hpet` no sistema ao vivo.**

**Decisão:** encerrar o item ACPI Baikal como **"sem driver necessário"**. Não será desenvolvido `baikal-acpi` nem `baikal-wdt`. Registrado no `BACKLOG.md`.

Se evidência futura surgir (ex.: leitura autorizada de `BAR2 + 0x109000` que retorne valor plausível de timer/watchdog), o item pode ser reaberto.
