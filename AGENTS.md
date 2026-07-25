# Instruções para Agentes — PS4 Linux Baikal

## 🔴 PRIORIDADE ALTA — Banco de Varreduras de Hardware (SEMPRE consultar antes de varrer de novo)

**Antes de fazer qualquer varredura de registradores/MMIO ao vivo (BAR0/BAR2/BAR4, ICC, glue), consultar primeiro `consolidado/ps4_hardware_memory.db` (SQLite)** — é a fonte única de leituras já feitas em hardware real, para não repetir teste (cada teste ao vivo custa um power cycle inteiro).

```bash
sqlite3 consolidado/ps4_hardware_memory.db ".tables"
```

Tabelas principais:
- `readonly_verification` — leituras confirmadas de registradores (endereço, valor baseline/atual, se mudou, notas). Contém, por exemplo, a varredura completa da janela Glue BAR2 `0x140000`-`0x180000` (2026-07-25).
- `hardware_registers` — catálogo de registradores conhecidos (device, BAR, offset, nome, safe_to_read/write, risk_level).
- `bar_regions` — mapeamento de BARs por dispositivo PCI.
- `write_sweep_results` — resultados de testes de escrita (valor antes/depois, se ping/telnet sobreviveram).
- `decompiled_functions` — catálogo de funções decompiladas do kernel Orbis (`kmem_dump_1252.bin`) no escopo MTS/GBE/ICC/glue. Cada linha: addr_hex, short_name (ex `dc5a0070`), category, role, file_path do .txt, status (`revisado`/`bruto`/`pendente`/`refutado`), validated_by_test_id (FK → test_history.id). View `v_decompiled_summary` agrega contagens. Para verificar o que já foi decompilado antes de pedir RE nova:
  ```bash
  sqlite3 consolidado/ps4_hardware_memory.db "SELECT addr_hex, role, file_path, status, validated_by_test_id FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"
  ```
- `test_history` — histórico cronológico de testes ao vivo (inclui os testes de RMU/loopback da GBE de 2026-07-25).

Os dumps brutos/análise textual de varreduras grandes (ex: a janela Glue BAR2) também ficam em `consolidado/glue_140000_180000_raw.txt`/`_analise.txt`, mas o SQLite é sempre a referência estruturada e consultável.

## 🔴 PRIORIDADE ALTA — Topologia de Rede (NUNCA confundir)

- **WiFi (`wlan0`, subnet `192.168.6.0/24`) é SÓ PARA SSH/acesso administrativo ao console.** IP típico do PS4: `192.168.6.128`. Porta SSH: 22 (root/ps4). Porta telnet 23 está fechada (telnetd não iniciado).
- **Rede cabeada (`eth0`, driver `mts.ko`) é a rede sob teste — IP FIXO `192.168.0.2`.** Host do PC no Ethernet: `192.168.0.1` (interface `enp60s0`).
- **NUNCA testar o `eth0` usando a subnet do WiFi (`192.168.6.x`).** Um ping "funcionando" para `192.168.6.100`/`192.168.6.128` passa pelo `wlan0`, não prova nada sobre o `eth0`.
- **Todo teste de RX/TX do driver `mts.ko` deve usar a subnet `192.168.0.0/24`**: `ping -c N 192.168.0.2` do lado do host, ou `ping -I eth0 -c N 192.168.0.1` do lado do PS4.
- SSH (WiFi) e eth0 (cabeada) são canais independentes — pode-se usar ambos simultaneamente.

## Conexão via SSH

**Preferência do usuário:** Use SSH diretamente (sshpass) — o telnetd não está rodando no PS4.

```bash
sshpass -p ps4 ssh root@192.168.6.128 "<cmd>"
```

---

## Compilação de Módulos

Use `sudo scripts/build_mts_module.sh` (já validado) para compilar o driver `mts.ko`.

Não criar `Makefile` ad-hoc nem comandos `gcc` diretos — o script já encapsula opções de cross-compile e flags corretas.

