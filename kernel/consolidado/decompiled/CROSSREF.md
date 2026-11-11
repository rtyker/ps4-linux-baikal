# Call-Graph de Funções MTS/GBE/ICC/glue

> Gerado automaticamente por `consolidado/tools/gen_crossref.py` a partir de:
> - `consolidado/ps4_hardware_memory.db` → tabela `decompiled_functions`
> - `consolidado/decompiled/extracted/*.txt` → header com callers/callees
>
> Cada função lista seus chamadores (quem a chama) e suas chamadas (quem ela chama).
> Endereços em formato curto (`dc5a0070`).

| **TOTAL** | 69 | 60 | 8 | 1 |
## Resumo de cobertura

| Categoria | Total | Bruto | Revisado | Refutado |
|---|---|---|---|---|
| GBE | 5 | 4 | 1 | 0 |
| GBE_LACUNA | 3 | 3 | 0 | 0 |
| GLUE_LACUNA | 4 | 4 | 0 | 0 |
| Glue | 2 | 0 | 2 | 0 |
| ICC | 9 | 8 | 1 | 0 |
| ICC_LACUNA | 2 | 2 | 0 | 0 |
| MSK | 3 | 3 | 0 | 0 |
| MTS | 15 | 11 | 3 | 1 |
| MTS_HELPER_LACUNA | 2 | 2 | 0 | 0 |
| MTS_LACUNA | 7 | 7 | 0 | 0 |
| MTS_helper | 1 | 1 | 0 | 0 |
| PCIe | 3 | 2 | 1 | 0 |
| PHY_REF | 2 | 2 | 0 | 0 |
| RTC (rtc.c) | 4 | 4 | 0 | 0 |
| RTC (rtc_mvl.c) | 4 | 4 | 0 | 0 |
| UNKNOWN | 3 | 3 | 0 | 0 |

## Call-graph por função

### `dc3f5bd0` — bruto — RTC (rtc.c)

- **Papel**: wrapper ICC query (major<=4, len<=0x401). Monta packet 2032B e chama dc797090 (ICC transport). Suporte read+write (com dc3f5a10 variante write).
- **Arquivo**: `consolidado/decompiled/icc_query_dc3f5bd0.c`

- **Chamadores** (20):
  - `dc84e420` FUN_ffffffffdc84e420 (?)
  - `dc913bb0` FUN_ffffffffdc913bb0 (?)
  - `dc399110` FUN_ffffffffdc399110 (?)
  - `dc9882f0` FUN_ffffffffdc9882f0 (?)
  - `dc399380` FUN_ffffffffdc399380 (?)
  - `dc799b80` FUN_ffffffffdc799b80 (?)
  - `dc84e250` FUN_ffffffffdc84e250 (?)
  - `dc8f8470` FUN_ffffffffdc8f8470 (?)
  - `dc989df0` FUN_ffffffffdc989df0 (?)
  - `dc735080` FUN_ffffffffdc735080 (?)
  - `dc988930` FUN_ffffffffdc988930 (?)
  - `dc8c85a0` FUN_ffffffffdc8c85a0 (?)
  - `dc8d1ea0` FUN_ffffffffdc8d1ea0 (?)
  - `dc9886b0` FUN_ffffffffdc9886b0 (?)
  - `dc36c020` FUN_ffffffffdc36c020 (?)
  - `dc99a6e0` FUN_ffffffffdc99a6e0 (?)
  - `dc84e460` FUN_ffffffffdc84e460 (?)
  - `dc8d2140` FUN_ffffffffdc8d2140 (?)
  - `dc799ad0` FUN_ffffffffdc799ad0 (?)
  - `dc36bb10` FUN_ffffffffdc36bb10 (?)
- **Chamadas** (4):
  - `dc797090` FUN_ffffffffdc797090 (?)
  - `dca17ba0` FUN_ffffffffdca17ba0 (?)
  - `dc60d4c0` FUN_ffffffffdc60d4c0 (?)
  - `dc60d400` FUN_ffffffffdc60d400 (?)

