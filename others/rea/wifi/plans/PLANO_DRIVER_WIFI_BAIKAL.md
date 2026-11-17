# Plano — WiFi MediaTek (NVRAM de fábrica, país BR)

**Atualizado:** 2026-11-13
**Acesso:** SSH `root@192.168.6.128` disponível (WiFi). Ethernet cabeada sem link (PHY mudo, fora deste plano).
**Decisões do usuário:** país = **BR**. SSH liberado para verificação ao vivo.

## Objetivo

Carregar a configuração de fábrica do WiFi (país, MAC, potência e 5 GHz) para o driver vendor MT6632/MT7668 deixar de usar os defaults. Critério de sucesso é **efeito**, não ausência de mensagem: o regdomain deve sair de `country = 00` e o MAC deve ser o real.

## Estado confirmado ao vivo (2026-11-13, leitura somente)

| Item | Valor | Evidência |
|---|---|---|
| NVRAM `/data/nvram/APCFG/APRDEB/WIFI` | **ausente** (`/data` não existe) | `ls` via SSH |
| `load manufacture data fail` | presente, em `3.29 s` | `dmesg` |
| `Cannot find the correct RegDomain. country = 00` | presente, em `3.47 s` | `dmesg` |
| MAC do `wlan0` | `00:0c:43:26:60:48` (origem **não verificada**; não é string do driver) | `/sys/class/net/wlan0/address` |
| MAC no eFUSE (bytes `0x004–0x009`) | `E8:D8:19:93:CC:AF` | `/proc/net/wlan/efuse_dump` |
| `hci0` (Bluetooth) | não encontrado neste boot | `/sys/class/bluetooth/` |
| Estado do link | `wlan0` UP, associado, SSH funcionando | `ip -br link`, `/proc/net/wireless` |

**Ponto a esclarecer:** o MAC do eFUSE e o `hci0` do BACKLOG (`E8:D8:19:93:CC:AE`) diferem só no último byte. É preciso confirmar qual é o endereço do WiFi e qual é o do BT antes de gravar qualquer MAC.

## Fase 0 — Leituras restantes (somente leitura, sem risco)

1. Procurar qualquer cópia do arquivo WIFI no sistema: `find / -xdev -iname '*wifi*' -path '*nvram*' 2>/dev/null` e `find / -xdev -iname 'WIFI*' 2>/dev/null | head`.
2. Ver se há partição do Orbis com dados de NVRAM: revisar os montados por `monta_particao.sh` (`sda27`, `sda29`, `sda25`) procurando `APCFG`/`APRDEB`. Isso é leitura, sem escrita.
3. Ler `dmesg` completo do boot atual com `dmesg | grep -i wlan` para comparar com o dump de 2026-11-12 (`others/rea/wifi/scans/wlan_dmesg_boot_20261112.txt`).
4. Confirmar o endereço do BT: `hciconfig -a` ou `btmgmt info` (se o módulo estiver carregado).

## Fase 1 — Descobrir o layout do NVRAM (somente leitura no código)

5. Localizar `WIFI_CFG_PARAM_STRUCT` na árvore `kernel/kernel_build_7.0/drivers/net/wireless/mediatek/mt76x8/drv_wlan/MT6632/wlan/` (`grep -rn "WIFI_CFG_PARAM_STRUCT" include/`).
6. Extrair tamanho e offsets de `aucMacAddress`, `aucCountryCode`, `u2Part1OwnVersion`, `u2Part2OwnVersion`.
7. Calcular `CFG_DRV_OWN_VERSION` a partir de `NIC_DRIVER_MAJOR_VERSION` (`include/config.h:338`), para garantir que o arquivo passe em `CFG_SW_NVRAM_VERSION_CHECK`.
8. Documentar o layout em `others/rea/wifi/docs/`.

## Fase 2 — Teste controlado com arquivo mínimo (no PS4, por SSH)

9. Gerar o arquivo `WIFI` com um script versionado em `distro/scripts/` (não à mão). Campos: versão correta, MAC confirmado na Fase 0, `aucCountryCode = "BR"`, demais campos com defaults. O script deve validar tamanho e versão, e falhar alto em caso de erro.
10. Copiar para `/data/nvram/APCFG/APRDEB/WIFI` por SSH. Criar o diretório antes (`mkdir -p`). Não tocar no HD do Orbis.
11. Reiniciar o `wlan0` (ou o módulo) e verificar: `load manufacture data fail` não aparece mais, o país deixa de ser `00`, e o MAC bate com o arquivo.
12. Se algo piorar (WiFi não associa, erro novo), remover o arquivo e reiniciar. O SSH via WiFi precisa continuar funcionando, porque é o único acesso administrativo além do UART.

