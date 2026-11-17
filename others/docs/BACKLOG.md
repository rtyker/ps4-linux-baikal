# Backlog do Projeto — Fonte Única de Pendências

**Última atualização:** 2026-11-16 (noite — reconciliação após a sessão da tag `20261116-s5-dma`: S5 resolvido, DMA→SPM provado, build otimizado. Itens obsoletos fechados, novos acrescentados na seção "Pendências abertas em 2026-11-16".)

> ℹ️ **Como ler este arquivo:** itens `[x]` fechados guardam o histórico da solução; itens dentro de
> `<details>` com o título "Histórico da investigação" são **registro do que foi refutado**, não
> pendências ativas. O estado do momento é sempre a entrada mais recente por data dentro de cada item.

Este é o **único documento** onde a lista de tarefas pendentes do projeto deve ser mantida. Nenhum outro arquivo (`STATUS_ATUAL.md`, `MASTER_CONSOLIDADO.md`, `O_QUE_FALTA.md`, etc.) deve manter sua própria lista de "próximos passos" — todos apontam para cá, para evitar itens duplicados ou desatualizados espalhados pelo projeto.

Convenção: `[ ]` pendente · `[~]` em andamento · `[x]` concluído (mover para "Concluídos recentemente" ao fechar).

O trabalho **ativo no momento** (investigação detalhada, passo a passo) fica nos documentos próprios linkados em cada item — aqui fica só o resumo do estado e o próximo passo objetivo.

---

## 🎯 Plano de correção da falha de clock recovery no link DP (PS4 → MN864729)

**Objetivo:** o link DP interno (GPU UNIPHY → ponte Panasonic MN864729) deve treinar e travar em 1,62 Gbps (ou 2,7 Gbps) de forma determinística em todo modeset, sem falhar o `clock recovery`.

**Blocos de causa identificados:**
1. **Init do lado DP da ponte MN864729 ausente no Linux** — o bloco que configura os registradores DP do lado sink da ponte está em `#if 0` (`ps4_bridge.c:520-600`), comentário "No idea. DP stuff probably. This borks for some reason". O Orbis o fazia antes do kexec.
2. **Voltage/pre-emphasis fixos sem adaptação** — em todas as 5 tentativas de treino o driver usa `voltage 0.4V pre_emph 0dB` sem ler o `DPCD 0x00206/0x00207` (link status) do sink e sem ajustar via `amdgpu_atombios_dp_get_adjust_train`.
3. **Link DP não testado ao vivo antes do kexec** — o treino já falha no boot (2,4 s), mas a imagem funciona porque o Orbis já configurou a ponte. O Linux não reconfigura, só tenta travar um link que o Orbis deixou pronto.
4. **`ps4_bridge_post_disable` zera o estado** — reseta a ponte (`TSRST` completo) e apaga `mn_bridge->mode`. O próximo enable não retoma do estado anterior; começa do zero sem o init do lado DP.
5. **DP sink informa 5,4 Gbps / 4 lanes; o driver treina a 1,62 Gbps** — o DPCD lido é `12 14 c4 41` (DP 1.2, 5,4 Gbps, 4 lanes). O driver pede `clock=162000` (1,62 Gbps). Não há tentativa de 2,7 Gbps.

**Passos do plano (ordem de execução, cada um validado antes do próximo):**

| Passo | Ação | Validação | Artefato |
|---|---|---|---|
| 1 | **Ativar o init do lado DP da ponte** (remover `#if 0` do `ps4_bridge_pre_enable` ou mover para `ps4_bridge_enable` antes do retreino). O bloco contém `cq_writereg` nos registradores 0x7657/0x76a5/0x76a6/0x7601/0x7602/0x7603/0x76a8/0x76ae/0x76af/0x76b0/0x76b1/0x76b2/0x76db/0x76dc/0x76dd/0x76e4/0x76e6. | Build passa; `drm.debug` mostra sequência executada; após enable inicial, link treina sem falha. | Patch `ps4-bridge-dp-init.patch` |
| 2 | **Ajustar taxa do link para 2,7 Gbps** se o sink suportar (DPCD `MAX_LINK_RATE=0x0A`). Em `ps4_bridge_get_modes` ou no enable, checar `DPCD 0x00001` (MAX_LINK_RATE) e usar `clock=270000` (ou 5,4 Gbps se o cabo/ponte aguentar) antes do treino. | DPCD lido mostra `MAX_LINK_RATE ≥ 0x0A`; treino inicia em 2,7 Gbps; zero falhas de clock recovery em 10 cycles de modo. | Patch `ps4-bridge-link-rate.patch` |
| 3 | **Voltage/pre-emphasis adaptativos** — após cada falha de CR, ler `DPCD 0x00202-0x00205` (lane status) e chamar `amdgpu_atombios_dp_get_adjust_train` com os valores lidos, em vez de usar 0.4V/0dB fixo. Se o `dce_v8_0` já fizer isso, conferir por que o `adjust_train` retorna o mesmo valor. | `drm.debug` mostra voltage/pre-emph mudando entre tentativas; contagem de falhas de CR cai a 0 em modoset. | Patch `ps4-bridge-adaptive-train.patch` |
| 4 | **Não resetar a ponte no `post_disable`** — remover o `TSRST` completo do `ps4_bridge_post_disable` (ou torná-lo condicional a `mn_bridge->mode==0`). Manter `mn_bridge->mode` vivo entre ciclos de disable/enable. | Modo persiste entre `status=off/on`; `chvt` não re-inicializa a ponte; zero falhas de CR em `chvt 1`→`7`. | Patch `ps4-bridge-keep-state.patch` |
| 5 | **Teste de estresse** — script que faz 50 ciclos `chvt 1`/`chvt 7` + `xrandr --off/--mode` aleatórios sem `drm.debug`, monitorando falhas de CR via `dmesg -w`. Zero falhas em 50 ciclos = PASS. | Log de 50 ciclos sem `clock recovery failed`. | `ps4_link_stress.sh` |

**Critério de aceite único:** 50 trocas de modo consecutivas (qualquer combinação de `chvt`, `xrandr --off`, `xrandr --mode`, hotplug) com **zero** `clock recovery failed` no `dmesg`. A imagem não some.

**Ordem de execução:** 1 → 2 → 3 → 4 → 5. Cada passo é um patch independente, aplicado pelo `00-build-kernel-7.0.sh` com `--check`, testado em build separado antes do próximo. Não fazer "mega-patch" único.

**Estado atual (2026-11-16):**
- Passo 1: ✅ **FEITO** — `ps4-bridge-dp-init.patch` aplicado no build (linhas 511-520 do `00-build-kernel-7.0.sh`) + `ps4-bridge-keep-mode.patch`. **Validado ao vivo na tag `20261116-keep-mode-aplicado`**: console puro estável 1h45m+, DP link training ativo.
- Passo 2: ⬜ **Pendente** — ajustar taxa 2.7 Gbps (DPCD `MAX_LINK_RATE=0x0A` → `clock=270000`)
- Passo 3: ⬜ **Pendente** — voltage/pre-emphasis adaptativos via `amdgpu_atombios_dp_get_adjust_train`
- Passo 4: 🟡 **Parcial** — `keep-mode` preserva `mode` via flag `idle`; falta confirmar se `TSRST` completo removido/condicional
- Passo 5: ⬜ **Pendente** — teste de estresse 50 ciclos (`chvt`/`xrandr`)

---

## 🔴 Incidente 2026-11-15 ~19:56 — sem vídeo com teclado vivo (NumLock responde)

Sessão Cinnamon ativa em `tty7` (lightdm + Xorg `:0` no `vt7`), `card0-HDMI-A-1` `connected`/`enabled`/`dpms On`. O log mostra falha de treinamento de link DP (`clock recovery tried 5 times` / `failed`) quatro vezes em 0,5 s em `5852 s` de uptime, sem nova tentativa depois. Hipóteses: monitor/cabo HDMI perdeu sinal ou o link caiu durante o período ocioso (mesmo horário do teste de ociosidade). Pendente: confirmar no monitor (cabo, entrada, ligado) e, se persistir, reiniciar o lightdm (derruba a sessão do usuário).

**Diagnóstico adicional (2026-11-15, ~19:58):** o usuário confirmou que o cabo não foi mexido. Desligar/religar a saída (`xrandr --output HDMI-A-0 --off`/`--mode`) em 1080p@60 **continuou falhando** o treinamento de link (erros em 5993 s). Trocar para `1280x720 --rate 60` gerou nova falha em 6005 s e depois ficou estável; o usuário relatou que **o vídeo voltou** (após essa troca). O treinamento de link DP já falhava no boot (2,4 s) quando o vídeo funcionava, então a falha é intermitente e ligada à taxa do link. Próximo passo: confirmar se 720p estabiliza e testar 1080p de novo, um de cada vez.

**Reprodução (2026-11-15, 19:59):** o sinal sumiu de novo com a saída em 720p e **sem** erro de link no log. Troca 1080p→720p: falha de link em `6041 s` (1080p) e `6051 s` (volta a 720p). Conclusão parcial: o treinamento falha **a cada troca de modo**, não só em ociosidade; o sinal some quando a falha ocorre. Próximo: investigar o caminho de link (taxa/lanes, `amdgpu.dc`/`dp_link_rate`) antes de novos testes de modo.

**Diagnóstico (2026-11-15 20:01):** (1) a primeira falha de link (`5852 s` = **19:56:28**) ocorreu **sem nenhuma ação minha**, coincidindo com `idle-delay=900` s do Cinnamon (15 min sem entrada) → o screensaver/DPMS desliga a saída e o religamento falha no treino do link DP; (2) **todo modeset** (xrandr, `chvt`) dispara nova falha (`clock recovery failed` a 5993, 6003, 6005, 6041, 6051, 6153, 6159 s; 44 no total); (3) o Xorg loga `drmmode_do_crtc_dpms cannot get last vblank counter` a cada troca; (4) a falha já existia no boot (2,4 s) e o vídeo funcionava mesmo assim (retry posterior). Conectores seguem `connected/enabled/dpms On`, então o kernel não percebe a perda de sinal. Mitigação aplicada no PS4 (gsettings, usuário `ps4`): `idle-delay=0`, `sleep-display-ac/battery=0`, `lock-enabled=false`, `idle-dim-ac=false`. **Eliminado o Xorg (20:03):** `systemctl stop lightdm` (sem Xorg/Cinnamon) + `chvt 1` → **continua sem imagem nem no tty** → a perda de sinal está no driver/saída (amdgpu + ponte DP), não no servidor gráfico nem no Cinnamon. Tentativas sem sucesso, todas gerando nova falha de treino de link: `status=detect`, `status=off/on`, religar `vtcon1` (fbcon), `fb0/blank=0`, `xrandr --off/--mode`, `chvt 1/7`. Sem recursos de depuração: `CONFIG_DEBUG_FS` desligado (sem `/sys/kernel/debug/dri`). O caminho que falha é o **legado** `amdgpu_atombios_dp_link_train` (`amdgpu.dc=-1`); `forcelongtraining` é parâmetro só-leitura (exige cmdline) e pertence ao caminho DC, então pode não ter efeito. **Causa raiz de fundo (treino de link DP na ponte do PS4) segue aberta.** Relação provável com o item de "congelamento por ociosidade": o que parecia o PS4 desligando pode ser a tela apagando.

