# Índice da Documentação — PS4 Linux Baikal

> **Revisão:** 2026-11-11 (reescrito). A versão anterior deste índice descrevia a era do kernel
> 5.4.247 (feeRnt/neocine) e uma árvore de `consolidado/` com subpastas (`HARDWARE/`,
> `VIDEO_EDID_MONITOR/`, `KERNEL_BUILD/`…) que **nunca existiram no layout atual** e listava
> documentos já removidos. Se algo aqui divergir do disco, o disco está certo — corrija este
> arquivo em vez de confiar na memória.

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
| 5 | [`STATUS_ATUAL.md`](STATUS_ATUAL.md) | Retrato do estado corrente (o que funciona / o que não funciona) |
| 6 | [`../../distro/RELEASE/README.md`](../../distro/RELEASE/README.md) | Artefatos prontos para deploy (`v1.0.0`) |

---

## 2. Estado, histórico e planejamento

| Arquivo | Conteúdo | Natureza |
|---------|----------|----------|
| [`STATUS_ATUAL.md`](STATUS_ATUAL.md) | Subsistemas funcionando, configs críticas, problemas conhecidos | **Vivo** |
| [`BACKLOG.md`](BACKLOG.md) | Pendências priorizadas (`[ ]`/`[~]`/`[x]`) | **Vivo** |
| [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) | Narrativa das grandes sagas técnicas (migração 7.0, GBE, SATA) e mapa de onde achar cada coisa | Histórico + mapa |
| [`MASTER_CONSOLIDADO.md`](MASTER_CONSOLIDADO.md) | Documento mestre (boot, hardware, kernel, build, troubleshooting). Migração 5.4 → 7.0 já concluída; trechos do 5.4 são registro histórico | Histórico/referência |
| [`CONSOLIDACAO_RESUMO.md`](CONSOLIDACAO_RESUMO.md) | Resumo do processo de consolidação da documentação (2026-07) | Histórico |
| [`RESUMO_TECNICO.md`](RESUMO_TECNICO.md) | Resumo técnico condensado | Histórico |
| [`TESTES_LOG.md`](TESTES_LOG.md) | Log cronológico de testes (o estado estruturado vive no SQLite, ver §5) | Histórico |
| [`BUILD_CHECKLIST_20260801_KVM_RTC_SATA.md`](BUILD_CHECKLIST_20260801_KVM_RTC_SATA.md) | Checklist do build da tag `20260801-kvm-rtc-sata-fix` (base do `RELEASE/v1.0.0`) | Registro de build |

Planejamento ativo fica em [`../docs/planos/`](../docs/planos/) e relatórios de teste em
[`../docs/relatorios/`](../docs/relatorios/).

---

## 3. Hardware do Baikal

| Arquivo | Conteúdo |
|---------|----------|
| [`HARDWARE.md`](HARDWARE.md) | Visão geral do PS4 (CPU Jaguar, GPU Gladius, RAM, southbridge) |
| [`PS4_HARDWARE_DOCS.md`](PS4_HARDWARE_DOCS.md) | Documentação técnica profunda do hardware |
| [`HARDWARE_PS4_BAIKAL.md`](HARDWARE_PS4_BAIKAL.md) | Baikal B1: pinout, UART, endereços |
| [`BAIKAL_HARDWARE_DISCOVERIES.md`](BAIKAL_HARDWARE_DISCOVERIES.md) | Descobertas experimentais (contém itens superados — checar datas) |
| `chip_id`, `hardware_report.txt`, `hardware_search_results.txt`, `kernel_hardware_info.txt`, `ps4_system_files.txt`, `IP-default` | Saídas brutas de coleta no console |

---

## 4. Subsistemas (documentos dedicados)

### Ethernet GBE (`mts.ko`)