## Fase 3 — Integração reproduzível

13. Incluir a geração do arquivo no `distro/01-build-image-7.0.sh`, com `mkdir -p /data/nvram/APCFG/APRDEB` no rootfs e cópia do arquivo gerado.
14. Entradas (país, MAC) vêm de variáveis explícitas. Sem valor padrão silencioso.
15. Registrar no `BACKLOG.md` e em `LICOES_APRENDIDAS.md`, e só então commitar (quando o usuário pedir).

## Fase 4 — Erros secundários (depois da Fase 2)

16. `Array index out of bound, ucBssIndex=4` e `P2P_ROLE` (`wlanBindBssIdxToNetInterface`): verificar se somem com o NVRAM.
17. `NO Res CMD TYPE[1] ID[0x11]` e `MailBox Status = 0x0003005A`: idem.

## Riscos

- **Regulatório:** a potência e os canais dependem do país. Com **BR** fixo, o regdomain deve ser o brasileiro. Confirmar depois no `iw reg get` (o `iw` não está no rootfs; checar `/proc` ou `dmesg`).
- **MAC errado:** gravar um MAC que colide com o do BT ou de outro dispositivo. Por isso a Fase 0 vem antes da Fase 2.
- **Falsa correção:** o driver pode aceitar o arquivo e ignorar campos por versão. O critério é o regdomain e o MAC reais.
- **Acesso:** o WiFi é o acesso administrativo. Testar uma mudança por vez e manter a tag `20260730-sata-polling-fase-ab` pronta para rollback.

## Referências externas