## 🔴 Novo (2026-11-15) — PS4 congela/desliga quando ocioso — EM TESTE

**Keep-alive descartado como mitigação:** o ping SSH a cada 20 s **não impediu** o sistema de desligar (observado pelo usuário em 2026-11-15). Não usar keep-alive como solução; ele só mascara o problema e polui os testes.

**Estado do teste (19:58):** keep-alive parado desde 19:43; `ping 192.168.6.128` responde (`LINUX_UP`). UART sem bytes em runtime (console só imprime no boot), então não há evidência de queda nesta janela ainda.

**Teste iniciado 2026-11-15:** keep-alive parado às **19:43:24** (host 19:45:13 para a UART). Tag `20261115-hwclock-min`, sem carga, `cpuidle` com estados POLL/C1/C2 (C2 com ~1,5 M usos no início). UART gravando por 30 min em `others/tests/uart_logs/idle-freeze_*.log`. Critério: se o `ping 192.168.6.128` ou o SSH param de responder, o congelamento está confirmado; a hora do último contato fica no log do keep-alive e a UART mostra a última mensagem do kernel.

---

## ✅ Teste ao vivo 2026-11-15 — tag `20261115-rtc-mem-restore` (restaura RTC + SPM)

Boot completo (UART mostrou kernel até o `console [tty0]`, tty1 subiu, SSH OK). Módulos novos instalados no rootfs do HD (causa do BTF mismatch: rootfs tinha módulos de build anterior) — nenhum erro de BTF no dmesg.

| Item | Resultado |
|---|---|
| `baikal-memory` + sysfs | ✅ `bar5_0x2f000` = `2c:cc:44:3f:69:5f`; `bar5_0x2c000` com dados; `/dev/baikal-memory` 0600 |
| `rtc-ps4-icc` | ✅ `/dev/rtc0` registra; `hwclock -w` OK e `/sys/class/rtc/rtc0/time` segue a hora do sistema |
| `hwclock -r` | ✅ **FUNCIONA** na tag `20261115-hwclock-min` — retorna `2026-11-15 18:20:34.848988-03:00`; fix `clear_bit(RTC_FEATURE_UPDATE_INTERRUPT)` confirmado ao vivo |
| Hora no boot | ❌ sobe em 2026-11-05 (hora da imagem; RTC é semeado pelo relógio do sistema, **não há fonte de tempo real**) |
| NTP | ❌ `timedatectl set-ntp` ativa o serviço mas `systemd-timesyncd` envia 0 pacotes (DNS e internet OK); contornado com `date -s` do host + `hwclock -w` |
| `smartd` | ❌ falha (`/dev/sdb` precisa de `-d removable`) |
| KVM | ✅ `/dev/kvm`, SVM/NPT |

### Correções aplicadas em 2026-11-15 (mesma sessão)
- **NTP ✅ validado ao vivo.** Causa raiz: `ONLINE_STATE=offline` em `/run/systemd/netif/state` — o `wlan0` é gerido pelo dhcpcd (`unmanaged` no networkd), então o `systemd-timesyncd` acha que está offline e nunca consulta servidor (0 pacotes, mesmo com DNS/internet OK e com servidores do NTP.br). Solução: `chrony` (independe do networkd) com `a/b/c/d.st1.ntp.br` + `br.pool.ntp.org`, `makestep 1.0 -1`, `rtcsync`. Evidência: `chronyc tracking` → offset 0,000000059 s, ref `200.20.186.76` (NIC.br); `timedatectl` → `System clock synchronized: yes`. Persistido em `distro/01-build-image-7.0.sh` (pacote `chrony`, `/etc/chrony.conf`, `chronyd` habilitado, `timesyncd` desabilitado).
- **smartd ✅** `/etc/smartd.conf` agora monitora o HDD interno `/dev/sda` (o `sdb` virou o SSD USB de boot, que não expõe SMART). `smartd` active, `systemctl --failed` vazio. Persistido no script da distro.
- **hwclock -r — causa raiz achada:** o core do RTC liga `RTC_FEATURE_UPDATE_INTERRUPT`+`ALARM` por padrão; com isso `RTC_UIE_ON` usa o caminho de alarme por IRQ, que o `rtc-ps4-icc` não tem, e o `hwclock` estoura o timeout. Fix: `clear_bit(RTC_FEATURE_UPDATE_INTERRUPT, rtc->features)` no probe → o core cai na emulação por polling (`CONFIG_RTC_INTF_DEV_UIE_EMUL=y`). **IMPLEMENTADO no driver** (`drivers/rtc/rtc-ps4-icc.c:158`) e **CONFIG habilitada no kernel** (`00-build-kernel-7.0.sh:858`). **Pendente: validar ao vivo em novo build** (tag `20261115-ntp-hwclock-fix` ou posterior). Histórico: o git NÃO mostra `hwclock -r` validado em nenhum momento (commit `68cf7c0` diz "ainda depende de UIE emulation").
- **Idempotência:** `clocksource-baikal-hpet.patch` e `baikal-wdt.patch` existiam mas nunca eram aplicados pelo `00-build-kernel-7.0.sh` (só entravam por estarem commitados na árvore local). Agora o script os aplica com `--check`+`exit 1`. Prova: os 8 patches aplicam em sequência, 2 ciclos de reset limpo, 0 falhas. Base da árvore do kernel: `9c260fc53`.

---

## ✅ Validado ao vivo 2026-11-15 — tag `20261115-hwclock-min` (config idêntico ao boot bom + fix do RTC)

Boot completo (tty1, SSH). Evidência:
| Item | Resultado |
|---|---|
| `hwclock -r` | ✅ retorna `2026-11-15 18:20:34.848988-03:00` (antes: `select() ... timed out`) — fix `clear_bit(RTC_FEATURE_UPDATE_INTERRUPT)` confirmado |
| NTP (chrony + NTP.br) | ✅ `Reference ID C8A007BA (a.st1.ntp.br)`, offset 0,000000096 s; `System clock synchronized: yes`; hora correta no boot, sem `date -s` |
| RTC | ✅ `/dev/rtc0`, `RTC time` = hora do sistema (UTC) |
| SPM | ✅ `bar5_0x2f000` = `2c:cc:44:3f:69:5f` |
| BTF | ✅ 0 ocorrências de "failed to validate module BTF"; `modprobe cifs` carrega |
| `systemctl --failed` | ✅ vazio (`smartd` e `chronyd` active) |
| Módulos | `baikal_dmac virt_dma mts baikal_memory rtc_ps4_icc` |

---

## ✅ KVM-AMD validado ao vivo (2026-11-15) — **JÁ HOMOLOGADO**

| Item | Status |
|---|---|
| `CONFIG_KVM` / `CONFIG_KVM_AMD` | ✅ Habilitados no `00-build-kernel-7.0.sh` (linhas 872-873) |
| `/dev/kvm` | ✅ Presente (`crw-rw-rw- root kvm`), `kvm_amd` com SVM, NPT, nested, TSC scaling |
| `qemu-base` | ✅ No `PKGS` do build (11.1.3, `qemu-system-x86_64`) |
| `virt-manager` / `libvirtd` | ✅ No `PKGS`, serviço ativo e habilitado |
| Teste guest | ✅ Boot sector 512 bytes (`K` na serial) rodou com `-accel kvm -cpu host`, saída capturada, guest executou e encerrou pelo timeout |

**Conclusão:** KVM-AMD **não é pendência** — já implementado, persistido no build e validado ao vivo. Item removido do backlog.

---

## ✅ lightdm ativo ao vivo (2026-11-15)

Causa da falha: o pacote `lightdm` estava instalado sem greeter (`Failed to find session configuration lightdm-gtk-greeter`), então o serviço caía e atingia `start-limit-hit`. Correção: `pacman -S lightdm-gtk-greeter` (2.0.9-2), `systemctl reset-failed` e `enable --now`. Estado: `lightdm` active, Xorg em `vt7` e `lightdm-gtk-greeter` rodando. Persistido em `distro/01-build-image-7.0.sh` (pacotes `lightdm`, `lightdm-gtk-greeter` e `systemctl enable lightdm`). Obs.: os `(EE)` de DEGAMMA_LUT/CTM/GAMMA_LUT nos CRTCs são só de color management, não impedem o uso. Pendente: login de usuário e validação de glamor no display do greeter.

---

## ✅ Mesa/Xorg validados ao vivo 2026-11-15 (tag `20261115-hwclock-min`)

Xorg 21.1.26 (`Xorg :0 vt2`, driver `amdgpu` + glamor) subiu sem erro de GPU. O Mesa 26.2.7 instalado **é o patchado** (reconhece `gladius`; o `pacman -Qi` só mostra o Packager do pacote original).
| Teste | Resultado |
|---|---|
| `glxinfo -B` | ✅ `AMD DG1501SML87LB (radeonsi, gladius, ACO, DRM 3.64)`, direct rendering: Yes, OpenGL 4.5 core/compat, GLES 3.2, VRAM 1024 MB |
| Xorg glamor | ✅ `glamor X acceleration enabled`, OpenGL 4.5 context |
| `vulkaninfo` | ✅ `AMD DG1501SML87LB (RADV GLADIUS)`, Vulkan 1.3.354, RADV, Mesa 26.2.7 |
| `eglinfo` | ✅ EGL 1.5, core profile 4.5 |
| `glxgears` | ✅ ~57-58 FPS (vsync 60 Hz) |
| dmesg | sem GPU hang/reset; só os `dp_link_train` do boot (já conhecidos) e `edid/my_edid.bin` ausente (inofensivo) |

Pendente: sem gerenciador de login (sddm/lightdm inativos) — Xorg sobe manualmente; `xrandr` não instalado; teste de `vkcube`/carga longa.

---

## 🔴 Incidente 2026-11-15: tela preta em 2 boots — tag `20261115-ntp-hwclock-fix`

