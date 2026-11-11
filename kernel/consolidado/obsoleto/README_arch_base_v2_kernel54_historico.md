# Arch Base v2 — PS4 Linux

Base completa do Arch Linux para PS4. Gerada a partir do bootstrap oficial (2026.07.01), com systemd rebaixado para 258.1-1, base-devel, ferramentas de rede, desenvolvimento e WiFi pré-configurado.

## Credenciais

| Usuário | Senha | Privilégios |
|---------|-------|-------------|
| `ps4` | `ps4` | Superusuário (wheel/sudo) |
| `root` | `ps4` | Root |

## Build (gravação no HD)

```bash
sudo ./build.sh
sudo ./burn.sh --apply /dev/sda
```

O que o build faz:
1. Cria loop image isolado em `/mnt/hdauxiliar/temp/arch_base_v2_staging/`
2. Extrai bootstrap Arch Linux
3. Instala: `base base-devel networkmanager iwd wireless_tools wpa_supplicant dhcpcd openssh sudo vim nano nvim gcc make cmake meson ninja pkgconf nodejs npm python python-pip git wget curl rsync unzip zip p7zip htop iotop iftop nethogs usbutils pciutils lsof strace man-db man-pages texinfo`
4. Downgrade systemd 261 → 258.1-1 (obrigatório para kernel 5.4)
5. Configura: DisableSandbox, IgnorePkg, multilib, locale pt_BR, timezone America/Sao_Paulo, keymap br-abnt2
6. Habilita NetworkManager + systemd-resolved
7. WiFi pré-configurado: `prfelicidade_5G` / `9911121314`
8. Cria `arch_base_v2.tar`

O que o burn faz:
1. Formata sda1 (FAT32) + sda2 (ext4, label `psxitarch`)
2. Copia boot files de `boot_referencia/` para sda1
3. Extrai `arch_base_v2.tar` para sda2

Pré-requisitos:
- HD conectado via USB (detectado como `/dev/sda`)
- `boot_referencia/` com bzImage, initramfs.cpio.gz, bootargs.txt
- `systemd_cache/` será baixado automaticamente se não existir

## Estrutura

```
arch_base_v2/
├── build.sh                    # Build isolado (loop image) -> arch_base_v2.tar
├── burn.sh                     # Grava no HD (dry-run por default, --apply para gravar)
├── arch_base_v2.tar            # Rootfs (base + base-devel + network + dev tools)
├── boot_referencia/            # Arquivos de boot validados
│   ├── bzImage                 # Kernel Neocine 5.4.247
│   ├── initramfs.cpio.gz       # Initramfs do projeto
│   ├── bootargs.txt            # Parâmetros validados (sem @60e)
│   └── README.md
├── systemd_cache/              # Pacotes systemd 258.1-1 (baixados uma vez)
├── downgrade_systemd.sh        # Script isolado de downgrade
├── LICOES_APRENDIDAS.md        # Erros documentados e como evitar
├── pkglist.x86_64.txt          # Lista de pacotes do bootstrap
├── version                     # Versão do bootstrap (2026.07.01)
└── README.md                   # Este arquivo
```

## Pacotes Principais Inclusos

**Base & Desenvolvimento:**
- `base base-devel` — Sistema base + toolchain completa (gcc, make, cmake, meson, ninja, pkgconf)
- `nodejs npm python python-pip` — Runtimes de desenvolvimento
- `git wget curl rsync unzip zip p7zip` — Ferramentas de source/code

**Rede & Wireless:**
- `networkmanager iwd wireless_tools wpa_supplicant dhcpcd net-tools iproute2 inetutils`
- `openssh` — SSH server habilitado

**Editores & Utilitários:**
- `vim nano nvim less htop iotop iftop nethogs`
- `usbutils pciutils lsof strace man-db man-pages texinfo`

**Sistema:**
- `systemd 258.1-1` (rebaixado — obrigatório para kernel 5.4 neocine)
- `DisableSandbox` no pacman (funciona dentro do chroot)
- `IgnorePkg` para kernel, mesa, systemd, vulkan-radeon
- `multilib` habilitado

## WiFi Pré-Configurado

| Rede | Senha |
|------|-------|
| `prfelicidade_5G` | `9911121314` |

O NetworkManager conecta automaticamente no boot se o adaptador WiFi estiver disponível.

## Login via console

Após bootar no PS4, na tela de login:
```
Login: ps4
Password: ps4
```

Ou como root:
```
Login: root
Password: ps4
```

## Boot no PS4

1. Conecte o HD no PS4
2. Abra o Payload Guest (3GB+ recomendado)
3. Envie o payload
4. O sistema deve bootar no console (sem interface gráfica)

## Observações

