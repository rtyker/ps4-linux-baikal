---
name: rtc-via-icc-re-validada-2026-07-25
description: "RE completa do driver RTC do kernel Orbis 12.52 (rtc_mvl.c + rtc.c) validou 100% o plano rtc_via_icc_plan.md: ICC major=2 minor=0x0b/0x0c sub=0x81/1 (save/load context), ICC major=4 minor=0x50 (bitmask alarmes), MMIO 0x5180000 (read time) e 0x5140000 (write settime). Encontrados DOIS drivers RTC em camadas no kernel: rtc_mvl.c (baixo nível, read-only) e rtc.c (alto nível via ICC, recomendado para o Linux). Constante Sony 0x4effa200 = offset de epoch Sony (NÃO usar no Linux)."
metadata:
  node_type: memory
  type: project
  originSessionId: re-rtc-2026-07-25
  modified: 2026-07-25T18:00:00.000Z
---

# RE do RTC do Orbis 12.52 — validação do plano `rtc_via_icc_plan.md`

**Data:** 2026-07-25
**Dump:** `consolidado/dumps_orbis/kmem_dump_1252.bin` (base ELF `0xffffffffdc350000`)
**Plano:** `consolidado/plans/rtc_via_icc_plan.md`
**Análise consolidada:** `consolidado/decompiled/baikal_rtc_mvl.txt`

## Descoberta-chave: DOIS drivers RTC em camadas

| Driver | Arquivo | Camada | Pode settime? |
|---|---|---|---|
| `rtc_mvl.c` | `sys/dev/scesb/rtc/rtc_mvl.c` | baixo nível (MMIO direto no SoC: offsets `0x100`/`0x130..0x13c`/`0x160..0x164`) | ❌ read-only |
| `rtc.c` | `sys/dev/scesb/rtc/rtc.c` | alto nível (via ICC + MMIO `0x5180000`/`0x5140000`) | ✅ sim |

> ⚠️ Um dos drivers linux seguirá é o `rtc.c` (tem settime e usa ICC que já expusemos via `bpcie_icc_cmd`). O `rtc_mvl.c` é read-only e usa barramento do SoC que não temos exposto no Linux.

## Funções decompiladas (registradas no `ps4_hardware_memory.db` — categoria "RTC (rtc_mvl.c)" e "RTC (rtc.c)")

### Driver `rtc_mvl.c` (baixo nível, read-only)

| Função | vaddr | tam | papel |
|---|---|---|---|
| `rtc_mvl_probe` | `dc5d63f0` | 89 B | `bus_alloc_resource` + `device_set_desc("rtc_mvl")` |
| `rtc_mvl_attach` | `dc5d6450` | 427 B | health-check em STATUS `0x100` (bit 2=OK, bit 8=battery fail); log `Battery/Clock failure` + `[Bug 142260]` |
| `read_aeolia_rtc` | `dc5d6600` | 619 B | retry loop básico, leitura estável dos 4 bytes `0x130..0x13c` (32-bit BE) |
| `rtc_mvl_gettime` | `dc5d6870` | 644 B | gettime completa: retry máx 21 × 100us (timeout `[Bug 55086]`) + status `+0` + time `+4` + extra `0x160`/`0x164` em `+8`/`+12` |

### Driver `rtc.c` (alto nível, ICC) — recomendado para o Linux

| Função | vaddr | tam | papel |
|---|---|---|---|
| `icc_query` (wrapper genérico ICC) | `dc3f5bd0` | 233 B | wrapper ICC (major≤4, len≤0x401), monta packet 2032B e chama `dc797090` (transport). Variante write = `dc3f5a10`. |
| `ssb_rtc_init_exclock` (boot init) | `dc57e9d0` | 465 B | boot init: ICC(4,0x50) lê bitmask de alarmes + vtable `get_registry_offset` + MMIO read `0x5180000`. |
| `rtc_load_context` | `dc57f340` | 601 B | ICC load ctx (major=2 minor=0x0c sub=0x81/1 via `dc6b1b80`) + MMIO read `0x5180000`; em cold start (flag=0) escreve `0x5140000` com epoch 1970 + ajuste Sony `0x4effa200` |
| `rtc_save_context` | `dc57f6f0` | 308 B | ICC save ctx (major=2 minor=0x0b sub=0x81/1 via `dc6b1a20`) + re-synca bitmask alarmes (softc `+0xc0/+0xc4/+0xc8`) para ICC(4,0x50) |

### Lacunas (ainda não decompiladas, mas referenciadas)

