---
name: kernel-7-0-wifi-manufacture-data-pendente
description: "PENDENTE (baixa prioridade): driver MT7668/MT6632 reporta 'load manufacture data fail' e country code 00 (regdomain não encontrado). Causa raiz CONFIRMADA no código-fonte 2026-07-22: falta o arquivo NVRAM /data/nvram/APCFG/APRDEB/WIFI (512 bytes, WIFI_CFG_PARAM_STRUCT, país no offset 10)."
metadata:
  node_type: memory
  type: project
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

Na sessão de 2026-07-16, o usuário definiu a ordem de prioridade: 1) dump/uso do firmware gladius real (ver [[kernel-7.0-gladius-firmware-ausente]]), 2) Ethernet sky2/eth0, e pediu para **anotar este item (WiFi manufacture data) para depois**, sem trabalhar nele agora.

**Sintoma:** mesmo com o firmware MT7668 completo embutido via `CONFIG_EXTRA_FIRMWARE` (`EEPROM_MT7668*.bin`, `mt7668_patch_e1/e2_hdr.bin`, `WIFI_RAM_CODE*`, `wifi.cfg`), o driver `wlan` reporta no dmesg: `wlanAdapterStart: load manufacture data fail`, `mtk_reg_notify:(RLM WARN) County Code is not assigned. Use default WW.` e `rlmDomainSearchRegdomainFromLocalDataBase(): Cannot find the correct RegDomain. country = 00.` (reconfirmado 2026-07-22 via `dmesg.log` capturado com `capture_dmesg.py`, linhas 854/858/859). **Não é fatal** — o WiFi conecta mesmo assim (confirmado na tag `20260716-wifissh`, ver [[kernel-7.0-wifissh-sucesso]]), usando defaults do eFuse do chip em vez do NVRAM ausente.

**CAUSA RAIZ CONFIRMADA 2026-07-22 (lendo o código-fonte real em `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/net/wireless/mediatek/mt76x8/drv_wlan/MT6632/wlan/`):**
- `os/linux/platform.c:92`: `#define WIFI_NVRAM_FILE_NAME "/data/nvram/APCFG/APRDEB/WIFI"` — esse arquivo não existe no rootfs (5.4 nem 7.0).
- `kalCfgDataRead16()` (`platform.c:449`) chama `nvram_read()` nesse caminho; falha porque o arquivo não existe.
- `glLoadNvram()` (`os/linux/gl_init.c:632`) só seta `prGlueInfo->fgNvramAvailable = TRUE` se a primeira leitura (do último word da struct) funcionar; senão fica `FALSE` (`gl_init.c:744`).
- `kalIsConfigurationExist()` (`os/linux/gl_kal.c:3769`) só retorna `fgNvramAvailable`.
- `wlan_lib.c:641`: se `kalIsConfigurationExist()==FALSE`, pula `wlanLoadManufactureData()` e loga exatamente o warning visto — daí o country code nunca é carregado e fica `00`.
- **Struct exata** (`include/CFG_Wifi_File.h:261`, `WIFI_CFG_PARAM_STRUCT`/`MT6620_CFG_PARAM_STRUCT`), tamanho fixo de **512 bytes** (tem `DATA_STRUCT_INSPECTING_ASSERT(sizeof(...)==512)` no próprio header):
  ```
  offset 0   : u2Part1OwnVersion   (2 bytes)
  offset 2   : u2Part1PeerVersion  (2 bytes)
  offset 4   : aucMacAddress[6]
  offset 10  : aucCountryCode[2]   <- 2 bytes ASCII do país (ex: "BR")
  offset 12+ : TX power / aucEFUSE[144] / band-edge / regdomain subbands / ...
  ```

**Como aplicar (fácil mecanicamente, mas com um risco real a considerar):** criar um arquivo binário de exatamente 512 bytes em `/data/nvram/APCFG/APRDEB/WIFI` (criar os diretórios), escrever o país nos bytes 10-11, persistir no rootfs via `01-build-image-7.0.sh`. Testável ao vivo via telnet sem rebuild de kernel (é dado lido em runtime). **Risco:** os outros ~500 bytes da struct não são inertes — são calibração real (`rTxPwr`, `aucEFUSE[144]`, band-edge power, regdomain subbands). Zerar tudo e só preencher o country code pode fazer o driver passar a confiar em campos zerados (ex: `ucTxPwrValid`) em vez dos defaults seguros que hoje vêm do eFuse do chip — podendo **piorar** potência/calibração em vez de só corrigir o regdomain. O eFuse real já foi dumpado (`hardware_ps4_real/01_wlan_efuse_dump_full.txt`, 960 bytes) e é a fonte certa para popular esses campos com calibração real, em vez de zeros arbitrários, se algum dia isso for feito.

**Quando retomar:** ainda baixa prioridade — só se (a) o warning causar problema prático real (canal/potência errados, banda 5GHz indisponível), ou (b) o usuário pedir explicitamente. Se retomar, o trabalho de descoberta já está pronto (offsets e caminho do arquivo confirmados no código-fonte); falta só decidir se popula os campos de calibração com o eFuse real ou aceita o risco de zerá-los.
