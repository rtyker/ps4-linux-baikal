# Análise do Monitor — LG Full HD (Teste PS4 Linux)

Monitor em teste para PS4 Linux (arch_base_v2). Capturado conectado ao PC em `/sys/class/drm/card1-HDMI-A-1/` no dia 2026-07-10.

---

## Identificação

| Campo | Valor |
|-------|-------|
| **Marca / Modelo** | LG FULL HD |
| **EDID Vendor Code** | GSM (LG) |
| **EDID Model Code** | 23519 (0x5BDF) |
| **Serial Number** | 207AZDB15770 |
| **Serial numérico (EDID)** | 39770 (0x9B5A) |
| **Fabricação** | Semana 7 de 2022 |
| **EDID Version** | 1.3 (com CTA-861 Ext Block rev 3) |
| **Tamanho físico** | 480mm × 270mm (≈ 23.0" diagonal) |
| **Conexão** | HDMI (conector HDMI-A) |
| **Bright/Gamma** | Gamma 2.20 |
| **Colorimetry** | RGB, YCbCr 4:4:4, YCbCr 4:2:2 |
| **Source Physical Address (HDMI)** | 1.0.0.0 |

---

## DPMS / Power

- Standby, Suspend, Off suportados (DPMS levels)
- Estado atual: **On** (conectado e ativo)

---

## Faixas de operação (Display Range Limits)

| Parâmetro | Min | Max |
|------------|-----|-----|
| Vertical (Hz) | 56 | 75 |
| Horizontal (kHz) | 30 | 85 |
| Dot clock (MHz) | — | 180 |

⚠️ **Importante**: Hsync máximo = 85 kHz, Vsync máximo = 75 Hz. **Não aceita 1080p@75** (apesar de ter DTD 1080p@74.97 — borderline). Modo 1080p@60 (67.5 kHz) está dentro da faixa com folga.

---

## Modos suportados (incluindo CEA/VIC)

### Modos CEA (HDMI) — via CTA-861 Video Data Block

| VIC | Resolução | Hz | H (kHz) | PixelClk (MHz) | Observação |
|-----|-----------|-----|---------|----------------|------------|
| **16** | **1920×1080** | **60.000** | **67.500** | **148.500** | **Nativo — preferido pelo PS4** |
| 4 | 1280×720 | 60.000 | 45.000 | 74.250 | Modo seguro (PS4 suporta) |
| 3 | 720×480 | 59.940 | 31.469 | 27.000 | NTSC |
| 1 | 640×480 | 59.940 | 31.469 | 25.175 | VGA |
| 18 | 720×576 | 50.000 | 31.250 | 27.000 | PAL |
| 31 | 1920×1080 | 50.000 | 56.250 | 148.500 | Europa |
| 19 | 1280×720 | 50.000 | 37.500 | 74.250 | Europa |

### Detailed Timings (DTD — declarados individualmente)

| DTD | Resolução | Hz | H (kHz) | PixelClk | Hblank total | Vblank total |
|-----|-----------|------|---------|----------|---------------|--------------|
| 1 | 1920×1080 | 60.00 | 67.50 | 148.50 MHz | 1920+88+44+148=2200 | 1080+4+5+36=1125 |
| 2 | 1920×1080 | 60.00 | 67.50 | 148.50 MHz | mesma (réplica do DTD 1) |
| 3 | 1920×1080 | 74.97 | 83.89 | 174.50 MHz | 1920+48+32+80=2080 | 1080+3+5+31=1119 |
| 4 | 1280×720 | 60.00 | 45.00 | 74.250 MHz | 1280+110+40+220=1650 | 720+5+5+20=750 |
| 5 | 720×480 | 59.94 | 31.47 | 27.000 MHz | NTSC timing |

⚠️ O DTD 3 (1080p@74.97) usa 83.89 kHz Hsync — **próximo do limite de 85 kHz** do monitor. Arriscado no PS4 se a ponte DP→HDMI não conseguir pullado a 83.89 kHz com timings instáveis. **Use 60 Hz**.

---

## Modos DMT (VESA) — Legacy (não relevantes para PS4)

640×480, 800×600, 1024×768, 1280×1024, 1600×900, 1680×1050, etc. (PC padrão)

---

## Compatibilidade com PS4 Linux (kernel Neocine 5.4.247)

### Análise técnica do driver ps4_bridge.c (do kernel Neocine)

O PS4 tem um **bridge DP→HDMI** dedicado (Panasonic MN86471A para CUH-1xxx, MN864729 para CUH-2xxx+), gerenciado em:
```
drivers/gpu/drm/amd/amdgpu/ps4_bridge.c
```

**Modos hardcoded** expostos via `ps4_bridge_get_modes()` (linha 709):
- **VIC 16 — 1920×1080@60Hz** (declarado, ativo)
- VIC 4 — 1280×720@60Hz (declarado, mas comentado no fonte — só 1080p é exposto)
- VIC 1 — 640×480@60Hz (declarado, mas comentado)

**`ps4_bridge_mode_valid()`** (linha 760) só permite VIC 16 e VIC 4:
```c
if (!vic || (vic != 16 && vic != 4)) {
    return MODE_BAD;
}
```

### Detecção do conector via HPD

`ps4_bridge_detect()` (linha 729) lê registrador TMONREG @ 0x7008 e só retorna "conectado" se bit `TMONREG_HPD (BIT(3))` estiver em 1. Se o monitor não levantar HPD suficientemente rápido na inicialização do DRM, o conector é declarado desconectado → **tela preta**.

### Veredito de compatibilidade

| Requisito PS4 bridge | Monitor LG | Status |
|----------------------|------------|--------|
| VIC 16 (1080p60) | ✅ Nativo, DTD 1 e 2 | **Perfeito** |
| VIC 4 (720p60) — fallback | ✅ Nativo, DTD 4 | **Perfeito** |
| HDMI HPD pin | (presumido) — padrão HDMI | ✅ |
| Dot clock ≤ 148.5 MHz | ✅ (limite 180 MHz) | ✅ |
| Hsync 67.5 kHz (1080p60) | ✅ (faixa 30–85 kHz) | ✅ |
| Vsync 60 Hz | ✅ (faixa 56–75 Hz) | ✅ |

**Conclusão**: O monitor **teoricamente suporta 100%** o modo 1080p60 que o bridge do PS4 exige. Se o Linux não inicializa nele, **não é incompatibilidade de modo** — é, na minha maioria das vezes, falha de HPD timing ou handshake HDCP.

---

## Bootargs para teste no PS4 (em ordem de preferência)

### Teste A — Forçar conector (sufixo `e`)
Especifica `video=HDMI-A-1:1920x1080@60e` — o kernel DRM define `DRM_FORCE_ON` em `drm_modes.c:1493` ignorando a detecção HPD em `drm_probe_helper.c:422`. Mantém 1080p nativo.

```
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0 console=ttyS0,115200n8 console=tty0 video=HDMI-A-1:1920x1080@60e quiet amdgpu.audio=1 usbcore.autosuspend=-1 amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1 systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes
```

### Teste B — Fallback para 720p (ainda VIC 4, aceito pelo bridge)
```
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0 console=ttyS0,115200n8 console=tty0 video=HDMI-A-1:1280x720@60e quiet amdgpu.audio=1 usbcore.autosuspend=-1 amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1 systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes
```

### Teste C — Adicionar DRM debug (caso A e B falhem, capturar diagnóstico pela serial)
```
... drm.debug=0xff video=HDMI-A-1:1920x1080@60e ...
```
Logs `dmesg | grep -i hdmi`, `dmesg | grep -i bridge`, `dmesg | grep -i hpd` mostrarão se o `ps4_bridge_detect` está falhando (`could not read TMONREG`) ou se está detectado mas `ps4_bridge_enable` falhando.

### Teste D — Forçar polling HPD longo (se monitor lento para levantar HPD)
```
... drm_kms_helper.poll=1 video=HDMI-A-1:1920x1080@60 ...
```

⚠️ **Não usar**`@60e` na TV Samsung/LG que detectou a prova — confirmado no `boot_referencia/README.md` que `@60e` causa tela preta em algumas TVs. Use só em monitor.

---

## Hipóteses sobre por que TV funciona e monitor não

1. **HPD timing**: TVs levantam HPD dentro de ~100ms do HS signal stability; alguns monitores LG requerem estágio HDCP completo. O bridge PS4 tem timeout curto (não temos o ms exato — é hardcoded no ICC firmware proprietário).

2. **HDCP**: Bridge PS4 tem reset de HDCP em `pre_enable` (linha 384: `TSRST_HDCPSRST`), mas em `ps4_bridge_enable` ele desabilita HDCP explicitamente (`HDCPEN_ENC_DIS`). Monitores mais novos às vezes recusam exibir se HDCP estiver habilitado pela source mas falto handshake; TVs geralmente sempre exibem anyway.

3. **EDFifth (`drm_connector_update_edid_property(connector, NULL)`)**: O bridge do PS4 intentionalmente não expõe o EDID do monitor ao DRM. Significa que mesmo que HDMI negocie via EDID com sucesso, o kernel DRM não sabe as capacidades do monitor — só confia no modo hardcoded 1080p60. **Isto não deveria causar tela preta sozinho**.

4. **TMDS link training**: Os comandos de inicialização no MN864729 (CUH-2xxx+) incluem waits por DP lane status (`cq_wait_set 0x60f8 0xff` etc.). Se TMDS link não treinar com o monitor (impedância/cabo), ele falagar e ficará preto. Tente cabo HDMI **curto e espessura** (22 AWG ou melhor), preferencialmente HDMI 2.0.

---

## Comandos para reproduzir a captura do EDID (em qualquer PC Linux)

```bash
# Salvar EDID bruto
sudo cat /sys/class/drm/card1-HDMI-A-1/edid > edid.bin

# Decodificar
edid-decode edid.bin            # saída formatada instalar: pacman -S edid-decode)
                               # Pacote edid-decode não estava disponível no repo no scan mas é o nome usual

# Ver modos reconhecidos pelo kernel
cat /sys/class/drm/card1-HDMI-A-1/modes

# Ver status do conector (connected/disconnected)
cat /sys/class/drm/card1-HDMI-A-1/status

# Confirmar qual i2c bus para DDC
ls -la /sys/class/drm/card1-HDMI-A-1/ddc
```

---

## Arquivos relacionados

| Arquivo | Descrição |
|---------|-----------|
| `monitor_edid/edid.bin` | EDID bruto do monitor (256 bytes, EDID 1.3 + CTA-861 ext) |
| `boot_referencia/bootargs.txt` | Bootargs atual (`@60` sem `e`) — validado para TV |

---

## Edição EDID (se forem precisar dum EDID falso)

O EDID armazenado já contém nativamente os V ICs 16 e 4, então **não há necessidade de injetar EDID falso**.
Se surgiu um caso de querer patched (por ex. forçar só o 720p em monitores problemáticos), pode usar `frontools-edid` ou `edid-generator` para criar um `.bin` e injetá-lo em `/lib/firmware/edid/<nome>.bin` + bootarg `drm.edid_firmware=HDMI-A-1:edid/<nome>.bin`.

⚠️ **Limitação importante**: o `ps4_bridge_get_modes` chama `drm_connector_update_edid_property(connector, NULL)` (passa NULL!), apagando qualquer EDID fornecido. Significa que **mesmo com bootarg `drm.edid_firmware`, o bridge não vai respeitar o EDID**.
Para usar EDID custom seria preciso modificar `ps4_bridge.c:709` para ler o EDID via `drm_get_edid` e adicionar os modos resultantes na lista. Esse hack não é necessário para o LG Full HD (já suporta 1080p60 nativamente).

---

## Próximos passos

1. Testar **bootargs Teste A** no PS4 com o monitor LG (deve ser a primeira tentativa).
2. Se falhar, tentar **Teste B** (720p).
3. Se ainda falhar, capturar `dmesg` via SSH (já configurado no rootfs) — usar o **Teste C** para ver onde exatamente o bridge falha.
4. Verificar o cabo HDMI (curto/certificado 2.0) — qualidade de TMDS link training é crítica.

---

## Hex dump EDID completo (256 bytes)

```
00 ff ff ff ff ff ff 00 1e 6d df 5b 5a 9b 00 00
07 20 01 03 80 30 1b 78 ea 31 35 a5 55 4e a1 26
0c 50 54 a5 4b 00 71 4f 81 80 95 00 b3 00 a9 c0
81 00 81 c0 90 40 02 3a 80 18 71 38 2d 40 58 2c
45 00 e0 0e 11 00 00 1e 00 00 00 fd 00 38 4b 1e
55 12 00 0a 20 20 20 20 20 20 00 00 00 fc 00 4c
47 20 46 55 4c 4c 20 48 44 0a 20 20 00 00 00 ff
00 32 30 37 41 5a 44 42 31 35 37 37 30 0a 01 9c

02 03 12 b1 47 90 04 03 01 12 1f 13 65 03 0c 00
10 00 02 3a 80 18 71 38 2d 40 58 2c 45 00 e0 0e
11 00 00 1e 2a 44 80 a0 70 38 27 40 30 20 35 00
e0 0e 11 00 00 1e 01 1d 00 72 51 d0 1e 20 6e 28
55 00 e0 0e 11 00 00 1e 8c 0a d0 8a 20 e0 2d 10
10 3e 96 00 e0 0e 11 00 00 18 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 63
```

- Checksum bloco 0: `0x9c` ✓
- Checksum bloco 1 (CTA): `0x63` ✓
