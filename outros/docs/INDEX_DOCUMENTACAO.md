# Índice da Documentação — PS4 Linux Baikal

> **Revisão:** 2026-11-13 (adicionados `BACKLOG_MOUNT.md`, `MONTAGEM_HD_INTERNO.md` e
> `ENVIO_DE_PAYLOADS.md`). Este índice
> lista apenas os arquivos que existem atualmente em `outros/docs/` e `kernel/drivers_mts/`.

> **Projeto:** PS4 Slim/Pro **Baikal** (CUH-2xxx) rodando Linux **7.0.8-Strawberry-ThinLTO-Baikal-+**
> carregado por `kexec` a partir de payload de jailbreak. Distribuição: Arch Linux mínima.

---

## 1. Comece por aqui (ordem de leitura)

| # | Arquivo | Para quê |
|---|---------|----------|
| 1 | [`../../README.md`](../../README.md) | Visão geral, status por subsistema, estrutura do repo |
| 2 | [`../../AGENTS.md`](../../AGENTS.md) | **Fonte única de regras e procedimentos** (build, deploy, SSH, UART, banco de RE). Auto-carregado via `../../CLAUDE.md` |
| 3 | [`LICOES_APRENDIDAS.md`](LICOES_APRENDIDAS.md) | Lições imperativas — o que já quebrou o console e por quê |
| 4 | [`BACKLOG.md`](BACKLOG.md) | **Único** lugar com pendências e próximos passos |
| 5 | [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) | Narrativa das grandes sagas técnicas (migração 7.0, GBE, SATA) e mapa de onde achar cada coisa |
| 6 | [`../../distro/RELEASE/README.md`](../../distro/RELEASE/README.md) | Artefatos prontos para deploy (`v1.0.0`) |

---

## 2. Estado, histórico e planejamento

| Arquivo | Conteúdo | Natureza |
|---------|----------|----------|
| [`BACKLOG.md`](BACKLOG.md) | Pendências priorizadas (`[ ]`/`[~]`/`[x]`) | **Vivo** |
| [`BACKLOG_MOUNT.md`](BACKLOG_MOUNT.md) | Pendências específicas da montagem de partições do HD interno (MOUNT-01 a MOUNT-09) | **Vivo** |
| [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) | Narrativa das grandes sagas técnicas (migração 7.0, GBE, SATA) e mapa de onde achar cada coisa | Histórico + mapa |
| [`LICOES_APRENDIDAS.md`](LICOES_APRENDIDAS.md) | Lições imperativas — o que já quebrou o console e por quê | **Vivo** |

Planejamento ativo e marcos validados ficam em [`../docs/MARCOS_CONSOLIDADOS.md`](../docs/MARCOS_CONSOLIDADOS.md). Procedimento de build/deploy em [`../docs/MIGRACAO_7.0.md`](../docs/MIGRACAO_7.0.md). Documentos do MTS foram centralizados em [`../../kernel/drivers_mts/`](../../kernel/drivers_mts/).

---

## 3. Hardware do Baikal

O acervo de coleta de hardware bruto (dmesg, lspci, pinouts, fotos) está em:
- [`../rea/`](../rea/) — banco SQLite `ps4_hardware_memory.db`, dumps do Orbis, saídas Ghidra
- [`pictures/`](pictures/) — fotos do console, UART, pinouts, placa NVG
- Capturas de dmesg do console estão em [`../../kernel/dmesg_ps4/`](../../kernel/dmesg_ps4/)

---

## 4. Subsistemas (documentos dedicados)

### Ethernet GBE (`mts.ko`)

> **Toda a documentação do MTS foi centralizada em [`../../kernel/drivers_mts/`](../../kernel/drivers_mts/)**
> (README + RE + testes). O índice completo está no
> [`README.md`](../../kernel/drivers_mts/README.md) do driver.