UART parou em `kexec: About to relocate and jump to kernel`, sem nenhum byte do kernel (nem earlycon). Diferenças de config vs. o último boot bom (`20261115-rtc-mem-restore`): `CONFIG_WATCHDOG=y`/`WATCHDOG_CORE=y` (embutidos), `CLKSRC_MMIO=y` (embutido, `select` do driver HPET), `CLKSRC_BAIKAL_HPET=m`, `BAIKAL_WDT=m`; bzImage +8 KB. Cabeçalhos do bzImage (`init_size`, align, pref) idênticos → não é formato. **Causa não confirmada.** Mitigação: WATCHDOG e CLKSRC_BAIKAL_HPET desligados por padrão no `00-build-kernel-7.0.sh` (patches continuam aplicados); tag `20261115-hwclock-min` tem config **idêntico** ao boot bom (diff vazio) e bzImage do mesmo tamanho (16135168). HPET e WDT precisam de teste isolado, um por vez.

Pendências derivadas: (1) trocar o SSD/cabo USB (erros CRC no `sdb`); (2) ~~validar `hwclock -r` na tag nova~~ — **FEITO** na tag `20261115-hwclock-min`; (3) congelamento por ociosidade (acima).

---

## 🔴 Regressão registrada (2026-11-15)

O build `20261113-full-rebuild` final saiu SEM `rtc-ps4-icc` e SEM `baikal-memory` (edições minhas removeram os patches do script). `hwclock` sem acesso e data errada. **Revertido**: script oficial restaurado; árvore do kernel fixada em `9c260fc53` (base onde os 8 patches aplicam). Rebuild em andamento com a tag `20261115-rtc-mem-restore`. Os opcodes ICC `0x51/0x52` escritos à mão **não têm RE**: não usar; o RTC continua semeado pelo relógio do sistema (sem fonte de tempo real legível validada).

---

## 🚨 PRIORIDADE MÁXIMA — Testes ao vivo executados 2026-11-15 (tag `20261113-full-rebuild`)

**Tag testada:** `20261113-full-rebuild` (HD USB `/dev/sda`, kernel 7.0.8-Strawberry-ThinLTO-Baikal-+)
**Deploy:** MD5 origem→destino verificado (3/3 OK). Rootfs `psxitarch` intacto.

### Resultados dos Testes (2026-11-15 08:30-08:40)

| # | Teste | Resultado | Detalhes |
|---|-------|-----------|----------|
| 1 | **Boot completo + vídeo HDMI** | ✅ **PASS** | Kernel carrega, SSH ativo, vídeo 1080p@60 |
| 2 | **SSH via WiFi** | ✅ **PASS** | `192.168.6.128`, root/ps4 |
| 3 | **eth0 cabeada** | ⚠️ **PARCIAL** | mts.ko carrega (após strip BTF), MAC `2c:cc:44:3f:69:5f` correto, **NO-CARRIER** (PHY não linka — bloqueador de firmware Sony, não solucionável via driver) |
| 4 | **RTC via ICC** | ✅ **PASS** (timekeeping) | `/dev/rtc0` existe, `/proc/driver/rtc` mostra hora correta (2026-11-15), system clock semeado no boot. `hwclock -r` timeout (UIE emulation no driver + kernel, **pendente validação ao vivo**) |
| 5 | **Baikal Memory v0.2** | ⚠️ **PARCIAL** | Módulo carrega, BARs mapeados, MAC lido em **offset 0x52f000** (`2c:cc:44:3f:69:5f`), ICC em 0x52c000. Sysfs não expõe `bar5_0x2f000`/`bar5_0x2c000` (offsets no device file diferem do esperado) |
| 6 | **Áudio HDMI** | ✅ **PASS** | `plughw:0,3` (HDMI 0) e `plughw:0,7` (HDMI 1) funcionam com `speaker-test`/`aplay` |
| 7 | **SATA interno a 6 Gbps** | ✅ **PASS** | `ata1.00: configured for UDMA/100`, 931.51 GiB, `dd` 27 MB/s, **zero `disable device`** |
| 8 | **CIFS mount** | ⚠️ **PARCIAL** | cifs.ko no rootfs tem BTF mismatch. Após strip BTF, falha symbols desconhecidos. Precisa rebuild do módulo contra kernel atual. Autofs configurado mas mountpoint some. |
| 9 | **pacman (SSL/clock)** | ✅ **PASS** | `pacman -Sy` sincroniza sem erro de certificado/clock |
| 10 | **S5 power-off (luz azul)** | ✅ **PASS** — `poweroff -f` desliga tudo (tag `20261116-s5-dma`, 2026-11-16) | 2026-11-16, tag `20261116-btf-disabled-s5`: luz azul e fan ligados; sem log UART do Linux. Ver `PLANO_S5_POWEROFF_ICC.md` §9 |

### Checksums confirmados (tag `20261113-full-rebuild`)
```
MD5:
e7f9adaa9e0e85bf3fc35a980991eccc  bootargs-7.0-20261113-full-rebuild.txt
3703beaeb39cac9d78eeec6b70aa63c5  bzImage-7.0-20261113-full-rebuild
bcf0f61fabeb92b801759ebea54d549b  config-7.0-20261113-full-rebuild
d6a85464494c735654cb3d31de22f900  initramfs-7.0-20261113-full-rebuild.cpio.gz
```

### Rollback (se necessário)
```bash
sudo ./deploy-boot-7.0.sh 20261113-dmaengine /media/anderson/BOOT
```

---

## Prioridade alta

### [ ] ⚙️ Auditoria de boot/otimização da tag `20261112-sky2builtin` (levantada ao vivo em 2026-11-12)

Medições reais no PS4 (boot completo, `systemd` `running`, 0 unidades falhadas):
`Startup finished in 9.581s (kernel) + 34.394s (userspace) = 43.975s`.

**P1 — correções de configuração (baixo risco):**
- [x] `systemd-modules-load` tenta carregar `crypto_user`, mas `CONFIG_CRYPTO_USER is not set` (origem: `/usr/lib/modules-load.d/bluez.conf`). **Habilitado `CONFIG_CRYPTO_USER=y`** em `kernel/00-build-kernel-7.0.sh` (linha 706).
- [x] `mitigations=off` no cmdline era inócuo — removido do heredoc de bootargs em `distro/01-build-image-7.0.sh` (herdados `drm.debug`, `loglevel`, `keep_bootcon`, `earlyprintk`, `audit`, `netconsole` também removidos).
- [x] `netconsole` nunca ativa (`eth0` só nasce aos ~44 s) — removido do cmdline do bootargs.
- [x] `/etc/dhcpcd.conf` tem `denyinterfaces eth0` **duplicado** — corrigido para append idempotente (`grep -q` antes do `echo >>`) em `distro/01-build-image-7.0.sh` (linhas ~416-420).
- [ ] **Persistir o acesso do usuário `anderson` no build** (hoje é tudo alteração viva no PS4, some num rebuild do rootfs): criar o usuário (uid 1001), `/etc/sudoers.d/zz-anderson` (`NOPASSWD`, nome com `zz-` porque o sudo aplica a última regra que casa e `%wheel` ordena depois), `/home/anderson/.bashrc` com `PATH` do OpenCode e as chaves autorizadas. Decidir se a chave pública do host vai no build (aceitável) e **não** embutir chave privada. O `opencode` em si (247 MB) deve continuar sendo instalado em runtime, não no rootfs.
- [x] `PermitEmptyPasswords yes` no `sshd_config` (em duplicidade): cada conexão SSH gerava uma falha no `pam_faillock` e travava a conta em 3 logins. Corrigido em 2026-11-12 — `PermitEmptyPasswords no` no PS4 e o build agora usa o drop-in `/etc/ssh/sshd_config.d/00-ps4-baikal.conf` (idempotente) em vez de reescrever o `sshd_config`.
- [x] `pam_faillock` × `audit=0`: o cmdline tem `audit=0`, mas o kernel tem `CONFIG_AUDIT=y` e o `pam_faillock.so` está no `system-auth`; cada login SSH gerava `pam_faillock(sshd:auth): Error sending audit message: Protocol not supported`. Removido `audit=0` do bootargs (`distro/01-build-image-7.0.sh`) — o `journald` já tem `Audit=no`, então o ruído não volta.
- [x] ✅ **BTF mismatch dos módulos** — OBSOLETO desde 2026-11-16: o BTF está **desligado** no kernel e o `distro/scripts/install-modules-7.0.sh` ainda faz o strip. Os módulos do rootfs foram reinstalados por ele (todos com `srcversion` igual ao do build `20261116-s5-dma`).
- [ ] **Módulos faltando no rootfs:** `baikal_wdt.ko` e `baikal-hpet.ko` não são gerados (o `install-modules` avisa "não encontrado") porque `CONFIG_BAIKAL_WDT`/`CONFIG_BAIKAL_HPET` estão desligados desde uma tela preta antiga. Precisam de teste isolado (ver seção ACPI/HPET/WDT abaixo).

**P2 — otimização de boot (44 s → meta ~15-20 s):**
- [x] **33 s** de `systemd-modules-load` eram o `mts.ko` — auto-carregamento DESATIVADO em 2026-11-12 (decisão do usuário: Ethernet fica para o futuro): `distro/01-build-image-7.0.sh` agora só cria `/etc/modules-load.d/mts.conf` quando `ENABLE_MTS=1`; no PS4 o arquivo foi renomeado para `mts.conf.disabled`. O `mts.ko` continua instalado e pode ser carregado à mão (`modprobe mts`, usa `stage=4` do `modprobe.d`). **Reativar:** `ENABLE_MTS=1 sudo ./01-build-image-7.0.sh <TAG>`, ou no rootfs vivo `mv /etc/modules-load.d/mts.conf{.disabled,}`. Quando retomar o trabalho de Ethernet: mover o carregamento para uma unit própria depois de `multi-user`/`network-pre`, em vez de `modules-load` (para não bloquear o boot).
- [x] `drm.debug=0x06` + `loglevel=8`: 257 das 1321 linhas do dmesg eram `drm`. Removidos do bootargs de produção (mantém `drm.debug=0` implícito e `loglevel` padrão).
- [x] `keep_bootcon earlyprintk=efi,keep` — removido do bootargs de produção.
- [x] `ldconfig.service` gasta 1,0 s; com `ld.so.cache` já pronto — mantido como `static` (condition-based), só roda quando necessário. Funciona corretamente, não requer ação.
- [x] Console serial UART custa 2,4-7 s no probe do `ata1` — mantido no bootargs (obrigatório para diagnóstico via `earlycon=uart8250,mmio32,0xC890E000`; ver convenções de bootargs no AGENTS.md).

