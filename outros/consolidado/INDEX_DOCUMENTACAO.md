# Índice da Documentação — PS4 Linux Baikal

> **Revisão:** 2026-11-11 (reescrito após limpeza). Este índice lista apenas os arquivos que
> existem atualmente em `outros/consolidado/` e `kernel/drivers_mts/`.

> **Projeto:** PS4 Slim/Pro **Baikal** (CUH-2xxx) rodando Linux **7.0.8-Strawberry-ThinLTO-Baikal-+**
> carregado por `kexec` a partir de payload de jailbreak. Distribuição: Arch Linux mínima.

---

## 1. Comece por aqui (ordem de leitura)

| # | Arquivo | Para quê |
|---|---------|----------|
| 1 | [`../../README.md`](../../README.md) | Visão geral, status por subsistema, estrutura do repo |
| 2 | [`../../AGENTS.md`](../../../AGENTS.md) | **Fonte única de regras e procedimentos** (build, deploy, SSH, UART, banco de RE). Auto-carregado via `../../CLAUDE.md` |
| 3 | [`LICOES_APRENDIDAS.md`](LICOES_APRENDIDAS.md) | Lições imperativas — o que já quebrou o console e por quê |
| 4 | [`BACKLOG.md`](BACKLOG.md) | **Único** lugar com pendências e próximos passos |
| 5 | [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) | Narrativa das grandes sagas técnicas (migração 7.0, GBE, SATA) e mapa de onde achar cada coisa |
| 6 | [`../../distro/RELEASE/README.md`](../../../distro/RELEASE/README.md) | Artefatos prontos para deploy (`v1.0.0`) |

---

## 2. Estado, histórico e planejamento

| Arquivo | Conteúdo | Natureza |
|---------|----------|----------|
| [`BACKLOG.md`](BACKLOG.md) | Pendências priorizadas (`[ ]`/`[~]`/`[x]`) | **Vivo** |
| [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) | Narrativa das grandes sagas técnicas (migração 7.0, GBE, SATA) e mapa de onde achar cada coisa | Histórico + mapa |
| [`LICOES_APRENDIDAS.md`](LICOES_APRENDIDAS.md) | Lições imperativas — o que já quebrou o console e por quê | **Vivo** |

Planejamento ativo fica em [`../docs/planos/`](../docs/planos/). Documentos do MTS foram
centralizados em [`../../drivers_mts/`](../../drivers_mts/).

---

## 3. Hardware do Baikal

O acervo de coleta de hardware bruto (dmesg, lspci, pinouts, fotos) está em:
- [`../rea/`](../rea/) — banco SQLite `ps4_hardware_memory.db`, dumps do Orbis, saídas Ghidra
- [`dmesg_ps4/`](dmesg_ps4/) — `PS4_DMESG_ate_20260721.tar.gz`
- [`pictures/`](pictures/) — fotos do console, UART, pinouts, placa NVG

---

## 4. Subsistemas (documentos dedicados)

### Ethernet GBE (`mts.ko`)

> **Toda a documentação do MTS foi centralizada em [`../../drivers_mts/`](../../drivers_mts/)**
> (README + RE + testes). O índice completo está no
> [`README.md`](../../drivers_mts/README.md) do driver.