| Arquivo | Conteúdo |
|---------|----------|
| [`../../kernel/drivers_mts/README.md`](../../kernel/drivers_mts/README.md) | **Fonte única do driver**: mapa de registradores, params, build, histórico |
| [`../../kernel/drivers_mts/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](../../kernel/drivers_mts/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md) | Plano consolidado e conclusão do PHY |
| [`../../kernel/drivers_mts/TESTES_HISTORICO.md`](../../kernel/drivers_mts/TESTES_HISTORICO.md) | Testes ao vivo consolidados (o que vale e o que foi refutado) |
| [`../../kernel/drivers_mts/MTS_INIT_SEQUENCE_dc5a31f0.md`](../../kernel/drivers_mts/MTS_INIT_SEQUENCE_dc5a31f0.md) | Sequência de init do MAC (`dc5a31f0`) |
| [`../../kernel/drivers_mts/RE_KERNEL_GBE_ATTACH.md`](../../kernel/drivers_mts/RE_KERNEL_GBE_ATTACH.md) | RE do attach da GBE no kernel Orbis |
| [`../../kernel/drivers_mts/RE_IF_MSK.md`](../../kernel/drivers_mts/RE_IF_MSK.md) | RE do `if_msk` (Aeolia/Belize) × `if_mts` (Baikal) |
| [`../../kernel/drivers_mts/ICC_GBE_TEST_LOG.md`](../../kernel/drivers_mts/ICC_GBE_TEST_LOG.md) | Log dos testes de energia via ICC/MMIO |
| [`../../kernel/drivers_mts/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md`](../../kernel/drivers_mts/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md) | Marco: `eth0` registrada com MAC real e DMA funcionando |

**Resumo do estado:** MAC liga via ICC, DMA TX funciona, mas o PHY nunca sai de power-down —
investigação de RE **encerrada** em 2026-07-30 (bloqueador é firmware Sony, não driver).

### SATA interno

| Arquivo | Conteúdo |
|---------|----------|
| `../patches/ahci-baikal-polling-fallback.patch` | O patch em si (as duas pontas, `.2` e `.7`) |

### HD interno / PFS (montagem de partições)

| Arquivo | Conteúdo |
|---------|----------|
| [`MONTAGEM_HD_INTERNO.md`](MONTAGEM_HD_INTERNO.md) | Fluxo completo de montagem (chave EAP → cryptsetup → mapper → UFS2/FUSE), modos de tweak e diagnóstico |
| [`BACKLOG_MOUNT.md`](BACKLOG_MOUNT.md) | Pendências e status da feature (MOUNT-01 a MOUNT-09) |

### Payloads (injeção no Orbis)

| Arquivo | Conteúdo |
|---------|----------|
| [`ENVIO_DE_PAYLOADS.md`](ENVIO_DE_PAYLOADS.md) | **Procedimento canônico** de envio de payload (GoldHEN BinLoader `:9090`, FTP `:2121`, klog `:3232`), regras e diagnóstico. **Console no Orbis = `192.168.6.130`** (MAC `6A:FA:C4:EA:34:9C`); no Linux = `192.168.6.128` |
| [`../scripts/ps4_send_payload.sh`](../scripts/ps4_send_payload.sh) | Script oficial de envio/recuperação (`--check`, envio, `--ftp-get`) |
| [`../tools/ps4_hdd_tools/README.md`](../tools/ps4_hdd_tools/README.md) | Caso concreto: compilar o `EAPDumper` e obter a chave EAP |

### GPU / vídeo / Mesa

| Arquivo | Conteúdo |
|---------|----------|
| [`MESA_GLADIUS_LIVERPOOL_FIX.md`](MESA_GLADIUS_LIVERPOOL_FIX.md) | Patch do Mesa para reconhecer `CHIP_GLADIUS`/`CHIP_LIVERPOOL` |
| Marco: firmware Gladius real + amdgpu → movido para [`../../kernel/MARCO_HISTORICO_GPU_GLADIUS_REAL.md`](../../kernel/MARCO_HISTORICO_GPU_GLADIUS_REAL.md) |

### Kernel, build e boot

| Arquivo | Conteúdo |
|---------|----------|
| Guia de compilação manual → movido para [`../../kernel/ROTEIRO_KERNEL.md`](../../kernel/ROTEIRO_KERNEL.md) (⚠️ **HISTÓRICO**: kernel 5.4 + sky2 banido; o oficial é `../../00-build-kernel-7.0.sh`) |

### RE e banco de hardware

> **Todo o acervo de RE foi movido para [`../rea/`](../rea/)** em 2026-11-11
> (dumps do Orbis, saídas do Ghidra, scripts, varreduras e o banco SQLite).

| Recurso | Conteúdo |
|---------|----------|
| [`../rea/ps4_hardware_memory.db`](../rea/ps4_hardware_memory.db) | **SQLite oficial** — registradores, BARs, testes ao vivo, funções decompiladas |
| [`../rea/INDEX.md`](../rea/INDEX.md) | Índice geral do acervo (mapa de subsistemas e onde está cada coisa) |
| [`../rea/<subsistema>/decompiled/`](../rea/INDEX.md) | Funções decompiladas do kernel Orbis, por subsistema (`acpi/`, `dma/`, `mts/`, `sata/`, `spm/`, ...) |
| [`../rea/tools/`](../rea/tools/) | Scripts de extração Ghidra e utilitários de RE |

```bash
# Antes de qualquer varredura nova ao vivo (cada uma custa um power cycle):
sqlite3 outros/rea/ps4_hardware_memory.db ".tables"
sqlite3 outros/rea/ps4_hardware_memory.db \
  "SELECT addr_hex, role, status FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"
```

---

## 5. Planos e relatórios (`docs/`)

**`docs/`** — marcos consolidados e procedimento:

| Arquivo | Tema |
|---------|------|
| `MARCOS_CONSOLIDADOS.md` | Marcos de sucesso e bloqueadores validados ao vivo (kernel 7.0 apenas) |
| `MIGRACAO_7.0.md` | Procedimento de build/deploy do kernel 7.0 e distro |

---

## 6. Diretórios do `consolidado/`

| Diretório | Conteúdo | Versionado? |
|-----------|----------|-------------|
| (movido) | Blobs de firmware da GPU extraídos do console → `../rea/firmware_gladius_real/` | Sim (8 blobs, 124 KB) |
| `pictures/` | Fotos do console, UART, pinouts, placa NVG | Local |
| Capturas de dmesg → `../../kernel/dmesg_ps4/` | Capturas de dmesg do PS4 | Local |
| `__pycache__/`, `rootfs.img` | Artefatos de execução | Ignorados |

---

## 7. Cheat sheet

```bash
# --- Acesso ao console (o IP muda conforme o ambiente!) ---
ping -c1 192.168.6.130                     # Orbis + GoldHEN (loader existe aqui)
ping -c1 192.168.6.128                     # Linux rodando (SSH root/ps4)
sshpass -p ps4 ssh root@192.168.6.128      # WiFi (administração, só com Linux rodando)
ping 192.168.0.2                           # eth0 do PS4 (rede sob teste, host 192.168.0.1)

# --- Payload no Orbis (antes do kexec; GoldHEN ativo em 192.168.6.130) ---
./outros/scripts/ps4_send_payload.sh --check <payload.bin>
./outros/scripts/ps4_send_payload.sh <payload.bin>          # BinLoader :9090
./outros/scripts/ps4_send_payload.sh --ftp-get /data/...    # FTP :2121

# --- Build / deploy (SEMPRE pelos scripts oficiais) ---
cd kernel && sudo ./00-build-kernel-7.0.sh <TAG>   # FRENTE 1: kernel (ThinLTO, Baikal)
cd ../distro                                       # FRENTE 2: distro
sudo ./01-build-image-7.0.sh <TAG>                 # rootfs Arch + initramfs
sudo ./02-burn-image-7.0.sh /dev/sdX "" <TAG>      # particiona + grava (label psxitarch!)
sudo ./deploy-boot-7.0.sh <TAG>                    # só o boot, mantém rootfs
./scripts/promote-release.sh <TAG>                 # promove tag testada para RELEASE/

# --- Driver mts.ko ---
sudo ../outros/scripts/build_mts_module.sh
../outros/scripts/deploy_mts.sh push && ../outros/scripts/deploy_mts.sh test

# --- UART TTL ---
../outros/scripts/uart_start.sh 900 <nome> && tail -f tests/uart_logs/<nome>_*.log
../outros/scripts/uart_stop.sh

# --- Console (dentro do PS4) ---
cat /proc/cmdline
cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,modes}
dmesg | grep -Ei 'ata1|ahci|mts|rtc'
```

---

## 8. Manutenção deste índice

- Arquivo novo em `consolidado/` → adicionar na seção correspondente **na mesma alteração**.
- Arquivo superado → consolidar o que importa no documento vivo correspondente e remover o arquivo
  (a pasta `consolidado/obsoleto/` foi apagada em 2026-11-11 por decisão do usuário).
- Pendência → só no `BACKLOG.md`. Regra → só no `AGENTS.md`. Narrativa → `ESTADO_E_HISTORICO.md`.
- Depois de mexer em qualquer `.md`, conferir os links relativos (todo destino de link deve
  resolver a partir da pasta do próprio arquivo) e a existência de cada arquivo citado. Usar
  caminho relativo, nunca `file://` nem caminho absoluto de máquina.