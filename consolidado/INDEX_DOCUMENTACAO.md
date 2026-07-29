# Índice Completo da Documentação — PS4 Linux (Baikal/Arch Minimal v2)

> **Última atualização**: 2026-07-20  
> **Versão**: Arch Minimal v2 — Kernel 5.4.247-neocine-1.1  
> **Status**: ✅ Consolidado e organizado (RELATORIO_COLETA_DUMPS.md incorporado ao MASTER Seção 3)

---

## 📋 SUMÁRIO EXECUTIVO

| Documento | Propósito | Público-Alvo |
|-----------|-----------|--------------|
| **MASTER_CONSOLIDADO.md** | Documento mestre completo (boot, hardware, kernel, build system) | Todos |
| **README.md** | Quick start e primeiros passos | Iniciantes |
| **INSTRUCOES.md** | Instruções detalhadas em português | Usuários |

---

## 🚀 INÍCIO RÁPIDO (Primeira vez?)

1. Leia: **README.md** (5 min)
2. Leia: **INSTRUCOES.md** (20 min)
3. Consulte: **MASTER_CONSOLIDADO.md** seção 1-4 (boot, hardware, kernel args)
4. Execute: Scripts em `distros/arch_minimal_v2/` (build-kernel, build-image, burn-image)

---

## 📚 DOCUMENTAÇÃO POR CATEGORIA

### 1. **VISÃO GERAL & ARQUITETURA**

| Arquivo | Conteúdo | Tamanho | Atualização |
|---------|----------|--------|------------|
| **MASTER_CONSOLIDADO.md** | Tudo em um: boot, hardware, kernel, scripts, troubleshooting | 457 linhas | 14/07/2026 |
| **DOCUMENTACAO_COMPLETA.md** | Visão geral do projeto (estrutura histórica) | 159 linhas | - |
| **STATUS_ATUAL.md** | Status atual do projeto | 147 linhas | - |
| **RESUMO_TECNICO.md** | Resumo técnico condensado | 101 linhas | - |

**📌 Recomendação**: Use **MASTER_CONSOLIDADO.md** como principal; DOCUMENTACAO_COMPLETA é histórico apenas.

---

### 2. **HARDWARE & SOUTHBRIDGE BAIKAL**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **HARDWARE.md** | Especificações do PS4 (CPU, GPU, RAM, southbridge) | Referência geral |
| **PS4_HARDWARE_DOCS.md** | Documentação técnica profunda do hardware | Debug de hardware |
| **HARDWARE_PS4_BAIKAL.md** | Foco em Baikal B1 (pinout, UART, adressen) | Soldagem, pinout |
| **BAIKAL_STATUS.md** | Status de drivers/subsistemas Baikal | Compatibilidade |
| **BAIKAL_HARDWARE_DISCOVERIES.md** | Descobertas experimentais do Baikal | Research/debugging |

**📌 Recomendação**: Leia HARDWARE.md primeiro; depois PS4_HARDWARE_DOCS.md se precisar de detalhe.

---

### 3. **VIDEO, EDID & MONITOR**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **MONITOR_INFO.md** | Análise completa do monitor LG + compatibilidade EDID | Compatibilidade monitor |
| **MONITOR_TENTATIVAS_LOG.md** | Log de testes com monitor | Debug vídeo |
| **BOOTARGS.md** | Kernel command line (video, console, EDID) | Ajustes de boot |

**🎯 Fluxo de Debug de Vídeo**:
1. Consulte: **BOOTARGS.md** (parâmetros video)
2. Se TV/monitor não funciona: **MONITOR_INFO.md**
3. Se ainda falha: **MONITOR_TENTATIVAS_LOG.md** (reproduza testes)

---

### 4. **KERNEL & COMPILAÇÃO**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **KERNELS.md** | Comparação de kernels (5.4 vs 7.0, feeRnt vs DFAUS) | Seleção de kernel |
| **ROTEIRO_KERNEL.md** | Guia passo-a-passo de compilação manual | Compilar kernel custom |
| **MIGRACAO_7.0.md** | Histórico e status da migração para kernel 7.0 | Entender histórico |

**📌 Recomendação**: Use o **00-build-kernel.sh** (automático); ROTEIRO_KERNEL.md só se customizar.

---

### 5. **BOOT & INICIALIZAÇÃO**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **PAYLOADS.md** | Payload kexec v24+, firmware-agnóstico | Entender boot |
| **INSTALACAO.md** | Instalação de distro no HDD | Preparar disco |
| **COMUNICACAO_PS4.md** | Comunicação PS4 ↔ PC (SSH, netconsole) | Debug remoto |

