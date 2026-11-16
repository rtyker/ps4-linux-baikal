# WiFi MediaTek — PS4 Baikal (índice da pasta)

**Dispositivo:** WiFi/BT MediaTek (MT6632 / MT7668) via SDIO (`mmc0:0001`), módulo do Slim.
**Driver em uso:** vendor MediaTek `drivers/net/wireless/mediatek/mt76x8/drv_wlan/MT6632/` (árvore do kernel, não é o `mt76` mainline — as mensagens `[wlan][N]` são deste driver).
**Status (2026-11-13):** associa e mantém SSH (`wlan0`), mas **sem arquivo NVRAM de fábrica**: `load manufacture data fail` e `country = 00`. Plano: [`plans/PLANO_DRIVER_WIFI_BAIKAL.md`](plans/PLANO_DRIVER_WIFI_BAIKAL.md).

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `plans/` | Plano de correção (NVRAM BR, MAC do eFUSE, verificação ao vivo) |
| `docs/` | Análise do código-fonte do driver vendor (caminho do NVRAM, gating, versão) |
| `dumps/` | Dumps do eFUSE e de `/proc/net/wlan` e `/proc/net/wireless` coletados no console |
| `scans/` | Linhas `wlan`/`mt7668`/`regulatory` extraídas do dmesg do boot (2026-11-12) |
| `tools/` | `gen_wifi_nvram_initramfs.sh`: gera o initramfs com o NVRAM (RE/diagnóstico, não é script de build) |

**Retomar daqui:** ver a seção "HANDOFF" em `plans/PLANO_DRIVER_WIFI_BAIKAL.md`.

## O que NÃO está aqui, e por quê

Estes itens participam do build oficial, cujos caminhos são fixos. Movê-los quebraria a reprodutibilidade (ver `AGENTS.md`, regra de build via scripts oficiais):

| Item | Onde fica | Motivo |
|---|---|---|
| Firmware `mt7668pr2h.bin` | `distro/firmware_wifi/mediatek/` | copiado para o rootfs por `distro/01-build-image-7.0.sh` (linhas ~683–690) |
| Config do kernel (`CONFIG_MT76_SDIO`, `CONFIG_MT7668`, `EXTRA_FIRMWARE`) | `kernel/00-build-kernel-7.0.sh` | build do kernel |
| `wpa_supplicant@wlan0` (template) | `distro/01-build-image-7.0.sh` (~linha 516) | geração do rootfs |
| Árvore do driver vendor `mt76x8/drv_wlan/MT6632` | `kernel/kernel_build_7.0/` (gitignored) | fonte vem do branch upstream do kernel, não é versionada por nós |

Se a decisão for mover também esses itens, é preciso alterar os caminhos em `01-build-image-7.0.sh` e `00-build-kernel-7.0.sh`. Isso precisa de aprovação, porque mexe no build oficial.

## Dados-chave (evidência ao vivo)

- NVRAM `/data/nvram/APCFG/APRDEB/WIFI`: **ausente** (`/data` não existe no rootfs), confirmado por SSH em 2026-11-13.
- MAC do `wlan0`: `00:0c:43:26:60:48` (origem não verificada). eFUSE bytes `0x004–0x009`: `E8:D8:19:93:CC:AF`.
- País: **BR** (definido pelo usuário). O driver cai em `country = 00` sem o NVRAM.
- Os bytes `0x004–0x009` do eFUSE são o mesmo endereço que o `hci0` reportou antes (`E8:D8:19:93:CC:AE` no BACKLOG), com último byte diferente. Verificar qual é o endereço de BT e qual é o de WiFi.
