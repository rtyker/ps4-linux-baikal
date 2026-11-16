# `rea/` — acervo de engenharia reversa

Tudo que vem de **engenharia reversa do hardware/firmware do PS4** mora aqui:
dumps do Orbis, código decompilado, varreduras de registradores, scripts de
Ghidra e o banco SQLite com o histórico de leituras/testes.

> **Regra do projeto (vale mais que qualquer convenience):** antes de varrer
> registradores ao vivo, pedir decompilação nova ou repetir um teste, **consulte
> primeiro** o banco e o catálogo — cada teste ao vivo custa um power cycle
> inteiro do console.

---

## Mapa da pasta

| Caminho | Conteúdo | Versionado |
|---|---|---|
| `ps4_hardware_memory.db` | **banco oficial** (SQLite): `bar0_register_map`, `hardware_registers`, `readonly_verification`, `write_sweep_results`, `decompiled_functions`, `test_history` | Sim (1,2 MB) |
| `decompiled/` | saídas do Ghidra (`*.txt` por função), `INDEX.md` (catálogo canônico) e `CROSSREF.md` | Sim (texto) |
| `decompiled/extracted/` | saída padrão dos scripts `ghidra_scripts/` | Sim |
| `decompiled/geom_crypt/` | pseudocódigo da pipeline de criptografia GEOM | Sim |
| `decompiled/legacy_raiz/` | decompilados antigos, preservados como referência | Sim |
| `dumps/` | **binários do console**: `kmem_dump_1252.bin` (kernel Orbis 12.52), `nor_sflash0_ftp.bin`, `sflash0*`, `coreos_extracted/`, `libkernel*.sprx` | **Não** (gitignored, ~174 MB) |
| `scans/` | varreduras e relatórios de MMIO: `glue_140000_180000_raw.txt`/`_analise.txt`, `M8`–`M12` (janela Glue BAR2), coletas de hardware (`hardware_report.txt`, `chip_id`, `IP-default`, …) | Sim (~1 MB) |
| `tools/` | scripts de RE: `ghidra_scripts/`, `xts_bruteforce/`, manutenção do banco, `Dockerfile.ghidra-py` | Sim |
| `firmware_gladius_real/` | blobs de firmware **genuíno** da GPU (Gladius) extraídos do console via `distro/scripts/fetch_gladius_fw.py` — backup de referência | Sim (8 blobs, 124 KB) |
| `tools/ghidra_project/` | projeto Ghidra headless (reconstituído a partir de `dumps/`) | **Não** (gitignored) |

## Banco de varreduras — consultas úteis

```bash
DB=others/rea/ps4_hardware_memory.db

sqlite3 $DB ".tables"
sqlite3 $DB "SELECT addr_hex, role, status FROM decompiled_functions WHERE category LIKE 'MTS%' ORDER BY addr_hex;"
sqlite3 $DB "SELECT addr_hex, role FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"
sqlite3 $DB "SELECT id, timestamp, phase, test_name, status FROM test_history ORDER BY id DESC LIMIT 20;"
```

Antes de escrever em qualquer registrador, confira `hardware_registers`
(`safe_to_read/write`, `risk_level`) e `write_sweep_results` (o que já foi
tentado e o que aconteceu).

## Decompilação (Ghidra headless)

Ghidra 12.1.2 está em `/mnt/hdauxiliar/ghidra_12.1.2`. O projeto Ghidra não é
versionado — recrie-o a partir do dump antes de extrair:

```bash
REA=others/rea
# 1. criar o projeto com o dump do kernel Orbis
/mnt/hdauxiliar/ghidra_12.1.2/support/analyzeHeadless \
  $REA/tools/ghidra_project orbis_mts -import $REA/dumps/kmem_dump_1252.bin

# 2. extrair funções (adicionar o endereço em TARGET_ADDRS do script antes)
/mnt/hdauxiliar/ghidra_12.1.2/support/analyzeHeadless \
  $REA/tools/ghidra_project orbis_mts \
  -process kmem_dump_1252.bin \
  -postScript $REA/tools/ghidra_scripts/ExtractMtsNamespaceNoAnalysis.py \
  -scriptPath $REA/tools/ghidra_scripts \
  -readOnly
```

Scripts prontos em `tools/ghidra_scripts/`: `ExtractMtsNamespaceNoAnalysis`,
`ExtractGeomCryptPipeline`, `FindGeomCryptFuncs`, `TraceIvOffsetFormula`
(versões `.py` e `.java`).

Fluxo da pipeline de criptografia do HD interno (GEOM):
`others/scripts/run_ghidra_geom_crypt.sh` → `decompiled/geom_crypt/`.

## O que **não** mora aqui

| Onde | O quê |
|---|---|
| `kernel/drivers_mts/` | documentação do **driver** MTS (`README.md`, RE do driver, testes, plano) — a RE do GBE Baikal é tão específica do driver que fica com ele |
| `others/docs/` | documentação técnica geral (SATA, GPU, RTC, build, lições, backlog) |
| `others/tools/harness/` | harnesses de teste **ao vivo** via SSH/telnet (sondagem MMIO no console) — são ferramentas de operação, não acervo de RE estático |
| `others/tools/ps4_hdd_tools/` | utilitários de HD (PFS/EAP) que **usam** os resultados da RE |

## Regra de manutenção

1. Toda descoberta nova entra no banco (`test_history` / `hardware_registers` /
   `decompiled_functions`) **e** no documento vivo correspondente.
2. Nada de varredura cega: se o offset já está no `bar0_register_map`, leia o
   que já foi medido.
3. Dumps grandes ficam fora do git (`dumps/`, `tools/ghidra_project/`); o que é
   texto (decompilado, análises, scripts) é versionado.