- **NÃO usar** kernel Strawberry 7.0 — trava com luz branca no PS4 Pro Baikal
- **Monitor**: use `video=HDMI-A-1:1280x720@60e` (720p60 + force enable) — **funciona**
- **TV**: use `video=HDMI-A-1:1920x1080@60` (sem `e`) — `@60e` causa tela preta na TV
- **Swap 8GB** é obrigatório após o primeiro boot (o PS4 tem ~4GB de RAM disponível)
- Pacotes críticos estão protegidos via `IgnorePkg` (kernel, mesa, systemd)

## Testado e Validado

| Data | Hardware | Payload | Video Mode | Login | Status |
|------|----------|---------|------------|-------|--------|
| 2026-07-10 | PS4 Pro Baikal (FW 12.52) | 4 GB (Payload Guest) | `1920x1080@60` (TV) | `ps4` / `ps4` | ✅ Funcionou — boot console, rede OK, systemd 258.1-1 |
| 2026-07-10 | PS4 Pro Baikal (FW 12.52) | 4 GB (Payload Guest) | `1280x720@60e` (Monitor LG) | `ps4` / `ps4` | ✅ **Monitor funcional** — 720p60 force enable |

**Detalhes do teste (TV):**
- Kernel: Neocine 5.4.247-neocine-1.1
- Initramfs: better-initramfs v0.9.1
- Rootfs: Arch Base v2 (bootstrap 2026.07.01 + systemd 258.1-1 + base-devel + network + dev tools)
- Video: `video=HDMI-A-1:1920x1080@60` (sem `e`) — TV 1080p OK
- cgroups: `systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes`
- WiFi: `prfelicidade_5G` conectado automaticamente via NetworkManager

**Detalhes do teste (Monitor LG Full HD):**
- Monitor: LG FULL HD (GSM 23519, EDID 1.3, 480×270mm)
- Modo que funcionou: `video=HDMI-A-1:1280x720@60e` (VIC 4, 74.25 MHz)
- Por que 1080p falhou: Bridge PS4 (MN86471A/29) não detecta HPD do monitor a tempo; `ps4_bridge_detect` lê TMONREG@0x7008 bit 3
- Force enable (`e` = `DRM_FORCE_ON`) contorna HPD no DRM core, mas bridge exige modo válido (VIC 4 ou 16)
- 1080p60e falhou pois bridge já desabilitou saída antes do force do DRM; 720p60e passou (clock menor, link training mais fácil)

## Tentativa 4 — Patch kernel para 1080p (2026-07-10) — **FALHOU**
**Kernel**: Neocine 5.4.247 patchado (`ps4_bridge.c`):
- `ps4_bridge_detect()`: retorna `connected` se `connector->force == DRM_FORCE_ON`
- `ps4_bridge_get_modes()`: lê EDID real + `drm_add_edid_modes()`
- `ps4_bridge_mode_valid()`: permite qualquer VIC CEA

**Bootargs**: `video=HDMI-A-1:1920x1080@60e`

**Resultado**: **Sem vídeo**, PS4 desligou sozinho após ~5s

**Análise provável**:
1. `drm_get_edid(connector, NULL)` falha sem DDC ativo (HPD=0 = sem barramento DDC)
2. Bridge desabilita saída antes do DRM core aplicar force
3. PS4 desligou = possível kernel panic silencioso / watchdog

**Regressão**: Voltado para **720p60e (Tentativa 3)** que funciona

## Sugestão de Implementação Futura — Suporte 1080p em Monitores

**Problema**: Bridge PS4 (MN86471A/29) lê HPD via `TMONREG@0x7008` bit 3 em `ps4_bridge_detect()`. Monitores lentos para levantar HPD fazem bridge retornar `disconnected` → saída desligada. Force enable (`video=...@60e`) não ajuda pois bridge roda antes do DRM core.

**Solução (patch kernel Neocine)** em `drivers/gpu/drm/amd/amdgpu/ps4_bridge.c`:

```c
// Em ps4_bridge_detect() — linha ~729:
enum drm_connector_status ps4_bridge_detect(struct drm_connector *connector, bool force)
{
    // ... código existente ...
    
    // NOVO: Se DRM force enable, ignorar HPD
    if (connector->force == DRM_FORCE_ON || connector->force == DRM_FORCE_ON_DIGITAL) {
        DRM_DEBUG_KMS("PS4 bridge: force enable, ignoring HPD\n");
        return connector_status_connected;
    }
    
    // ... resto da detecção HPD existente ...
}

// Em ps4_bridge_get_modes() — linha ~709:
// Remover: drm_connector_update_edid_property(connector, NULL);
// Adicionar leitura de EDID real/firmware e expor todos os modos VIC suportados

// Em ps4_bridge_mode_valid() — linha ~760:
// Permitir todos os VICs do EDID, não só 16 e 4
```

**Resultado esperado**: 1080p60 (`@60e`) funcionaria em qualquer monitor com EDID válido, sem precisar baixar para 720p.