**P3 — runtime (pendências validadas ou descobertas nos testes 2026-11-15):**
- [x] `/etc/fstab` gerado com raiz + CIFS — `distro/01-build-image-7.0.sh` (linhas ~701-705): `LABEL=psxitarch / ext4 rw,noatime,errors=remount-ro 0 1` + `//192.168.6.101/dados_aux /mnt/hdauxiliar cifs credentials=...,uid=1001,gid=1001,..._netdev,nofail,x-systemd.automount 0 0` + `mkdir -p /mnt/hdauxiliar`.
- [x] Sem `smartd` (instalado, serviço `disabled`) e sem `paccache`: o cache do pacman está em **767 MB / 413 pacotes** num SSD que está falhando. Implementado no build de `distro/01-build-image-7.0.sh`: `pacman-contrib` adicionado ao `PKGS` (linha ~209); `/etc/smartd.conf` gerado com `/dev/sdb -d sat -a -m root` (SMART via bridge USB JMicron); `smartd.service` e `paccache.timer` habilitados via `systemctl enable` no chroot.
- [x] **`fstrim` não é suportado** por este enclosure: `/sys/block/sdb/queue/discard_max_bytes=0` (`fstrim /` → "the discard operation is not supported"). **Não** habilitar `fstrim.timer`; sem TRIM o SSD degrada mais rápido. Item considerado resolvido: não há ação a tomar além de não habilitar o timer.
- [x] `/etc/mkinitcpio.conf.pacnew` — resolvido: o script `distro/01-build-image-7.0.sh` já gera `/etc/mkinitcpio.conf` diretamente (linha ~538) com `MODULES` e `HOOKS` específicos do PS4 (`ext4 ahci sd_mod ... mts usbhid uas usb_storage`, HOOKS `base udev modconf block filesystems keyboard fsck set-time-from-cmdline`), então não há `.pacnew` pendente.
- [x] `archlinux-keyring-wkd-sync.service` gastou **2min13s** no boot atual — implementado override no build (`distro/01-build-image-7.0.sh` linhas ~419-427): `OnBootSec=10min`, `Persistent=false`, `RandomizedDelaySec=30min`. **Validado ao vivo 2026-11-13** — timer ativo com trigger atrasado, não roda no boot.
- [x] Sem swap e sem uso de zram: `/dev/zram0` existe, `SwapTotal=0`, mas `zswap.enabled=1` — zswap sem swap não faz nada. Implementado no build (`distro/01-build-image-7.0.sh`): `zram-generator` adicionado ao `PKGS` (linha ~237); `/etc/systemd/zram-generator.conf` gerado com `zram-size = ram/2`, `compression-algorithm = zstd`, `swap-priority = 100`; `zswap.enabled=1` removido do bootargs. **Validado ao vivo 2026-11-13:** zram0 3.4 GiB ativo como swap (zstd), zswap desabilitado (`N`).
- [~] **`cpufreq` — config habilitado, `cpupower` NÃO instalado:** `amd_pstate` falha (`the _CPC object is not present in SBIOS`), `CONFIG_X86_ACPI_CPUFREQ=y` habilitado no kernel. **Falta:** adicionar `cpupower` ao `PKGS` no `01-build-image-7.0.sh` + rebuild distro + deploy para validar `cpupower frequency-info`.
- [x] ✅ **SATA interno UDMA/100 (3.0 Gbps link) — LIMITE DE HARDWARE** — `libata.force=1.00:3.0Gbps` removido do bootargs; `ahci.mobile_lpm_policy=1` removido. O drive `TOSHIBA MQ04ABF100` é SATA 6 Gbps mas o controlador/porta do PS4 negocia **3.0 Gbps** (SStatus 123 SControl 300). `ata1.00: configured for UDMA/100`, `dd` 27 MB/s, zero `disable device`. **Não é bug — é limite físico da porta SATA do PS4.** Item fechado.
- [~] **cgroup v1 — bootargs legacy removidos, PROVAVELMENTE OK:** `systemd.unified_cgroup_hierarchy=0` e `systemd.legacy_systemd_cgroup_controller=yes` removidos do bootargs. Kernel `CONFIG_CGROUP_V2=n`. Ao vivo: cgroup2 montado, hierarquias v1 ativas (cpu, cpuacct, blkio, devices, freezer, net_cls, perf_event, hugetlb, pids, misc, dmem, debug). **Provavelmente funcional sem warnings** — confirmar no próximo rebuild distro.
- [x] `usb usb3-port1/usb4-port1: over-current condition` com as duas portas vazias — ruído esperado do xhci_aeolia, ignorar. Item considerado resolvido: não há ação a tomar.
- [ ] **Baikal Memory: ajustar offsets sysfs** — offsets no device file (`/dev/baikal-memory`: MAC em 0x52f000, ICC em 0x52c000) divergem dos atributos sysfs (`bar5_0x2f000`, `bar5_0x2c000`). Corrigir driver para expor offsets corretos.
- [x] ✅ **RTC: `hwclock -r` FUNCIONA** — validado ao vivo na tag `20261115-hwclock-min` (retorna `2026-11-15 18:20:34.848988-03:00`). Fix `clear_bit(RTC_FEATURE_UPDATE_INTERRUPT)` + `CONFIG_RTC_INTF_DEV_UIE_EMUL=y` confirmados no build atual.
- [x] **Adicionar `alsa-utils` ao `PKGS`** — **JÁ PRESENTE** em `distro/01-build-image-7.0.sh` linha 244.
- [x] ✅ **S5 power-off (luz azul)** — RESOLVIDO 2026-11-16: `poweroff -f` desliga o console por completo na tag `20261116-s5-dma` (patch `ps4-icc-s5-poweroff-prepare.patch`). Ver o item `[x]` mais abaixo e `PLANO_S5_POWEROFF_ICC.md` §12. Pendente só `shutdown -h now`/`reboot` (seção nova).
- [x] ✅ **Mesa patchado (Gladius/Liverpool)** — confirmado incluído no full-rebuild `20261113-full-rebuild` (o dmesg do teste ao vivo mostrou `gladius`). Reabrir só se for atualizar o Mesa (`distro/mesa/01-build-mesa.sh`).
- [ ] **Adicionar `cpupower` ao `PKGS` + rebuild distro + deploy** para validar `cpufreq` (`CONFIG_X86_ACPI_CPUFREQ=y` já no kernel).
- [x] ✅ **SATA a 6 Gbps — LIMITE DE HARDWARE (3.0 Gbps)** — não é bug; controlador PS4 negocia 3.0 Gbps. `ata1.00: configured for UDMA/100` funcional.
- [ ] **Confirmar cgroup v1 sem warnings no próximo rebuild distro** (bootargs legacy removidos; ao vivo hierarquias v1 ativas).

---

### [ ] 🔍 Investigação de travamento do Xorg / SDDM pós-restart (hipótese: autostart do Steam)
**Contexto (2026-08-01):** Na primeira reinicialização do SDDM via SSH a interface gráfica subiu perfeitamente (`Session started true`, PID 1716). Na segunda tentativa de reinicialização do SDDM/Xorg, a rede/interface gráfica travou.
**Hipótese do Usuário:** O travamento pode ter sido causado por autostart/inicialização em background do cliente Steam durante o re-login do SDDM. Validar e analisar logs em sessão posterior.

---

### [x] 🔒 GBE Ethernet — PHY nunca sai de power-down — INVESTIGAÇÃO ENCERRADA 2026-07-30 (bloqueador de firmware, não solucionável via driver Linux)

**Contexto:** MAC ligado com sucesso via ICC (`0x004=0xb19`), TX por software funcional (~95%, doorbell corrigido em 2026-07-25). Mas o PHY nunca responde a MDIO — Clause 45 (MMD1/MMD7) e Clause 22 (BMCR, scan completo endereços 0-31) sempre retornam zero/timeout. RX permanece morto (`MTS_CNT_PKTS=0`, ping 100% perda).

**Já descartado:** `MTS_MAC_EN2` como causa; hipótese de IRQ real (`IMR=0x7d`) reproduzindo full-duplex; correção do efuse (BAR4 em vez de BAR2) foi necessária mas insuficiente sozinha.

**🔒 FECHAMENTO FORMAL 2026-07-30 — RE completa da thread `gbe_phy_ctrl` (`dc5a44c0`):** 11 funções extraídas via Ghidra Java headless (Docker), árvore de chamada inteira analisada. **Nenhuma chamada ICC ou SAMU encontrada** — a thread só monitora o PHY via MDIO packed reads e dorme esperando eventos. Varredura binária do `kmem_dump_1252.bin` confirma: 0 cross-refs para `dc5a44c0`, 0 referências a ICC major=5 (SAMU) no range GBE, 0 referências a MMIO de mailbox SAMU no range GBE. **Conclusão: o power-on físico do PHY é feito pelo firmware/bootloader Sony antes do kernel Orbis assumir — não há sequência replicável via MDIO, ICC, SAMU ou RMU que um driver Linux possa executar.** Esta via de investigação está **esgotada com os dados disponíveis** — não reabrir sem fonte de dados nova (ex: vazamento de firmware, dump de SAMU, documentação de terceiros sobre o PHY Baikal). Detalhes em `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` e `memory/sessao-ghidra-java-passo1-2026-07-30.md`. Prioridade do projeto redirecionada para as frentes já ativas (S5 shutdown, KVM).

---

### [x] ✅ S5 no `poweroff -f` — RESOLVIDO 2026-11-16 (tag `20261116-s5-dma`)

**Contexto:** `sync && poweroff -f` encerra o SO e derruba a rede, mas o console fica com a luz azul acesa/pulsando — desligamento total da fonte (S5) não ocorre.

**Já feito:**
1. [x] RE no dump Orbis 12.52 (disassembly de `icc_power_shutdown`, offset `0x1d8a3c`): estrutura real do payload ICC S5 tem **20 bytes** (`cause` em `+0x0E`, `depth` em `+0x0F`, `hand` em `+0x10`) — o driver Linux enviava só 6 bytes truncados.
2. [x] Patch aplicado em `ps4-bpcie-icc.c` e `ps4-apcie-icc.c`: monta o payload de 20 bytes e loga o hex dump da resposta do MCU.

**Build + teste 2026-07-25 (tag `s5-poweroff-fix-20260725`):**
- `bzImage-7.0-s5-poweroff-fix-20260725` (15.84 MB) compilado e deployed via `deploy-boot-7.0.sh`
- **Teste ao vivo:** `sync && poweroff -f` → SO desliga (SSH cai), mas **luz azul permanece acesa/pulsando + fan ligado** = S5 **não** atingido
- dmesg pós-boot não mostrou log do ICC S5 shutdown (verificar se payload foi enviado)

**Correção 2026-11-16:** o item 2 de "Já feito" **não vale para a árvore atual**: o patch de julho nunca virou `.patch` e foi perdido; `icc_shutdown` voltou ao código original de 6 bytes (que já é enviado com 20 bytes por causa do padding `ICC_MIN_PAYLOAD`). A fonte RE `0x1d8a3c` **não existe no repo**. Ver `others/docs/PLANO_S5_POWEROFF_ICC.md` §0.

**✅✅ 2026-11-16 — RESOLVIDO:** `poweroff -f` com o kernel `20261116-s5-dma` (patch `ps4-icc-s5-poweroff-prepare.patch`) desliga o console por completo, luz e fan. `test_history` id 91; detalhes em `PLANO_S5_POWEROFF_ICC.md` §12. Pendente: `shutdown -h now`, `reboot` e promover a tag.

