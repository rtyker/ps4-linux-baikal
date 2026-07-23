# Status Atual - PS4 Linux (Baikal/Arch Minimal v2)

**Última atualização**: 2026-07-20  
**Versão**: Arch Minimal v2 - Kernel 5.4.247-neocine-1.1

---

## ✅ FUNCIONANDO

| Subsistema | Detalhes |
|------------|----------|
| **Boot** | kexec via payload (PSFree/GoldHEN) → kernel → initramfs → rootfs |
| **SSH** | root/ps4 em 192.168.6.128 (Dropbear/OpenSSH) |
| **Vídeo HDMI** | 1920x1080@60 forçado, ps4_bridge VIC mode 16 |
| **EDID Persistente** | Firmware override `/lib/firmware/edid/ps4_tv_edid.bin` |
| **Rede** | ✅ Ethernet GBE funcional via driver `mts.ko` (`eth0`, MAC real `2c:cc:44:3f:69:5f`), netconsole ativo por padrão |
| **Áudio HDMI** | snd_hda_intel (1002:9921) |
| **RTC/Time** | Payload injeta `time=UNIX_TS`, hook early seta relógio |
| **VRAM Control** | `vram.txt` (FAT32) lido pelo payload, default 1024MB |
| **Storage** | SATA AHCI + USB 3.0 xHCI + SD/MMC |
| **Build System** | 3 scripts: build-kernel, build-image, burn-image |
| **NOR Dump (Orbis)** | `nor_sflash0.bin` (32MB) dumpado do PS4 real via ps4-sflash0-dumper. Partição `C0020001` (WiFi calibration) extraída. |
| **sd8797_uapsta.bin** | ✅ Obtido do feeRnt/ps4-linux-initramfs — Orbis custom (443 KB) confirmado vs upstream (522 KB) |
| **Kernel Dump 12.52** | 🔄 `scene-kmem-dumper` TCP (porta 9020) em teste — dumper USB descartado (open() falha no 12.52 por rootvnode corrompido) |
| **CoreOS/SLB2** | ✅ Analisado: 4 contêineres SLB2 extraídos, build#1281815, kernel cifrado via SAMU (dump offline inviável) |

---

## ⚙️ CONFIGURAÇÕES CRÍTICAS

### bootargs.txt (kernel cmdline)
```bash
video=HDMI-A-1:1920x1080@60
drm.edid_firmware=edid/ps4_tv_edid.bin
radeon.dpm=0 amdgpu.dpm=0
console=ttyS0,115200n8 console=tty0
netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff  # ✅ ATIVO — eth0 sobe em stage=4 no boot
```

### Arquivos na partição FAT32 (/dev/sda1)
```
bzImage              # 9.3MB - kernel
initramfs.cpio.gz    # 7.1MB - initramfs com hooks
bootargs.txt         # cmdline acima
vram.txt             # "1024" (MB)
bootlog.txt          # vazio (payload escreve)
```

### Initramfs Hooks
```
/hooks/early/set-time-from-cmdline   # lê time= do cmdline
/hooks/init/00-settime               # backup no rootfs
```

---

## 🔧 HARDWARE (Baikal CUH-2xxx)

| Componente | Driver | Status |
|------------|--------|--------|
| GPU Gladius (1002:9924) | amdgpu (CIK) | ✅ |
| Display DCE v8.0 | amdgpu DC/DCN1 | ✅ |
| HDMI Bridge | ps4_bridge (custom) | ✅ |
| Ethernet | sky2 (5.4) / stmmac (7.0) | ❌ GBE power-gated — precisa ICC power-on |
| USB 3.0 | xhci_aeolia | ✅ |
| SATA AHCI | ahci | ✅ |
| SD/MMC | sdhci | ✅ |
| HDMI Audio | snd_hda_intel | ✅ |
| WiFi/BT MT7668 | mt76x8 | ❌ fw ausente |

---

## 📁 ESTRUTURA DO PROJETO

