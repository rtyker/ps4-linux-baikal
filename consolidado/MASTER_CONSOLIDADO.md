# MASTER CONSOLIDADO — PS4 Linux (Baikal/Arch Minimal v2)

> **Última atualização**: 2026-07-20  
> **Versão**: Arch Minimal v2 — Kernel 5.4.247-neocine-1.1  
> **Hardware**: PS4-RTYKER (CUH-2xxx), Southbridge Baikal B1 (0x30201), FW 12.52, GoldHEN v2.4b18.9

---

## 1. RESUMO EXECUTIVO

| Subsistema | Status | Detalhes |
|------------|--------|----------|
| **Boot** | ✅ | kexec via payload → kernel → initramfs → rootfs |
| **SSH** | ✅ | root/ps4 @ 192.168.6.128 (Dropbear/OpenSSH) |
| **Vídeo HDMI** | ✅ | 1920×1080@60 forçado, ps4_bridge VIC mode 16 |
| **EDID Persistente** | ✅ | Firmware override `/lib/firmware/edid/ps4_tv_edid.bin` |
| **Rede (Ethernet)** | ❌ | GBE power-gated (Syscon/ICC) — sky2 probe falha `unsupported chip type 0x0` — ver Seção 18 |
| **Áudio HDMI** | ✅ | snd_hda_intel (1002:9921) |
| **RTC/Time** | ✅ | Payload injeta `time=UNIX_TS`, hook early seta relógio |
| **VRAM Control** | ✅ | `vram.txt` (FAT32) lido pelo payload, default 1024 MB |
| **Storage** | ✅ | SATA AHCI + USB 3.0 xHCI + SD/MMC |
| **Build System** | ✅ | 3 scripts: build-kernel, build-image, burn-image |
| **NOR Dump (PS4 real)** | ✅ | `nor_sflash0.bin` (32 MB) — dumpado via ps4-sflash0-dumper |
| **C0020001 (WiFi calibração)** | ✅ | Extraído do NOR em `boot_referencia/C0020001_wifi_calibration.bin` |
| **sd8797_uapsta.bin (Orbis)** | ❌ | **Não está no NOR** — firmware fica no HDD Orbis, não na flash |
| **MWIFIEX_SDIO** | ⏳ | Será desabilitado no build 7.0 (Baikal usa MT7668, não Marvell) |
| **WiFi/BT (MT7668)** | ❌ | Firmware ausente no kernel |
| **Kernel Dump 12.52** | 🔄 | `scene-kmem-dumper` TCP (porta 9020) em teste — ver Seção 18 |

---

## 2. HARDWARE — PS4 Baikal (CUH-2xxx)

### Especificações Principais
| Componente | Detalhe |
|------------|---------|
| **Modelo** | PS4-RTYKER |
| **Firmware** | 12.52 |
| **Southbridge** | Baikal B1 (0x30201) |
| **HEN / GoldHEN** | 12.52 / v2.4b18.9 |
| **IP LAN / MAC** | 192.168.6.130 / 2C:CC:44:3F:69:5F |
| **WiFi MAC** | E8:D8:19:93:CC:AF |
| **CPU** | 8-core AMD Jaguar x86-64 @ 1.6 GHz |
| **GPU** | AMD GCN 1.8 TFLOPS (Gladius, 1002:9924) |
| **RAM** | 8 GB GDDR5 unificada (≈4-5 GB livres p/ Linux) |

### Southbridges do PS4
| Southbridge | Modelos | UART Addr |
|-------------|---------|-----------|
| **Aeolia** | PS4 Phat (inicial) | `0xD0340000` |
| **Belize** | PS4 Slim, PS4 Pro | `0xD0340000` |
| **Baikal (B1)** | PS4 Slim/Pro (revisões recentes) | **`0xC890E000`** |

### Drivers Principais
| Componente | Driver | Status |
|------------|--------|--------|
| GPU Gladius (1002:9924) | amdgpu (CIK) | ✅ |
| Display DCE v8.0 | amdgpu DC/DCN1 | ✅ |
| HDMI Bridge | ps4_bridge (custom) | ✅ |
| Ethernet | sky2 | ❌ GBE power-gated (precisa ICC/Syscon power-on) |
| USB 3.0 | xhci_aeolia | ✅ |
| SATA AHCI | ahci | ✅ |
| SD/MMC | sdhci | ✅ |
| HDMI Audio | snd_hda_intel | ✅ |
| WiFi/BT MT7668 | mt76x8 | ❌ fw ausente |