**✅ 2026-11-16 — CAUSA RAIZ CONFIRMADA (Fase 1):** o 4/1 original `{0,0,2,0,1,0}` enviado pelo ioctl `/dev/icc` (`others/tools/icc_cmd`) com o Linux rodando **desliga o console por completo** (luz apaga, fan para). O payload está certo; o problema é que o `icc_shutdown` roda no `pm_power_off` com LAPIC desligado e em contexto atômico. **Próximo:** Fase 2A, mandar o mesmo 4/1 num handler `SYS_OFF_MODE_POWER_OFF_PREPARE` (ver `PLANO_S5_POWEROFF_ICC.md` §10). `test_history` id 86.

**Teste 2026-11-16 (tag `20261116-btf-disabled-s5`):** ❌ Linux e monitor desligam, **luz azul e fan continuam ligados**. **Inconclusivo**: captura UART sem nenhuma linha do Linux, e o patch usado implementa offsets refutados e pode nem enviar o 4/1 (ver §9 do plano). **Próximo:** Fase 0 com UART do Linux confirmada + Fase 1 (ioctl `/dev/icc`, sem build).

---

## Prioridade média

### [x] 🌐 Habilitar o cliente CIFS/SMB no kernel do PS4 — **CONCLUÍDO 2026-11-12**

**Resultados:**
1. [x] Config adicionada ao `kernel/00-build-kernel-7.0.sh`: `CONFIG_CIFS=m`, `CONFIG_CIFS_XATTR=y`, `CONFIG_CIFS_POSIX=y`.
2. [x] Compilado no `adsv2` com TAG `20261112-cifs` em **41m11s**, sem erros. Snapshot salvo.
3. [x] Teste ao vivo **sem reboot** (2026-11-12 ~12:00): mount OK, `stat` reporta `1001:1001 anderson:anderson`, escrita sem `sudo` em dirs 775/777.
4. [x] Rootfs rebuildado em container Arch (`distro/scripts/build-image-docker.sh 20261112-cifs --incremental`): módulos no rootfs, initramfs + bootargs em `distro/boot_referencia/`.
5. [x] Persistido no `/etc/fstab` do PS4 **e na receita de build** `distro/01-build-image-7.0.sh` (geração de `/etc/fstab` + `mkdir -p /mnt/hdauxiliar`).
6. [x] Autenticação Samba real implementada: `smbpasswd -a anderson` no `adsv2`, removidas `guest ok = Yes` + `guest only = Yes` da share `[dados_aux]`; mount com `credentials=/etc/samba/credentials` no PS4. Escrita em dirs 755 (incl. `downloads`) funciona como `anderson` **sem `sudo`**.

**Critério de aceite ATENDIDO:** `findmnt /mnt/hdauxiliar` mostra `FSTYPE cifs`; `stat` reporta `1001:1001`; `anderson` cria/apaga arquivos sem `sudo` em dirs 775/777 **e 755**; montagem sobrevive a reboot via `x-systemd.automount`.

---

### [x] 🔴 Teste ao vivo da tag `20261111-preflight-test` — SUPERADO (2026-11-16)
**Superado:** esta tag foi substituída por todas as de 2026-11-13 a 2026-11-16, que já foram testadas ao vivo (vídeo, SSH, SATA, áudio HDMI, S5). Mantido só como histórico; o texto abaixo é do estado de 2026-11-11.
**Estado:** build + deploy testados em loopback; falta o teste no console real.
**Próximo passo exato:** `cd distro && sudo ./deploy-boot-7.0.sh 20261111-preflight-test` (HD USB plugado, partição BOOT montada), plugar o HD no PS4, power-cycle, e conferir: vídeo HDMI, SSH em `192.168.6.128`, `eth0` com MAC real em `192.168.0.2/24` (ping do host `192.168.0.1` **na subnet cabeada**, nunca `192.168.6.x`), e `dmesg | grep -i 'ata1\|disable'` (SATA interno).
**Atenção:** a imagem foi gerada **sem o Mesa patchado** (Gladius/Liverpool) — a corrupção visual conhecida continua valendo até rodar `distro/mesa/01-build-mesa.sh` e refazer o build.

---

### [x] 🔴 Gerar/atualizar o Mesa patchado (Gladius/Liverpool) e refazer o build da distro — CONFIRMADO INCLUÍDO (2026-11-16)
**Estado:** `distro/mesa/mesa-ps4-gladius-liverpool-latest.tar.xz` existe (build 2026-11-13, 11.3 MB). O script `distro/01-build-image-7.0.sh` o referencia (linha 679) e extrai se presente.
**Próximo passo exato:** confirmar se o full-rebuild `20261113-full-rebuild` o incluiu (verificar `glxinfo -B` no dmesg do teste ao vivo mostrou `gladius` → **sim, incluiu**). Se precisar atualizar: `cd distro/mesa && ./01-build-mesa.sh` (produz o tar), depois refazer `./scripts/build-image-docker.sh <TAG>` e só então promote-release. A chave do patch está em `distro/mesa/`; ver `others/docs/MESA_GLADIUS_LIVERPOOL_FIX.md`.

---

### [x] 🔵 Decidir a estrutura da fonte do driver MTS — **DECIDIDO 2026-11-13**
`drivers_mts/` é a **fonte única autoritativa** (mts.c, mts.h). O patch `kernel/patches/mts-baikal-kconfig.patch` contém **apenas** Kconfig/Makefile do vendor Sony (drivers/net/ethernet/sony/Kconfig + Makefile). O driver em si vem de `drivers_mts/` copiado direto para a árvore do kernel no build. Patch antigo `mts-baikal-gbe-driver.patch` (3.200+ linhas) → **substituído** por `mts-baikal-kconfig.patch` (~50 linhas). Build script aplica patch Kconfig/Makefile, depois copia `drivers_mts/mts.c` e `drivers_mts/mts.h` para `drivers/net/ethernet/sony/`. Elimina duplicação ~3.200 linhas; mantém idempotência.

---

### [x] 🏆 SATA interno (HD Toshiba MQ04ABF100) — **FEATURE CONCLUÍDA 2026-07-30, funcional pela primeira vez**
**Resolvido via Fase B (polling timer de 1ms) do `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md`, testado ao vivo na tag `20260730-sata-polling-fase-ab`:**
- `ata1.00: configured for UDMA/100`, zero exceções/`disable device` em todo o dmesg (1322 linhas).
- Leitura real confirmada: `dd if=/dev/sda bs=1M count=50` → 71.2 MB/s sem erro. `fdisk -l /dev/sda` retorna a tabela completa (931.51 GiB).
- `PxIE` ficou em `0x7840007f` após o único `thaw()` do probe (t=3.02s) e nunca mais zerou (antes reincidia ~37s e desabilitava ~84s).
- **Novo baseline oficial/ponto de rollback:** tag `20260730-sata-polling-fase-ab`. Patch atual: `patches/ahci-baikal-polling-fallback.patch` (contém as duas pontas: função `.2` e `.7`).
- **Ressalva 2026-08-01:** o patch foi **perdido e reconstruído** naquele dia; a reconstrução inicial colocou o timer na PCI function errada (`.2`, AHCI genérico) — `ata1` pertence à function `.7` (`xhci_aeolia`). O patch atual já contém as duas pontas e compila/aplica limpo, mas **não há registro de boot validando a tag `20260801-kvm-rtc-sata-final`** (a base do `RELEASE/v1.0.0`). Antes de tratar o `v1.0.0` como "SATA comprovado", um boot com `dmesg | grep 'polling timer started on xhci-aeolia'` + `ata1.00: configured for UDMA/100` por 90s+ é obrigatório.

---

### [x] 🔑 Obter a chave EAP real via EAPDumper — **CONCLUÍDO 2026-07-31 / 2026-11-13**
Chave EAP canônica obtida ao vivo (5 dumps, 3 boots): sha256 `990c1aa3…c8bf` — **estável entre 3 boots** (entropia 4.88 constante no offset real `0x026C4CF0`). A chave em si **não** é registrada em documento (só em `.env.keys`, gitignored).
**🔴 DESCOBERTA CRÍTICA 2026-07-31:** `pycryptodome 3.23.0` **não tem `MODE_XTS`** — todos os testes XTS anteriores foram **falso-negativo total**. Refiz com `cryptography 49.0.0` (XTS real, vetores NIST OK): **ZERO hits** em TODOS os testes. **Chave EAP está CORRETA**. **Falta o tweak/IV correto** — hipótese principal: `ivoffset_field` (`iVar2[0x20]`) ≠ 0 no `g_crypt_create_provider`.
**✅ RESOLVIDO em 2026-11-13:** o offset correto **não** é o LBA e sim o IV offset `(dev_no - 1) << 32` (`sda27` → `111669149696`), aplicado via `dmsetup` porque o `cryptsetup` não tem opção de `iv_offset`. Ver `MONTAGEM_HD_INTERNO.md` §2 e `LICOES_APRENDIDAS.md` #76.

---

### [x] 🏆 Montagem Nativa do HD Interno (/dev/sda) — **RESOLVIDO E VALIDADO AO VIVO (2026-11-13)**
✅ **`sda27` (user) MONTA read-only com a chave EAP** — 884 GiB, 485 GiB usados, `app/` com 44 títulos, `savedata`, `trophy`, `appmeta`, `bgft`. Também montam `sda29` (`eap_user`, UFS2) e `sda25` (`update`, FAT32).
**Causa raiz do bloqueio histórico:** o IV do dm-crypt nestes consoles (CUH-1100+/Baikal) é **`iv_offset = (dev_no - 1) << 32`** — com IV=0 o mapper decifra lixo (`bad magic number`). O `cryptsetup` não sabe aplicar isso (`--offset`/`--skip` são *data offset*), então o mapper é criado com `dmsetup create -r`. **Premissa errada corrigida:** `sda27` não é PFS, é **UFS2** (o PFS é o formato dos containers `app/<TITLE>/app.pkg` dentro dela); `sda13` **não é montável** (é o swap antigo, chave versioned_key + OpenPsId).

**Concluídas as 5 fases do plano:**
1. Inspeção completa das 29 partições, extração da chave EAP da NOR, derivação da chave XTS, validação de `cryptsetup` com `-o ro`.
2. Scripts modulares `/usr/local/bin/monta_particao.sh`, `desmonta_particao.sh`, `automount.sh` (chave em `/etc/ps4-keys/eap_hdd_key.bin`, provisionada com `distro/scripts/provisiona-chave.sh`). `sda27` monta com `iv_offset = 26 << 32` via `dmsetup`.
3. Cópia automática dos scripts e utilitários no gerador de imagens `01-build-image-7.0.sh`. Adicionado `sleuthkit` no `PKGS`.
4. Acesso total sem senha (`NOPASSWD: ALL` em `/etc/sudoers.d/ps4-hdd`) e regra udev `/etc/udev/rules.d/99-ps4-disk-permissions.rules` (permissão `0666` para `/dev/sda*`, `/dev/dm-*`, `/dev/mapper/`). Integrado no build.
5. Driver FUSE **`ps4_pfs_fuse`** (`/usr/local/bin/ps4_pfs_fuse`) com I/O sob demanda via `pread` para montagem/navegação transparente das partições PFS. Integrado ao build.

