# Índice de Funções Decompiladas — MTS / GBE / ICC / Glue

> Catálogo canônico das funções decompiladas do kernel Orbis 12.52 (`consolidado/dumps_orbis/kmem_dump_1252.bin`) que pertencem ao escopo de interesse do projeto: driver MTS, GBE, ICC e glue Baikal.
>
> **Critério de inclusão**: função decompilada em arquivo próprio, referenciada em testes ao vivo (`ps4_hardware_memory.db`) ou em callgraph a partir de raízes MTS (`dc5a0070` mtsc_pci_attach, `dc5a34f0` mts_attach, `dc5a41d0` gbe_mac_attach, `dc5a44c0` gbe_phy_attach).
>
> Cada entrada traz status: ✅ revisado / ⚠️ bruto não revisado / 🚫 refutado em teste.

---

## 1. MTS — Driver de Rede (`0xffffffffdc5a????`)

### PCI / Attach (raiz do call-graph)

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc5a0070` | `mtsc_pci_attach_dc5a0070.txt` | 199 | ⚠️ | `mtsc_pci_attach` — entrada do driver MTS (PCI probe) |
| `dc5a0070` | `mtsc_pci_attach_ghidra.txt` | 199 | ⚠️ | versão Ghidra alternativa (mesma função) |
| `dc5a0070` | `mtsc_pci_attach_asm.txt` | 418 | ⚠️ | disassembly raw (complementar) |
| `dc5a34f0` | `mts_attach_dc5a34f0.txt` | 99 | ⚠️ | `mts_attach` — attach da interface de rede |
| `dc5a41d0` | `legacy_raiz/decompiled_gbe_mac_attach.txt` | 95 | ⚠️ | `SceGbeMtsCtrl_attach` — attach do MAC GBE |
| `dc5a44c0` | `legacy_raiz/decompiled_gbe_phy_attach.txt` | 161 | ⚠️ | `SceGbeMtsPhyCtrl_attach` — attach do PHY (thread gbe_phy_ctrl) |

### Mac Start / Stop / Calibração

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc5a0ba0` | `legacy_raiz/decompiled_dc5a0ba0_gbe_phy_calib.txt` | 530 | ⚠️ | `gbe_phy_calibration` — loop de calibração do PHY (66 iterações `0x1bc-0x1d4`) |
| `dc5a0c80` | `legacy_raiz/decompiled_dc5a0c80.txt` | 444 | ⚠️ | chamado por `dc5a0ba0` — sub-rotina de calibração |
| `dc5a3060` | `legacy_raiz/decompiled_dc5a3060.txt` | 83 | 🚫 | `mac_stop` — parada do MAC. **Refutado** em `obsoleto/GBE_BRINGUP_DEEP_ANALYSIS.md` seção 3.6 ( escreve em `*(softc+0x3068)+0x10` = BAR0 do MAC, **não** PCI config space). Instruções corretas de stop/soft-reset em `AGENTS.md`. |
| `dc5a31f0` | `legacy_raiz/decompiled_dc5a31f0.txt` | 126 | ✅ | `mac_enable` — start do MAC (par oposto de `dc5a3060`). Sequência correta em `MTS_INIT_SEQUENCE_dc5a31f0.md`. |
| `dc5a3810` | `legacy_raiz/decompiled_dc5a3810.txt` | 254 | ⚠️ | desconhecido — analisar se é `mts_open` ou sub-rotina attach |
| `dc5a58d0` | `legacy_raiz/decompiled_dc5a58d0.txt` | 72 | ⚠️ | handshake RMU — seta bit 2 de BAR0+0x34 ao enviar frame RMU |

