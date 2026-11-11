# Controle de Tentativas — Kernel 7.0 Baikal (2026-07-16)

Registro de cada build/tag testada no HD, para não repetirmos testes que já
sabemos o resultado. Tags ficam em `boot_referencia/` como
`bzImage-7.0-<TAG>`, `initramfs-7.0-<TAG>.cpio.gz`, `bootargs-7.0-<TAG>.txt`.
Deploy só-boot via `./deploy-boot-7.0.sh <TAG>` (não mexe no rootfs).

## Linha do tempo

### 1. `bzImage` original do dia (compilado 09:47, antes de qualquer fix)
- **Firmware GPU**: gladius_*.bin vazios (0 bytes, fallback `touch` do build.sh)
- **Ethernet**: CONFIG_SKY2=m (módulo, não builtin)
- **Bootargs**: sem `netconsole=`
- **Initramfs**: nenhum (não testado com debug)
- **RESULTADO**: tela preta, HD sem nenhuma escrita (nem `bootlog.txt`, nem rootfs). Boot não chegou nem perto de montar root. **Zero visibilidade.**

### 2. Tag `20260716-sky2builtin`
- **Mudança**: `CONFIG_SKY2=y` (builtin) + `CONFIG_NETCONSOLE=y` (builtin) explícitos no `00-build-kernel-7.0.sh`. Bootargs com `netconsole=6665@192.168.0.2/eth0,6666@192.168.0.1/b4:45:06:6c:f6:4f`.
- **Firmware GPU**: ainda vazio (gladius_*.bin 0 bytes)
- **Initramfs**: produção (mkinitcpio) — depois trocado por debug (ver item 3)
- **RESULTADO**: sem cabo Ethernet conectado neste teste → netconsole nunca teve chance de funcionar (não é falha do kernel, é falta de canal). Luz azul acesa, numlock respondia à época (antes de sabermos que isso não é confiável sem HID), HD sem atividade de escrita no rootfs.

### 3. Tag `20260716-debug` (mesmo kernel do item 2 + initramfs de debug)
- **Initramfs**: custom busybox, grava dmesg em qualquer partição FAT a cada 5s (`PS4_DMESG_*.txt`), pisca capslock/numlock ao gravar.
- **RESULTADO**: **primeira visibilidade real.** dmesg capturado:
  - ✅ bpcie glue + ICC OK, chip revision lido
  - ✅ AHCI/SATA: `TOSHIBA MQ04ABF100` detectado
  - ✅ USB/xHCI OK (por isso numlock respondia)
  - ❌ **amdgpu**: `Failed to load firmware "gladius_sdma.bin"` → `Fatal error during GPU init` (firmware vazio, como esperado)
  - ❌ **sky2/Ethernet**: `netconsole: eth0 doesn't exist, aborting` — interface nunca veio a existir (driver não bindou a tempo, ou nunca bindou)
  - ❌ **WiFi MT7668**: falha ao carregar `wifi.cfg`, `mt7668_patch_e2_hdr.bin`, `WIFI_RAM_CODE_MT7668.bin` (firmware não estava no `CONFIG_EXTRA_FIRMWARE` ainda)

### 4. Tag `20260716-gladiusfw` (firmware gladius = cópia de liverpool_*.bin, kernel build #4)
- **Firmware GPU**: `gladius_{ce,me,mec,mec2,pfp,rlc,sdma,sdma1}.bin` = cópia de `liverpool_*.bin` (mesma geração CIK/gfx_v7; fonte: initramfs 5.4 funcional + build tree, ago/2021)
- **Initramfs**: debug (mesmo do item 3)
- **RESULTADO**: **maior progresso da GPU até agora**, mas ainda tela preta:
  - ✅ SDMA, GMC, VRAM (1024M), IH, DCE v8 OK — firmware liverpool funciona para SDMA
  - ✅ Chegou a enumerar conector HDMI-A-1 (encoder INTERNAL_UNIPHY)
  - ❌ `gfx_v7_0`: `ring gfx test failed (-110)` (timeout) → `hw_init failed` → Fatal. **Command Processor (GFX/CP) do Gladius NÃO aceita microcódigo do Liverpool.** SDMA é compatível entre as variantes, CP não é.
  - dmesg salvo em `firmware_gpu/dmesg-7.0-liverpoolfw-gfxfail.txt`
  - **Conclusão: para vídeo funcionar, precisa do firmware gladius REAL (dump do console rodando Orbis, método fail0verflow `ps4-kexec/firmware.c`). Liverpool não resolve o GFX/CP.**

### 5. Build de produção (kernel #6: WiFi MT7668 completo embutido + BTF desabilitado; rootfs novo com WiFi/SSH configurados)
- **Firmware WiFi**: adicionado `EEPROM_MT7668*.bin`, `mt7668_patch_e1/e2_hdr.bin`, `TxPwrLimit_MT76x8.dat`, `wifi.cfg`, `WIFI_RAM_CODE*` ao `CONFIG_EXTRA_FIRMWARE` (paridade com 5.4 neocine)
- **CONFIG_DEBUG_INFO_BTF**: desabilitado (causava OOM no `pahole` durante build, matando o processo)
- **rootfs novo**: `01-build-image-7.0.sh` corrigido (removidos módulos `stmmac-pci/stmmac-platform/dwmac-generic` inexistentes que travavam o `mkinitcpio`; adicionado wpa_supplicant com SSID `prfelicidade_5G`, usuário `ps4`, sudoers, sshd_config permissivo — paridade completa com 5.4)
- **Gravação**: full burn via `02-burn-image-7.0.sh` (corrigido bug de falta de `umount` defensivo antes do `mkfs`, causava corrida com auto-mount do udisks2)
- **Initramfs**: **produção** (mkinitcpio), NÃO debug — sem log em FAT
- **Bootargs**: sem `console=ttyS0` (evita conflito UART+vídeo), sem `quiet`, `loglevel=8`
- **RESULTADO**: **teste às cegas, inconclusivo.** Sem cabo Ethernet conectado (netconsole não tinha como funcionar). Varredura extensa de rede (nmap -sn, arping, port scan 22) na sub-rede WiFi `192.168.6.0/24` por >15-20min: nenhum host novo com SSH aberto encontrado. IP conhecido do 5.4 (`192.168.6.128`) não respondeu a ARP nem porta 22. **Conclusão do usuário: boot morto/travado, tempo demais sem sinal.** Não sabemos ONDE travou porque o initramfs de produção não loga nada em lugar nenhum.