**🔌 Fluxo de Boot**:
1. Payload kexec → detecção de southbridge (Baikal/Aeolia/Belize)
2. Lê `bootargs.txt`, `vram.txt` de FAT32 (sda1)
3. Injeta `time=` (RTC), monta inicializa kernel
4. Initramfs executa hooks: set-time, EDID firmware
5. Mount rootfs ext4 (sda2), start systemd

---

### 6. **PÓS-INSTALAÇÃO & CONFIGURAÇÃO**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **POS_INSTALACAO.md** | Configuração pós-boot (timezone, locale, swap, SSH) | Setup inicial |
| **README_pos_install.md** | Documentação complementar de pós-instalação | Referência |
| **SCRIPTS.md** | Descrição dos scripts de build | Entender automatização |

**✅ Checklist pós-instalação**:
- [ ] Timezone: `timedatectl set-timezone America/Sao_Paulo`
- [ ] Locale: `echo "pt_BR.UTF-8 UTF-8" > /etc/locale.gen && locale-gen`
- [ ] Swap: `fallocate -l 8G /swapfile && mkswap /swapfile && swapon /swapfile`
- [ ] IgnorePkg: `IgnorePkg = systemd linux mesa` em `/etc/pacman.conf`

---

### 7. **COMUNICAÇÃO & DEBUG**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **CABO_UART.md** | Pinout UART Baikal (J1/J2), adaptador USB-serial — **FUNCIONAL** (2026-07-27: solda validada, stream 0x20 @ 115200 8N1) | Debug headless |
| **COMUNICACAO_PS4.md** | SSH, netconsole, remote boot | Debug remoto |
| **TODO_NETCONSOLE.md** | Implementação de netconsole | Logs kernel UDP |
| **TESTES_LOG.md** | Log de testes e resultados | Referência histórica |

**🔧 Debug Remoto (SSH)**:
```bash
ssh root@192.168.6.128    # senha: ps4
ssh ps4@192.168.6.128     # senha: ps4
```

**📡 Debug Headless (UART)**:
```bash
# PC host
screen /dev/ttyUSB0 115200
```

---

### 8. **FIRMWARE & EXTRAÇÃO**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **DUMP_FIRMWARE_ORBIS.md** | Dump de firmware, extração de blobs (EDID, WiFi) | Reverse engineering |

---

### 9. **EXPERIÊNCIAS & LIÇÕES**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **LICOES_APRENDIDAS.md** | Erros cometidos e soluções (18 lições) | Evitar armadilhas |
| **MILESTONE_2026-07-14.md** | Milestone recente com descobertas | Histórico recente |

**⚠️ Lições Críticas**:
- **#18**: UART + vídeo HDMI **não coexistem** no Baikal. Use netconsole ou UART isolado.
- **#1**: Não use `video=@60e` (sufixo `e`) — tela preta em TVs. Use `@60` (sem `e`).
- **systemd**: Fixar em 258.1-1 — versões > 261 quebram boot cgroup.
- **NTFS**: Nunca extrair tarball em NTFS (corrompe permissões Linux). Use ext4.

---

### 10. **REFERÊNCIAS & LINKS**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **REFERENCIAS.md** | Links para GitHub, documentação, ferramentas | Recursos externos |

**🔗 Links Principais**:
- Kernel Neocine: https://github.com/feeRnt/ps4-linux-12xx (v5.4.247__neocine-1.1)
- Payload: https://github.com/ArabPixel/ps4-linux-payloads
- Guia: https://dionkill.github.io/ps4-linux-tutorial/
- Strawberry 7.0: https://github.com/rmuxnet/linux

---

### 11. **DISTROS & VARIANTES**

| Arquivo | Conteúdo | Casos de Uso |
|---------|----------|-------------|
| **DISTROS.md** | Lista de distros disponíveis | Escolher distro |
| **MESA_VULKAN.md** | Mesa/Vulkan para PS4 (RADV, DRM) | Gráficos 3D |
| **ARCH_ORIGINAL_README.md** | Arch original (deprecated, histórico) | Referência histórica |

---

## 🔍 TABELA DE CONTEÚDO RÁPIDA (Por Situação)

### "Quero iniciar do zero"
1. **README.md** (visão geral)
2. **INSTRUCOES.md** (passo-a-passo)
3. **MASTER_CONSOLIDADO.md** (seções 1-9)

### "Vídeo não funciona"
1. **BOOTARGS.md** (parâmetros corretos)
2. **MONITOR_INFO.md** (compatibilidade)
3. **LICOES_APRENDIDAS.md** #1, #18