---

## 3. FIRMWARE ORBIS & COREOS — Engenharia Reversa

### 3.1 Coleta de Arquivos via FTP (GoldHEN — FW 12.52)

Inventário de executáveis e módulos extraídos do PS4 real via FTP (porta 2121, GoldHEN) — salvos em `consolidado/dumps_orbis/`:

**ELF do sistema:**
| Arquivo | Tamanho | Função |
|---------|---------|--------|
| `mini-syscore.elf` | 627 KB | Daemon central de serviços baixo nível |
| `SceSysAvControl.elf` | 833 KB | Handshake HDMI/AV |
| `safemode.elf` | 4.7 MB | Modo de segurança |
| `system_sys_SceSysCore.elf` | 940 KB | Núcleo de serviços do sistema |
| `system_sys_orbis_setip.elf` | 54 KB | Configuração de IP/rede |
| `system_sys_GnmCompositor.elf` | 298 KB | Compositor gráfico GNM |
| `system_sys_coredump.elf` | 325 KB | Dump de crash |
| `system_sys_gpudump.elf` | 120 KB | Rastreamento GPU |
| `system_sys_orbis_audiod.elf` | 747 KB | Daemon de áudio |
| `system_sys_SceVdecProxy.elf` | 137 KB | Decodificador de vídeo |
| `system_sys_SceVencProxy.elf` | 906 KB | Codificador de vídeo |

**SPRX (bibliotecas FreeBSD):**
| Arquivo | Tamanho | Função |
|---------|---------|--------|
| `libkernel.sprx` | 449 KB | Wrapper de syscalls Orbis |
| `libkernel_sys.sprx` | 454 KB | IOCTLs de sistema |
| `libSceNet.sprx` | 282 KB | Sockets/pilha TCP/IP |
| `libSceNetCtl.sprx` | 72 KB | Controle de interface de rede (Ethernet/WiFi) |
| `libSceGnmDriver.sprx` | 97 KB | Driver gráfico GNM |
| `libSceSdma.sprx` | 69 KB | Driver DMA do Southbridge |
| `libSceDipsw.sprx` | 51 KB | Leitura de DIP Switches |
| `Sce.Vsh.Registry.dll.sprx` | 266 KB | Registro/configurações de sistema |

### 3.2 CoreOS — Análise do Contêiner SLB2

A partição `sflash0s1.crypt` (30 MB, exposta pelo block device desciptografado do Orbis) contém quatro contêineres **SLB2**:

| Offset | Conteúdo | Tamanho |
|--------|----------|---------|
| `0x4000` | Slot 0 de Boot (`80000001`) | 151 KB |
| `0x42000` | Slot de Backup (`80000001`) | 151 KB |
| `0x1C0000` | **CoreOS Slot 1 Ativo** (7 partições, incluindo kernel) | — |
| `0xE80000` | **CoreOS Slot 2 Backup** (kernel reserva) | — |

Os arquivos extraídos do SLB2 têm cabeçalhos Sony adicionais. A assinatura ELF (`\x7fELF`) inicia em:
- `80010002` (FreeBSD Kernel): offset **64** → `kernel.elf` (10.8 MB)
- `80010001` (Secure Bootloader / `sam_ipl`): offset **96** → `sam_ipl.elf` (98 KB)
- Módulos SAMU (`80010006`–`8001000B`): offset **128**

**Build identificado:** `#1281815` (lido de `vshlog.0.txt` no FTP).

### 3.3 Limitação SAMU — Dump Offline Inviável

O kernel dentro do CoreOS passa por **dupla camada de proteção**:
1. A partição block `sflash0s1.crypt` entrega o SLB2 desciptografado
2. Mas os segmentos do kernel dentro de `80010002` têm **segunda criptografia via hardware SAMU**, descriptografada dinamicamente apenas durante o boot

A ferramenta `ps4-pup-unpacker` extrai 0 bytes — o fluxo ZLIB/Deflate a partir do offset `0x2b0` falha por estar cifrado.

**Conclusão:** A única via para obter o kernel Orbis desciptografado é o dump de RAM ativa (payload rodando no PS4 após o boot completo, lendo a memória já desciptografada pelo hardware). Este é o objetivo do `scene-kmem-dumper` (TCP porta 9020) — ver Seção 18.