### TX / RMU / Frame

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc5a2680` | `legacy_raiz/decompiled_dc5a2680.txt` | 102 | ⚠️ | papel desconhecido, args `(arg1,arg2,arg3)` |
| `dc5a2bd0` | `legacy_raiz/decompiled_dc5a2bd0.txt` | 164 | ⚠️ | papel desconhecido, 11 vars locais — provável setup de descritor |
| `dc5a2d00` | `legacy_raiz/decompiled_dc5a2d00.txt` | 46 | ⚠️ | papel desconhecido |
| `dc5a5ae0` | `legacy_raiz/decompiled_dc5a5ae0.txt` | 199 | ⚠️ | papel desconhecido |
| `dc5a5ec0` | `legacy_raiz/decompiled_dc5a5ec0.txt` | 186 | ⚠️ | **RMU frame build** — confirmado por teste `2026-07-25 01:20`. Frame RMU de 34B (magic `0xfa42`) reconstruído das linhas 131-148 deste arquivo. |

### Lacunas MTS **ainda não decompiladas** (validadas em testes ao vivo)

| Função | Origem da referência | Próximo arquivo |
|---|---|---|
| `dc5a2840` | `test_history` #61 — leitura high word (bits 31:16) MDIO | `decompiled_dc5a2840.txt` |
| `dc5a2950` | `test_history` #61 — escrita opcode 0x2000 MDIO (wait bit 15) | `decompiled_dc5a2950.txt` |
| `dc5a4950` | `test_history` #59 — gatilho BAR0+0x1c = 0x80000000 (ativou motor MAC/PHY, alterou `0x1c` para `0x80030000`) | `decompiled_dc5a4950.txt` |
| `dc5a4e90` | test_history #60 (relacionado a RMU/dc5a5200) | `decompiled_dc5a4e90.txt` |
| `dc5a5050` | provável próximo chamado de dc5a4e90 | `decompiled_dc5a5050.txt` |
| `dc5a5200` | `test_history` #60 — RMU sub-header `0x9807` (offset 26/27 do frame) | `decompiled_dc5a5200.txt` |
| `dc5a6290` | apareceu na chamada de sub-rotina | `decompiled_dc5a6290.txt` |

> **Estimativa de lacuna**: ~40% do fluxo do driver MTS sem cobertura própria. Handlers reais de TX-ring, NAPI, IRQ, timers e sysfs triggers ainda não estão indexados (refletidos em `test_history` como "já testados mas sem RE própria").

---

## 2. MTS — Helpers compartilhados (`dc5b????`)

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc5ba5e0` | `res_alloc_helper_dc5ba5e0.txt` | 87 | ⚠️ | `res_alloc_helper` — alocador de recursos chamado por attach de vários drivers |
| `dc5ba8d0` | referenciado em `baikal_pcie_attach.txt` | — | 🔴 faltando | usado em `dc718eb0` para alocar BARs |
| `dc5baa30` | referenciado em `mtsc_pci_attach_dc5a0070.txt` | — | 🔴 faltando | chamado por `dc5a0070` para criar interface ifnet |

---

## 3. GBE clk/PHY/attach (`dc52????`, `dc53????`)

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc526a60` | `legacy_raiz/decompiled_dc526a60.txt` | 7 | ⚠️ | boolean pequeno — `fcn.dc526a60(void)` |
| `dc526da0` | `legacy_raiz/decompiled_dc526da0.txt` | 41 | ⚠️ | papel desconhecido |
| `dc526e40` | `legacy_raiz/decompiled_dc526e40.txt` | 10 | ✅ | **stepping checker** — `val & 0xff0000 == 0x30000`. Confirmado em `GBE_BRINGUP_DEEP_ANALYSIS.md` seção 2.B. |
| `dc528760` | `icc_power_dc528760.txt` e referenciado em `legacy_raiz/decompiled_dc526da0.txt` | 33 | ✅ | `icc_power` — init dispatcher ICC. LL em seção 4. |
| `dc530200` | `legacy_raiz/decompiled_dc530200.txt` | 110 | ⚠️ | papel desconhecido |
| `dc536580` | `legacy_raiz/decompiled_dc536580.txt` | 139 | ⚠️ | função grande com várias sub-rotinas |

### Lacunas GBE identificadas

`dc529ed0`, `dc529f40`, `dc52a4f0`, `dc530260`, `dc530357/dc5303d8` (jumps internos — provavelmente já estão cobertos nos arquivos acima como blocos, não funções separadas).

---

## 4. ICC — Syscon (`dc7c8???`, `dc478???`, `dc3f5???`)

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc7c8b80` | `icc_device_power_main_dc7c8b80.txt` | 124 | ⚠️ | `icc_device_power_main` — dispatcher principal ICC |
| `dc7c8a30` | `icc_devpower_set_dc7c8a30.txt` | 55 | ⚠️ | `icc_devpower_set` (variante) — função `dc7c8860` |
| `dc7c8a70` | `icc_devpower_set_dc7c8a70.txt` | 21 | ⚠️ | `icc_devpower_set` (variante B) |
| `dc7c8a00` | `legacy_raiz/decompiled_dc7c8a00.txt` | 31 | ⚠️ | papel desconhecido |
| `dc7c8fb0` | `icc_devpower_get_dc7c8fb0.txt` | 29 | ⚠️ | `icc_devpower_get` |
| `dc478a70` | `legacy_raiz/decompiled_icc_power_set.txt` | 21 | ⚠️ | outro "icc_power_set" — wrapper ICC (provável alias de `dc7c8a70`) |
| `dc478b80` | `legacy_raiz/decompiled_icc_power.txt` | 124 | ⚠️ | "icc_power" — provável clone de `dc7c8b80` |
| `dc528600` | `icc_power_dc528760.txt` | 33 | ✅ | `icc_power` — dispatcher de handlers (6 registrados via `dc574150`, último `dc528ef0` é `4/0x38` = GBE power-on) |
| `dc3f5bd0` | (em `baikal_rtc_mvl.txt`/plano rtc_via_icc_plan) | 233 | ⚠️ | **`icc_query` wrapper** — generic ICC dispatcher (major≤4, len≤0x401). Chamado em `rtc.c`, power, glue. |
| `dc3f5400` | `legacy_raiz/decompiled_dc3f5400.txt` | 13 | ⚠️ | apenas 13 linhas — incompleto? |