---

## Deploy do mts.ko

Script: `./scripts/deploy_mts.sh [push|test]` (usa sshpass)

- **push**: Compila (se necessário), copia mts.ko via SCP, insmod stage=4
- **test**: Configura eth0 (192.168.0.2), ping -I eth0 192.168.0.1, captura dmesg + mts_regs

Uso:
```bash
./scripts/deploy_mts.sh push
./scripts/deploy_mts.sh test
```

Para passar module params:
```bash
sshpass -p ps4 scp drivers_mts/build/mts.ko root@192.168.6.128:/tmp/mts.ko
sshpass -p ps4 ssh root@192.168.6.128 "rmmod mts 2>/dev/null; insmod /tmp/mts.ko stage=4 hold_val=0x10 enable_phy_calib_table=0"
```

Requer: sshpass, scp no host. PS4 precisa ter SSH rodando.

## ⚠️ REGRAS CRÍTICAS DO DRIVER mts.ko

### MAC Enable/Stop (descobertas 2026-07-24/25)
- **NUNCA escrever 0 em BAR0+0x34/0x38** — corrompe estado permanentemente
- Para **STOP** (rmmod/ifconfig down): escrever **2** (bit 1 = soft-reset) em 0x34 e 0x38, poll bit 1 até zerar (ACK)
- Para **ENABLE** (insmod): escrever **1** (bit 0) DIRETO com `mts_write()`, NUNCA `mts_set()` (RMW escreve 0x09 que é rejeitado)
- **NUNCA re-escrever** MAC enable depois de ativado — é one-shot por power cycle
- Sequência stop correta (Orbis dc5a3060): IMR=0x7ffffa → 0x34=2 (poll bit1) → 0x38=2 (poll bit1) → drain TX/RX → 0x1c8 &= ~0x440

### 0x200 (descoberta 2026-07-24)
- Escrever 0 em BAR0+0x200 TRAVA o MAC enable permanentemente
- O Orbis escreve 0x200=0 na calibração (dc5a0ba0), mas ativa o MAC DEPOIS (dc5a31f0, ifconfig up)
- **NÃO tocar em 0x200** no driver Linux — a calibração e o enable já não escrevem lá

### PHY MDIO
- GBE hold/pulse usa bit 4 (hold_val=0x10), NÃO bit 0 como SATA
- Clock config (0x10A030) necessário: `(reg & 0xfffffe07) | 0xd8` — persiste entre reloads
- Clause 45 MDIO retorna 0x0000 (PHY power-gated) — Clause 22 sempre timeout
- PHY não acorda mesmo com hold=0x10 + clock config + soft-reset via MDIO + hold/pulse no offset correto (ver correção abaixo, testado ao vivo 2026-07-25)

### ICC GBE Power (descobertas 2026-07-24)
- ICC `bpcie_icc_cmd(4, 0x38, &on=1, 1, &reply, 1)` confirma GBE MAC power-on (reply=0x01)
- Requer LOOP de retry (até 100x, 50ms delay) — não funciona na primeira tentativa
- ICC acorda o MAC core (BAR0+0x004 muda de 0 para 0xb19), mas NÃO o PHY
- **PHY tem domínio de power SEPARADO** (`SceGbeMtsPhyCtrl`) — ICC 4 0x38 não liga o PHY
- **NUNCA varrer ICC minors com data=1** — causa crash/reboot do PS4
- `bpcie_icc_cmd` é built-in: `ffffffff821db120 T`

