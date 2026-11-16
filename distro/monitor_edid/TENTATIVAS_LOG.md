# Log de Tentativas — Monitor LG Full HD no PS4 Linux

**Monitor**: LG FULL HD (GSM 23519, EDID 1.3, 480×270mm, semana 7/2022)
**Suporta nativamente**: VIC 16 (1080p60), VIC 4 (720p60) — ambos dentro das faixas do bridge PS4

---

## Tentativa 1 — 1080p60 sem force (original)
**Bootargs**: `video=HDMI-A-1:1920x1080@60`
**Resultado**: Funciona na TV, **tela preta no monitor**
**Data**: 2026-07-10
**Análise**: Bridge PS4 não detecta HPD do monitor a tempo (TMONREG_HPD não sobe).

---

## Tentativa 2 — 1080p60 com force enable (`e`)
**Bootargs**: `video=HDMI-A-1:1920x1080@60e`
**Resultado**: **Tela preta**, HD ativo mas sem vídeo
**Data**: 2026-07-10
**Análise**: DRM force (`e` = `DRM_FORCE_ON`) ignora detecção de conector, mas bridge PS4 (`ps4_bridge_detect`) roda antes e pode desabilitar a saída se TMONREG_HPD=0. Force do DRM core não sobrescreve bridge driver.

---

## Tentativa 4 — 1080p60 com patch kernel (force enable + EDID + todos VICs)
**Bootargs**: `video=HDMI-A-1:1920x1080@60e`
**Kernel**: Neocine 5.4.247 com patch aplicado em `ps4_bridge.c`:
- `ps4_bridge_detect()`: retorna `connected` se `connector->force == DRM_FORCE_ON`
- `ps4_bridge_get_modes()`: lê EDID real via `drm_get_edid()` + `drm_add_edid_modes()`
- `ps4_bridge_mode_valid()`: permite qualquer VIC CEA (não só 16/4)

**Resultado**: **FALHOU** — sem vídeo, PS4 desligou sozinho após alguns segundos
**Data**: 2026-07-10
**Análise**: Patch aplicado e kernel recompilado, mas:
1. `drm_get_edid(connector, NULL)` pode não funcionar sem DDC ativo (HPD baixo = sem DDC)
2. Bridge pode desabilitar saída antes do DRM core chamar `detect()` com force
3. `drm_add_edid_modes()` precisa de EDID válido; se HPD=0, não há DDC = sem EDID
4. PS4 desligou sozinho = possível kernel panic silencioso ou watchdog

**Regressão**: Revertido para **720p60e (Tentativa 3)** que funciona

---

## Tentativa 3 — 720p60 com force enable (`e`)  ← **SUCESSO ✅**
**Bootargs**: `video=HDMI-A-1:1280x720@60e`
**Resultado**: **FUNCIONOU!** Monitor LG exibe imagem perfeita
**Data**: 2026-07-10
**Racional**: 
- 720p60 = VIC 4, permitido pelo `ps4_bridge_mode_valid` (linha 766)
- Pixel clock 74.25 MHz (metade do 1080p) — link training mais fácil
- Force enable contorna HPD; bridge aceitou modo válido (VIC 4)
- O EDID do monitor tem DTD 4 explicitamente para 720p60

---

## Próximas tentativas planejadas (se 3 falhar)

### Tentativa 4 — 1080p60 com force + DRM debug + poll
```
video=HDMI-A-1:1920x1080@60e drm.debug=0x1f drm_kms_helper.poll=1 drm_kms_helper.delay=10000
```
- Força poll do conector a cada 10s para re-detectar HPD
- Debug alto para ver o que bridge reporta no dmesg

### Tentativa 5 — 480p60 (VIC 1, comentado no bridge mas talvez funcione)
```
video=HDMI-A-1:640x480@60e
```
- Modo mais básico, clock 25 MHz
- Comentado no `ps4_bridge_get_modes` mas bridge pode aceitar

### Tentativa 6 — Injetar EDID via firmware (se bridge não ignora)
1. Copiar `edid.bin` para `/lib/firmware/edid/monitor.bin` na initramfs
2. Bootarg: `drm.edid_firmware=HDMI-A-1:edid/monitor.bin`
- **Risco**: `ps4_bridge_get_modes` chama `drm_connector_update_edid_property(connector, NULL)` — zera EDID e força modo hardcoded. Pode ignorar firmware.

### Tentativa 7 — Patch kernel (recompilar)
Em `ps4_bridge.c:709` (`ps4_bridge_get_modes`):
- Remover `drm_connector_update_edid_property(connector, NULL)`
- Adicionar leitura de EDID firmware/real e expor todos os modos suportados
- Em `ps4_bridge_mode_valid`: permitir todos os VICs do EDID, não só 16/4
- Em `ps4_bridge_detect`: retornar `connector_status_connected` se `connector->force == DRM_FORCE_ON`

---

## Observações técnicas do bridge PS4 (Neocine kernel)

**Arquivo**: `drivers/gpu/drm/amd/amdgpu/ps4_bridge.c`

| Função | Linha | Comportamento |
|--------|-------|---------------|
| `ps4_bridge_detect` | 729 | Lê TMONREG@0x7008; retorna conectado só se `BIT(3)` (HPD) = 1 |
| `ps4_bridge_get_modes` | 709 | Adiciona **apenas** modo 1080p60 hardcoded; zera EDID property |
| `ps4_bridge_mode_valid` | 760 | Aceita **apenas** VIC 16 (1080p60) e VIC 4 (720p60) |
| `ps4_bridge_enable` | 399 | Configura bridge MN86471A/29 via ICC (I2C-over-PCIe) |

**Conclusão**: O bridge é **rigido por design** — não lê EDID, não expõe modos além do hardcoded. Force do DRM (`e`) ajuda se `detect` for chamado depois, mas bridge pode já ter desabilitado a saída.

---

## Como testar cada tentativa
1. Editar `/run/media/anderson/BOOT/bootargs.txt` no PC
2. `sync` e eject HD
3. Conectar HD no PS4
4. Payload ≥ 3GB
5. Verificar: light bar azul = Linux booteou; imagem no monitor?

---

**Última atualização**: 2026-07-10 — Tentativa 3 gravada no HD, pronta para teste.