### Lacunas ICC

| Função | Origem | Próximo arquivo |
|---|---|---|
| `dc3f5bd0` | referenciado em `GBE_BRINGUP_DEEP_ANALYSIS.md` seção 2.A como `icc_query(major=4, minor=0x38)` — **wrapper fundamental** que envia ICC ao Syscon | `decompiled_dc3f5bd0.txt` |
| `dc574150` | chamado 6x em `icc_power_dc528760` para registrar handlers ICC | `decompiled_dc574150.txt` |
| `dc528ef0` | handler `4/0x38` GBE power-on | `decompiled_dc528ef0.txt` |

---

## 5. Glue &Baikal PCIe (`dc6df`, `dc718`, `dc719`)

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc6df850` | `baikal_glue_block_reset_dc6df.txt` | 82 | ✅ | **`glue_block_reset`** — confirmou bloco `0x2000` = GBE (2026-07-25). Hold `0x180020`, pulse `0x180074`. ⚠️ `0x180034` label antigo está **ERRADO** em `AGENTS.md` legacy. |
| `dc718710` | `baikal_glue_write_dc718710.txt` | 17 | ✅ | `glue_write` — write primitive do glue (BLOCK + register) |
| `dc718d20` | `baikal_pcie_probe.txt` | 53 | ⚠️ | `baikal_pcie_probe` |
| `dc718eb0` | `baikal_pcie_attach.txt` / `_asm.txt` / `_ghidra.txt` | 84/133/84 | ⚠️ | `baikal_pcie_attach` — 3 versões (recomendado: `_ghidra`) |
| `dc7190d0` | `legacy_raiz/decompiled_dc7190d0.txt` | 32 | ⚠️ | clock init — escreve `BAR2+0x10a030 = (reg & 0xfffffe07) | 0xd8`. Causou tela preta quando aplicado prematuro no Linux (ver `GBE_BRINGUP_DEEP_ANALYSIS.md` seção 2.B). |

### Lacunas Glue/PCIe

| Função | Origem | Próximo arquivo |
|---|---|---|
| `dc6dfb60` | chamado por `dc6df850(0x4000)` e em `0x2000` bloco GBE — primitiva de reset | `decompiled_dc6dfb60.txt` |
| `dc7187a0` | chamado em `dc72bfb0` (SATA PHY init) — read glue | `decompiled_dc7187a0.txt` |
| `dc7187d0` | chamado em `dc6df850` — read glue | `decompiled_dc7187d0.txt` |
| `dc718800` | chamado em `dc6df850` — write glue | `decompiled_dc718800.txt` |

---

## 6. PHY init para outros dispositivos (referência cruzada)

| Função | Arquivo | Linhas | Papel |
|---|---|---|---|
| `dc72bfb0` | `baikal_sata_phy_init_dc72bfb0.txt` | 1106 | SATA PHY init — usa `dc718710` para toggling. Modelo para GBE PHY. |
| `dc7db0b0` | `baikal_usb_phy_init_dc7db0b0.txt` | 570 | USB PHY init — modelo para GBE PHY. |

---

## 6.B. RTC — Real-Time Clock Aeolia/Marvell (`dc5d6???` e `dc57e???`)

O kernel Orbis tem **DOIS drivers RTC em camadas**.

### (a) `rtc_mvl.c` — driver de BAIXO nível (MMIO direto, read-only)

Driver `sys/dev/scesb/rtc/rtc_mvl.c` — família `_mvl` (Marvell = Baikal).
Base ELF do dump: `0xffffffffdc350000`. Análise consolidada em `baikal_rtc_mvl.txt`.

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc5d63f0` | `baikal_rtc_mvl.txt` §2.1 | 89 | ⚠️ | **`rtc_mvl_probe`** — `bus_alloc_resource` + `device_set_desc("rtc_mvl")`. Falha → ENXIO (6). |
| `dc5d6450` | `baikal_rtc_mvl.txt` §2.2 | 427 | ⚠️ | **`rtc_mvl_attach`** com health-check: lê STATUS `BAR+0x100` (bit 2=OK, bit 8=battery failure); em falha loga `WARNING: Battery/Clock failure indication` e `[Bug 142260] Status:%X, Time:%X`. Retorna `22` (EINVAL) em comprometido, `0` em OK. |
| `dc5d6600` | `baikal_rtc_mvl.txt` §2.3 | 619 | ⚠️ | **`read_aeolia_rtc`** básica — retry loop de leitura estável dos 4 bytes `0x130..0x13c` (32-bit BE), DELAY 100 us. Sem timeout explícito. |
| `dc5d6870` | `baikal_rtc_mvl.txt` §2.4 | 644 | ⚠️ | **`rtc_mvl_gettime`** completa — mesma retry (máx 21 tentativas = 2.1ms com timeout `[Bug 55086] retry error, timeout`) + status em `+0` + time em `+4` + extra `0x160`/`0x164` em `+8`/`+12`. |

