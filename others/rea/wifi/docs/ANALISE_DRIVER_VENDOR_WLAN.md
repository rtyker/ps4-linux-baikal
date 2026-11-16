# Análise do driver vendor WLAN (MT6632/MT7668) — caminho do NVRAM

**Base:** leitura direta do código em `kernel/kernel_build_7.0/drivers/net/wireless/mediatek/mt76x8/drv_wlan/MT6632/wlan/` (árvore gitignored, vinda do branch upstream do kernel). Caminhos abaixo são relativos a essa pasta `wlan/`.

## Cadeia de carregamento de manufacture data

1. `os/linux/gl_init.c` ~632–650: `kalCfgDataRead16(...)` lê 2 bytes no offset `sizeof(WIFI_CFG_PARAM_STRUCT) - 2`. Se a leitura der certo, `prGlueInfo->fgNvramAvailable = TRUE` e o MAC, o país e demais campos são lidos do NVRAM para `prRegInfo`.
1b. `common/wlan_lib.c` ~637–642, dentro de `wlanAdapterStart()` (o nome bate com o dmesg): `if (kalIsConfigurationExist(...) == TRUE) wlanLoadManufactureData(...); else DBGLOG(..., "load manufacture data fail")`. É aqui que a mensagem é emitida. Uma versão anterior atribuía isso ao `gl_init.c`, o que estava errado.
1c. `os/linux/gl_kal.c:3769`: `kalIsConfigurationExist()` retorna `fgNvramAvailable` **também no x86** (o ramo `#else` de `CONFIG_X86` retorna o mesmo valor). A leitura do MAC (`gl_kal.c` ~3231) também usa o NVRAM no x86.
2. `os/linux/platform.c:92`: `WIFI_NVRAM_FILE_NAME "/data/nvram/APCFG/APRDEB/WIFI"`.
3. `os/linux/platform.c:314`: `nvram_read()` abre o arquivo com `filp_open` e faz seek no offset. Se o arquivo não existe, retorna erro.
4. `os/linux/platform.c:~449`: `kalCfgDataRead16()` retorna FALSE quando `nvram_read` não lê exatamente 2 bytes.
5. `common/wlan_lib.c:5163`: `wlanLoadManufactureData()`:
   - passo 1: `kalGetConfigurationVersion` e checagem de versão (`CFG_SW_NVRAM_VERSION_CHECK == 1`). Retorna `WLAN_STATUS_FAILURE` se `u2Part1CfgPeerVersion > CFG_DRV_OWN_VERSION`, ou se as versões próprias forem menores que `CFG_DRV_PEER_VERSION`.
   - passo 2: envia TX power ao firmware se `ucTxPwrValid`.
   - passo 3: 5 GHz (`CFG_SUPPORT_NVRAM_5G=1`). Há um `ucEnable5GBand = 1` forçado no código ("Temp Open").
   - passo 4 em diante: envia dados de eFUSE e de NVRAM ao firmware (`CMD_ID_SET_NVRAM_SETTINGS`, com `WIFI_CFG_PARAM_STRUCT`).

## Defines relevantes (`include/config.h`)

| Define | Valor | Efeito |
|---|---|---|
| `CFG_SUPPORT_NVRAM` | 1 | liga a leitura de NVRAM |
| `CFG_NVRAM_EXISTENCE_CHECK` | 1 | marca "NVRAM WARNING" no scan |
| `CFG_SW_NVRAM_VERSION_CHECK` | 1 | rejeita NVRAM com versão incompatível |
| `CFG_SUPPORT_NVRAM_5G` | 1 | carrega dados de 5 GHz |
| `CFG_DRV_PEER_VERSION` | 0x0000 | versão mínima aceita |
| `CFG_DRV_OWN_VERSION` | `(NIC_DRIVER_MAJOR_VERSION << 8) \| …` (linha 338) | versão que o driver espera |

## Leituras de NVRAM no driver

- `kalCfgDataRead16`: MAC (`aucMacAddress`) e código do país (`aucCountryCode`) vêm do NVRAM.
- Sem o arquivo, o MAC lido do NVRAM falha (`fgIsReadError`). O `wlan0` ao vivo tem `00:0c:43:26:60:48`. **Não verifiquei de onde vem esse valor**: a busca por `00:0c:43` no código do driver não achou nada. Dizer que é "o padrão do driver" era suposição minha.
- Sem país, o regdomain cai em `country = 00` (log `rlmDomainSearchRegdomainFromLocalDataBase`). O país que o usuário quer é **BR**, e isso precisa ser passado pelo NVRAM ou por outro caminho.

## Pontos ainda não confirmados

- Layout exato de `WIFI_CFG_PARAM_STRUCT` (tamanho, offsets de `aucMacAddress`, `aucCountryCode`, `u2Part1OwnVersion`, `u2Part2OwnVersion`). Não foi localizado; é o próximo passo do plano.
- Valor de `NIC_DRIVER_MAJOR_VERSION` (para calcular `CFG_DRV_OWN_VERSION`).
- Se o firmware de 2 bytes de checagem (`sizeof - 2`) precisa ser exatamente o último campo do struct.