| Função | referenciada em | papel |
|---|---|---|
| `dc839e40` | `dc57e9d0` + `dc57f340` | wrapper MMIO READ 8 bytes — usado com `(0x5180000, &buf, 8)` e `(0x5140000, &buf, 8)` |
| `dc839d90` | `dc57f340` (cold start) | wrapper MMIO WRITE 8 bytes — usado em `settime` com `(0x5140000, &buf, 8)` |
| `dc6b1a20` | `rtc_save_context` | dispatch ICC save (sub-op 0x81) — traduz para major=2 minor=0x0b |
| `dc6b1b80` | `rtc_load_context` | dispatch ICC load (sub-op 0x81) — traduz para major=2 minor=0x0c |
| `dc797090` | `icc_query` | ICC transport subjacente — envia pacote ICC de 2032B ao SC |

## Globais (kernel x86)

| Endereço | conteúdo |
|---|---|
| `0xffffffffde526a88` | ponteiro para `ssb_rtc` softc (RTC device) |
| `0xffffffffdeaacea0` | mutex recursiva do módulo RTC |

> O plano original cita endereços `0x80xxxxxx` — esses são do SC ARM (cópia de trabalho); o kernel x86 referenciadas as estruturas em `0xffffffffde...`. Para driver Linux o importante é o protocolo; globais só importam para kprobe (não necessários).

## Strings-chave do driver `rtc.c`

- `Aeolia RTC` / `Belize RTC` / `Baikal RTC` — descrições de device (PS4 Fat / Pro / Slim)
- `pci/ssb_rtc` (driver PCI), `ssb_rtc_pci` (probe), `ssb_rtc` (device name)
- `rtc_rw` (sx-lock), `rtc_mtx_lock` (mutex), `rtc_shutdown_event` (hook shutdown)
- `get_registry_offset` e `set_registry_offset` (vtable methods)
- `RTC: icc save context fail %d` e `RTC: icc load context fail %d`
- `[RTC] ERR: %s sceRegMgrGetBin() Fail :%d` e `sceRegMgrSetBin() Fail :%d`
- `RTC device error: Set Usertime 1970/01/01` (warning em cold start)

## Constante mágica Sony `0x4effa200`

O Orbis trabalha com uma "epoch arbitrária Sony" (offset `0x4effa200` aplicado à epoch unix
ao ler/escrever `0x5140000`). **NÃO usar no driver Linux** — escrever epoch unix puro
diretamente. O RTC mantém o offset internamente; ao ler de volta, ele adiciona o ajuste.
No Linux o driver deve usar `read 0x5180000` / `write 0x5140000` como epoch unix puro e
validar com `date +'%s'` vs `cat /sys/class/rtc/rtc0/since_epoch`.

## ⚠️ Para nunca ter que re-fazer

- **NÃO há função de `settime` em `rtc_mvl.c`** — driver de baixo nível é read-only. Somente
  `rtc.c` (camada ICC) faz escrita. Se alguém achar "settime" no dump, é porque está em `rtc.c`.
- **`0xffffffffdc5d65c4`** reportada pelo r2 (162 B) **não é função real** — é goto interno
  `code_r0xffffffffdc5d6559` dentro de `rtc_mvl_attach`. Artefato do pseudo-C do r2ghidra.
- **Os endereços `0x80266b00`, `0x80447090`, `0x800a5bd0`, `0x800a5a10`** mencionados no plano
  original são do SC ARM (mini-syscore.elf), NÃO deste dump. Equivalentes x86:
  `dc6b1a20` (save), `dc6b1b80` (load), `dc3f5bd0` (icc_query read), `dc3f5a10` (icc_query write).
- **Kernel base correto do ELF**: `0xffffffffdc350000` (confirmado por `readelf -l` — PHDR LOAD
  R+E começa em offset 0 → vaddr `0xffffffffdc350000`). O artigo `icc-shutdown-s5-analise-dump-1252.md`
  menciona `0xffffffff948dc000` mas esse era da análise antiga com kern_base_finder — está **errado**
  para este dump, que tem entry point `0xffffffffdc3ba410`.

## Links

- Plano de implementação: `consolidado/plans/rtc_via_icc_plan.md` (atualizado 2026-07-25 com seção "Validação da RE")
- Análise consolidada (rtc_mvl.c): `consolidado/decompiled/baikal_rtc_mvl.txt`
- Índice canônico de funções decompiladas: `consolidado/decompiled/INDEX.md` §6.B
- DB: `ps4_hardware_memory.db` — 8 funções RTC registradas na tabela `decompiled_functions`

---

## Progresso de implementação (2026-07-25)

### Fase 1: Configuração do kernel — ✅ EDITADA

Edição aplicada em `distros/arch_minimal_v2/00-build-kernel-7.0.sh` linhas 513-528 (antes do `olddefconfig`):