### `dc528ef0` — bruto — ICC_LACUNA

- **Papel**: handler 4/0x38 = GBE power-on. Sem callers (registrado via callback).
- **Arquivo**: `decompiled/extracted/decompiled_dc528ef0.txt`

- **Chamadores**: nenhum (registrado via callback - provável handler de IRQ/timer)
- **Chamadas** (4):
  - `dc6c8300` FUN_ffffffffdc6c8300 (?)
  - `dc5746d0` FUN_ffffffffdc5746d0 (?)
  - `dc6c85b0` FUN_ffffffffdc6c85b0 (?)
  - `dc574770` FUN_ffffffffdc574770 (?)

### `dc529ed0` — bruto — GBE_LACUNA

- **Papel**: carta branca - origem desconhecida
- **Arquivo**: `decompiled/extracted/decompiled_dc529ed0.txt`

- **Chamadores** (20):
  - `dc802fd0` FUN_ffffffffdc802fd0 (?)
  - `dc8333e0` FUN_ffffffffdc8333e0 (?)
  - `dc82bfc0` FUN_ffffffffdc82bfc0 (?)
  - `dc99b670` FUN_ffffffffdc99b670 (?)
  - `dc9196f0` FUN_ffffffffdc9196f0 (?)
  - `dc594ae0` FUN_ffffffffdc594ae0 (?)
  - `dc9a4ea0` FUN_ffffffffdc9a4ea0 (?)
  - `dc7e53a0` FUN_ffffffffdc7e53a0 (?)
  - `dc7874f0` FUN_ffffffffdc7874f0 (?)
  - `dc934c10` FUN_ffffffffdc934c10 (?)
  - `dc800d90` FUN_ffffffffdc800d90 (?)
  - `dc9a56c0` FUN_ffffffffdc9a56c0 (?)
  - `dc82d380` FUN_ffffffffdc82d380 (?)
  - `dc7fe990` FUN_ffffffffdc7fe990 (?)
  - `dc9a4fc0` FUN_ffffffffdc9a4fc0 (?)
  - `dc9a5430` FUN_ffffffffdc9a5430 (?)
  - `dc798dd0` FUN_ffffffffdc798dd0 (?)
  - `dc9a5690` FUN_ffffffffdc9a5690 (?)
  - `dc7ffd00` FUN_ffffffffdc7ffd00 (?)
  - `dc833650` FUN_ffffffffdc833650 (?)
- **Chamadas** (3):
  - `dca17ba0` FUN_ffffffffdca17ba0 (?)
  - `dc60d400` FUN_ffffffffdc60d400 (?)
  - `dc60d4c0` FUN_ffffffffdc60d4c0 (?)

### `dc529f40` — bruto — GBE_LACUNA

- **Papel**: carta branca - origem desconhecida
- **Arquivo**: `decompiled/extracted/decompiled_dc529f40.txt`

- **Chamadores** (16):
  - `dc7190d0` FUN_ffffffffdc7190d0 (PCIe)
  - `dc76f800` FUN_ffffffffdc76f800 (?)
  - `dc985a40` FUN_ffffffffdc985a40 (?)
  - `dc45cd00` FUN_ffffffffdc45cd00 (?)
  - `dc985290` FUN_ffffffffdc985290 (?)
  - `dc97d790` FUN_ffffffffdc97d790 (?)
  - `dc9882f0` FUN_ffffffffdc9882f0 (?)
  - `dc9886b0` FUN_ffffffffdc9886b0 (?)
  - `dc76fe50` FUN_ffffffffdc76fe50 (?)
  - `dc76fc80` FUN_ffffffffdc76fc80 (?)
  - `dc985240` FUN_ffffffffdc985240 (?)
  - `dc989df0` FUN_ffffffffdc989df0 (?)
  - `dc566c30` FUN_ffffffffdc566c30 (?)
  - `dc98d1e0` FUN_ffffffffdc98d1e0 (?)
  - `dc988930` FUN_ffffffffdc988930 (?)
  - `dc989b70` FUN_ffffffffdc989b70 (?)