### "Preciso recompilar o kernel"
1. **KERNELS.md** (qual versão)
2. **ROTEIRO_KERNEL.md** (passo-a-passo)
3. **SCRIPTS.md** (00-build-kernel.sh)

### "Sistema não bota"
1. **MASTER_CONSOLIDADO.md** (seção 11, problemas)
2. **LICOES_APRENDIDAS.md** (erros comuns)
3. **CABO_UART.md** (debug headless)

### "Quero entender o hardware"
1. **HARDWARE.md** (visão geral)
2. **PS4_HARDWARE_DOCS.md** (profundidade)
3. **BAIKAL_HARDWARE_DISCOVERIES.md** (Baikal específico)

### "Preciso debugar via SSH"
1. **COMUNICACAO_PS4.md** (SSH, netconsole)
2. **POS_INSTALACAO.md** (rede pré-configurada)

---

## 📂 ESTRUTURA DO DIRETÓRIO CONSOLIDADO

```
/consolidado/
├── INDEX_DOCUMENTACAO.md          ← Você está aqui
├── MASTER_CONSOLIDADO.md          ← Documento mestre (comece aqui)
├── LICOES_APRENDIDAS.md           ← Lições imperativas (leia antes de agir)
├── STATUS_ATUAL.md                ← Estado resumido
├── README.md                      ← Quick start
├── INSTRUCOES.md                  ← Instruções detalhadas
├── DOCUMENTACAO_COMPLETA.md       ← Visão geral histórica
│
├── HARDWARE/
│   ├── HARDWARE.md
│   ├── PS4_HARDWARE_DOCS.md
│   ├── HARDWARE_PS4_BAIKAL.md
│   ├── BAIKAL_STATUS.md
│   ├── BAIKAL_HARDWARE_DISCOVERIES.md
│   └── BAIKAL_GBE_EXPERIMENTS.md
│
├── VIDEO_EDID_MONITOR/
│   ├── BOOTARGS.md
│   ├── MONITOR_INFO.md
│   └── MONITOR_TENTATIVAS_LOG.md
│
├── KERNEL_BUILD/
│   ├── KERNELS.md
│   ├── ROTEIRO_KERNEL.md
│   └── MIGRACAO_7.0.md
│
├── BOOT_PAYLOAD/
│   ├── PAYLOADS.md
│   ├── INSTALACAO.md
│   └── COMUNICACAO_PS4.md
│
├── POS_INSTALACAO/
│   ├── POS_INSTALACAO.md
│   └── README_pos_install.md
│
├── DEBUG_COMUNICACAO/
│   ├── CABO_UART.md
│   ├── TODO_NETCONSOLE.md
│   └── TESTES_LOG.md
│
├── DISTROS_DRIVERS/
│   ├── DISTROS.md
│   ├── MESA_VULKAN.md
│   └── ARCH_ORIGINAL_README.md
│
├── EXPERIENCIAS/
│   ├── LICOES_APRENDIDAS.md
│   └── MILESTONE_2026-07-14.md
│
├── FIRMWARE/
│   └── DUMP_FIRMWARE_ORBIS.md     # NOR dump + sd8797_uapsta.bin
│   (RELATORIO_COLETA_DUMPS.md → incorporado ao MASTER_CONSOLIDADO.md Seção 3)
│
└── REFERENCIA/
    ├── REFERENCIAS.md
    ├── SCRIPTS.md
    ├── STATUS_ATUAL.md
    ├── RESUMO_TECNICO.md
    └── DOCUMENTACAO_COMPLETA.md  (histórico)
```

---

## ⚡ COMANDOS RÁPIDOS (CHEAT SHEET)

```bash
# Build completo (do zero ao PS4)
sudo ./00-build-kernel.sh && \
sudo ./01-build-image.sh && \
sudo ./02-burn-image.sh /dev/sda

# Build kernel apenas
sudo ./00-build-kernel.sh

# SSH
ssh root@192.168.6.128    # senha: ps4

# UART (headless)
screen /dev/ttyUSB0 115200

# Netconsole (PC host)
nc -u -l -p 6666

# EDID raw
cat /sys/bus/i2c/devices/3-0050/eeprom | xxd

# Status vídeo
cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,modes}

# Boot args atuais
cat /proc/cmdline

# VRAM info
cat /sys/kernel/debug/dri/0/amdgpu_vram_mm 2>/dev/null
```

---

## 🚀 ROADMAP DE LEITURA RECOMENDADO

### Nível 1: Iniciante (30 min)
- [ ] README.md
- [ ] MASTER_CONSOLIDADO.md seções 1-3

