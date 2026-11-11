# O Que Falta — PS4 Linux Kernel 7.0 Baikal

Atualizado: 2026-07-17

## Funcional

- [x] Boot kernel no PS4 RTYKER (Baikal B1)
- [x] Vídeo (HDMI via adaptador HDMI-VGA)
- [x] WiFi (MT7668 SDIO, WPA2, DHCP)
- [x] Telnet (initramfs debug)
- [x] USB (xHCI func 7)
- [x] SATA detecta Toshiba (func 7, AHCI 6Gbps)
- [x] Bluetooth (hci0, firmware OK)
- [x] Áudio HDMI (snd_hda_intel detecta)
- [x] PS4 platform drivers (led, fan, buzzer)
- [x] Baikal PCIe glue + IRQ domains (todas 8 funções)
- [x] Ethernet GBE Baikal (driver `mts.ko`, interface `eth0`, MAC real `2c:cc:44:3f:69:5f`, netconsole ativo no boot)

## Pendente

### 1. Ethernet mts (Sony MTS GBE) — ✅ RESOLVIDO (2026-07-22)
- **Status:** Resolvido com o driver nativo `mts.ko` (Sony MTS). Interface `eth0` registrada, anéis DMA programados, endereço MAC lido da SPM e auto-carregamento no boot em `stage=4` ativado.
- **Netconsole:** Ativado e transmitindo via UDP por padrão.

### 2. SATA Interno (Toshiba MQ04ABF100) — NÃO RESOLVIDO
- Drive cai após ~31s — HIPM/DIPM power management mata o drive
- Bootargs atuais **não incluem** `libata.fpm=0` (fix recomendado no INTERNAL_SATA_FIX.md)
- **Próximo:** Adicionar `libata.fpm=0` ao bootargs e re-testar. Se não resolver, rebuild com `ATA_HORKAGE_NOLPM` no quirk do Toshiba.
- **Prioridade:** Média (rootfs está no USB, mas acesso ao HD interno é útil)

### 3. GPU amdgpu GFX/CP — FALHA -110
- `ring gfx test failed (-110)` em `gfx_v7_0` (Command Processor)
- Firmware gladius real injetado via kexec, mas CP não responde
- SDMA funciona, GMC funciona, VRAM (1024M) ok
- **Próximo:** Investigar se o firmware está sendo injetado corretamente (`/lib/firmware/amdgpu/gladius_*.bin` via telnet). Verificar se é problema de variant (gladius vs liverpool CP microcode).
- **Prioridade:** Média (vídeo funciona via fallback DRM, mas aceleração 3D não)

### 4. Rootfs Completo (Systemd) — NÃO TESTADO
- Initramfs debug roda solto, nunca faz pivot pro rootfs
- Rootfs Arch no USB (sdb2, label `psxitarch`) nunca foi montado no 7.0
- **Próximo:** Depois que SATA+Ethernet estiverem estáveis, testar boot completo até systemd login
- **Prioridade:** Baixa (precisa dos items 1-3 antes)

### 5. WiFi Manufacture Data — WARNING
- `wlanAdapterStart: load manufacture data fail` — NVRAM `/data/nvram/APCFG/APRDEB/WIFI` ausente
- WiFi conecta mesmo assim (usa defaults do eFUSE), mas pode ter potência/canal subótimo
- **Prioridade:** Baixa (funcional sem fix)

### 6. amdgpu áudio HDMI — NÃO TESTADO
- `snd_hda_intel` detecta o codec em `00:14.1` (func 1 audio)
- `amdgpu.audio=1` nos bootargs
- Áudio pode não funcionar se amdgpu GFX não inicializou
- **Prioridade:** Baixa