- **Chamadas** (3):
  - `dca17ba0` FUN_ffffffffdca17ba0 (?)
  - `dc60d400` FUN_ffffffffdc60d400 (?)
  - `dc60d4c0` FUN_ffffffffdc60d4c0 (?)

### `dc52a4f0` — bruto — GBE_LACUNA

- **Papel**: carta branca - origem desconhecida
- **Arquivo**: `decompiled/extracted/decompiled_dc52a4f0.txt`

- **Chamadores** (5):
  - `dc7190d0` FUN_ffffffffdc7190d0 (PCIe)
  - `dc5297a0` FUN_ffffffffdc5297a0 (?)
  - `dc9a4da0` FUN_ffffffffdc9a4da0 (?)
  - `dc566c30` FUN_ffffffffdc566c30 (?)
  - `dc9a56f0` FUN_ffffffffdc9a56f0 (?)
- **Chamadas** (3):
  - `dca17ba0` FUN_ffffffffdca17ba0 (?)
  - `dc60d400` FUN_ffffffffdc60d400 (?)
  - `dc60d4c0` FUN_ffffffffdc60d4c0 (?)

### `dc574150` — bruto — ICC_LACUNA

- **Papel**: registra handlers ICC - chamado 94x (todos os drivers). 2 callees.
- **Arquivo**: `decompiled/extracted/decompiled_dc574150.txt`

- **Chamadores** (20):
  - `dc962750` FUN_ffffffffdc962750 (?)
  - `dc71d9d0` FUN_ffffffffdc71d9d0 (?)
  - `dc5bc880` FUN_ffffffffdc5bc880 (?)
  - `dc57f1c0` FUN_ffffffffdc57f1c0 (?)
  - `dc8a5a90` FUN_ffffffffdc8a5a90 (?)
  - `dc7d7a10` FUN_ffffffffdc7d7a10 (?)
  - `dc579bf0` FUN_ffffffffdc579bf0 (?)
  - `dc3862d0` FUN_ffffffffdc3862d0 (?)
  - `dc399380` FUN_ffffffffdc399380 (?)
  - `dc9c3e70` FUN_ffffffffdc9c3e70 (?)
  - `dc7b6a80` FUN_ffffffffdc7b6a80 (?)
  - `dc3cf960` FUN_ffffffffdc3cf960 (?)
  - `dc8b6320` FUN_ffffffffdc8b6320 (?)
  - `dc59ed80` FUN_ffffffffdc59ed80 (?)
  - `dc7ca8c0` FUN_ffffffffdc7ca8c0 (?)
  - `dc7b5750` FUN_ffffffffdc7b5750 (?)
  - `dc832740` FUN_ffffffffdc832740 (?)
  - `dca183f0` FUN_ffffffffdca183f0 (?)
  - `dc7cfdb0` FUN_ffffffffdc7cfdb0 (?)
  - `dc528600` FUN_ffffffffdc528600 (ICC)
- **Chamadas** (2):
  - `dc5741c0` FUN_ffffffffdc5741c0 (?)
  - `dc359520` FUN_ffffffffdc359520 (?)

### `dc5a2840` — bruto — MTS_LACUNA

- **Papel**: MDIO read high word (bits 31:16)
- **Arquivo**: `decompiled/extracted/decompiled_dc5a2840.txt`

- **Chamadores** (4):
  - `dc5a65e0` FUN_ffffffffdc5a65e0 (?)
  - `dc5a0ba0` FUN_ffffffffdc5a0ba0 (MTS)
  - `dc5a3810` FUN_ffffffffdc5a3810 (MTS)
  - `dc5a44c0` FUN_ffffffffdc5a44c0 (MTS)