### 6. Tag `20260716-wifidebug` (kernel #6 do item 5 + initramfs de DEBUG)
- Combina o kernel com WiFi firmware completo + firmware gladius(liverpool) com o initramfs de debug (grava dmesg em FAT/pendrive a cada 5s, independente de rede/vídeo)
- **Objetivo**: descobrir se o WiFi conecta (dmesg mostra tentativa de firmware/handshake) e confirmar que GFX ainda é o único bloqueador de vídeo, agora com o conjunto completo de firmware WiFi.
- **RESULTADO**: **maior volume de dados até agora (230s de boot, 28 capturas) e um achado NOVO e crítico:**
  - ❌ **GPU**: mesmo bloqueio de sempre — `ring gfx test failed (-110)` no `gfx_v7_0` (GFX/CP). Firmware liverpool-como-gladius não resolve.
  - ⚠️ **WiFi (SDIO MT7668)**: progresso parcial. Cartão SDIO detectado (`mmc0: new UHS-I speed SDR104 SDIO card`), driver `wlan` inicializa, mas: `wlanAdapterStart: load manufacture data fail` e `rlmDomainSearchRegdomainFromLocalDataBase(): Cannot find the correct RegDomain` — dados de calibração/EEPROM (`EEPROM_MT7668*.bin`?) não estão sendo aplicados corretamente mesmo estando no `CONFIG_EXTRA_FIRMWARE`. WiFi NÃO chegou a associar/conectar.
  - ❌ **Ethernet**: `netconsole: eth0 doesn't exist, aborting` — sky2 nunca cria a interface, como sempre.
  - 🔴 **ACHADO CRÍTICO — SATA do próprio HD cai durante o boot real no PS4:**
    - `t=1.1s`: disco detectado normal (`TOSHIBA MQ04ABF100`, 1953525168 setores, link 3.0 Gbps, UDMA/100) — é daqui que o kernel/initramfs carregaram.
    - `t=31.8s`: primeiro erro `READ FPDMA QUEUED` timeout → `ata1: hard resetting link`.
    - `t=37s-48s`: mais timeouts, downgrade de velocidade do link 3.0→1.5 Gbps.
    - `t=62s`: `ata1.00: disable device` e `sda: detected capacity change from 1953525168 to 0` — **o disco literalmente some do barramento.**
    - A partir daí o `/init` do debug-initramfs roda mas nunca consegue montar `sda2` (raiz) — por isso ficou preso em "DEBUG LOOP" piscando NUM LOCK por >3min sem nunca completar o boot. O log continuou sendo gravado porque a escrita ia para o pendrive USB de resgate (FAT32), não para a partição sda1.
    - **Isso muda o diagnóstico**: pelo menos parte dos boots "mortos" anteriores pode não ser travamento de kernel/GPU, mas o HD perdendo conexão física a meio do boot dentro do PS4 — mesmo padrão de erro de I/O já visto quando o HD estava ligado ao PC (timeouts, "medium may have changed"). Pode ser cabo/conector SATA-USB frouxo, alimentação insuficiente, ou incompatibilidade do controlador Baikal SATA sob carga (coincide com o período de inicialização pesada de GPU+WiFi).

### 7. Tag `20260716-wifissh` (kernel #6 + initramfs debug v2 com WiFi+telnet) — **EM TESTE**
- **Mudança**: initramfs de debug ganhou pilha WiFi completa em RAM (independente do SATA/rootfs):
  - `wpa_supplicant` 2.11 + `wpa_cli` do host Arch + 19 libs (initramfs foi de 844K → 9,4MB)
  - `udhcpc` (busybox) com script próprio, hostname DHCP `ps4-debug`
  - `telnetd` (busybox) porta 23, shell root sem senha (diagnóstico LAN)
  - a cada loop grava `PS4_NETSTAT.txt` no FAT: `ip addr`, `wpa_cli status`, scan, rotas, `/proc/partitions` (monitora se o SATA morre/volta)
- **Base da decisão** (investigação do log do item 6):
  - Driver wlan cria `wlan0` (NIC_INF_NAME="wlan%d" em `gl_init.c`); logs P2P FSM/GTK indicam netdevs registrados
  - `load manufacture data fail` vem de `kalIsConfigurationExist()` → o driver procura NVRAM no caminho **arquivo** `/data/nvram/APCFG/APRDEB/WIFI` (512 bytes, `WIFI_CFG_PARAM_STRUCT`) — nem o rootfs 5.4 nem o 7.0 têm esse arquivo, e o WiFi do 5.4 funcionava mesmo assim → warning NÃO é fatal (driver usa defaults do eFUSE do chip)
  - Bluetooth `hci0` do mesmo chip MT7668 baixou firmware OK → chip vivo e se comunicando
  - No teste 6 o WiFi "não conectou" simplesmente porque NENHUM userspace rodou (rootfs nunca montou por causa da queda do SATA) — não havia wpa_supplicant para associar