### 3.4 Alvos de Análise Pós-Dump

Com o kernel em mãos, os alvos no Ghidra/IDA são:
- **Interface `gbe0`** — controle da Ethernet Gigabit (Marvell Yukon `sky2` adaptado Baikal)
- **Syscon power management** — mapeamento de registradores MMIO pervasive e chamadas ICC (`/dev/icc_device_power`) para ativar o clock/power da GBE

---

## 4. PARTIÇÃO DE BOOT (FAT32, /dev/sda1, 50 MB)

### Arquivos Obrigatórios
```
bzImage              # 9.3 MB — kernel Linux
initramfs.cpio.gz    # 7.1 MB — initramfs com hooks
bootargs.txt         # kernel command line
vram.txt             # "1024" (MB)
bootlog.txt          # vazio (payload escreve)
```

### `vram.txt` — Controle de VRAM
| Valor (MB) | Uso |
|------------|-----|
| 32-512 | Server headless (libera RAM p/ CPU) |
| **1024** | **Padrão** — Desktop/Gaming |
| 2048-3072 | Gaming pesado |
| 4096 | Máximo (4 GB VRAM, 4 GB RAM CPU) |

> Payload lê `vram.txt` **antes** do kexec. Prioridade sobre valor embutido no payload.

---

## 5. KERNEL COMMAND LINE (`bootargs.txt`)

### Linha Atual (FUNCIONAL — sem UART conflituoso)
```text
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0
radeon.dpm=0 amdgpu.dpm=0 drm.debug=0
console=ttyS0,115200n8 console=tty0
video=HDMI-A-1:1920x1080@60
drm.edid_firmware=edid/ps4_tv_edid.bin
quiet amdgpu.audio=1 usbcore.autosuspend=-1
amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1
systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes
audit=0
netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff
```

### Parâmetros Críticos Explicados
| Parâmetro | Função |
|-----------|--------|
| `video=HDMI-A-1:1920x1080@60` | Força 1080p60 (sem sufixo `e`) |
| `drm.edid_firmware=edid/ps4_tv_edid.bin` | EDID persistente (TV off OK) |
| `radeon.dpm=0 amdgpu.dpm=0` | Desliga DPM — evita travamentos |
| `console=ttyS0,115200n8 console=tty0` | Serial + framebuffer (sem UART Baikal) |
| `drm.debug=0` | Reduz verbosidade DRM |
| `amdgpu.gpu_recovery=1` | Auto-recovery GPU |
| `mitigations=off` | +5-15% CPU (Spectre/Meltdown off) |
| `zswap.enabled=1` | Swap comprimido na RAM |
| `netconsole=...` | Logs kernel via UDP 6666 ✅ **OPERANTE** — `eth0` ativada via driver `mts.ko` (stage=4) |
| `systemd.unified_cgroup_hierarchy=0` | cgroup v1 p/ systemd 258 |

### ⚠️ NÃO USAR (Conflita com Vídeo)
```text
console=uart8250,mmio32,0xC890E000   # UART Baikal — quebra HDMI!
```
> **Lição #18**: UART + vídeo HDMI **não coexistem** no Baikal. Use netconsole ou cabo serial **isolado** (sem `video=`).

---

## 6. INITRAMFS — Hooks Customizados

### Estrutura
```
/hooks/early/set-time-from-cmdline   # lê time= do /proc/cmdline
/hooks/init/00-settime               # backup no rootfs
```

### `set-time-from-cmdline` (early hook)
```sh
#!/bin/sh
for i in $(cat /proc/cmdline); do
    case "${i}" in
        time=*)
            TIMESTAMP="${i#time=}"
            if [ -n "${TIMESTAMP}" ] && [ "${TIMESTAMP}" -gt 0 ] 2>/dev/null; then
                date -s "@${TIMESTAMP}" || true
                hwclock -w -u || true
            fi
            ;;
    esac
done
```
> Payload injeta `time=UNIX_TIMESTAMP` automaticamente.

---

## 7. EDID FIRMWARE — Vídeo sem TV Ligada

### Arquivo
- **Local**: `/lib/firmware/edid/ps4_tv_edid.bin` (256 bytes)
- **Origem**: `/sys/bus/i2c/devices/3-0050/eeprom` (I2C bus 3, addr 0x50)
- **Monitor**: Samsung M8N4627 9" (1080p60 only)