```bash
scripts/config --enable  CONFIG_RTC_CLASS
scripts/config --enable  CONFIG_RTC_INTF_DEV      # /dev/rtc interface
scripts/config --enable  CONFIG_RTC_INTF_SYSFS    # /sys/class/rtc
scripts/config --enable  CONFIG_RTC_INTF_PROC     # /proc/driver/rtc
scripts/config --enable  CONFIG_RTC_DRV_CMOS      # driver cmos (IO 0x70/0x71)
scripts/config --enable  CONFIG_RTC_HCTOSYS       # kernel lê RTC no boot
scripts/config --set-str CONFIG_RTC_HCTOSYS_DEVICE "rtc0"
scripts/config --enable  CONFIG_RTC_SYSTOHC      # hwclock escreve de volta
scripts/config --set-str CONFIG_RTC_SYSTOHC_DEVICE "rtc0"
```

Observações:
- `CONFIG_RTC_DRV_PS4_ICC` **não** habilitado ainda (o driver não existe; faria `olddefconfig` falhar com "unknown symbol").
- `CONFIG_RTC_DRV_CMOS=y` ativa o driver padrão do Linux que lê port I/O `0x70/0x71`. Dmesg histórico (dezembro 2026) já mostra `"platform rtc_cmos: registered platform RTC device (no PNP device found)"` — então o `rtc_cmos` já está se registrando mesmo sem `RTC_CLASS` ligado. Habilitar `RTC_CLASS` deve dar `/dev/rtc0` imediato, lendo do CMOS do PC (não é o RTC real do SC via ICC ainda — é o "rtc-cmos" legado).
- Esta fase **não foi compilada ainda** (agrupada com Fases 2+3 num rebuild único).

### Fase 2: Wrapper ICC com retry — ✅ IMPLEMENTADA E VALIDADA

Patch criado: `distros/arch_minimal_v2/patches/ps4-icc-rtc-wrapper.patch` (106 linhas, puro aditivo).

Arquivos tocados (em `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/`):
- `ps4-bpcie-icc.c` — adicionada função `ps4_icc_rtc_cmd()` (47 linhas) ao fim do arquivo + `EXPORT_SYMBOL_GPL(ps4_icc_rtc_cmd)`
- `baikal.h` — declarada `ps4_icc_rtc_cmd()` + `PS4_ICC_RTC_RETRIES=100` + `PS4_ICC_RTC_RETRY_DELAY_MS=50`
- `aeolia.h` — mesma declaração (idêntica para Aeolia/Belize)

Wrapper:
```c
int ps4_icc_rtc_cmd(u8 major, u16 minor, const void *data, u16 length,
                    void *reply, u16 reply_length);
// Retry 100× 50ms se -EAGAIN/-EINTR/-ETIMEDOUT. Despacha para bpcie_icc_cmd
// (Baikal) ou apcie_icc_cmd (Aeolia/Belize) conforme CONFIG_X86_PS4_BAIKAL.
// Aplicação no script (`00-build-kernel-7.0.sh`):
//   git apply patches/ps4-icc-rtc-wrapper.patch || echo "AVISO: já aplicado"
```

Validação:
- `make drivers/ps4/ps4-bpcie-icc.o` compilou limpo.
- `nm drivers/ps4/ps4-bpcie-icc.o` mostra `T ps4_icc_rtc_cmd` + `r __export_symbol_ps4_icc_rtc_cmd` (símbolo exportado).
- Patch é aditivo (não altera nada existente). `git apply` funciona em estado limpo.
- **Importância**: `bpcie_icc_cmd` já era `EXPORT_SYMBOL_GPL` antes — a Fase 2 não toca nisso; só encapsula com retry.

### Fase 3: Driver `rtc-ps4-icc.c` — ✅ CONCLUÍDA (2026-07-31)

`drivers/rtc/rtc-ps4-icc.c` já existia no source tree desde 2026-07-25 (criado numa sessão
anterior, nunca documentado como concluído aqui) mas tinha um **bug nunca detectado**:
`ps4_rtc_read_time()` lia de `sc->mmio_write` (`0x5140000`, endereço de ESCRITA) em vez de
`sc->mmio_read` (`0x5180000`, leitura) — teria devolvido hora errada/lixo em qualquer teste real.
Corrigido em 2026-07-31. `drivers/rtc/Kconfig` e `drivers/rtc/Makefile` já tinham as entradas
`RTC_DRV_PS4_ICC` corretas (também de 2026-07-25, não documentado). `00-build-kernel-7.0.sh`
atualizado para habilitar `CONFIG_RTC_DRV_PS4_ICC` como módulo (antes ficava explicitamente
desabilitado com comentário "driver não existe").