- [linux-ps4 (meerzulee)](https://github.com/meerzulee/linux-ps4): build 5.4-baikal com WiFi mt7668 funcionando.
- [feeRnt/ps4-linux-12xx](https://github-users.yhajoa.workers.dev/feeRnt/ps4-linux-12xx): driver vendor MT7668 para 5.4.247.
- [Forum LibreELEC, MT7668](https://forum.libreelec.tv/thread/21213-mediatek-mt7668-wifi-chip/): relatos de porte do driver.
- [Google coral, mt7668-wifi-mod](https://coral.googlesource.com/mt7668-wifi-mod/+/refs/heads/master/chips/mt7668.c): referência do chip.
- [PSDevWiki, PS4 Wireless](https://psdevwiki.com/ps4/Wireless): não foi possível ler (HTTP 403). Traz o nome do firmware de fábrica `C0020001` em flash, que deve ser conferido quando acessível.

## Achados da implementação (2026-11-13)

- **Layout confirmado** em `include/CFG_Wifi_File.h`: struct `WIFI_CFG_PARAM_STRUCT` tem **512 bytes**. `u2Part1OwnVersion`@0, `u2Part1PeerVersion`@2, `aucMacAddress`@4 (6 bytes), `aucCountryCode`@10 (2 bytes), `u2Part2OwnVersion`@256, `u2Part2PeerVersion`@258. `kalCfgDataRead16` lê os últimos 2 bytes (@510), então o arquivo precisa ter 512 bytes.
- **Versão:** `CFG_DRV_OWN_VERSION` = `(2<<8)|0` = `0x0200` (`os/version.h`: 2.0). Usado `OWN=0x0200` e `PEER=0x0000`, que passam em `CFG_SW_NVRAM_VERSION_CHECK`.
- **Ordem de boot (dmesg ao vivo):** o probe do WiFi acontece em `3.28 s`, **antes** de `Run /init` (`3.43 s`) e da montagem do rootfs `/dev/sdb2` (`5.82 s`). Um arquivo no rootfs **nunca seria visto** pelo driver. O arquivo precisa estar no **initramfs**, que é desempacotado antes.
- **Formato do initramfs:** o `initramfs.cpio.gz` da partição BOOT (`sdb1`) é na verdade **cpio newc sem compressão** (magic `070701`). Dá para acrescentar um segundo archive cpio ao final, e o kernel desempacota os dois em sequência. Não é preciso tocar em `01-build-image-7.0.sh`.
- **Artefato gerado (só no host, nada gravado no PS4):** `scratchpad/wifi/initramfs.wifi.cpio` = `initramfs.orig.cpio.gz` (15 155 922 bytes, sha256 `333ae571…4846ca`) + fragmento com `data/nvram/APCFG/APRDEB/WIFI`. Extração do fragmento verificada byte a byte.
- **Conteúdo do WIFI:** `OWN 0x0200`, MAC `E8:D8:19:93:CC:AF` (eFUSE 0x004–0x009, a confirmar), país `BR`, o resto zerado. `ucTxPwrValid`=0, então o driver não sobrescreve potência com valores zerados.

**Pendente para aplicar:** trocar `sdb1/initramfs.cpio.gz` no HD e reiniciar pelo kexec. Isso exige que você faça o power cycle e confirme a troca. O arquivo original deve ser guardado como backup no próprio BOOT antes da troca.

## HANDOFF — retomar daqui

**Estado em 2026-11-13: pausado, nada aplicado no PS4.** O WiFi continua sem NVRAM e com país `00`. SSH via WiFi está funcionando.

**Já feito:**
- Layout do struct (512 bytes), versão e ordem de boot confirmados (seção "Achados").
- Gerador reproduzível: `others/rea/wifi/tools/gen_wifi_nvram_initramfs.sh <orig> <saida> [MAC] [PAIS]`. Testado: o arquivo WIFI gerado é idêntico ao anterior. O archive inteiro não é byte a byte igual, porque o cabeçalho cpio guarda inode e mtime. Isso é esperado e não afeta o conteúdo.
- Original da BOOT: `sdb1/initramfs.cpio.gz`, sha256 `333ae5719c27d9179f09516ba8fbd0fdfbfb11b44018ad5817f93790eb4846ca`, 15 155 922 bytes.

**Para retomar (próxima sessão):**
1. Recopiar o original do PS4 (somente leitura): `mount -o ro /dev/sdb1 /mnt/ps4_boot_ro` (subdir dedicado, nunca `/mnt`), `cat .../initramfs.cpio.gz`, `umount`. Conferir o sha256 acima.
2. Gerar o artefato com o script. Se o MAC do BT/WiFi tiver sido confirmado, passar o MAC certo como 3º argumento.
3. **Pedir confirmação do usuário** antes de gravar na BOOT. Antes da troca, guardar backup dentro da própria BOOT (`initramfs.cpio.gz.bak-wifi`).
4. Trocar o arquivo e reiniciar pelo kexec (power cycle manual pelo usuário).
5. Verificar: `dmesg | grep -E "manufacture|RegDomain"` e `ls /proc/net/wlan`. Critério: sem `load manufacture data fail` e sem `country = 00`.
6. Se o boot falhar, restaurar o backup pelo mesmo caminho.

**Pendências abertas:** confirmar MAC do WiFi versus BT (`E8:D8:19:93:CC:AF` versus `…AE`); layout dos campos de potência, que ficaram zerados de propósito.

## Retomada planejada (2026-11-17) — passos guardados, a decidir com o usuário depois

**Estado reconferido ao vivo em 2026-11-17 (kernel `20261117-dp-diag2`):** continua tudo sem NVRAM. `/data` não existe; `wlanAdapterStart: load manufacture data fail` aos 2,96 s; `country = 00` (`iw reg get`: `country 00: DFS-UNSET`); `Array index out of bound, ucBssIndex=4` 2 vezes. MAC do `wlan0` = `00:0c:43:26:60:48` (origem ainda desconhecida); eFUSE `0x004–0x009` = `E8:D8:19:93:CC:AF`. O `hci0` existe, mas o endereço do BT **não foi relido hoje** (`bluetoothctl` travou); o BACKLOG registrou `…CC:AE` antes, o que sugere que não colide com o do WiFi. O `initramfs` atual do HD continua cpio newc puro (`070701`), então o método de acrescentar um segundo archive vale.

**Passos propostos (nada executado):**
1. Gerar o `initramfs` com o NVRAM a partir do `initramfs` da tag atual: `others/rea/wifi/tools/gen_wifi_nvram_initramfs.sh <initramfs_original> <saida> E8:D8:19:93:CC:AF BR`.
2. Gravar como **tag nova de teste** (sugestão `20261117-wifi-nvram`): mesmo `bzImage`/`config`/`bootargs` da tag em uso, só o `initramfs` trocado, via `deploy-boot-7.0.sh` com o HD no PC, conferindo o MD5. O `initramfs` da tag boa não é tocado, então o rollback é um `deploy-boot` simples.
3. Boot e verificação: `dmesg | grep -E "manufacture|RegDomain"` e `iw reg get`; critério: sem `load manufacture data fail`, sem `country = 00`, MAC igual ao do arquivo, e o SSH via WiFi continua funcionando.
4. Se o WiFi piorar: `deploy-boot` da tag anterior.

**Antes de executar, o usuário precisa decidir:** (a) confirmar o país `BR`; (b) confirmar o MAC do eFUSE `…CC:AF` para o `wlan0`; (c) reler o endereço do BT (por `hciconfig` ou `btmgmt`, com timeout) para garantir que não colide.

## Itens que permanecem no lugar (build)

Ver `others/rea/wifi/INDEX.md`, seção "O que NÃO está aqui".
