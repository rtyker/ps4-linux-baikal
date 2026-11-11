# Log de Testes — Arch Minimal v2 no PS4 Pro Baikal (FW 12.52)

**Monitor**: LG Full HD (GSM 23519, EDID 1.3, 23", semana 7/2022)
**TV**: Samsung/LG 1080p (funcionou com arch_minimal original)
**Payload**: Payload Guest ≥ 3GB
**Data**: 2026-07-11

---

## Resumo dos Kernels

| Kernel | Versão | Origem | Notas |
|--------|--------|--------|-------|
| **DFAUS** | 5.4.247-DFAUS-blkscrn_Fix_mt7668_hdmia | `/kernels/5.4.247/bzImage` | **Funcionou na TV** (arch_minimal original). Tem fixes mt7668 + hdmia. |
| **Neocine** | 5.4.247-neocine-1.1 | `/kernels/5.4.247-neocine/bzImage` | Baseado no DFAUS. Tentativa 3 (720p@60e) **funcionou em 2026-07-10** (doc). Causa kernel panic com 1080p@60e. |

---

## Testes de Vídeo (Cronológicos)

| # | Kernel | Bootargs | Resultado | Logs/Erro |
|---|--------|----------|-----------|-----------|
| 1 | DFAUS (arch_minimal original) | `1920x1080@60` | ✅ **TV funcionou** | — |
| 2 | DFAUS (build 02-burn) | `1920x1080@60e` | ❌ Rescueshell (CRTC falha) | `failed to set mode on CRTC` |
| 3 | DFAUS (build 02-burn) | `1920x1080@60e` | ❌ PS4 desligou (luz branca) | Kernel panic silencioso |
| 4 | DFAUS (build direto) | `1920x1080@60` | ❌ DP link training failed | `clock recovery failed` |
| 5 | DFAUS (build direto) | `1920x1080@60e` | ❌ CRTC falha | `failed to set mode on CRTC` ×4 |
| 6 | DFAUS | `1920x1080@60` + polling 10s | ❌ Sem boot (desligou cedo) | — |
| 7 | DFAUS | `1920x1080@60e` + polling 10s + debug | ❌ Luz branca, sem video | Kernel panic |
| 8 | Neocine | `1280x720@60e` (Tentativa 3) | ❌ Sem boot | PS4 desligou cedo |
| 9 | Neocine | `1280x720@60e` | ❌ Sem boot | PS4 desligou cedo |

---

## Configuração que BOOTOU COMPLETAMENTE (systemd + SSH + WiFi + logs)

| Item | Valor |
|------|-------|
| **Kernel** | DFAUS 5.4.247-DFAUS-blkscrn_Fix_mt7668_hdmia |
| **Bootargs** | `video=HDMI-A-1:1280x720@60e` (sem drm.debug) |
| **Vídeo** | ❌ Tela preta (CRTC falha: `failed to set mode on CRTC`) |
| **WiFi** | ❌ Não conectou (country 00, passive scan) |
| **SSH** | ✅ Habilitado, mas sem rede |
| **Logs** | ✅ `/var/log/boot_debug/` preenchido |

---

## Problemas Identificados

### Vídeo (Monitor LG)
1. **Bridge PS4 é rígido**: só aceita VIC 16 (1080p60) e VIC 4 (720p60) no `ps4_bridge_mode_valid`
2. **HPD timing**: Monitor LG levanta HPD tarde → `ps4_bridge_detect` retorna disconnected
3. **Force enable (`e`)**: Contorna HPD mas bridge já pode ter desabilitado saída
4. **DFAUS + 1080p@60e**: Force ON mas CRTC falha (`failed to set mode on CRTC`)
5. **DFAUS + 1080p@60 sem `e`**: DP link training falha (`clock recovery failed`)
6. **Neocine + 720p@60e**: **Documentado como funcional** (Tentativa 3, 2026-07-10) mas agora desliga

### WiFi (MT7668)
1. **Firmware**: Kernel 5.4 não suporta firmware `.zst` comprimido → copiar `.bin` descomprimido para `/lib/firmware/mediatek/`
2. **Country code**: Driver self-managed ignora `iw reg set BR` → precisa `country=BR` no wpa_supplicant.conf ANTES do scan
3. **Passive scan**: Em `country 00` todos canais 5GHz são PASSIVE-SCAN → lento
4. **Solução**: `country=BR` + `freq_list` 2.4GHz + restart wpa_supplicant após boot

---

## Próximos Testes Prioritários

1. **Neocine + 720p@60e** (configuração documentada funcional) — testar novamente, talvez payload size diferente
2. **DFAUS + 1080p@60e** (config que bootou completo) + tentar resolver CRTC
   - Verificar se `ps4_bridge_get_modes` expõe modo 1080p corretamente
   - Patch kernel `ps4_bridge_1080p_monitor.patch` para forçar EDID
3. **Payload Guest** — testar versões diferentes (3GB, 4GB, 5GB)
4. **Cabo HDMI** — testar cabo curto/certificado 2.0 (TMDS link training crítico)

---

## Configuração Atual (2026-07-12) — Tentativa de Boot via HDD Interno

**Kernel**: Neocine 5.4.247-neocine-1.1 (md5: 6307314db0dc83e0f2769b5ec93a9b7d)  
**Bootargs**: `panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0 console=uart8250,mmio32,0xC890E000 console=ttyS0,115200n8 console=tty0 video=HDMI-A-1:1280x720@60e amdgpu.audio=1 usbcore.autosuspend=-1 amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1 systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes`  
**SSH**: Habilitado (root/ps4, ps4/ps4)

**Arquivos atualizados**:
- `/mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/boot_referencia/bzImage` → Neocine
- `/mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/boot_referencia/bootargs.txt` → 720p@60e
- `/mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/boot_referencia/initramfs.cpio.gz` → better-initramfs v0.9.1

**Objetivo**: Copiar os 3 arquivos para `/data/linux/boot/` no HDD interno via GoldHEN FTP, para que o payload encontre os arquivos sem depender do USB.

---

## Comandos Úteis para Debug Remoto

```bash
# Ver logs de boot
cat /var/log/boot_debug/dmesg_drm.log
cat /var/log/boot_debug/dmesg_wifi.log
cat /var/log/boot_debug/iw_reg.log

# Ver status bridge
dmesg | grep -iE 'ps4_bridge|drm|hdmi|crtc|link_train'

# Ver WiFi
iw reg get
iw dev wlan0 link
systemctl status wpa_supplicant@wlan0
journalctl -u wpa_supplicant@wlan0

# Debug CRTC
dmesg | grep -i 'crtc\|bridge\|mode\|enable'
```

---

## Marcos e Memórias (2026-07-14)
*   **Mesa + Xorg + glxgears FUNCIONANDO no Baikal (kernel 5.4.247)**
    *   Kernel 5.4.247-neocine-1.1 (DRM 3.35.0) compatível apenas com Mesa ≤21.x
    *   Mesa oficial 26.x e DionKill 26.x git exigem DRM 3.42+ (kernel 5.15+) → **incompatível**
    *   **Solução**: Mesa 20.0.8 + LLVM 9.0.1 do tarball custom noob404 (`custom-mesa-arch-v1-ps4linux.tar.xz`)
    *   Configuração: `/home/noob404/mesa` + LD_LIBRARY_PATH/LIBGL_DRIVERS_PATH override
    *   **Resultado**: Direct rendering: Yes, OpenGL 4.5, ~60 FPS @ 1080p60 VSync
    *   GPU detectada: AMD DG1501SML87LB (LIVERPOOL/Gladius, PCI 0x1002:0x9924)
    *   Pacotes base: xorg-server 21.1.24, xf86-video-amdgpu-ps4 25.0.0, mesa-utils 9.0.0
    *   Repo DionKill documentado para futuro (kernel 5.15+)

---

## Marcos e Memórias (2026-07-13)
*   **Kernel Compilado com Sucesso**: Kernel Neocine (`5.4.247-neocine-1.1`) compilado localmente no PC Host (com correções do GCC 16 nas Makefiles e no driver MediaTek) dando boot completo com sucesso no PS4 Pro Baikal.
*   **Cenário de Testes**: Rodando e validado na **TV** (console limpo, ignore_loglevel removido, loglevel reduzido a 3 e audit desativado).
*   **Conectividade e Entrada**:
    *   **WLAN**: Funcionando de forma estável, conectando automaticamente no Wi-Fi `prfelicidade_5G` com IP dinâmico (`192.168.6.127`).
    *   **SSH**: Acesso remoto funcionando perfeitamente com login de root/ps4 (com a ressalva de usar `ip neigh replace` no PC host para contornar o bloqueio de rede local do cliente VPN).
    *   **Teclado**: Layout `pt-br` funcionando e validado.