### Nível 2: Intermediário (2-3 horas)
- [ ] INSTRUCOES.md
- [ ] MASTER_CONSOLIDADO.md completo
- [ ] BOOTARGS.md
- [ ] LICOES_APRENDIDAS.md

### Nível 3: Avançado (6+ horas)
- [ ] Tudo acima +
- [ ] PS4_HARDWARE_DOCS.md
- [ ] ROTEIRO_KERNEL.md
- [ ] MONITOR_INFO.md (se ajustando vídeo)
- [ ] DUMP_FIRMWARE_ORBIS.md (se reverse engineering)

### Nível 4: Expert (especialização)
- [ ] Código-fonte nos repositórios GitHub
- [ ] Kernel source: `arch/x86/boot/`, `drivers/gpu/drm/amd/`
- [ ] Payloads: `ps4-linux-payloads/linux/main-aio.c`

---

## 📝 NOTAS IMPORTANTES

### ✅ O QUE DEVE ESTAR AQUI (atualizado 2026-07-25 — bloco anterior descrevia a era kernel 5.4, obsoleto)
- ✅ Boot completo (kernel 7.0 Baikal, `7.0.8-Strawberry-ThinLTO-Baikal-+`, baseline `v7.0-20260722-clean-video-ok`)
- ✅ WiFi + SSH funcional (192.168.6.128)
- ✅ Vídeo HDMI 1080p60 + EDID firmware
- ✅ Áudio HDMI (snd_hda_intel)
- ✅ RTC via time= no payload
- ✅ SATA, USB 3.0, SD/MMC
- ✅ GPU Gladius (amdgpu, 32 CUs, OpenGL 4.5 @ 55 FPS)
- ✅ Kernel Dump 12.52 via TCP (`scene-kmem-dumper` porta 9020) — concluído 2026-07-20

### ❌ O QUE NÃO FUNCIONA AINDA
- ❌ UART + vídeo simultaneamente (conflito Baikal)
- ❌ Dumper USB para kernel 12.52 (`jailbreak()` corrompe `rootvnode` — irrelevante agora, substituído pelo dumper TCP)
- ❌ Ethernet GBE — RX (bloqueador atual: PHY nunca sai de power-down, MDIO Clause 45/22 sempre zero/timeout)

### 🔄 EM PROGRESSO
- 🔄 Ethernet GBE — driver próprio `mts.ko` (não é `sky2`; MAC ligado via ICC, TX por software ~95%, PHY mudo é o bloqueador). Ver `../../PLANO_FASES_GBE_2026-07-25.md`.
- 🔄 WiFi/BT: dados de manufatura/regdomain (baixa prioridade)
- 🔄 Mesa/Vulkan RADV otimizado

---

## 🔗 CONSOLIDAÇÃO DE DUPLICATAS

| Duplicata Original | Consolidado em | Status |
|-------------------|-----------------|--------|
| `distros/arch_minimal_v2/LICOES_APRENDIDAS.md` | `consolidado/LICOES_APRENDIDAS.md` | ✅ Mantido (consolidado) |
| `distros/arch_minimal_v2/README.md` | Integrado em `MASTER_CONSOLIDADO.md` + quick start em `README.md` | ✅ Consolidado |
| `distros/arch_minimal_v2/PS4_HARDWARE_DOCS.md` | `consolidado/PS4_HARDWARE_DOCS.md` | ✅ Copiado |
| `monitor_edid/MONITOR_INFO.md` | `consolidado/MONITOR_INFO.md` | ✅ Copiado |

**Recomendação**: Manter versão em consolidado como canonical; subpastas podem referenciar com symlink ou README.

---

## 📞 SUPORTE & TROUBLESHOOTING

Se algo não funcionar:

1. **Vídeo preto**: Consulte **MONITOR_INFO.md** + **BOOTARGS.md**
2. **Boot falha**: Consulte **LICOES_APRENDIDAS.md** + **CABO_UART.md** (debug)
3. **Rede não funciona**: Consulte **COMUNICACAO_PS4.md** + **BAIKAL_HARDWARE_DISCOVERIES.md**
4. **Kernel falha**: Consulte **KERNELS.md** + **ROTEIRO_KERNEL.md**
5. **Dúvida geral**: Consulte **MASTER_CONSOLIDADO.md** seção 11 (problemas conhecidos)

---

> **Última revisão**: 2026-07-16  
> **Consolidação**: Documentação de 21 arquivos consolidada em um índice único com referências cruzadas.  
> **Manutenção**: Atualizar este arquivo ao adicionar/remover documentação.