### Kernel Config
```kconfig
CONFIG_DRM_LOAD_EDID_FIRMWARE=y
```

### Bootarg
```text
drm.edid_firmware=edid/ps4_tv_edid.bin
```

### Verificação
```bash
# EDID raw
cat /sys/bus/i2c/devices/3-0050/eeprom | xxd

# Status conector
cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,modes}
```

---

## 8. PAYLOADS kexec (v24+ Firmware-Agnóstico)

### Repositório
```bash
git clone https://github.com/ArabPixel/ps4-linux-payloads
cd ps4-linux-payloads/linux && make
```

### Características v24+
- **Um binário para todos FW** (5.05 → 13.50)
- Detecção **runtime** de southbridge (Baikal/Aeolia/Belize) e modelo (PRO/non-PRO)
- VRAM via `vram.txt` ou embutido (32 MB → 4 GB)
- Paths de boot: USB/HDD externo (FAT32) → `/data/linux/boot/` → `/user/system/boot/`
- RTC via cmdline: `time=CURRENTTIME`

### Arquivos de Boot Necessários
```
bzImage
initramfs.cpio.gz
bootargs.txt  (opcional)
vram.txt      (opcional)
```

### Carregamento
```bash
# Via PSFree-Enhanced (host web)
# Via GoldHEN PayLoader
# Via netcat (porta 9090)
nc -w 3 192.168.6.130 9090 < linux-3072mb.bin
```

---

## 9. KERNELS RECOMENDADOS PARA BAIKAL

### Kernel 5.4.247-neocine-1.1 (feeRnt) — ATUAL
- Base: DFAUS-git/ps4-baikal-5.4.247-kernel
- WiFi/BT: MediaTek 7668 (mt76x8; MT6632 variant)
- Fixes: Tela preta login/initramfs, AMDGPU Gladius Registers
- ZRAM/ZSWAP/ZBUD, march=btver2, -O3
- Compilador: Clang/LLVM-14 ou GCC-11
- ⚠️ Mesa ≤ 25.1 (libdrm novo quebra aceleração 3D)

### Kernel 7.0.8 (Strawberry/rmuxnet) — BLEEDING EDGE
- Primeira porta Baikal para kernel 7.x
- UART, USB, display, WiFi/BT MT7668
- Perfis: General (desktop/gaming) ou Server (headless)
- ThinLTO / FullLTO
- GitHub Actions geram bzImage pré-compilado

### Compilação (feeRnt 5.4)
O código-fonte deste kernel já está clonado localmente na pasta de build: `/mnt/hdauxiliar/temp/kernel_build`.

Para compilar de forma automatizada com patches, use o script `00-build-kernel.sh`. Para clonar/compilar manualmente em outro local:
```bash
git clone https://github.com/feeRnt/ps4-linux-12xx --branch v5.4.247__neocine-1.1
cd ps4-linux-12xx
make -j$(nproc) bzImage
# Saída: arch/x86/boot/bzImage
```

---

## 10. BUILD SYSTEM — Arch Minimal v2

### Scripts Principais
| Script | Função |
|--------|--------|
| `00-build-kernel.sh` | Compila kernel neocine (patches MediaTek, sky2, gcc16) |
| `01-build-image.sh` | Cria rootfs Arch + initramfs (hooks EDID, time, vram) |
| `02-burn-image.sh` | Grava HD: FAT32 boot + ext4 root (LABEL=psxitarch) |
| `rebuild-initramfs.sh` | Reconstrói initramfs após mudança de hooks |

### Fluxo Completo
```bash
sudo ./00-build-kernel.sh && sudo ./01-build-image.sh && sudo ./02-burn-image.sh /dev/sda
```

### O que `01-build-image.sh` Faz
1. Bootstrap Arch oficial → chroot
2. Downgrade systemd → 258.1-1 (fixo via IgnorePkg)
3. Instala: openssh, wpa_supplicant, dhcpcd, nettools, debug tools
4. Cria hooks initramfs: `set-time-from-cmdline`, `00-settime`
5. Copia EDID firmware → `/lib/firmware/edid/ps4_tv_edid.bin`
6. Configura rede estática (192.168.0.2), SSH, netconsole service
7. Gera `initramfs.cpio.gz` com hooks
8. Empacota `arch_minimal_v2.tar`