- **Chamadas** (4):
  - `dc6c8300` FUN_ffffffffdc6c8300 (?)
  - `dc6c85b0` FUN_ffffffffdc6c85b0 (?)
  - `dc4afb10` FUN_ffffffffdc4afb10 (?)
  - `dc630420` FUN_ffffffffdc630420 (?)

### `dc5a2950` — bruto — MTS_LACUNA

- **Papel**: MDIO write opcode 0x2000 (wait bit 15=0)
- **Arquivo**: `decompiled/extracted/decompiled_dc5a2950.txt`

- **Chamadores** (4):
  - `dc5a65e0` FUN_ffffffffdc5a65e0 (?)
  - `dc5a0ba0` FUN_ffffffffdc5a0ba0 (MTS)
  - `dc5a3810` FUN_ffffffffdc5a3810 (MTS)
  - `dc5a44c0` FUN_ffffffffdc5a44c0 (MTS)
- **Chamadas** (4):
  - `dc6c8300` FUN_ffffffffdc6c8300 (?)
  - `dc6c85b0` FUN_ffffffffdc6c85b0 (?)
  - `dc4afb10` FUN_ffffffffdc4afb10 (?)
  - `dc630420` FUN_ffffffffdc630420 (?)

### `dc5a4950` — bruto — MTS_LACUNA

- **Papel**: gatilho BAR0+0x1c = 0x80000000 (ativou motor MAC/PHY 0x0->0x80030000)
- **Arquivo**: `decompiled/extracted/decompiled_dc5a4950.txt`

- **Chamadores** (1):
  - `dc5a3810` FUN_ffffffffdc5a3810 (MTS)
- **Chamadas** (4):
  - `dc4dfa20` FUN_ffffffffdc4dfa20 (?)
  - `dca17ba0` FUN_ffffffffdca17ba0 (?)
  - `dc4afb10` FUN_ffffffffdc4afb10 (?)
  - `dc4dfa40` FUN_ffffffffdc4dfa40 (?)

### `dc5a4e90` — bruto — MTS_LACUNA

- **Papel**: relacionado ao RMU/dc5a5200
- **Arquivo**: `decompiled/extracted/decompiled_dc5a4e90.txt`

- **Chamadores** (1):
  - `dc5a3810` FUN_ffffffffdc5a3810 (MTS)
- **Chamadas** (3):
  - `dc5a5570` FUN_ffffffffdc5a5570 (?)
  - `dc4afb10` FUN_ffffffffdc4afb10 (?)
  - `dc5a5200` FUN_ffffffffdc5a5200 (MTS_LACUNA)

### `dc5a5050` — bruto — MTS_LACUNA

- **Papel**: provavel proximo chamado de dc5a4e90
- **Arquivo**: `decompiled/extracted/decompiled_dc5a5050.txt`

- **Chamadores** (2):
  - `dc5a3810` FUN_ffffffffdc5a3810 (MTS)
  - `dc5a6290` FUN_ffffffffdc5a6290 (MTS_LACUNA)
- **Chamadas** (2):
  - `dc4e0540` FUN_ffffffffdc4e0540 (?)
  - `dc5a5200` FUN_ffffffffdc5a5200 (MTS_LACUNA)

### `dc5a5200` — bruto — MTS_LACUNA

- **Papel**: MDIO read high word (32-bit read devad=1 reg=0)
- **Arquivo**: `decompiled/extracted/decompiled_dc5a5200.txt`

- **Chamadores** (4):
  - `dc5a65e0` FUN_ffffffffdc5a65e0 (?)
  - `dc5a5050` FUN_ffffffffdc5a5050 (MTS_LACUNA)
  - `dc5a4e90` FUN_ffffffffdc5a4e90 (MTS_LACUNA)
  - `dc5a6290` FUN_ffffffffdc5a6290 (MTS_LACUNA)