```
/mnt/t/downloads/PS4/linux_in_ps4/
├── CLAUDE.md                 # Regras + estado (carregado auto pelo assistente)
├── consolidado/              # Documentação (fonte única)
├── memory/                   # Memórias de sessões (24 arquivos)
├── scene-kmem-dumper/        # Payload dumper TCP (12.52)
├── ps4-payload-sdk/          # SDK C para payloads
├── ps4-linux-payloads/       # Payloads kexec Linux
├── kernels/                  # Kernels compilados
├── distros/                  # Distribuições Linux
└── scripts/                  # Scripts auxiliares
```

---

## 🚀 COMANDOS RÁPIDOS

```bash
# Build completo
sudo ./00-build-kernel.sh && sudo ./01-build-image.sh && sudo ./02-burn-image.sh /dev/sda

# Apenas rebuild initramfs (após mudar hooks)
./rebuild-initramfs.sh && sudo cp boot_referencia/initramfs.cpio.gz /mnt/boot/

# SSH no PS4
ssh root@192.168.6.128  # senha: ps4

# Netconsole (logs kernel)
nc -u -l -p 6666

# Ver EDID raw
cat /sys/bus/i2c/devices/3-0050/eeprom | xxd

# Status display
cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,modes}
```

---

## ⚠️ PROBLEMAS CONHECIDOS

| Problema | Causa | Workaround |
|----------|-------|------------|
| TV desligada = sem vídeo | EDID lido via I2C falha | `drm.edid_firmware=edid/ps4_tv_edid.bin` ✅ |
| DP link training error | ps4_bridge usa caminho custom | Normal, bridge força enable |
| DPM causa instabilidade | Clocks dinâmicos bugados | `radeon.dpm=0 amdgpu.dpm=0` ✅ |
| systemd > 258 quebra boot | Incompatibilidade cgroup | Downgrade fixo 258.1-1 ✅ |
| UART + vídeo não coexistem | Conflito console | NÃO usar `console=uart8250...` com vídeo |
| Dumper USB falha no 12.52 | `jailbreak()` corrompe `rootvnode` | Usar TCP (`scene-kmem-dumper`) em vez de filesystem |
| Kernel cifrado offline | Criptografia SAMU em hardware | Só dump de RAM ativa (payload rodando pós-boot) |
| `__readmsr()` em userland | Instrução privilegiada → Kernel Panic | Sempre usar `kexec()` para código kernel |

---

## 📋 PRÓXIMOS PASSOS

> Pendências que não bloqueiam nada agora ficam em **[`BACKLOG.md`](BACKLOG.md)** (com prioridade).
> O trabalho ativo da GBE está em **[`GBE_ACTION_PLAN.md`](GBE_ACTION_PLAN.md)**.

1. **Kernel Dump 12.52** — Recompilar `scene-kmem-dumper` via Docker `ps4sdk` (toolchain gcc 15.2.0) e capturar dump TCP completo
2. **Análise do Kernel Orbis** — Ghidra/IDA no dump: power-gate GBE e Syscon ICC
3. **WiFi/BT** - Adicionar firmware `mt7668pr2h.bin` no kernel
4. **UART Console** - Cabo JST-SH 3.3V, testar isolado (sem vídeo)
5. **Power Management** - Reativar DPM com testes de estresse
6. **Mesa/Vulkan** - radv para CIK (Gladius)
7. **Kernel Mainline** - Migrar para 6.x quando suporte PS4 amadurecer

---

## 📚 REFERÊNCIAS

- Kernel: https://github.com/feeRnt/ps4-linux-12xx (branch v5.4.247__neocine-1.1) (Clonado localmente em `/mnt/hdauxiliar/temp/kernel_build`)
- Payloads: https://github.com/ArabPixel/ps4-linux-payloads
- Guia: https://dionkill.github.io/ps4-linux-tutorial/
- PSFree: https://arabpixel.github.io/PSFree-Enhanced/