### Particionamento Alvo (`02-burn-image.sh`)
```bash
sda1: 50 MB  FAT32  LABEL=BOOT      (bzImage, initramfs, bootargs, vram.txt, bootlog.txt)
sda2: resto  ext4   LABEL=psxitarch  (rootfs extraído)
```

---

## 11. PÓS-INSTALAÇÃO NO PS4 (via SSH)

### Credenciais
```bash
ssh root@192.168.6.128   # senha: ps4
```

### Configurações Essenciais
```bash
# Timezone / Locale
timedatectl set-timezone America/Sao_Paulo
echo "pt_BR.UTF-8 UTF-8" > /etc/locale.gen && locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

# Swap (essencial — 8 GB RAM unificada)
fallocate -l 8G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
echo "vm.swappiness=90" >> /etc/sysctl.d/99-swappiness.conf

# systemd 258 fixo (IgnorePkg no pacman.conf)
IgnorePkg = linux linux-headers mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon systemd systemd-libs systemd-sysvcompat

# DisableSandbox no pacman.conf
DisableSandbox
```

### Verificação
```bash
# Status display
cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,modes}

# EDID raw
cat /sys/bus/i2c/devices/3-0050/eeprom | xxd

# Netconsole (PC host)
nc -u -l -p 6666

# VRAM atual
cat /sys/kernel/debug/dri/0/amdgpu_vram_mm 2>/dev/null
```

---

## 12. PROBLEMAS CONHECIDOS & WORKAROUNDS

| Problema | Causa | Workaround |
|----------|-------|------------|
| TV desligada = sem vídeo | EDID lido via I2C falha | `drm.edid_firmware=edid/ps4_tv_edid.bin` ✅ |
| DP link training error | ps4_bridge caminho custom | Normal, bridge força enable |
| DPM causa instabilidade | Clocks dinâmicos bugados | `radeon.dpm=0 amdgpu.dpm=0` ✅ |
| systemd > 258 quebra boot | Incompatibilidade cgroup | Downgrade fixo 258.1-1 ✅ |
| **UART + vídeo não coexistem** | Conflito console Baikal | **NÃO USAR** `console=uart8250...` com vídeo |
| WiFi/BT não funciona | Firmware MT7668 ausente | Adicionar `mt7668pr2h.bin` no kernel |
| Mesa > 25.1 quebra 3D | libdrm novo incompatível 5.4 | Travar Mesa ≤ 25.1 |
| **Dumper USB falha no 12.52** | `jailbreak()` corrompe `rootvnode` | Usar TCP (`scene-kmem-dumper`) em vez de filesystem |
| **Kernel cifrado offline** | Criptografia SAMU em hardware | Só dump de RAM ativa (payload rodando pós-boot) |
| **`/dev/kmem` bloqueado** | GoldHEN bloqueia `open()` | Não usar kmem; ler via `kexec`+`copyout` |
| **MSR direto em userland** | Instrução privilegiada → Kernel Panic | Sempre usar `kexec()` para código kernel |

---

## 13. CABO UART (Debug Headless)

### Pinout J1/J2 (Baikal)
| Pino | Função | Conexão |
|------|--------|---------|
| 1 | VCC (3.3V) | **NÃO LIGAR** |
| 2 | TX (PS4→PC) | → RX adaptador |
| 3 | RX (PC→PS4) | → TX adaptador |
| 4 | GND | → GND adaptador |

### Adaptador USB-Serial
- Chipset: **CP2102, CH340G, FT232RL, PL2303** — **3.3V logic level**
- **NÃO usar 5V** — queima southbridge

### Teste (sem vídeo)
```bash
# PC host
screen /dev/ttyUSB0 115200
# ou
picocom -b 115200 /dev/ttyUSB0
```
> Bootargs **sem** `video=` nem `drm.edid_firmware`; apenas `console=uart8250,mmio32,0xC890E000 console=tty0`.

---

## 14. NETCONSOLE — Logs Kernel Remotos (✅ OPERANTE)

### PS4 (bootargs configurado, eth0 ativa por padrão)
```text
netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff
```

### PC Host (receptor)
```bash
python3 scripts/netconsole_listener.py
# ou
nc -u -l -p 6666
```

> **Nota:** Netconsole utiliza a interface `eth0` provida pelo driver `mts.ko` (stage=4 por padrão) para transmitir todos os logs do kernel via UDP durante o boot.

---

## 15. ESTRUTURA DO PROJETO