**Limpeza pendente (não bloqueante):** remover instrumentação de debug (`ahci_dbg:` em `freeze()`/`thaw()`/`ahci_error_handler()`) num próximo rebuild.

---

## Prioridade baixa

### [~] Enxugar o kernel: remover tudo que não é específico do PS4 nem tem uso prático — **1ª RODADA FEITA 2026-11-16**
**Objetivo:** reduzir o `.config` ao que o console realmente usa. Ganhos: builds mais rápidos, menor pico de memória, `bzImage` menor.
**Caso exemplar — `CONFIG_DEBUG_INFO_BTF`:**
- Gera metadados para **BPF CO-RE** (bpftrace, BCC, libbpf). Nada disso é usado aqui.
- Custo medido 2026-07-21: `pahole` consome **10,9 GB de RSS** (maior consumidor do build).
- Desabilitar **não desabilita BPF** (`CONFIG_BPF_SYSCALL` continua); só remove metadados.
- Projeto roda cgroup v1 (`systemd.unified_cgroup_hierarchy=0`), então nem usos de BPF do systemd pesam.
- **STATUS ATUAL (2026-11-16):** `DEBUG_INFO_BTF` e `DEBUG_INFO` (DWARF) **desligados**. **1ª rodada de enxugamento aplicada** em `00-build-kernel-7.0.sh`: 96 símbolos a menos (AMD Display Core, WiFi mt76/Marvell, btrfs, NFS, batman-adv, x25, ieee802154, mptcp, wireguard, virtio convidado). Medição, motivo de cada item e tempos em `OTIMIZACAO_BUILD_2026-11-16.md`. Boot validado ao vivo na tag `20261116-s5-dma`. **Falta:** uma 2ª rodada (candidatos: som USB, joystick/HID de fabricantes, SCSI/MD/RAID não usados, tty/serial legados, DRM de GPUs não-AMD) — só depois de congelar o config, para o ccache valer.
**Outros candidatos a avaliar** (não verificados ainda): drivers de hardware inexistente no console, FS não usados (só ext4, vfat, initramfs), subsistemas de virtualização já parcialmente desligados. `CONFIG_DEBUG_INFO` em si: avaliar caso a caso.
**Cuidado:** mudar o `.config` dispara recompilação ampla (~40 min). Agrupar todas as remoções em **uma única** rodada e testar o boot depois. Manter tag anterior em `boot_referencia/` para rollback.

---

### [ ] WiFi — manufacture data (NVRAM) ausente → movido para `others/rea/wifi/`
Pendência e plano de correção (NVRAM `/data/nvram/APCFG/APRDEB/WIFI`, país BR, MAC do eFUSE) agora vivem em [`others/rea/wifi/plans/PLANO_DRIVER_WIFI_BAIKAL.md`](../rea/wifi/plans/PLANO_DRIVER_WIFI_BAIKAL.md). Índice da pasta: [`others/rea/wifi/INDEX.md`](../rea/wifi/INDEX.md).

---

### [ ] Power Management — reativar DPM
`radeon.dpm=0 amdgpu.dpm=0` está fixo hoje por instabilidade de clocks dinâmicos. Reativar com testes de estresse quando houver tempo, não é bloqueador.

---

## 🔴 Pendências CRÍTICAS identificadas na varredura 2026-11-16 (não estavam no BACKLOG ou estavam desatualizadas)

### [x] ✅ **Passo 1 do plano DP: aplicar `ps4-bridge-dp-init.patch` no build** — CONCLUÍDO 2026-11-16
O patch **existe** (`kernel/patches/ps4-bridge-dp-init.patch`), **bloco de aplicação adicionado** no `00-build-kernel-7.0.sh` (linhas 511-520). **Aplicado e validado ao vivo** na tag `20261116-keep-mode-aplicado`: init do lado DP da ponte MN864729 ativo, DP link training funcionando. Juntamente com `ps4-bridge-keep-mode.patch` (keep-mode), console puro estável 1h45m+ idle.

### [~] **Módulos do rootfs: BTF resolvido; `baikal_wdt` e `baikal-hpet` ainda faltam**
- **BTF mismatch: RESOLVIDO** (2026-11-16). O kernel não tem BTF e o `install-modules-7.0.sh` faz o strip. Módulos reinstalados e conferidos por `srcversion`.
- **[ ] Faltam `baikal_wdt.ko` e `baikal-hpet.ko`:** os patches `baikal-wdt.patch` e `clocksource-baikal-hpet.patch` são aplicados, mas `CONFIG_BAIKAL_WDT`/`CONFIG_BAIKAL_HPET` estão desligados por causa de uma tela preta antiga. **Próximo:** build de teste isolado com cada um como `=m` (nunca `=y`), carregar ao vivo e conferir o boot.

### [ ] **Baikal Memory sysfs offsets desalinhados**
Device file `/dev/baikal-memory` expõe MAC em offset `0x52f000` e ICC em `0x52c000`, mas atributos sysfs (`bar5_0x2f000`, `bar5_0x2c000`) não mostram dados. Driver `drivers/ps4/baikal-memory.c` precisa ajustar os offsets dos atributos para bater com o mapeamento real do device file.

### [x] ✅ **S5 power-off** — RESOLVIDO 2026-11-16 (tag `20261116-s5-dma`)
`sync && poweroff -f` desliga o console por completo (luz azul e fan). Causa raiz: o `icc_shutdown` rodava no `pm_power_off`, depois do `lapic_shutdown()`; o 4/1 `{0,0,2,0,1,0}` sempre esteve certo. Correção: enviá-lo em `SYS_OFF_MODE_POWER_OFF_PREPARE`. `test_history` ids 86 e 91.


### [ ] **DMAC2 (BAR2) sem IRQ — investigação pendente**
Driver `baikal-dmac` v0.1 carrega (visto no `lsmod`), `dmatest` **não rodou neste boot**. IRQ do DMAC2 (BAR2) não chega — DMAC1 (BAR0) tem IRQ MSI funcional; DMAC2 completa por polling (`hrtimer`). **Próximo:** rodar `dmatest` ao vivo + RE estática do `bpcie_handle_edge_irq` / `dmac_mtk.c` no Orbis para confirmar mapeamento BAR0↔DMAC1 / BAR2↔DMAC2.

### [x] ✅ **Módulo `rtc-ps4-icc`: `hwclock -r` FUNCIONA** — validado ao vivo na tag `20261115-hwclock-min` e no build atual. Fix `clear_bit(RTC_FEATURE_UPDATE_INTERRUPT, rtc->features)` (linha 158) + `CONFIG_RTC_INTF_DEV_UIE_EMUL=y` (linha 858) confirmados. Retorna hora correta sem timeout.

---

## Concluídos recentemente (referência — não repetir)

### [x] ✅ Reorganização do repo em duas frentes + **build da distro testado de ponta a ponta** (2026-11-11)
**Reorg (frente 1 / frente 2):** `kernel/` ficou só com build+patches; documentação do driver MTS consolidada em [`../../kernel/drivers_mts/`](../../kernel/drivers_mts/); acervo de RE em [`../rea/`](../rea/); harnesses e ferramentas em [`../tools/`](../tools/); `boot_referencia/` migrou para `distro/boot_referencia/` (fonte única, consumida pelas duas frentes).
**Build da distro validado de ponta a ponta** (tag `20261111-preflight-test`): kernel → bzImage 16.122.880 B, versão `7.0.8-Strawberry-ThinLTO-Baikal-+`, snapshot 559 MB; distro via Docker → rootfs Arch + initramfs (14.7 MB) + bootargs (578 B) + tar do rootfs (3,2 GB); deploy testado contra partição vfat de loopback (label `BOOT`, 200 MB): sanity, cópia, **MD5 origem→destino OK nos 3 arquivos**, `active-tag.txt` gravado.
**Bugs corrigidos na revisão:** 61/62 `.sh` versionados como `100644` → `chmod +x` + modo `100755` no git; wrapper Docker para host sem Arch; `mkinitcpio` aborta se módulo inexistente; initramfs modo 600 → 644; divergência silenciosa `drivers_mts/mts.c` × patch → build compara e aborta; `vram.txt` deixa de ser requisito; documentação initramfs corrigida (mkinitcpio resolve `root=LABEL=psxitarch` via blkid/udev).

### [x] ✅ `rootwait` no lugar de `rootdelay=10` — **10,5s de boot economizados, validado ao vivo 2026-07-28**
Medição isolando fase de initramfs: `rootdelay=10` = 21,7s; `rootwait` = 11,2s. Ganho de **10,5s**. `dmesg | grep -ic "Waiting for root"` = **0**. **Usar `rootwait` em todo bootargs novo.** Modelo: `boot_referencia/bootargs-7.0-20260728-sata-diag.txt`.

### [x] **GPU amdgpu/Gladius (GFX/CP)** — `ring gfx test failed (-110)` resolvido 2026-07-23 com firmware genuíno via `kexec`; 32 CUs ativos, OpenGL 55 FPS, Vulkan 1.3.

### [x] **Migração para kernel 7.0 Baikal** — concluída 2026-07-22 (baseline `v7.0-20260722-clean-video-ok`).

### [x] **Rootfs completo via systemd (RELEASE, sem debug loop)** — validado ao vivo 2026-07-23.

### [x] **Ethernet GBE — MAC core e TX por software** — interface `eth0` sobe, MAC ligado via ICC, TX ~95% funcional (RX bloqueado por firmware).

### [x] **Kernel Dump 12.52 via TCP** — concluído 2026-07-20 (32.2 MB em 3s, zero corrupção).

### [x] ✅ Testes ao vivo completos na tag `20261113-full-rebuild` (2026-11-15) — ver tabela acima.

---

## Achado do RE (2026-07-28) — lock do ACK do glue diverge do Orbis
O `baikal_pcie_neighborhood.txt` continha a função `dc718b40`, equivalente Orbis do nosso `bpcie_handle_edge_irq()`. Catalogada em `decompiled_functions`, status `revisado`. Valores mágicos do demux **estão corretos**. Diferença: `0x110084` é seletor compartilhado entre func 4, 5, 7; acesso não-atômico (escreve seletor, lê máscara). Orbis serializa com **mutex global único**; nós usamos `raw_spin_lock(&desc->lock)` — por descritor, sem exclusão mútua entre descritores. **Provavelmente NÃO é causa da falha do SATA** (instrumentação mediu zero corridas). Corrigir mesmo assim, por ser bug real.