### Hold Registers são WRITE-ONLY (2026-07-24)
- Hold registers sempre leem 0 após escrita — padrão Baikal confirmado: write-only por design.
- ⚠️ **CORREÇÃO 2026-07-25 (a linha abaixo estava com os offsets trocados):** a label "GBE hold=0x180034" **estava errada** — veio de inferência por padrão (hold = pulse - 0x40) nunca cruzada com a descompilação real. A descompilação de `fcn.ffffffffdc6df850` (`consolidado/decompiled/baikal_glue_block_reset_dc6df.txt`) mostra `fcn.dc59fe10()` (rotina de STOP do MAC da GBE, já confirmada por RE) chamada **imediatamente antes** de `dc6dfb60(0x2000)` + `dc718710(0x20,1)` + `dc718710(0x74,1)` — ou seja, **GBE hold = `0x180020`, pulse = `0x180074`** (bloco `0x2000`, confirmado). `0x180034` pertence a um bloco DIFERENTE e não identificado (`0x3c00`), que sequer tem par hold/pulse (só uma chamada `dc718710`). SATA é `0x18002c`/`0x18006c` (nunca foi `0x180020`). `drivers_mts/mts.c` corrigido para usar `0x180020`; testado ao vivo 2026-07-25 sem incidente (console permaneceu estável), mas o PHY continuou mudo mesmo com o offset correto — toggling hold/pulse sozinho não é suficiente. Ver `test_history` no `ps4_hardware_memory.db`.

### BAR0+0x004 Link Status (2026-07-24)
- STABLE_ZERO antes do ICC power-on; muda para 0x00000b19 após ICC+clock+calibração
- Bits: 0 (link?), 3, 4 (speed?), 8, 9 (duplex?) — reflete estado do MAC, não do PHY
- Valor difere do 0x61 que forçamos na calibração — o registrador está vivo

## 🔴 PRIORIDADE ALTA — Funções Decompiladas do Kernel Orbis (panorama MTS/GBE/ICC/glue)

**Antes de pedir nova descompilação ao vivo ou tentar inferir comportamento de uma função do kernel Orbis**, consultar:
- `consolidado/decompiled/INDEX.md` — catálogo canônico (~50 funções indexadas por papel/status).
- `ps4_hardware_memory.db` → tabela `decompiled_functions` — mesmo catálogo, consultável: `addr_hex`, `category`, `role`, `status` (`revisado`/`bruto`/`pendente`/`refutado`), `validated_by_test_id` (FK → test_history.id), `file_path` do `.txt` decompilado.

Processo para nova RE:
```bash
# 1. Lista o que já existe no escopo MTS:
sqlite3 consolidado/ps4_hardware_memory.db "SELECT addr_hex, role, status FROM decompiled_functions WHERE category LIKE 'MTS%' ORDER BY addr_hex;"

# 2. Lista as lacunas pendentes (ainda não decompiladas):
sqlite3 consolidado/ps4_hardware_memory.db "SELECT addr_hex, role FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"

# 3. Antes de pedir RE de uma função, ver se já foi validada/refutada em testes ao vivo:
sqlite3 consolidado/ps4_hardware_memory.db "SELECT t.id, t.phase, t.status FROM decompiled_functions d JOIN test_history t ON d.validated_by_test_id = t.id WHERE d.addr_hex = 'dc5a44c0';"
```

Os dumps brutos/análise textual de varreduras grandes (ex: a janela Glue BAR2) também ficam em `consolidado/glue_140000_180000_raw.txt`/`_analise.txt`, mas o SQLite e o `INDEX.md` são sempre a referência estruturada e consultável.

Ghidra headless está instalado em `/mnt/hdauxiliar/ghidra_12.1.2` e os scripts de extração em `consolidado/tools/ghidra_scripts/`. Para extrair novas funções:
```bash
/mnt/hdauxiliar/ghidra_12.1.2/support/analyzeHeadless consolidado/tools/ghidra_project orbis_mts \
  -process kmem_dump_1252.bin \
  -postScript consolidado/tools/ghidra_scripts/ExtractMtsNamespaceNoAnalysis.py \
  -scriptPath consolidado/tools/ghidra_scripts \
  -readOnly
```
Adicionar novo endereço em `TARGET_ADDRS` do `ExtractMtsNamespaceNoAnalysis.py` antes de rodar. Saídas em `consolidado/decompiled/extracted/`.