| Arquivo | Conteúdo |
|---------|----------|
| [`../../drivers_mts/README.md`](../../drivers_mts/README.md) | **Fonte única do driver**: mapa de registradores, params, build, histórico |
| [`../../drivers_mts/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](../../drivers_mts/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md) | Plano consolidado e conclusão do PHY |
| [`../../drivers_mts/TESTES_HISTORICO.md`](../../drivers_mts/TESTES_HISTORICO.md) | Testes ao vivo consolidados (o que vale e o que foi refutado) |
| [`../../drivers_mts/MTS_INIT_SEQUENCE_dc5a31f0.md`](../../drivers_mts/MTS_INIT_SEQUENCE_dc5a31f0.md) | Sequência de init do MAC (`dc5a31f0`) |
| [`../../drivers_mts/RE_KERNEL_GBE_ATTACH.md`](../../drivers_mts/RE_KERNEL_GBE_ATTACH.md) | RE do attach da GBE no kernel Orbis |
| [`../../drivers_mts/RE_IF_MSK.md`](../../drivers_mts/RE_IF_MSK.md) | RE do `if_msk` (Aeolia/Belize) × `if_mts` (Baikal) |
| [`../../drivers_mts/ICC_GBE_TEST_LOG.md`](../../drivers_mts/ICC_GBE_TEST_LOG.md) | Log dos testes de energia via ICC/MMIO |
| [`../../drivers_mts/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md`](../../drivers_mts/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md) | Marco: `eth0` registrada com MAC real e DMA funcionando |

**Resumo do estado:** MAC liga via ICC, DMA TX funciona, mas o PHY nunca sai de power-down —
investigação de RE **encerrada** em 2026-07-30 (bloqueador é firmware Sony, não driver).

### SATA interno

| Arquivo | Conteúdo |
|---------|----------|
| [`../docs/planos/DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md`](../docs/planos/DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md) | Descoberta do mascaramento MSI (`Masking=000000fe`) |
| `../patches/ahci-baikal-polling-fallback.patch` | O patch em si (as duas pontas, `.2` e `.7`) |

### GPU / vídeo / Mesa

| Arquivo | Conteúdo |
|---------|----------|
| [`MARCO_HISTORICO_GPU_GLADIUS_REAL.md`](MARCO_HISTORICO_GPU_GLADIUS_REAL.md) | Marco: firmware Gladius real + amdgpu |
| [`MESA_GLADIUS_LIVERPOOL_FIX.md`](MESA_GLADIUS_LIVERPOOL_FIX.md) | Patch do Mesa para reconhecer `CHIP_GLADIUS`/`CHIP_LIVERPOOL` |

### Kernel, build e boot

| Arquivo | Conteúdo |
|---------|----------|
| [`ROTEIRO_KERNEL.md`](ROTEIRO_KERNEL.md) | Guia de compilação manual (⚠️ **HISTÓRICO**: kernel 5.4 + sky2 banido; o oficial é `../../00-build-kernel-7.0.sh`) |

### RE e banco de hardware

> **Todo o acervo de RE foi movido para [`../rea/`](../rea/)** em 2026-11-11
> (dumps do Orbis, saídas do Ghidra, scripts, varreduras e o banco SQLite).

| Recurso | Conteúdo |
|---------|----------|
| [`../rea/ps4_hardware_memory.db`](../rea/ps4_hardware_memory.db) | **SQLite oficial** — registradores, BARs, testes ao vivo, funções decompiladas |
| [`../rea/decompiled/INDEX.md`](../rea/decompiled/INDEX.md) | Catálogo das funções do kernel Orbis decompiladas |
| [`../rea/decompiled/`](../rea/decompiled/) | Saídas textuais do Ghidra (`*.txt`) |
| [`../rea/tools/`](../rea/tools/) | Scripts de extração Ghidra e utilitários de RE |

```bash
# Antes de qualquer varredura nova ao vivo (cada uma custa um power cycle):
sqlite3 outros/rea/ps4_hardware_memory.db ".tables"
sqlite3 outros/rea/ps4_hardware_memory.db \
  "SELECT addr_hex, role, status FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"
```

---

## 5. Planos e relatórios (`docs/`)

**`docs/planos/`** — frentes de investigação/implementação:

| Arquivo | Tema |
|---------|------|
| `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md` | Decriptação do HD interno (chave EAP, tweak XTS) |
| `PLANO_MONTAGEM_NATIVA_HD_INTERNO_SDA.md` | Montagem nativa das partições PFS do HD interno |
| `PLANO_MONTAGEM_NATIVA_NEMO_NAUTILUS_FUSE.md` | Driver FUSE `ps4_pfs_fuse` |
| `PLANO_RTC_FINALIZACAO_2026-08-01.md` | RTC via ICC (Fase 4) |
| `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md` | Viabilidade do KVM-AMD |
| `PLANO_KEXEC_WARM_REBOOT_2026-07-27.md` | `kexec` a partir do Linux nativo |
| `DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md` | Descoberta (não plano): mascaramento MSI do AHCI |

---

## 6. Diretórios do `consolidado/`

| Diretório | Conteúdo | Versionado? |
|-----------|----------|-------------|
| (movido) | Blobs de firmware da GPU extraídos do console → `../rea/firmware_gladius_real/` | Sim (8 blobs, 124 KB) |
| `dmesg_ps4/`, `pictures/` | Capturas de dmesg, fotos do console, pinouts | Local |
| `__pycache__/`, `rootfs.img` | Artefatos de execução | Ignorados |

---

## 7. Cheat sheet

```bash
# --- Acesso ao console ---
sshpass -p ps4 ssh root@192.168.6.128      # WiFi (administração)
ping 192.168.0.2                           # eth0 do PS4 (rede sob teste, host 192.168.0.1)

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