```
/mnt/t/downloads/PS4/linux_in_ps4/
├── CLAUDE.md                     # → Carregado auto pelo assistente (regras + estado atual)
├── consolidado/                  # Documentação consolidada (fonte única)
│   ├── MASTER_CONSOLIDADO.md     # ← Você está aqui
│   ├── LICOES_APRENDIDAS.md      # Lições imperativas
│   ├── INDEX_DOCUMENTACAO.md     # Índice completo
│   ├── STATUS_ATUAL.md           # Estado resumido
│   └── ... (50+ arquivos de doc)
├── memory/                       # Memórias de sessões (24 arquivos)
│   └── MEMORY.md                 # Índice de memórias
├── scene-kmem-dumper/            # Payload dumper TCP (FW 12.52)
│   ├── source/main.c             # Payload reconstruído
│   ├── rebuild.sh                # Recompila via Docker ps4sdk
│   └── inject.sh                 # Injetar no PS4
├── ps4-payload-sdk/              # SDK C para payloads
├── ps4-linux-payloads/           # Payloads kexec Linux
├── scene-kernel-dumper/          # Dumper C original (USB)
├── kernels/                      # Kernels compilados
├── distros/                      # Distribuições Linux
├── initramfs/                    # Configs de initramfs
└── scripts/                      # Scripts auxiliares
```

---

## 16. COMANDOS RÁPIDOS (CHEAT SHEET)

```bash
# Build completo
sudo ./00-build-kernel.sh && sudo ./01-build-image.sh && sudo ./02-burn-image.sh /dev/sda

# Apenas rebuild initramfs (mudança de hooks)
./rebuild-initramfs.sh && sudo cp boot_referencia/initramfs.cpio.gz /mnt/boot/

# SSH
ssh root@192.168.6.128    # senha: ps4

# Netconsole
nc -u -l -p 6666

# EDID raw
cat /sys/bus/i2c/devices/3-0050/eeprom | xxd

# Status display
cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,modes}

# VRAM info
cat /sys/kernel/debug/dri/0/amdgpu_vram_mm 2>/dev/null

# Verificar bootargs atuais
cat /proc/cmdline
```

---

## 17. ROADMAP PRÓXIMOS PASSOS

1. **Kernel Dump 12.52** — Recompilar `scene-kmem-dumper` via Docker `ps4sdk` (toolchain correto gcc 15.2.0) e capturar dump TCP completo da RAM
2. **Análise do Kernel Orbis** — Ghidra/IDA: achar power-gate da GBE (`devpm: gbe off`) e chamadas ICC para ativar Ethernet
3. **WiFi/BT** — Adicionar `mt7668pr2h.bin` no kernel
4. **UART Console** — Cabo JST-SH 3.3V, testar **isolado** (sem `video=`)
5. **Power Management** — Reativar DPM com testes de estresse
6. **Mesa/Vulkan** — radv para CIK (Gladius)
7. **Kernel Mainline** — Migrar para 6.x quando suporte PS4 amadurecer

---

## 18. KERNEL DUMP FIRMWARE 12.52 — Estado Atual

### 20.1 Contexto
Precisamos do dump completo do kernel Orbis FW 12.52 (região R+E ~13.6 MB) para analisar os drivers de GBE (`sky2`/`bpcie`) e Syscon power management. O kernel Orbis está cifrado offline (criptografia SAMU em hardware), só acessível descriptografado na RAM ativa.

### 20.2 Histórico — USB Falhou (Causa Raiz Identificada)
- `jailbreak()` da libPS4 original corrompe as credenciais de `rootvnode` no 12.52 → `open("/mnt/usb0/...")` falha silenciosamente
- `/dev/kmem` é ativamente bloqueado pelo GoldHEN atual (`open()` retorna `-1`)
- **PROVADO 2026-07-19:** os 3 dumps parciais obtidos via USB (3.9MB, 1.4MB) têm **zero chunks zerados** — `read()` via `kexec`+`copyout` nunca falhou. O culpado era o `open()` do USB.
- Smart Dumper (que usou `get_kernel_base()`/`get_memory_dump()` corretamente) leu **3.9MB de kernel real**, zero chunks corrompidos — prova de que `kexec`+`copyout` funciona no 12.52.