---

## Hardware — pendentes (re-verificação 2026-11-12/15)

### [x] ⚡ Ethernet GBE eth0 (00:14.1) — **MAC FUNCIONAL, PHY NÃO LINKA** (bloqueador de firmware) — validado 2026-11-15
Driver `mts` carrega e registra `eth0` com MAC correto `2c:cc:44:3f:69:5f` (lido da SPM). Anéis DMA programados, TX por software funcional. **NO-CARRIER** — PHY não responde a MDIO, link não sobe. Ping 100% perda (esperado sem link físico). **Módulo no rootfs tem BTF mismatch** — strip BTF via `objcopy` no `01-build-image-7.0.sh` resolve. **Causa raiz confirmada:** power-on físico do PHY é feito pelo firmware/bootloader Sony **antes** do kernel assumir. Não há sequência replicável via MDIO, ICC, SAMU ou RMU. Status: Driver funcional, MAC correto, TX pronto. **PHY não linka** — bloqueador de firmware, não solucionável via driver Linux. Reabrir só com nova fonte de dados.

### [x] 📶 Bluetooth — **FUNCIONANDO** (validado 2026-11-13)
Driver `btmtksdio` (MT7668) carregado e bound ao SDIO function 2. Controlador `hci0` detectado (MAC: `E8:D8:19:93:CC:AE`). Bluetooth daemon rodando, descoberta funcionando ("L3250 Series" detectado). **Teste do usuário:** Bluetooth, **áudio via Bluetooth em caixa de som** e **joystick** testados e funcionando. Pendente: parear DualShock 4 (testar se funciona com profile HIDP já habilitado).

### [~] 🔌 Baikal ACPI (00:14.0) — sem driver · HPET/WDT da glue (00:14.4) — driver inexistente
**a) Função ACPI `00:14.0` — SEM DRIVER (mantido).** PM1a_EVT `0x1000`, PM1a_CNT `0x1004`, PM_TMR `0x1008`, GPE0 `0x1014` já reclamados pelo núcleo ACPI. DSDT 396 bytes: nenhum objeto de dispositivo. Power button já implementado (`ps4-apcie-pwrbutton.c` / `icc_pwrbutton_init()` → `KEY_POWER` via ICC). Shutdown já implementado (`icc_shutdown` → `pm_power_off`). **Sleep/wake NÃO implementado** (`bpcie_icc_suspend()`/`bpcie_icc_resume()` são stubs vazios).

**b) HPET/WDT da glue `00:14.4` (subfunção ICC 22) — REABERTO, leitura ao vivo feita, driver inexistente.**
Leitura pontual (2026-11-13): `BAR2(00:14.4) + 0x109000` = `0xc8909000`, valor `0x05f5e10000002301` (REV_ID=1, NUM_TIM_CAP=3, LEG_RT_CAP=1, vendor ID=0x0000 atípico). **PS4 permaneceu ligado** — leitura segura. Validado em 2 boots (valor idêntico). Registrado em `readonly_verification` id 893. **Próximas tarefas:** `drivers/watchdog/baikal_wdt.c` (ou clocksource HPET) como `pci_driver` da glue, ligando `CONFIG_WATCHDOG`/`CONFIG_HPET` (hoje desligados). **Nenhuma escrita** em `0xc8909000` ou `0xc8909010` até driver pronto e validado. Plano: `others/rea/acpi/plans/PLANO_DRIVER_ACPI_BAIKAL.md`.

### [~] 🔄 Baikal DMA (00:14.5) — driver `dmaengine` `baikal-dmac` v0.1 **validado ao vivo** (dmatest 3000/0 falhas)
Dispositivo `104d:90dc`, dois controladores: BAR0 `ca000000` (DMAC1?) e BAR2 `ca800000` (DMAC2?), 4K cada. **Memcpy por descritor validado nos dois** (cadeia de descritores, até 1 MiB, alinhamentos 4–64 B, ~900 MB/s). **Interrupção MSI funciona no BAR0 e NÃO chega no BAR2.** Decisão: driver começa com IRQ no DMAC1 e **polling no DMAC2**.
**Concluído:** driver escrito (`drivers/dma/baikal-dmac.c`, v0.1), patch `baikal-dmac.patch` aplicado no build (`git apply --check` + `exit 1`), `CONFIG_DMA_ENGINE=y`, `CONFIG_DMA_VIRTUAL_CHANNELS`, `CONFIG_BAIKAL_DMAC=m`, `CONFIG_DMATEST=m`. Build tag `20261113-dmaengine` concluído e deployado no PS4 (2026-11-13). `baikal-dmac` carregou: `virt-dma` → `baikal-dmac`; `dma0chan0` e `dma0chan1`; IRQ 37 (DMAC1); sem erro. `dmatest`: 3000 testes, 0 falhas (canal 0 IRQ 200/200; canal 1 polling 200/200; 2 canais simultâneos 2400/2400). 3 ciclos `rmmod`/`insmod` sem problema.
**Falta:** persistir módulos no rootfs (item BTF mismatch), `CON` fora do alinhamento, `len=0`, erro induzido, e **IRQ do DMAC2** — `dmatest` não rodou neste boot; DMAC1 com IRQ, DMAC2 por polling.
**▶️ FRENTE REABERTA em 2026-11-16 (DMA → SPM):** o DMAC vê a SPM em `0xC0000000` (= BAR2 PCI + `0x40000000`; `0x80000000` dá erro). Leitura ~1,5 GB/s e escrita ~0,9 GB/s por DMA, contra ~4 MB/s e ~81 MB/s pela CPU. Provado com padrão aleatório gravado e relido, e escrita por DMA com guarda intacta (`test_history` 87–90; `PLANO_DMA_SPM_DDR3_2026-11-16.md` §8). **Próximo:** integrar no `baikal-memory` (ver seção nova). Pendências antigas desta frente continuam: IRQ do DMAC2, `CON` fora do alinhamento, `len=0`, erro induzido.

### [x] 💾 Baikal Memory (00:14.6) — Fases 1–5 **VALIDADAS AO VIVO** (2026-11-15); Fase 6 pendente
Módulo carrega (v0.2, vermagic OK). BARs mapeados: BAR0 (4 KiB), BAR2 (1 GiB endereçado, 256 MB real), BAR4 (1 MiB), BAR5 (256 KiB). `/dev/baikal-memory` expõe BAR0 @ 0x0, BAR2 (4 MiB) @ 0x1000, BAR5 @ 0x500000. **MAC real lido em offset 0x52f000**: `2c:cc:44:3f:69:5f` ✅. **Região ICC (spm.icc) em offset 0x52c000**: dados válidos ✅. Escrita controlada (`allow_write=0`) ativa por padrão.
⚠️ **Sysfs offsets:** atributos `bar5_0x2c000` e `bar5_0x2f000` **não expõem os dados** — mapeamento do device file usa offsets diferentes (MAC em 0x52f000 vs 0x2f000). Driver funciona via `/dev/baikal-memory` mas sysfs precisa ajuste (ver pendência crítica acima).

### [x] 🔊 Áudio HDMI (00:01.1) — **FUNCIONAL** (validado 2026-11-15)
`snd_hda_intel` carregado, dispositivos: `controlC0`, `hwC0D0`, `pcmC0D3p` (HDMI 0), `pcmC0D7p` (HDMI 1). `aplay -D plughw:0,3` e `plughw:0,7` → **áudio sai pelo HDMI** ✅. `speaker-test -t sine -D plughw:0,3` → tom 440Hz estéreo confirmado ✅. Dispositivo default (`default`) tem problema de dmix, mas hardware específico funciona. `alsa-utils` **já está no PKGS** (linha 244 do build).

### [x] 💾 Swap — **CONFIGURADO E VALIDADO** (2026-11-13)
Implementado no build: `zram-generator` no `PKGS`; `/etc/systemd/zram-generator.conf` com `zram-size = ram/2`, `compression-algorithm = zstd`, `swap-priority = 100`; `zswap.enabled=1` removido do bootargs. **Validado ao vivo 2026-11-13:** zram0 3.4 GiB ativo como swap (zstd), zswap desabilitado (`N`).

---

## ✅ Concluídos em 2026-11-15 — Full build `20261113-full-rebuild` COM SUCESSO

### Build completo executado e validado:
| Etapa | Status | Detalhes |
|-------|--------|----------|
| **ETAPA 1 - Kernel** | ✅ | Kernel 7.0.8-Strawberry-ThinLTO-Baikal-+ compilado com todos os patches (AHCI polling, RTC ICC, Baikal Memory, DMA, WDT, HPET, MTS, etc.) |
| **ETAPA 2 - Distro** | ✅ | Rootfs Arch via Docker, initramfs, bootargs limpos, Mesa patchado, módulos copiados (sem rebuild BTF), initramfs gerado |
| **ETAPA 3 - Burn** | ⚠️ | Falhou: `/dev/sda` não encontrado (HD USB não plugado — esperado) |

### Testes ao vivo executados no PS4 (2026-11-15, tag `20261113-full-rebuild`):
(Ver tabela na seção PRIORIDADE MÁXIMA acima)

### Artefatos gerados (tag `20261113-full-rebuild`):
- `bzImage-7.0-20261113-full-rebuild` (16.1 MB)
- `config-7.0-20261113-full-rebuild`
- `initramfs-7.0-20261113-full-rebuild.cpio.gz` (23.8 MB)
- `bootargs-7.0-20261113-full-rebuild.txt` (limpo, sem drm.debug/netconsole/audit)
- Sentinela `.build-complete-20261113-full-rebuild`

### Correções aplicadas nos scripts de build (2026-11-15):
| Item | Arquivo | Mudança |
|------|---------|---------|
| Patch `baikal-memory-fase2.patch` removido | `kernel/00-build-kernel-7.0.sh` | Driver já na árvore (commit 9c260fc53) |
| Patch `ps4-icc-rtc-wrapper.patch` removido | `kernel/00-build-kernel-7.0.sh` | Driver RTC escrito manualmente (evita truncamento) |
| Rebuild módulos removido | `distro/01-build-image-7.0.sh` | Módulos copiados do kernel build (sem rebuild BTF) |
| Driver RTC corrigido | `drivers/rtc/rtc-ps4-icc.c` | `timer_delete` + UIE emulation + sintaxe corrigida |