Mapa de registradores do hardware (Aeolia RTC):
- `0x100` STATUS — bit 2 = OK, bit 8 = battery failure
- `0x130/134/138/13c` timestamp 32-bit big-endian (LSB em `0x130`)
- `0x160/0x164` campos extra (sub-segundos/ajuste)

> **Descoberta importante**: nenhuma função de `settime` ou `write` foi localizada em
> `rtc_mvl.c` — driver é **read-only** no hardware. Consistente com o projeto linux
> injetando tempo via cmdline `time=` (ver `BOOTARGS.md`).

⚠️ A função `0xffffffffdc5d65c4` reportada pelo r2 (162 B) não é função real — é
continuação `goto code_r0xffffffffdc5d6559` dentro de `rtc_mvl_attach` (artefato do
pseudo-C).

### (b) `rtc.c` — driver de ALTO nível (via ICC + MMIO 0x5180000/0x5140000)

Driver `sys/dev/scesb/rtc/rtc.c` — driver genérico "ssb_rtc" suporta Aeolia/Belize/Baikal
(strings de device desc `0xffffffffdcb0908b/096/0a1`). **Este é o driver recomendado para
o Linux** (tem settime e usa o protocolo ICC que já expomos no `bpcie_icc_cmd`). Análise
consolidada em `consolidato/plans/rtc_via_icc_plan.md` seção "Validação da RE (2026-07-25)".

| Função | Arquivo | Linhas | Status | Papel |
|---|---|---|---|---|
| `dc3f5bd0` | plano `rtc_via_icc_plan.md` | 233 | ⚠️ | **`icc_query`** — wrapper ICC (major≤4, len≤0x401). Monta packet ICC de 2032B e chama `dc797090`. Variante write = `dc3f5a10`. |
| `dc57e9d0` | plano `rtc_via_icc_plan.md` | 465 | ⚠️ | **`ssb_rtc_init_exclock`** — boot init: ICC(4,0x50) lê bitmask alarmes + vtable `get_registry_offset` + MMIO read `0x5180000`. |
| `dc57f340` | plano `rtc_via_icc_plan.md` | 601 | ⚠️ | **`rtc_load_context`** — ICC load ctx (major=2 minor=0x0c sub=0x81/1 via `dc6b1b80`) + MMIO read `0x5180000`; em cold start (flag=0) escreve `0x5140000` com "epoch Sony" (-0x4effa200 - time). |
| `dc57f6f0` | plano `rtc_via_icc_plan.md` | 308 | ⚠️ | **`rtc_save_context`** — ICC save ctx (major=2 minor=0x0b sub=0x81/1 via `dc6b1a20`) + re-synca bitmask alarmes 0xc0/0xc4/0xc8 para ICC(4,0x50). |
| `dc839e40` | referenciado por `dc57e9d0`/`dc57f340` | — | 🔴 faltando | wrapper MMIO READ 8 bytes — usado com `(0x5180000, &buf, 8)` e `(0x5140000, &buf, 8)`. |
| `dc839d90` | referenciado por `dc57f340` | — | 🔴 faltando | wrapper MMIO WRITE 8 bytes — usado em cold start com `(0x5140000, &buf, 8)`. |
| `dc6b1a20` | referenciado por `rtc_save_context` | — | 🔴 faltando | dispatch ICC save (sub-op 0x81) — traduz p/ major=2 minor=0x0b. |
| `dc6b1b80` | referenciado por `rtc_load_context` | — | 🔴 faltando | dispatch ICC load (sub-op 0x81) — traduz p/ major=2 minor=0x0c. |
| `dc797090` | referenciado por `icc_query` | — | 🔴 faltando | ICC transport subjacente — envia pacote ICC 2032B ao SC. |