### 20.3 Solução Atual — `scene-kmem-dumper` (TCP porta 9020)
Payload reescrito em 2026-07-19 que usa **TCP** em vez de filesystem:
- **Base do kernel:** `get_kernel_base()` (via `kexec`, comprovado funcional) — **NÃO** `__readmsr(0xC0000082)` (MSR direto causa Segfault/Kernel Panic em userland)
- **Leitura:** `get_memory_dump()` (via `kexec`+`copyout` real, fault-safe)
- **Transporte:** TCP porta 9020 — PC envia `[u64 start][u64 size]` (LE, relativos à kernel_base), PS4 transmite o cru em chunks de `PAGE_SIZE=0x4000`
- **Chunk ilegível:** vira 16KB de zeros (preserva alinhamento)
- **Receptor:** `receive_kmem_dump.py` (retomável, imprime comando exato para continuar)

### 20.4 Limitações Conhecidas do 12.52
| Problema | Causa | Status |
|----------|-------|--------|
| `jailbreak()` corrompe USB | Offsets `K1252_ROOTVNODE`/`K1252_PRISON_0` não verificados | **BANIDO** — não usar |
| `/dev/kmem` bloqueado | GoldHEN v2.4b18.9 bloqueia `open()` | Contornado (TCP, sem kmem) |
| `__readmsr(0xC0000082)` em userland | Instrução privilegiada — Segfault + Kernel Panic | Proibido — só via `kexec()` |
| Loop de scan com dereference direto (candidato) | Page fault em modo kernel se página não mapeada | Corrigir antes de repetir |

### 20.5 Ferramentas Relacionadas
- **`ps4-kernel-dumper-1252.bin`** (em `ps4-linux-payloads/`): **ARQUIVO FALSO** (9 bytes = corpo de HTTP 404). Ignorar/deletar.

### 20.6 Status dos Testes — SUCESSO (2026-07-20)
- **v1 a v2 (USB e TCP iniciais):** sofriam com travamentos e Kernel Panics causados por corrupção de stack (desempacotamento de argumentos inválido no `kexec` da SDK) e por page faults silenciosos no kernel em Ring 0 ao ler buffers de memória "demand-zero" (`result` e `buf`).
- **v3 (Corrigido por Antigravity):**
  1. Corrigimos a assinatura e o desempacotamento de argumentos no kernel (`struct kern_base_finder_args` e `struct kexec_direct_dump_args`).
  2. Forçamos a paginação (`memset`) dos buffers `result` e `buf` em userland antes das chamadas de kernel.
  3. Comentamos a varredura perigosa `try_scan_method`.
  4. Substituímos `get_memory_dump` da SDK por uma versão robusta `direct_memory_dump` chamando `copyout` diretamente.
- **Resultado do teste ao vivo (2026-07-20):** O dumper extraiu com sucesso o dump completo do kernel (32.21 MB) via rede TCP em apenas 3 segundos sem panics ou hangs!

### 20.7 Regras de Teste (Gravar na Memória)
- `send_payload_loop.py` só injeta na porta **9090** (nunca na 9020)
- **NUNCA** fazer probe TCP (`connect()`) nas portas 9090/9020 — só `ping` — consome o `accept()` único
- Sempre avisar o usuário e esperar "pronto" antes de disparar o payload (Regra de Ouro da Injeção)

---

## 19. REFERÊNCIAS

- Kernel: https://github.com/feeRnt/ps4-linux-12xx (branch v5.4.247__neocine-1.1)
- Payloads: https://github.com/ArabPixel/ps4-linux-payloads
- Guia: https://dionkill.github.io/ps4-linux-tutorial/
- PSFree: https://arabpixel.github.io/PSFree-Enhanced/
- DFAUS kernels: https://github.com/DFAUS-git/ps4-baikal-5.4.247-kernel
- Strawberry 7.0: https://github.com/rmuxnet/linux (baikal/7.0.8-Stable)

---

> **Nota**: Este documento consolida `BOOTARGS.md`, `HARDWARE.md`, `PAYLOADS.md`, `KERNELS.md`, `INSTALACAO.md`, `SCRIPTS.md`, `STATUS_ATUAL.md`, `LICOES_APRENDIDAS.md`, `CABO_UART.md`, `DISTROS.md`, `DOCUMENTACAO_COMPLETA.md`, `README.md`, os arquivos da pasta `arch_minimal_v2/` e a análise CoreOS/SLB2 que estava em `RELATORIO_COLETA_DUMPS.md` (excluído — conteúdo incorporado à Seção 3). Informações duplicadas foram unificadas; nada de relevante foi removido.