### Itens pendentes para próximos builds/testes (consolidados das pendências críticas acima):
1. [x] ✅ **Aplicar `ps4-bridge-dp-init.patch` no build** — CONCLUÍDO 2026-11-16 (bloco de aplicação adicionado, validado ao vivo tag `20261116-keep-mode-aplicado`)
2. [~] **Módulos faltando (baikal_wdt, baikal-hpet)** — o BTF mismatch está resolvido (BTF desligado + strip no `install-modules`); falta gerar esses dois módulos (teste isolado, `=m`)
3. [ ] **Baikal Memory sysfs offsets** — device file: MAC `0x52f000`, ICC `0x52c000`; sysfs `bar5_0x2f000`/`bar5_0x2c000` vazios → ajustar `drivers/ps4/baikal-memory.c`
4. [x] ✅ **RTC: `hwclock -r` FUNCIONA** — validado ao vivo na tag `20261115-hwclock-min` e build atual; fix confirmado.
5. [x] ✅ **S5 power-off (luz azul)** — RESOLVIDO 2026-11-16 (tag `20261116-s5-dma`)
6. [x] ✅ **Mesa patchado** — confirmado incluído no full-rebuild (gladius no dmesg)
7. [ ] **Adicionar `cpupower` ao `PKGS` + rebuild distro + deploy** para validar `cpufreq` (`CONFIG_X86_ACPI_CPUFREQ=y` já no kernel)
9. [x] ✅ **SATA a 6 Gbps — LIMITE DE HARDWARE (3.0 Gbps)** — não é bug; `ata1.00: configured for UDMA/100` funcional.
10. [ ] **Confirmar cgroup v1 sem warnings no próximo rebuild distro** (hierarquias v1 ativas ao vivo)

---

## 🆕 Pendências abertas em 2026-11-16 (sessão da tag `20261116-s5-dma`)

1. [x] ✅ **`shutdown -h now` (systemd) e `reboot`** — **homologados pelo usuário em 2026-11-16** com o kernel `20261116-s5-dma` (`test_history` ids 92 e 93; sem log, pois a UART do Linux segue muda). Com o `poweroff -f` (id 91), o S5 está completo. Obs.: o `bpcie` não tem `icc_reboot`; o reboot funciona pelo caminho padrão do kernel.
2. [x] ✅ **Tag `20261116-s5-dma` promovida** para `distro/RELEASE/20261116-s5-dma/` (2026-11-16, `promote-release.sh … --no-tar`: 4 artefatos + `sha256sums.txt`, conferidos). **Sem tarball da distro:** o `arch_minimal_v2-7.0.tar` existente é do build da tag anterior (módulos antigos), então não foi linkado. Gerar o tarball dessa tag exige um `01-build-image` completo. A pasta é gitignored (só `README.md` e `v1.0.0/` são versionados).
3. [x] ✅ **DMA integrado no `baikal-memory` e validado ao vivo (2026-11-16)** — plano em `others/rea/spm/plans/PLANO_BAIKAL_MEMORY_DMA_2026-11-16.md` (resultados na §5.1; `test_history` 94–97). Patch `kernel/patches/baikal-memory-dma.patch` (via `dmaengine` do `baikal-dmac`), aplicado pelo `00-build-kernel-7.0.sh`. Leitura de 1 MiB: 547–624 MB/s contra 4,1 MB/s da CPU; escrita de 64 KiB por DMA lida de volta idêntica. Corrigidos no caminho: `len=0` (`dma_chunk` antes da alocação do bounce), divisão cabeça/miolo/cauda, reaquisição do canal sob demanda, `use_dma` padrão ligado. **Falta gravar no HD** (item 3c). Plano mãe fechado: `others/rea/dma/plans/PLANO_DMA_SPM_DDR3_2026-11-16.md` §9.
3b. [x] ✅ 🐞 **Bug da lacuna `0x401000`–`0x4fffff` CORRIGIDO** no mesmo patch: a leitura devolve 0 bytes (fim de dados), sem oops (testado ao vivo, `test_history` 96). `cat /dev/baikal-memory` agora para no fim da janela do BAR2 e **não chega à BAR5** (`0x500000`); para ler a BAR5 use `skip=` no offset `0x500000`.
3c. [x] ✅ **Tag `20261116-dma-final` GRAVADA no HD e VALIDADA no console em 2026-11-16 (`test_history` 98 e 99).** Feito com o HD plugado no PC, montado em `/mnt/ps4_rootfs_7.0` e `/mnt/ps4_boot_7.0`: backup dos módulos em `lib/modules/backup-7.0.8-…-pre-20261116-dma-final`; `distro/scripts/install-modules-7.0.sh` (`rc=0`, 13 módulos; o `baikal-memory.ko` do rootfs tem o mesmo código do build, conferido seção a seção); `sudo distro/deploy-boot-7.0.sh 20261116-dma-final` (`md5` de `bzImage`, `bootargs` e `initramfs` conferidos origem→destino, partições desmontadas). `bootargs` e `initramfs` são cópias da `20261116-dma-test`. O `bzImage` tem 10,56 MiB, igual ao que rodava; o aviso de "acima de 10 MB" do script não se confirma. **Validação no console (boot que subiu):** módulo carregado sem parâmetros, `use_dma=Y`, `ativo DMAC1` após a primeira leitura (sobe `sem canal` porque o `baikal_dmac` ainda não foi pego), 1 MiB a 513–642 MB/s, `dmesg` sem erro. **Ressalva (item 3e):** a 1ª tentativa de boot desligou o console sozinho. Rollback: `sudo distro/deploy-boot-7.0.sh 20261116-dma-test` e restaurar `lib/modules/backup-…-pre-20261116-dma-final`. Os 4 módulos de rede/NLS (`tcp_bic`, `tcp_htcp`, `tcp_westwood`, `nls_ucs2_utils`) também foram reinstalados do build novo (sem mudança de fonte).
3d. [x] **Itens do DMA (todos tratados, exceto o 3e e o 3f abaixo):** (a) ✅ fallback por erro do DMAC **exercitado ao vivo** com injeção de falha (`dma_fault_inject=2` = erro real do DMAC; `=1` = aborto simulado; `test_history` 101 e 102). **Achou um bug real:** a versão gravada no HD usa `callback` e ignora o aborto do `baikal-dmac`, devolvendo dado velho do bounce com `dma_errors=0`; corrigido no patch com `callback_result` e validado (leitura certa pela CPU, `dma_errors=1`, DMA desligado, regressão do caminho normal OK); (b) um erro desliga o DMA até recarregar o módulo, e o `dma_state` não diz o motivo; (c) ✅ "nada além do limite muda" na escrita parcial: o hash da BAR5 não serve (dados vivos), mas um controle pareado de 10 rodadas sem escrita × 10 com escrita não achou nenhum offset que mude só com escrita (`test_history` 100); sem evidência de efeito, não é prova formal; (d) ✅ o `baikal-memory-dma-v2.patch` (abandonado, com o bug do `dma_chunk`) foi removido do repositório; (e) ✅ o bloco duplicado do `dd iflag=direct` sob o título do bug `len=0` no `AGENTS.md` foi apagado.
3e. [ ] **Console desligou sozinho na 1ª tentativa de boot da tag `20261116-dma-final` (2026-11-16)**, ao carregar o Linux; na 2ª tentativa subiu normal. **Causa desconhecida:** a captura de UART só rodou na 2ª. Com 2 boots não dá para dizer se é a tag (o `bzImage` é uma recompilação, 787 mil bytes diferentes do `dma-test`, com `config` idêntica) ou uma falha comum do processo de boot (exploit/kexec). Para decidir: bootar mais vezes com a UART capturando (`others/scripts/uart_start.sh`) e contar falhas; se repetir, o rollback é `deploy-boot-7.0.sh 20261116-dma-test`.
3f. [ ] **Regravar no HD o módulo com a correção do aborto do DMA (tag `20261116-dma-faultfix`).** A tag `20261116-dma-final` que está no HD tem o `baikal-memory.ko` que **ignora** um erro do DMAC (devolve dado velho do bounce, `dma_errors=0`). Isso só acontece se o DMAC der erro (não ocorre com o endereço correto da SPM), mas é um risco de integridade de dado. A correção está em `kernel/patches/baikal-memory-dma.patch` e foi validada ao vivo com o módulo carregado de `/tmp` (erro real do DMAC → fallback certo; regressão OK). Para gravar: HD no PC, `install-modules-7.0.sh` com o build atual da árvore e `deploy-boot-7.0.sh 20261116-dma-faultfix` (precisa de `bootargs`/`initramfs` copiados da `20261116-dma-test`, como na tag anterior). O `bzImage` não muda na prática (`baikal-memory` é `=m`).
4. [ ] **Console serial do Linux some com 0,63 s de boot:** `console=uart8250,…` é substituído por `tty0` (`/proc/consoles` só lista `tty0`), então nenhuma captura UART mostra o Linux. Já era assim antes do build novo. Sem isso, o S5 foi validado sem o log `pr_emerg` do handler.
5. [ ] **Ponte USB JMicron `152d:0578` do HD do PS4:** o modo UAS gerou erros de leitura e reset no host. O quirk `usb-storage` (`152d:0578:u`) vale só até reiniciar o PC; falta torná-lo permanente (`/etc/modprobe.d/`) e decidir o que fazer no PS4 (lição #79 já descreve o HD como instável).
6. [ ] **Áudio HDMI com som de verdade:** com o Display Core removido, os dispositivos HDMI aparecem (`HDMI 0`, `HDMI 1`, codec ATI R6xx), mas não foi tocado som depois do build novo (`speaker-test -D plughw:0,3`). `SND_HDA_COMPONENT` saiu junto com o DC.
7. [ ] **Limpeza no rootfs do PS4** (`psxitarch`): a pasta `/lib/modules/backup-7.0.8-…-pre-20261116-s5-dma` e os arquivos de teste em `/root` (`baikal_dmac_test_spm.ko`, `icc_cmd`) — remover quando não forem mais necessários.
8. [ ] **`config` na partição BOOT fica desatualizado:** o `deploy-boot-7.0.sh` não copia o `config` da tag (só `bzImage`, `initramfs`, `bootargs`). Só informativo, mas confunde a conferência.
9. [ ] **Congelar o config do kernel:** o ccache só acerta com o mesmo config (`OTIMIZACAO_BUILD_2026-11-16.md`). Medir o próximo build com o config igual (esperado: ~1 min de compilação + link com o cache do ThinLTO).
10. [ ] **Segunda rodada de enxugamento** (ver item "Enxugar o kernel").

Fora desta lista, por decisão do usuário: **`eth0`/GBE** (PHY mudo, bloqueador de firmware).

---


## Critério de aceite geral (hardware)
- Cada item `[ ]` acima só fecha quando o driver está carregado **e** o dispositivo é utilizável ao vivo no PS4 (não apenas "compila").
- Para itens sem solução via software (ex: GBE PHY), a tarefa fecha quando há documentação/fonte de dados que justifique o fechamento permanente ou quando uma nova abordagem viável é encontrada.
- Qualquer novo hardware descoberto deve ser adicionado aqui como `[ ]`, não em others documentos do projeto.