Validado com compile isolado no source tree (`sudo make ARCH=x86_64 drivers/rtc/rtc-ps4-icc.o`):
compilou limpo, sem erros nem warnings, após dois ajustes: `#include <linux/mod_devicetable.h>`
(faltava para `struct platform_device_id`) e cast `(unsigned long)` no `dev_info` dos endereços
MMIO. `nm` confirma `ps4_icc_rtc_cmd` como símbolo indefinido (`U`) — resolve no link do módulo
contra o `EXPORT_SYMBOL_GPL` já existente em `ps4-bpcie-icc.c`.

⚠️ Este compile isolado só prova que o C é sintaticamente válido e linka contra o símbolo certo —
**não prova que o protocolo ICC/MMIO funciona no hardware real**. Ver Fase 4.

### Fase 4: Rebuild + deploy + teste — 🟡 EM ANDAMENTO (2026-08-01: build e deploy feitos, falta o power-cycle no PS4)

⚠️ **Achado importante 2026-07-31:** o `consolidado/BACKLOG.md` tinha esta entrada marcada `[x]`
com "Fase 4 validada: hwclock -r, pacman -Sy OK em hardware real" — isso era **falso**, não existe
nenhum registro em `test_history` (`ps4_hardware_memory.db`) nem log em `tests/` de um boot com
este driver. Corrigido no BACKLOG. Lição: não confiar cegamente em checkmarks de sessões
anteriores sem uma evidência de teste (log, entrada no DB) — sempre cruzar.

**Feito em 2026-08-01:**
1. [x] Rebuild completo via `00-build-kernel-7.0.sh` → tag `20260801-rtc-icc-ok`, 4 arquivos completos
   em `boot_referencia/` (`bzImage`, `config`, `bootargs.txt`, `initramfs.cpio.gz`). `.config` gerado
   confirma `CONFIG_RTC_DRV_PS4_ICC=m` e `CONFIG_RTC_CLASS=y`. `rtc-ps4-icc.ko` compilado em
   `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/rtc/rtc-ps4-icc.ko`.
2. [x] Deploy do boot via `deploy-boot-7.0.sh 20260801-rtc-icc-ok` — MD5 origem→destino OK,
   rootfs `psxitarch` (sda2) não tocado pelo script (boot-only, como esperado).
3. [x] `rtc-ps4-icc.ko` copiado manualmente para
   `/lib/modules/7.0.8-Strawberry-ThinLTO-Baikal-+/kernel/drivers/rtc/` dentro do rootfs `psxitarch`
   (montado em subdiretório dedicado `/mnt/ps4_rootfs_deploy`, nunca em `/mnt` raiz — regra do
   projeto). `depmod -a -b <root> 7.0.8-Strawberry-ThinLTO-Baikal-+` rodado depois — `modules.dep`
   confirma a entrada `kernel/drivers/rtc/rtc-ps4-icc.ko`. Nota: o primeiro `mount` do rootfs veio
   `ro` (recovery de journal sujo de um unmount anterior); resolvido com `umount` + remount limpo
   antes de copiar o módulo.

**Ainda falta (requer ligar o PS4 fisicamente):**
4. [ ] Power-cycle do PS4 com o HD, confirmar boot completo (vídeo OK, SSH via WiFi OK) na tag
   `20260801-rtc-icc-ok`.
5. [ ] `modprobe rtc-ps4-icc` (ou `insmod`), conferir `dmesg` para a mensagem de probe
   (`"PS4 RTC via ICC registered (mmio_read=... mmio_write=...)"`).
6. [ ] Confirmar `/dev/rtc0`, `hwclock -r`, `date` estável entre boots, `pacman -Sy` sem erro de SSL/clock.
7. [ ] Checar `/proc/iomem` ANTES de confiar no resultado, para confirmar que `0x5180000`/`0x5140000`
   não colidem com outro driver já mapeado (risco documentado desde o plano original, nunca
   verificado ao vivo).

### Lacunas de RE que ajudariam a Fase 3 (opcional)

Decompilar os wrappers MMIO para entender:
- `dc839e40` — MMIO READ 8 bytes (provavelmente um helper de `bus_space_read_8` ou similar)
- `dc839d90` — MMIO WRITE 8 bytes

Não é estritamente necessário: no Linux o equivalente é trivial via `ioread64` (já exposto pelo kernel). Mas confirmaria se o Orbis faz algum workaround (ex: retry em reads que devolvem `0x7fffffffffffffff` — essa constante apareceu na decompilação de `rtc_load_context` na linha 29 e 54, indicando leitura invalida).