- **Chamadas** (7):
  - `dca17ba0` FUN_ffffffffdca17ba0 (?)
  - `dc60d4c0` FUN_ffffffffdc60d4c0 (?)
  - `dc3f3950` FUN_ffffffffdc3f3950 (?)
  - `dc3f3660` FUN_ffffffffdc3f3660 (?)
  - `dc4afb10` FUN_ffffffffdc4afb10 (?)
  - `dc5a58d0` FUN_ffffffffdc5a58d0 (MTS)
  - `dc60d400` FUN_ffffffffdc60d400 (?)

### `dc5a6290` — bruto — MTS_LACUNA

- **Papel**: sub-rotina vista em chamada
- **Arquivo**: `decompiled/extracted/decompiled_dc5a6290.txt`

- **Chamadores** (2):
  - `dc5a41d0` FUN_ffffffffdc5a41d0 (MTS)
  - `dc5a5ec0` FUN_ffffffffdc5a5ec0 (MTS)
- **Chamadas** (9):
  - `dca17ba0` FUN_ffffffffdca17ba0 (?)
  - `dc60d4c0` FUN_ffffffffdc60d4c0 (?)
  - `dc3f3950` FUN_ffffffffdc3f3950 (?)
  - `dc3f3660` FUN_ffffffffdc3f3660 (?)
  - `dc5b7b80` FUN_ffffffffdc5b7b80 (?)
  - `dc5a58d0` FUN_ffffffffdc5a58d0 (MTS)
  - `dc5a5050` FUN_ffffffffdc5a5050 (MTS_LACUNA)
  - `dc5a5200` FUN_ffffffffdc5a5200 (MTS_LACUNA)
  - `dc60d400` FUN_ffffffffdc60d400 (?)

### `dc5ba8d0` — bruto — MTS_HELPER_LACUNA

- **Papel**: aloca BARs (chamado por dc718eb0)
- **Arquivo**: `decompiled/extracted/decompiled_dc5ba8d0.txt`

- **Chamadores** (20):
  - `dc3cb570` FUN_ffffffffdc3cb570 (?)
  - `dc6fcf90` FUN_ffffffffdc6fcf90 (?)
  - `dc3fc3e0` FUN_ffffffffdc3fc3e0 (?)
  - `dc47bfd0` FUN_ffffffffdc47bfd0 (?)
  - `dc74c340` FUN_ffffffffdc74c340 (?)
  - `dc3531d0` FUN_ffffffffdc3531d0 (?)
  - `dc353b70` FUN_ffffffffdc353b70 (?)
  - `dc59f840` FUN_ffffffffdc59f840 (?)
  - `dc7704d0` FUN_ffffffffdc7704d0 (?)
  - `dc380420` FUN_ffffffffdc380420 (?)
  - `dc572440` FUN_ffffffffdc572440 (?)
  - `dc73e6e0` FUN_ffffffffdc73e6e0 (?)
  - `dc68a1b0` FUN_ffffffffdc68a1b0 (?)
  - `dc7fbb30` FUN_ffffffffdc7fbb30 (?)
  - `dc359290` FUN_ffffffffdc359290 (?)
  - `dc5142b0` FUN_ffffffffdc5142b0 (?)
  - `dc4dbbb0` FUN_ffffffffdc4dbbb0 (?)
  - `dc571090` FUN_ffffffffdc571090 (?)
  - `dc5bca20` FUN_ffffffffdc5bca20 (?)
  - `dc388260` FUN_ffffffffdc388260 (?)
- **Chamadas** (1):
  - `dc4ebcf0` FUN_ffffffffdc4ebcf0 (?)

### `dc5baa30` — bruto — MTS_HELPER_LACUNA

- **Papel**: cria ifnet (chamado por dc5a0070)
- **Arquivo**: `decompiled/extracted/decompiled_dc5baa30.txt`