Globais importantes (kernel x86): `0xffffffffde526a88` = softc RTC; `0xffffffffdeaacea0` = mutex RTC.
Constante mágica Sony `0x4effa200` = offset de epoch arbitrária — **NÃO usar no driver Linux** (escrever epoch unix puro).

Strings do driver `rtc.c`: `Aeolia RTC`, `Belize RTC`, `Baikal RTC` (device desc),
`ssb_rtc_pci` (probe), `rtc_shutdown_event`, `rtc_mtx_lock`, `rtc_rw`, `get_registry_offset` /
`set_registry_offset`, `RTC: icc save context fail %d`, `RTC: icc load context fail %d`,
`[RTC] ERR: %s sceRegMgrGetBin/SetBin() Fail :%d`, `RTC device error: Set Usertime 1970/01/01`.

---

## 7. Referência cruzada: testes ao vivo por função

As funções MTS só são validadas em testes ao vivo. Consultar `ps4_hardware_memory.db`:

```bash
sqlite3 consolidado/ps4_hardware_memory.db \
  "SELECT id, phase, substr(test_name,1,90), status FROM test_history
   WHERE test_name LIKE '%dc5a%' OR action_taken LIKE '%dc5a%' OR complementary_info LIKE '%dc5a%'
   ORDER BY id DESC;"
```

Testes que confirmaram o papel de funções específicas:

| Teste | Função | Achado |
|---|---|---|
| #61 — `Correcao Clause 22 MDIO BMCR=0x1040` | `dc5a2840` + `dc5a2950` | MDIO Clause 22 ativado (BMCR=0x1040 estável). **Bring-up PHY ativo.** |
| #60 — `RMU sub-header 0x9807` | `dc5a5200` | RMU TX processado com sub-header 0x9807. |
| #59 — `BAR0 0x1c Trigger` | `dc5a4950` | Confirmado: BAR0+0x1c=0x80000000 ativa motor MAC/PHY (0x0→0x80030000, bit 17). |
| #54 — `handshake RMU` | `dc5a5ec0` | RMU 34B (+magic 0xfa42) enviado via DMA TX. Hardware aceitou. |
| #52 — `Poll PHY 20s replicando Orbis` | `dc5a44c0` | HIPÓTESE REFUTADA: 20s não é o problema. PHY mudo. Thread é orientada a eventos — espera IRQ/sinal ext. |

---

## 8. Próximos alvos para decompilação (Fase 3 deste plano)

Prioridade alta (já validadas em testes, impactam diretamente o bring-up):

1. `dc5a2840` — MDIO read high word
2. `dc5a2950` — MDIO write opcode
3. `dc5a4950` — gatilho BAR0+0x1c
4. `dc5a5200` — RMU sub-header 0x9807
5. `dc3f5bd0` — wrapper `icc_query(4, 0x38)` fundamental

Prioridade média (callgraph MTS):

6. `dc5a3810` (254 linhas — grande, provável núcleo de TX/NAPI)
7. `dc5a4e90`, `dc5a5050` ( sequência pós-trigger)
8. `dc5baa30`, `dc5ba8d0` (alocador e criação de ifnet)
9. `dc6dfb60` (primitiva de reset do glue)
10. `dc7187a0/d/800` (primitivas read/write do glue)

Prioridade baixa:

11. `dc957e10`, `dc95a780`, `dc95a950` (sem contexto claro se pertencem a MTS)
12. Funções `msk_*` (driver Marvell Yukon genérico — competidor, não Sky2 path do PS4 Pro Baikal)

---

## 9. Histórico

- **2026-07-20**: Primeira leva de decompilações geradas por Ghidra manual — driver MTS, GBE attach.
- **2026-07-21**: Decompilação cirúrgica dos PHY init (SATA, USB), glue, ICC.
- **2026-07-25**: Testes ao vivo confirmaram/refutaram múltiplas funções MTS. GBE hold corrigido para `0x180020`. MDIO Clause 22 ativo.
- **2026-07-26** (este INDEX): Consolidação de 49 arquivos em catálogo único. 42 funções únicas, 3 com versão dupla/tripla.