| Arquivo | Conteúdo |
|---------|----------|
| [`../docs/planos/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](../docs/planos/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md) | Plano consolidado (fonte dos próximos passos da frente GBE) |
| [`MARCO_HISTORICO_ETH0_MTS_BAIKAL.md`](MARCO_HISTORICO_ETH0_MTS_BAIKAL.md) | Marco: `eth0` registrada com MAC real e DMA funcionando |
| [`RE_KERNEL_GBE_ATTACH.md`](RE_KERNEL_GBE_ATTACH.md) | RE do attach da GBE no kernel Orbis |
| [`RE_IF_MSK.md`](RE_IF_MSK.md) | RE do mascaramento de interrupções (`IF_MSK`) |
| [`MTS_INIT_SEQUENCE_dc5a31f0.md`](MTS_INIT_SEQUENCE_dc5a31f0.md) | Sequência de init do MAC (`dc5a31f0`) |
| [`ICC_GBE_TEST_LOG.md`](ICC_GBE_TEST_LOG.md) | Log dos testes de energia via ICC |
| [`../docs/relatorios/PHY_DEBUG_SESSION_20260724.md`](../docs/relatorios/PHY_DEBUG_SESSION_20260724.md) | Sessão de debug do PHY (2026-07-24) |
| [`../docs/relatorios/TESTE_*`](../docs/relatorios/) | Resultados de testes pontuais (Clause 22, RX OWN, tail pointer, subnet) |

**Resumo do estado:** MAC liga via ICC, DMA TX funciona, mas o PHY nunca sai de power-down —
investigação de RE **encerrada** em 2026-07-30 (bloqueador é firmware Sony, não driver).

### SATA interno

| Arquivo | Conteúdo |
|---------|----------|
| [`INTERNAL_SATA_FIX.md`](INTERNAL_SATA_FIX.md) | Fix do SATA interno (polling timer) |
| [`../docs/planos/DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md`](../docs/planos/DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md) | Descoberta do mascaramento MSI (`Masking=000000fe`) |
| [`../memory/marco-sata-interno-funcional-2026-07-30.md`](../memory/marco-sata-interno-funcional-2026-07-30.md) | Marco: `ata1` funcional pela 1ª vez (tag `20260730-sata-polling-fase-ab`) |
| [`../memory/sata-polling-device-errado-14-2-vs-14-7-2026-08-01.md`](../memory/sata-polling-device-errado-14-2-vs-14-7-2026-08-01.md) | `ata1` pertence à function `.7` (`xhci_aeolia`), não à `.2` |
| `../patches/ahci-baikal-polling-fallback.patch` | O patch em si (as duas pontas, `.2` e `.7`) |
| [`obsoleto/PLANO_SATA_INTERNO_100PCT_2026-07-28.md`](obsoleto/PLANO_SATA_INTERNO_100PCT_2026-07-28.md) | Plano histórico da investigação (superado pela solução) |

### GPU / vídeo / Mesa

| Arquivo | Conteúdo |
|---------|----------|
| [`MARCO_HISTORICO_GPU_GLADIUS_REAL.md`](MARCO_HISTORICO_GPU_GLADIUS_REAL.md) | Marco: firmware Gladius real + amdgpu |
| [`MESA_GLADIUS_LIVERPOOL_FIX.md`](MESA_GLADIUS_LIVERPOOL_FIX.md) | Patch do Mesa para reconhecer `CHIP_GLADIUS`/`CHIP_LIVERPOOL` |
| [`INTEGRACAO_IMAGEM_7.0_GLADIUS_E_WIFI.md`](INTEGRACAO_IMAGEM_7.0_GLADIUS_E_WIFI.md) | Como firmware/Mesa/WiFi entram no `01-build-image-7.0.sh` |
| [`MESA_VULKAN.md`](MESA_VULKAN.md) | Estado de Mesa/Vulkan (RADV) |
| [`MONITOR_INFO.md`](MONITOR_INFO.md) | EDID/limitações do monitor LG e modos que funcionam |
| [`BOOTARGS.md`](BOOTARGS.md) | Parâmetros de vídeo/console validados (⚠️ `console=ttyS0` **não** funciona) |
| [`../../distro/monitor_edid/`](../../distro/monitor_edid/) | EDID e utilitários do monitor |

### Kernel, build e boot

| Arquivo | Conteúdo |
|---------|----------|
| [`KERNELS.md`](KERNELS.md) | Comparação de kernels (5.4 neocine vs 7.0 Strawberry) |
| [`../docs/MIGRACAO_7.0.md`](../docs/MIGRACAO_7.0.md) | Histórico da migração 5.4 → 7.0 |
| [`FULL_BUILD.md`](FULL_BUILD.md) | Procedimento de build completo do Arch Minimal v2 |
| [`ROTEIRO_KERNEL.md`](ROTEIRO_KERNEL.md) | Guia de compilação manual (⚠️ caminhos citados são da era 5.4 — o oficial é `../distros/arch_minimal_v2/00-build-kernel-7.0.sh`) |
| [`SCRIPTS.md`](SCRIPTS.md) | Descrição dos scripts de build |
| [`INSTALACAO.md`](INSTALACAO.md) | Instalação da distro no HD |
| [`POS_INSTALACAO.md`](POS_INSTALACAO.md) · [`README_pos_install.md`](README_pos_install.md) | Pós-instalação (locale, timezone, swap, SSH) |
| [`DISTROS.md`](DISTROS.md) · [`ARCH_ORIGINAL_README.md`](ARCH_ORIGINAL_README.md) | Distros usadas / README original do Arch (histórico) |

### RE e banco de hardware

| Recurso | Conteúdo |
|---------|----------|
| [`ps4_hardware_memory.db`](ps4_hardware_memory.db) | **SQLite oficial** — registradores, BARs, testes ao vivo, funções decompiladas |
| [`decompiled/INDEX.md`](decompiled/INDEX.md) | Catálogo das funções do kernel Orbis decompiladas |
| [`decompiled/`](decompiled/) | Saídas textuais do Ghidra (`*.txt`) |
| [`tools/`](tools/) | Scripts de extração Ghidra e utilitários de RE |
| [`update_dangerous_registers.py`](update_dangerous_registers.py) · [`init_database.py`](init_database.py) | Manutenção do banco |

```bash
# Antes de qualquer varredura nova ao vivo (cada uma custa um power cycle):
sqlite3 consolidado/ps4_hardware_memory.db ".tables"
sqlite3 consolidado/ps4_hardware_memory.db \
  "SELECT addr_hex, role, status FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"
```

---

## 5. Planos e relatórios (`docs/`)

**`docs/planos/`** — frentes de investigação/implementação:

| Arquivo | Tema |
|---------|------|
| `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` | GBE/`eth0` (plano ativo consolidado) |
| `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md` | Decriptação do HD interno (chave EAP, tweak XTS) |
| `PLANO_MONTAGEM_NATIVA_HD_INTERNO_SDA.md` | Montagem nativa das partições PFS do HD interno |
| `PLANO_MONTAGEM_NATIVA_NEMO_NAUTILUS_FUSE.md` | Driver FUSE `ps4_pfs_fuse` |
| `PLANO_RTC_FINALIZACAO_2026-08-01.md` | RTC via ICC (Fase 4) |
| `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md` | Viabilidade do KVM-AMD |
| `PLANO_KEXEC_WARM_REBOOT_2026-07-27.md` | `kexec` a partir do Linux nativo |
| `DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md` | Descoberta (não plano): mascaramento MSI do AHCI |

**`docs/relatorios/`** — resultados de testes ao vivo (PHY, Clause 22, RX OWN, tail pointer,
subnet `eth0`). São registros datados; o estado consolidado fica no SQLite e no `BACKLOG.md`.

---

## 6. Diretórios do `consolidado/`

| Diretório | Conteúdo | Versionado? |
|-----------|----------|-------------|
| `decompiled/` | Saídas do Ghidra + `INDEX.md` | Sim (texto) |
| `tools/` | Scripts Ghidra (`ghidra_scripts/`), brute-force XTS | Sim |
| `obsoleto/` | Documentos superados (planos refutados, README do Arch Base v2, `CABO_UART.md`, `BAIKAL_STATUS.md`, entre outros). Mantidos só como histórico | Sim |
| `dumps_orbis/` | `kmem_dump_1252.bin` e afins | **Não** (gitignored, ~32 MB) |
| `firmware_gladius_real/` | Blobs de firmware da GPU | **Não** (gitignored) |
| `dmesg_ps4/`, `pictures/`, `payload_output/` | Capturas de dmesg, fotos do console, saídas de payload | Local |
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
sudo ./01-build-image-7.0.sh               # rootfs Arch + initramfs
sudo ./02-burn-image-7.0.sh /dev/sdX       # particiona + grava (label psxitarch!)
sudo ./deploy-boot-7.0.sh <TAG>            # só o boot, mantém rootfs
./scripts/promote-release.sh <TAG>         # promove tag testada para RELEASE/

# --- Driver mts.ko ---
sudo scripts/build_mts_module.sh
scripts/deploy_mts.sh push && scripts/deploy_mts.sh test

# --- UART TTL ---
scripts/uart_start.sh 900 <nome> && tail -f tests/uart_logs/<nome>_*.log
scripts/uart_stop.sh

# --- Console (dentro do PS4) ---
cat /proc/cmdline
cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,modes}
dmesg | grep -Ei 'ata1|ahci|mts|rtc'
```

---

## 8. Manutenção deste índice

- Arquivo novo em `consolidado/` → adicionar na seção correspondente **na mesma alteração**.
- Arquivo superado → mover para `consolidado/obsoleto/` e ajustar aqui (não apagar histórico).
- Pendência → só no `BACKLOG.md`. Regra → só no `AGENTS.md`. Narrativa → `ESTADO_E_HISTORICO.md`.
- Depois de mexer em qualquer `.md`, conferir os links relativos (todo destino de link deve
  resolver a partir da pasta do próprio arquivo) e a existência de cada arquivo citado. Usar
  caminho relativo, nunca `file://` nem caminho absoluto de máquina.