- **Chamadores** (17):
  - `dc3cb570` FUN_ffffffffdc3cb570 (?)
  - `dc6fcf90` FUN_ffffffffdc6fcf90 (?)
  - `dc5a0070` FUN_ffffffffdc5a0070 (MTS)
  - `dc7b3a40` FUN_ffffffffdc7b3a40 (?)
  - `dc43f380` FUN_ffffffffdc43f380 (?)
  - `dc74c340` FUN_ffffffffdc74c340 (?)
  - `dc62b0e0` FUN_ffffffffdc62b0e0 (?)
  - `dc572440` FUN_ffffffffdc572440 (?)
  - `dc7fbb30` FUN_ffffffffdc7fbb30 (?)
  - `dc4c5140` FUN_ffffffffdc4c5140 (MSK)
  - `dc5142b0` FUN_ffffffffdc5142b0 (?)
  - `dc88c940` FUN_ffffffffdc88c940 (?)
  - `dc4dbbb0` FUN_ffffffffdc4dbbb0 (?)
  - `dc5bca20` FUN_ffffffffdc5bca20 (?)
  - `dc388260` FUN_ffffffffdc388260 (?)
  - `dc7982e0` FUN_ffffffffdc7982e0 (?)
  - `dc72dfd0` FUN_ffffffffdc72dfd0 (?)
- **Chamadas** (2):
  - `dc5b7b80` FUN_ffffffffdc5b7b80 (?)
  - `dc4ebcf0` FUN_ffffffffdc4ebcf0 (?)

### `dc6dfb60` — bruto — GLUE_LACUNA

- **Papel**: primitiva reset do glue (chamado por dc6df850(0x4000) e 0x2000)
- **Arquivo**: `decompiled/extracted/decompiled_dc6dfb60.txt`

- **Chamadores** (1):
  - `dc6df850` FUN_ffffffffdc6df850 (Glue)
- **Chamadas** (4):
  - `dc4afb10` FUN_ffffffffdc4afb10 (?)
  - `dc718800` FUN_ffffffffdc718800 (GLUE_LACUNA)
  - `dc630420` FUN_ffffffffdc630420 (?)
  - `dc7187d0` FUN_ffffffffdc7187d0 (GLUE_LACUNA)

### `dc7187a0` — bruto — GLUE_LACUNA

- **Papel**: glue read (chamado em dc72bfb0 SATA PHY init)
- **Arquivo**: `decompiled/extracted/decompiled_dc7187a0.txt`

- **Chamadores** (3):
  - `dc5a0ba0` FUN_ffffffffdc5a0ba0 (MTS)
  - `dc7db0b0` FUN_ffffffffdc7db0b0 (PHY_REF)
  - `dc72bfb0` FUN_ffffffffdc72bfb0 (PHY_REF)
- **Chamadas**: nenhuma (leaf function - provavelmente I/O direto)

### `dc7187d0` — bruto — GLUE_LACUNA

- **Papel**: glue read (chamado em dc6df850)
- **Arquivo**: `decompiled/extracted/decompiled_dc7187d0.txt`

- **Chamadores** (3):
  - `dc6df850` FUN_ffffffffdc6df850 (Glue)
  - `dc6dfb60` FUN_ffffffffdc6dfb60 (GLUE_LACUNA)
  - `dc714850` FUN_ffffffffdc714850 (?)
- **Chamadas**: nenhuma (leaf function - provavelmente I/O direto)

### `dc718800` — bruto — GLUE_LACUNA

- **Papel**: glue write (chamado em dc6df850)
- **Arquivo**: `decompiled/extracted/decompiled_dc718800.txt`

- **Chamadores** (2):
  - `dc6df850` FUN_ffffffffdc6df850 (Glue)
  - `dc6dfb60` FUN_ffffffffdc6dfb60 (GLUE_LACUNA)
- **Chamadas**: nenhuma (leaf function - provavelmente I/O direto)