- **Como testar**: bootar com pendrive FAT32 conectado. Se WiFi associar: procurar `ps4-debug` no DHCP do roteador ou `nmap -p23 192.168.6.0/24`, conectar com `telnet <ip>`. Se não: ler `PS4_NETSTAT.txt`/`PS4_DMESG_LATEST.txt` do pendrive.
- **RESULTADO**: ✅ **SUCESSO — WiFi conecta e telnet root funciona.** IP `192.168.6.128` (reserva DHCP conhecida), ping e `telnet 192.168.6.128 23` deram shell root imediatamente. Achado crítico durante a investigação via shell: `root=/dev/sda2` no `bootargs-7.0.txt` de produção apontava para o disco INTERNO do PS4 (que sempre falha), não para nosso disco de boot (que aparece como `sdb`, não `sda`, dentro do PS4). Corrigido para `root=LABEL=psxitarch` em TODOS os bootargs do projeto (lição #24). Coleta completa de hardware real feita nesta sessão via telnet — ver `BAIKAL_HARDWARE_DISCOVERIES.md` seção 5 e pasta `hardware_ps4_real/` (eFuse do WiFi, PCI, USB, DMI, dmesg completo, etc.). GPU/GFX-CP segue com o mesmo bloqueio de sempre (-110), sem mudança.
- **Lição extra**: cheguei a substituir o initramfs de debug pelo de produção (mkinitcpio) ao vivo via telnet para validar o fix do `root=` — isso foi um erro (lição #25): perdemos toda visibilidade no teste seguinte porque produção não loga nada. Revertido para o initramfs de debug (`wifissh`) e mantido como padrão até aprovação explícita do usuário para trocar.

---

## O que já sabemos que NÃO funciona (não repetir)
- ❌ Firmware liverpool como gladius para GFX/CP (SDMA ok, CP não) — só dump real resolve vídeo
- ❌ Netconsole via eth0 sem cabo conectado (óbvio, mas já perdemos um teste inteiro por isso)
- ❌ `01-build-image-7.0.sh` antigo (módulos stmmac fantasmas travavam mkinitcpio) — já corrigido
- ❌ `02-burn-image-7.0.sh` sem unmount defensivo — já corrigido

## O que ainda não testamos / próximos passos
- [ ] WiFi: investigar por que `load manufacture data fail` / regdomain não encontrado mesmo com firmware completo embutido — **baixa prioridade, adiado a pedido do usuário em 2026-07-16**, não é bloqueador (ver memória `kernel-7.0-wifi-manufacture-data-pendente`).

### 8. Sessão 2026-07-16 (continuação): gladius real via kexec + fix stmmac Ethernet — build em andamento, PAUSADO para amanhã

**Diagnóstico 1 — firmware gladius real (RESOLVIDO na teoria, aguardando teste):**
O payload kexec (`ps4-linux-payloads`, carregado via "Payload Guest") já extrai automaticamente o firmware Gladius **real** da RAM do Orbis a cada boot e injeta no initramfs (`ps4-kexec-common/firmware.c::firmware_extract()`, detecta `gpu_devid_is_9924()`). O bloqueio nunca foi "não temos o firmware real" — é que `00-build-kernel-7.0.sh` embutia firmware Gladius **falso** (cópia do Liverpool) via `CONFIG_EXTRA_FIRMWARE`, e firmware embutido no kernel (`fw_get_builtin_firmware`) tem prioridade sobre o que vem do initramfs/filesystem — o real nunca era sequer tentado. **Fix aplicado:** removidas as 8 entradas `amdgpu/gladius_*.bin` do `CONFIG_EXTRA_FIRMWARE`.

**Diagnóstico 2 — Ethernet (investigação NOVA, docs antigos `PESQUISA_ETHERNET_BAIKAL.md`/`BAIKAL_GBE_EXPERIMENTS.md` desconsiderados a pedido do usuário):**
Confirmado ao vivo via telnet (tag `wifissh`) que `00:14.1` (`104d:90d8`, classe não-padrão `0x088001`, BAR0 4K) **não tem nenhum driver vinculado**. Achados no código-fonte do kernel 7.0 atual:
- Bug 1: script usava o símbolo Kconfig errado (`CONFIG_STMMAC`, não existe neste kernel) em vez de `CONFIG_STMMAC_ETH` — fazia todo o stmmac desaparecer do `.config` silenciosamente (nem `# ... is not set` aparecia).
- Bug 2: `stmmac_pci.c` não tinha entrada para o vendor Sony na `stmmac_id_table[]` — sem isso o driver nunca tenta fazer probe do dispositivo, mesmo com Kconfig certo.
- `sky2.c` deste kernel **não tem** `PCI_DEVICE_ID_SONY_BAIKAL_GBE` na tabela (diferente do que os docs antigos de 5.4 sugeriam) — sky2 nunca tenta nem erra, simplesmente ignora o dispositivo.
- **Fix aplicado:** `CONFIG_STMMAC_ETH` habilitado corretamente + patch idempotente via Python injetando `{ PCI_DEVICE_DATA(SONY, BAIKAL_GBE, &snps_gmac5_pci_info) }` na tabela de IDs do `stmmac_pci.c` (confirma-se que `snps_gmac5_pci_info` existe neste checkout).

**🔴 ACHADO CRÍTICO DE SEGURANÇA (ALTA SUSPEITA) — ler `LICOES_APRENDIDAS.md` antes de testar a tag resultante:**
Durante a investigação ao vivo, `cat /sys/bus/pci/devices/0000:00:14.1/config` (leitura completa do espaço de configuração PCI) **travou o PS4 de forma reproduzível** (confirmado por teste A/B controlado: `enable` é seguro e instantâneo, `config` trava — telnet cai, ping para, precisa ciclo completo de energia). Há alta suspeita de que `stmmac_pci_probe()` real (que habilita a função + percorre capabilities do PCI, mexendo na mesma vizinhança de offsets) reproduza esse travamento **automaticamente no primeiro boot com o driver**. Ver memória `baikal-gbe-toque-trava-desliga-ps4` para o mecanismo técnico suspeito (southbridge Baikal compartilha barramento/glue entre todas as funções 00:14.x; função GBE pode estar clock/power-gated).

**Consequência prática — REGRA PARA O PRÓXIMO TESTE:**
1. **NUNCA fazer deploy dessa build sobre a tag `wifissh`** (marco de boot funcional com WiFi+telnet — é o fallback garantido).
2. Build compilado com `sudo` + `taskset -c 0-3` (metade dos 8 núcleos, a pedido do usuário) na tag `20260716-gladiusreal-stmmac`. **Estava em andamento quando a sessão foi pausada** (~861 unidades compiladas de um total de milhares, ThinLTO é lento) — checar se terminou em `logs/build-kernel-7.0-20260716-gladiusreal-stmmac.log` (procurar por `Build concluído` ou erro) antes de continuar. Se não terminou, só rodar de novo `sudo ./00-build-kernel-7.0.sh 20260716-gladiusreal-stmmac` (incremental, reaproveita o que já compilou).
3. Depois de pronto: `sudo ./deploy-boot-7.0.sh 20260716-gladiusreal-stmmac` — testar com o usuário observando o console fisicamente e pronto para ciclo de energia se travar. Se travar: reverter para `wifissh` com `sudo ./deploy-boot-7.0.sh wifissh` antes de investigar mais.
4. Ler o dmesg persistido no pendrive FAT do initramfs de debug (sobrevive a travamento) em vez de tentar reproduzir/diagnosticar via telnet ao vivo — mais seguro.

### 9. Teste da tag `20260716-gladiusreal-stmmac` (2026-07-17) — build retomada, stmmac NÃO compilou, GPU ainda -110

**Achado 1 (build):** o `.config` final não tinha NENHUMA entrada `STMMAC`/`NET_VENDOR_STMICRO`, apesar do `stmmac_pci.c` estar corretamente patcheado com o ID Sony (confirmado lendo o source em `/mnt/hdauxiliar/temp/kernel_build_7.0`). Causa: `00-build-kernel-7.0.sh` habilita `CONFIG_STMMAC_ETH` mas nunca habilita o gate pai `CONFIG_NET_VENDOR_STMICRO` (que vinha `is not set` do config base) — sem o pai, `olddefconfig` descarta o filho silenciosamente, mesmo bug de categoria já visto com o nome de símbolo errado. **Fix pendente:** adicionar `scripts/config --enable CONFIG_NET_VENDOR_STMICRO` antes das linhas STMMAC no script. Como o driver não compilou, o teste desta tag NÃO valida (nem arrisca) o fix de Ethernet — só o firmware gladius foi de fato testado.

**Achado 2 (deploy):** usado `deploy-boot-7.0.sh` (não a imagem completa) com `bootargs`/`initramfs` copiados 1:1 da tag `wifissh` (só o `bzImage` mudou). `wifissh` preservada no próprio HD como fallback.

**Achado 3 (GPU, RESULTADO NEGATIVO):** tela preta, igual sempre. Log lido em `PS4_DMESG_449.txt` (pendrive FAT):
```
[    1.158568] amdgpu 0000:00:01.0: [drm:amdgpu_ring_test_helper] *ERROR* ring gfx test failed (-110)
[    1.158593] amdgpu 0000:00:01.0: hw_init of IP block <gfx_v7_0> failed -110
[    1.158611] amdgpu 0000:00:01.0: Fatal error during GPU init
```
Mesmíssimo erro do teste anterior com firmware liverpool-como-substituto (ver item 8 / memória `kernel-7.0-gladius-firmware-ausente`). Nenhuma linha de firmware (load/erro) aparece no dmesg entre a detecção do `gfx_v7_0` e o timeout — não dá pra confirmar pelo log se o kexec injetou o firmware real dessa vez. Ver memória para hipóteses e próximo passo sugerido (checar via telnet ao vivo `/lib/firmware/amdgpu/gladius_*.bin`).

**Achado 4 (rede):** WiFi associou (`192.168.6.128`, `wpa_state=COMPLETED`) segundo `PS4_NETSTAT.txt`, mas o arquivo parou de ser atualizado em "LOOP 44" (~6min de uptime) enquanto o dmesg continuou até o loop 449 (~49min) — algo trava a captura de rede (script de netstat/scan?) bem antes do kernel parar de rodar. PS4 ficou inalcançável via ping/nmap quando testado depois desse ponto. Kernel seguiu vivo em `DEBUG LOOP` indefinidamente — isso é esperado (initramfs de debug não faz pivot pro rootfs por padrão, roda solto), não é sinal de travamento do kernel.

**Achado 5 (infra):** HD USB (SSD Kingston via ponte JMicron) deu falha de I/O real durante a sessão (`timing out command, waited 180s`, erro de escrita no superbloco ext4 de `sda2`) — resolvido fisicamente desconectando/reconectando o cabo (não é problema de software). `fsck.vfat` rodado na partição BOOT depois por precaução (dirty bit sujo, sem outros danos).

---

### 10. Sessão 2026-07-17 (continuação): fix `CONFIG_NET_VENDOR_STMICRO`, MDIO, fixed-link — 3 builds/testes no PS4 real

**Fix do Kconfig (`00-build-kernel-7.0.sh`):** `CONFIG_STMMAC_ETH` mora dentro de `if NET_VENDOR_STMICRO` (`drivers/net/ethernet/stmicro/Kconfig`). O config base tinha `NET_VENDOR_STMICRO` desabilitado, e o script nunca reabilitava o gate pai — mesma classe de bug do item 9 (símbolo certo, mas dependência de Kconfig não satisfeita, `olddefconfig` descarta tudo silenciosamente). Fix: `scripts/config --enable CONFIG_NET_VENDOR_STMICRO` adicionado antes das linhas STMMAC.

**Tag `20260717-stmmacfix` (fix acima, SEM fix de MDIO ainda) — testada no PS4 real:**
- ✅ **Vídeo funcionou** (tela preta virou imagem, mesmo firmware gladius do item 9 que tinha falhado) — variação entre boots do firmware real injetado via kexec, causa exata ainda não confirmada.
- ✅ `stmmac_pci_probe()` RODOU em `00:14.1` sem travar o console — **derruba a alta suspeita de travamento** documentada no item 8 / memória `baikal-gbe-toque-trava-desliga-ps4` (atualizada). Detectou DWMAC4/5, configurou DMA/rings, leu MAC address real (`ba:d2:4c:27:b6:8f`).
- ❌ Probe falhou limpo: `error -EIO: Cannot register the MDIO bus` → `probe with driver stmmaceth failed with error -5`. Nenhum PHY responde via MDIO nessa silício. Sem `eth0` em `ip link`.

**Fix do MDIO (`stmmac_pci.c`):** setup próprio `sony_baikal_gbe_default_data()` que chama `snps_gmac5_default_data()` e depois zera `plat->mdio_bus_data` (faz `stmmac_mdio_register()` retornar 0 direto — `if (!mdio_bus_data) return 0;`). Injeção via patch idempotente movida pro Python inline no script pra `patches/stmmac-baikal-fixedlink.patch` (git apply) na iteração seguinte.

**Tag `20260717-stmmacfix2` (fix do MDIO) — testada no PS4 real:**
- ✅ Vídeo funcionou de novo (2ª vez seguida).
- ✅ **`eth0` aparece em `ip link`!** (`link/ether 9e:dd:cf:2a:db:39`, sem mais erro -EIO/-5). Progresso real.
- ❌ `stmmaceth 0000:00:14.1 eth0: no phy found` — interface fica `DOWN`, sem link. Esperado: zerar `mdio_bus_data` só evita o erro de registro, não configura link. `phylink_expects_phy()` só retorna `false` em modo `MLO_AN_FIXED` (fixed-link), que não estava configurado.

**Fix do fixed-link (3 arquivos, patch `patches/stmmac-baikal-fixedlink.patch`):**
- `include/linux/stmmac.h`: novos campos `bool force_fixed_link` + `struct phylink_link_state fixed_link_state` em `plat_stmmacenet_data`.
- `stmmac_pci.c`: `sony_baikal_gbe_default_data()` popula esses campos (chute: `SPEED_1000`/`DUPLEX_FULL`/`link=1`/`an_complete=1`, baseado no `phy_interface = GMII` herdado — sem datasheet, pode precisar ajuste).
- `stmmac_main.c` (`stmmac_phylink_setup()`): depois de `phylink_create()`, se `force_fixed_link` chama `phylink_set_fixed_link(phylink, &fixed_link_state)` — API oficial do phylink pra forçar link sem MDIO/fwnode (`pl->cfg_link_an_mode = MLO_AN_FIXED`).
- Script atualizado pra aplicar esse patch via `git apply` (idempotente com `git apply --reverse --check`) em vez de injeção Python ad-hoc — mais fácil de manter com 3 arquivos.

**Tag `20260717-fixedlink` — testada no PS4 real, RESULTADO AMBÍGUO:**
- ✅ Vídeo funcionou (3ª vez seguida).
- 🔴 **Usuário reportou aparente travamento** (teclado sem resposta, luz do PS4 mudou de branca pra azul) pouco depois do `netconsole` terminar de inicializar na tela.
- **Pós-mortem via log FAT (`PS4_DMESG_449.txt`) NÃO bate com um travamento claro:**
  - Nenhum panic/oops/hang task/soft-lockup em lugar nenhum do log.
  - `DEBUG LOOP` chegou a **449** (uptime ~48,6min) — **exatamente o mesmo número máximo** de TODOS os testes anteriores de hoje, inclusive os que não travaram visualmente. Forte indício de que isso é um limite/característica do próprio initramfs de debug (loop com contador fixo? esgotamento de RAM do tmpfs acumulando ~450 arquivos `PS4_DMESG_*.txt`?), não relacionado ao patch de Ethernet.
  - WiFi associou e telnet subiu normalmente, igual sempre.
  - **Anomalia real e não explicada:** nenhuma linha `stmmaceth` aparece em NENHUM lugar do log dessa vez — nem o "Version ID not available" que sempre aparecia nos 2 testes anteriores. Confirmado que o código compilou certo (`nm vmlinux | grep sony_baikal` mostra os símbolos `sony_baikal_gbe_default_data`/`sony_baikal_gbe_pci_info` presentes). Não dá pra saber pelos logs se o probe travou silenciosamente bem cedo (antes do primeiro print) ou se por algum motivo não foi chamado.
- **Conclusão em aberto:** não é possível afirmar com confiança se o travamento foi causado pelo `phylink_set_fixed_link()` (chamado durante o probe, mexe em locks internos do phylink — área mais arriscada) ou se é o mesmo comportamento de "fim do loop" que talvez aconteça em todo boot por volta dos ~49min, coincidência de timing com o que o usuário estava observando na tela. **Próximo passo recomendado:** repetir o teste da tag `fixedlink` observando via telnet DESDE O INÍCIO do boot (não só depois), pra ver ao vivo se o probe do stmmac chega a imprimir alguma coisa e onde exatamente para, em vez de inferir só pelo log pós-morte.
- HD ficou saudável durante toda essa etapa (sem repetição do problema de I/O do item 9).

### 11. Testes 2026-07-17 (continuação): retest fixedlink + manualeth0 — CAUSA RAIZ ENCONTRADA, stmmac era o driver ERRADO

**Retest da tag `20260717-fixedlink` (mesma do item 10, agora observado ao vivo):**
- Vídeo ok, mas travou CEDO (~1,7s de uptime), congelando a tela com call trace visível (foto): `init_netconsole → netpoll_setup → dev_open → __dev_open → ...` — o **próprio `netconsole=...eth0` do bootarg** força `dev_open()` na eth0 logo nos initcalls, antes do initramfs rodar. Nos testes do item 10 esse caminho não tinha sido percorrido tão cedo de forma determinística — isso explica a "anomalia" do item 10 (a ausência de linhas stmmaceth no log era porque o crash acontecia antes do primeiro flush pro FAT).

**Tag `20260717-manualeth0`** (mesmo kernel `fixedlink`, bootarg SEM `netconsole=`): boot avançou até o DEBUG LOOP, e o crash veio quando o script do initramfs subiu a eth0 — desta vez com **Oops completo na tela** (foto):
- `BUG: unable to handle page fault for address: ffffc900000ac000` / `#PF: supervisor read access` / `not-present page`
- `RIP: dwmac4_dma_reset+0x7/0x90`, call trace: `stmmac_reset → stmmac_hw_setup → __stmmac_open → stmmac_open → __dev_open → ... → dev_ioctl` (comando `ip`, PID 171)
- Final: `note: ip[171] exited with irqs disabled` — IRQs nunca reabilitadas → sistema morre de verdade (teclado, tela). **Também explica o travamento "aos ~49min" do item 10:** mesmo bug, só que o timing do colapso total variou.
- **Causa mecânica:** BAR0 da GBE tem só **4KB** (`pci 0000:00:14.1: BAR 0 [mem 0xc2000000-0xc2000fff]`, confirmado no log FAT). Os registros de DMA do DWMAC4 começam em 0x1000 — primeira leitura fora da página mapeada → page fault. Fault address = base do ioremap + 0x1000 exato.

**DESCOBERTA PRINCIPAL (lendo a árvore do kernel):** a GBE do PS4 **nunca foi Synopsys** — é um **Marvell Yukon 2 (driver sky2)**. O fork fail0verflow já traz `sky2.c` adaptado com os IDs `AEOLIA_GBE` (0x909e) e `BELIZE_GBE` (0x90c9) + glue apcie (IRQs via apcie_assign_irqs, MAC address via SPM da função MEM, quirks de reset). **Só faltou adicionar o `BAIKAL_GBE` (0x90d8) do PS4 Pro.** (A tag default do build script sempre se chamou "sky2builtin" — pista que estava lá desde o começo.) Os "sinais de DWMAC" do item 10 eram ilusão: "Version ID not available", dma_cap zerada ("queues exceeds dma capability") e MAC aleatória são exatamente o que se vê lendo registros errados/zerados de um hardware que não é DWMAC.

**Fix aplicado — `patches/sky2-baikal-gbe.patch`** (só `drivers/net/ethernet/marvell/sky2.c`):
1. ID `PCI_DEVICE_ID_SONY_BAIKAL_GBE` na `sky2_id_table[]`.
2. Helpers `sky2_is_baikal_gbe()` / `sky2_ps4_assign_irqs()` / `sky2_ps4_free_irqs()`: no Baikal os MSI das subfunções passam pelo **bpcie** (`bpcie_assign_irqs`), não pelo apcie — replicado o padrão do `xhci-aeolia.c` (que já funciona no nosso Pro). Declarações vêm de `<asm/ps4.h>`, sem include novo. 4 call sites trocados (probe, erro do probe, err_out_free_netdev, remove).
3. MAC address: **zero mudanças** — `aeolia_get_mac_address()` já é vendor-wide e os offsets são idênticos (FUNC_ID_MEM=6 nos dois, SPM BP em BAR5+0x2f000 nos dois; BAR5 da 00:14.6 confirmado presente no log: `0xcd400000-0xcd43ffff`).
4. Quirks Aeolia-only (magic writes no reset, skip phy reset, phy_addr=1 do "l2 switch") NÃO estendidos ao Baikal — Belize também não os usa, mantido o precedente.
- stmmac: patch `stmmac-baikal-fixedlink.patch` **revertido da árvore** e configs STMMAC desabilitadas no `00-build-kernel-7.0.sh` (se ficasse builtin, poderia disputar o device com o sky2 e reintroduzir o Oops). Patch mantido em `patches/` só como histórico.
- Build tag `20260717-sky2baikal`; bootargs sem `netconsole=` no primeiro teste (se a eth0 subir limpa, reativar netconsole na tag seguinte).

### 12. Teste da tag `20260717-sky2baikal` (2026-07-17, noite) — sky2 probou SEM crash; GBE está DESENERGIZADA pelo Syscon

**Resultado do boot:** vídeo ok, boot completo, DEBUG LOOP estável (30+ iterações), WiFi/telnet normais — o Oops do stmmac desapareceu como previsto. O sky2 probou a GBE e falhou de forma limpa:
```
sky2: driver version 1.30
sky2 0000:00:14.1: unsupported chip type 0x0
sky2 0000:00:14.1: probe with driver sky2 failed with error -95
```

**Investigação ao vivo via telnet** (busybox sem devmem; usado `dd if=/dev/mem bs=4 ... | od -An -tx4` — MMIO 32-bit dentro dos 4KB do BAR0, seguro): o device responde MMIO (0x0→0x79498100, 0xB0→0x001f03ff, valores voláteis entre leituras), mas o mapa não é de um Yukon acordado e o B2_CHIP_ID (0x11a) lê 0.

**CAUSA RAIZ (documentação):** página Southbridge do psdevwiki, saída do comando `devpm` (Device Power Management) do Syscon: **`# gbe off`** é o estado default (junto com `sdio off`; wlan/hdd/usb/bd/acdc/pg3/hdmi todos on). O Orbis liga o domínio da GBE via ICC quando usa LAN com fio. Achados de suporte:
- ICC major 5 = device power no código do fork (`resetBtWlan()`: minor 0x00 val 3=on p/ wlan/bt; `resetUsbPort()`: minor 0x10 val 1=on p/ usb, em `ps4-apcie-icc.c`).
- Página IOCTL do psdevwiki lista `icc_device_power_*` só até bd (wlan 0x00/0x01, usb 0x10/0x11, hdd 0x20/0x21, bd 0x30/0x31) — GBE não é exposta ao userland do Orbis; por extrapolação o minor da GBE deve ser 0x40/0x41.
- Kernel 5.4 neocine (binário no old_project) analisado: só tem o ID AEOLIA_GBE — Ethernet nunca funcionou em Baikal em nenhum fork; caminho inédito.
- `drivers/ps4/Makefile` (fail0verflow): "sky2 (implements ps4-gbe)" — confirmação final do driver.

**Preparado (falta deploy):** tag `20260717-iccdbg` = sky2baikal + `/proc/ps4_icc` (patch `patches/ps4-icc-proc-debug.patch`) pra enviar comandos ICC arbitrários via telnet e mapear o serviço device-power ao vivo (sanity `2 6` = fw version; GETs `5 0x01/0x11/0x21/0x31/0x41`; ligar com `5 0x40 01`; verificar chip id via dd; reprobar sem reboot com `echo 0000:00:14.1 > /sys/bus/pci/drivers/sky2/bind`). HD ficou no PS4 no fim da sessão; ao trazer pro PC, rodar também `fsck.fat` na partição de boot (aviso "sdb1: please run fsck" apareceu — flag suja de desligamentos forçados, não-fatal). Roteiro completo: memória `marco-2026-07-17-sky2baikal-pronto-teste`.

### 13. Teste da tag `20260717-iccdbg` (2026-07-18) — hipótese do ICC device_power DESCARTADA; GBE é MAC core clock-gated

**Setup:** tag `20260717-iccdbg` (sky2baikal + `/proc/ps4_icc`) bootada no PS4 real. `/proc/ps4_icc` funcional. Acesso via telnet `nc 192.168.6.128 23`. Boot confirmado pelo dmesg salvo no FAT (`PS4_DMESG_LATEST.txt`, build #19 Jul 17 23:31): contém os comandos `ps4_icc` que enviei — é este boot.

**Mapeamento ICC device_power (major 5) ao vivo — resultado: GBE NÃO está neste serviço.**
- Sanity `2 6` (fw version): `ret=46`, reply plausível → interface ICC OK.
- GETs válidos, todos `ret=20`, reply começa `00 00 01` (ligado): `5 0x01` (wlan/bt), `5 0x11` (usb), `5 0x21` (hdd), `5 0x31` (bd).
- **`5 0x41` (candidato GBE): reply `01 05 00...` — que é o padrão de NAK/minor inválido.** Calibrado com `5 0x03` (minor sabidamente inexistente) → reply IDÊNTICO `01 05`. Varredura `5 0x51`..`5 0xf1`: todos NAK `01 05`.
- Conclusão: o serviço `icc_device_power` do **EMC** tem exatamente 4 dispositivos (bate com a página IOCTL: `9C01..9C08` = wlan_bt/usb/hdd/bd control+get). **A extrapolação "GBE = minor 0x40/0x41" do item 12 estava ERRADA.** GBE não se liga por ICC device_power.

**Caracterização MMIO ao vivo da BAR0 (0xc2000000), leituras `dd if=/dev/mem` de 32 bits:**
- `0x000`=0x79498100, `0x008`=0x0f597c00 → valores reais e **estáveis** (a camada wrapper PCIe está ligada).
- `0x004` (B0_CTST)=0, `0x11a` (B2_MAC_CFG)=0, `0x11b` (B2_CHIP_ID)=0 → o **core do MAC Yukon está com clock/power gated**. `sky2_init` roda o clock-enable padrão do Yukon (`PCI_DEV_REG3=0` + `B0_CTST=CS_RST_CLR`) e mesmo assim chip id = 0 ⇒ o gate é EXTERNO ao MAC. `glue_set_region` descartado como causa (a BAR responde). A GBE é uma rail do **Syscon** (`devpm: gbe off`), chip separado do EMC — por isso o device_power do EMC não a alcança.

**SEGURANÇA — varredura MMIO em rajada da janela de 4KB é SEGURA (refuta o medo do item 12/memória de risco):** durante e após ~21 leituras `/dev/mem` em loop, o kernel NÃO travou — o DEBUG LOOP seguiu até 593 (~64 min) escrevendo no FAT, sem Oops/panic/page fault no dmesg. O que caiu foi só o WiFi/telnet (flakiness conhecida da rede, não do console). Ler a BAR0 inteira (0x000–0xfff) em varredura é seguro. (O travamento do `cat config` cru do espaço estendido continua sendo fenômeno real e SEPARADO.)

**Mapa do bpcie glue extraído do dmesg (para a próxima investigação):** função glue = **00:14.4** (`BAIKAL_FUNC_ID_PCIE`), com:
- BAR0 `0xc8000000`-`0xc8001fff` (eMMC), BAR2 `0xc8800000`-`0xc89fffff` (pervasive 0, 2MB, = `sc->bar2` do glue_read32/write32), BAR4 `0xc9000000`-`0xc91fffff` (pervasive 1, 2MB).
- Referência viva do mecanismo de power: USB/SATA são acordados escrevendo em `sc->bar2 + BPCIE_USB_BASE` (0x180000) → físico **0xc8980000** (pulse/hold offsets). O clock-gate da GBE provavelmente está em outro offset da mesma região pervasive `0xc8800000`-`0xc89fffff`.
- Chip revision do glue lido no boot: `5c202021:7ca85ea9:0000b100`.

**PRÓXIMO PASSO (próximo boot):** varrer ao vivo via `/dev/mem` a região pervasive `0xc8800000`+ (leitura é segura) procurando o registrador de clock/reset da GBE — comparar com a área USB (`+0x180000`) como referência. Alternativas se não achar: (a) outro serviço ICC que o EMC use para pedir a rail ao Syscon; (b) byte de config na NVS (`offset 0x38` = "gbe related" na página NVS do psdevwiki) — **NVS write pode brickar, só com autorização explícita do usuário.** Detalhe em `marco-2026-07-17-sky2baikal-pronto-teste` e memória `baikal-gbe-e-sky2-nao-stmmac`.

### 13b. Varredura da pervasive (2026-07-18, tarde) — block-read DESLIGOU o PS4; blind-scan é técnica MORTA

Tentativa de achar o clock-gate da GBE varrendo a região pervasive do bpcie glue (00:14.4, BAR2 físico 0xc8800000, 2MB, via `/dev/mem`). **Leituras de 1 palavra (4B) em offsets alinhados a 64KB = seguras**, mapa obtido:
- Ativos: 0x100000=`f570c001`, 0x140000=`10206333`, 0x160000=`62003532`, 0x170000=`000b0331`, 0x180000=`00000001` (USB power, referência viva).
- Não-mapeados (`ffffffff`): 0x120000, 0x130000, 0x190000–0x1f0000.
- Zerados: 0x110000, 0x150000. Low half 0x00000–0xf0000: uniforme `0x00511148` (aliasing provável).
- Sanidade: chip revision lido em BAR4 (0xc900c020/c024, 0xc9004084) = `5c202021:7ca85ea9:0000b100`, idêntico ao dmesg → aritmética de endereço correta.

**INCIDENTE:** `dd if=/dev/mem bs=128 count=1 skip=$((0xc8940000/128))` (block-read de 128B no bloco ativo 0x140000) **DESLIGOU o PS4** (confirmado fisicamente). O offset 0 lia limpo, mas algum word entre 0x04–0x7c é registrador "veneno" → trava barramento do southbridge → watchdog do Syscon desliga. **Detalhe/regra em [[baikal-gbe-toque-trava-desliga-ps4]]: NÃO fazer block-read/varredura contígua do pervasive.**

**Conclusão estratégica:** sondar o hardware às cegas atrás do clock-gate da GBE é inviável (perigoso + agulha no palheiro). Próxima abordagem tem que vir de REFERÊNCIA, não de tentativa e erro: (a) driver GBE do kernel Orbis Baikal (FreeBSD, no firmware do PS4) que conhece a sequência exata de power-on; (b) notas/código mais completos da fail0verflow p/ Baikal; (c) datasheet Marvell Yukon 2 + doc do wrapper Sony. Sem uma dessas, o caminho da Ethernet fica bloqueado.

### 14. Análise dos dumps Orbis (2026-07-18) — userland NÃO tem power da GBE; está no kernel cifrado

Usuário coletou 43 arquivos do PS4 Pro via FTP/GoldHEN em `consolidado/dumps_orbis/` (ELF/SPRX FreeBSD x86_64 DESCRIPTOGRAFADOS + partições NOR). Relatório: `consolidado/RELATORIO_COLETA_DUMPS.md`. Payload movido p/ `ps4-linux-payloads/ps4-sflash0-dumper.bin`. Análise (objdump, offline, sem risco ao console):

- **CoreOS `sflash0s1.bin` (30MB, o kernel + drivers) está CIFRADA** (header "SONY COMPUTER ENTERTAINMENT INC.", sem strings) — NÃO temos o kernel em claro. `sflash0s1_crypt.bin` = cópia cifrada idem.
- **`mini-syscore.elf` e `libSceNet.sprx`: `gbe0` é só nome de INTERFACE de rede** (mini-syscore tem um mapeador nome→índice: lo0/eth0/eth1/dbg0/wlan0/wlan1/**gbe0**=idx6/bt0/phone0/pppoe0). O userland assume o barramento já ligado — não há sequência de power ali.
- **Nenhum binário liga `gbe` a power/clock/pcie/reset** (grep em todos os 15 ELF/SPRX = 0 hits).
- **`libkernel_sys.sprx` — prova definitiva:** wrapper de `/dev/icc_device_power` faz `open` → `ioctl(fd, 0x____9c__, &arg)` → `close`. IOCTLs presentes: **só 9c03/9c04/9c07/9c08** (usb+bd control/get), todos dentro do conjunto wlan/usb/hdd/bd (9c01–9c08). **NÃO existe 9c09+ para GBE.** Confirma 100% o teste ao vivo do item 13 (minor 0x41 = NAK): a GBE não é controlável por icc_device_power. `/dev/icc_power` (9901–990b) = boot status/powerup cause/tempo, nada de GBE.

**CONCLUSÃO:** o power/clock do barramento da GBE Baikal é feito pelo **driver GBE do kernel FreeBSD (CoreOS)**, que está cifrado — os dumps atuais (userland + NOR + CoreOS cifrada) NÃO contêm a sequência. Precedente: o `bpcie_baikal_sata_phy_init()` do fork foi RE'ado de um kernel Orbis 5.4 Baikal DESCRIPTOGRAFADO (o comentário cita "The 5.4 Baikal sequence"); a fail0verflow tinha esse kernel mas nunca fez a parte da GBE. **PRÓXIMO ALVO REAL: um dump do kernel Orbis DESCRIPTOGRAFADO p/ Baikal** (via payload kernel-dumper rodando no Orbis, OU o mesmo kernel 5.4 que a f0f usou) — aí achamos a sequência de registradores do glue/pervasive que liga o clock da GBE. Sem isso, a Ethernet continua bloqueada no clock-gate (item 13b: sondar o pervasive às cegas DESLIGA o console).
