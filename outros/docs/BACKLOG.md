# Backlog do Projeto — Fonte Única de Pendências

**Última atualização:** 2026-11-15 (full build `20261113-full-rebuild` CONCLUÍDO COM SUCESSO: kernel + distro + deploy artifacts. Testes ao vivo: SATA ✅, RTC timekeeping ✅, Áudio HDMI ✅, SATA 6Gbps ✅, Baikal Memory device ✅/sysfs ⚠️, RTC timekeeping ✅, eth0 NO-CARRIER ⚠️, CIFS BTF mismatch ⚠️, S5 não testado. Build artifacts em `distro/boot_referencia/` tag `20261113-full-rebuild`. Próximos builds: corrigir BTF mismatch módulos (CIFS, MTS, etc.), sysfs offsets Baikal Memory, RTC UIE, S5, Mesa patchado.)

> ℹ️ **Como ler este arquivo:** itens `[x]` fechados guardam o histórico da solução; itens dentro de
> `<details>` com o título "Histórico da investigação" são **registro do que foi refutado**, não
> pendências ativas. O estado do momento é sempre a entrada mais recente por data dentro de cada item.

Este é o **único documento** onde a lista de tarefas pendentes do projeto deve ser mantida. Nenhum outro arquivo (`STATUS_ATUAL.md`, `MASTER_CONSOLIDADO.md`, `O_QUE_FALTA.md`, etc.) deve manter sua própria lista de "próximos passos" — todos apontam para cá, para evitar itens duplicados ou desatualizados espalhados pelo projeto.

Convenção: `[ ]` pendente · `[~]` em andamento · `[x]` concluído (mover para "Concluídos recentemente" ao fechar).

O trabalho **ativo no momento** (investigação detalhada, passo a passo) fica nos documentos próprios linkados em cada item — aqui fica só o resumo do estado e o próximo passo objetivo.

## 🔴 Novo (2026-11-15) — PS4 congela quando ocioso (gerenciamento de energia)

**Sintoma (relato do usuário):** com o Linux parado/ocioso o console "dorme" e fica congelado (SSH e vídeo mortos).
**Medido ao vivo na tag `20261113-full-rebuild`:** `/sys/power/state` NÃO existe (kernel sem suspend/PM de sistema), `consoleblank=0`, `logind.conf` sem `IdleAction`, `cpuidle` driver = `acpi_idle`, sem `cpufreq` em `cpu0` — ou seja **não é suspend do userspace**; a suspeita é C-state profundo (acpi_idle/HLT) ou o firmware/ICC cortando energia.
**Contorno:** keep-alive por SSH (`/tmp/ps4ssh.sh 'date'` a cada 20 s) durante builds/testes.
**Hipóteses a testar (uma por boot, com UART ligada):** `processor.max_cstate=1`; `idle=halt`; `idle=poll` (só diagnóstico); `nohz=off`; verificar se o freeze ocorre sem rede ociosa.
- [ ] Reproduzir deixando ocioso sem keep-alive e capturar UART; depois testar as hipóteses.


### Achado (2026-11-15) — sysfs do baikal-memory zerado: causa REAL
(Correção: a hipótese anterior "BAR2 em vez de BAR5" estava errada — `/dev/baikal-memory` `0x500000+` já mapeia o BAR5.) O sysfs antigo extraía o offset do nome do atributo com `simple_strtoul("bar5_0x00",…,16)`, que devolve `0xba`; e os offsets úteis (`0x2f000` MAC, `0x2c000` spm.icc) nem tinham atributo. Ambos já estão corrigidos em `kernel/patches/baikal-memory-fase2.patch` (atributos com offset/len explícitos, MAC via `%pM`). A tag `20261113-full-rebuild` ficou sem esse patch; a `20261115-rtc-mem-restore` o inclui — **validar** `cat /sys/bus/pci/devices/0000:00:14.6/bar5_0x2f000` = `2c:cc:44:3f:69:5f`. KVM: `/dev/kvm` OK (NPT, TSC scaling); PS4 aguentou 5+ min ocioso com keep-alive.

## ✅ Teste ao vivo 2026-11-15 — tag `20261115-rtc-mem-restore` (restaura RTC + SPM)

Boot completo (UART mostrou kernel até o `console [tty0]`, tty1 subiu, SSH OK). Módulos novos instalados no rootfs do HD (causa do BTF mismatch: rootfs tinha módulos de build anterior) — nenhum erro de BTF no dmesg.

| Item | Resultado |
|---|---|
| `baikal-memory` + sysfs | ✅ `bar5_0x2f000` = `2c:cc:44:3f:69:5f`; `bar5_0x2c000` com dados; `/dev/baikal-memory` 0600 |
| `rtc-ps4-icc` | ✅ `/dev/rtc0` registra; `hwclock -w` OK e `/sys/class/rtc/rtc0/time` segue a hora do sistema |
| `hwclock -r` | ❌ ainda dá `select() ... timed out` (UIE emulation não entrega o tick) — pendente |
| Hora no boot | ❌ sobe em 2026-11-05 (hora da imagem; RTC é semeado pelo relógio do sistema, **não há fonte de tempo real**) |
| NTP | ❌ `timedatectl set-ntp` ativa o serviço mas `systemd-timesyncd` envia 0 pacotes (DNS e internet OK); contornado com `date -s` do host + `hwclock -w` |
| `smartd` | ❌ falha (`/dev/sdb` precisa de `-d removable`) |
| **SSD do rootfs (`sdb`, Kingston SV300 USB)** | 🔴 erros de leitura `ASC=0x47 ASCQ=0x1` (CRC) em ~36 s e ~156 s de uptime — confirma o P0 "SSD corrompendo" |
| KVM | ✅ `/dev/kvm`, SVM/NPT |

### Correções aplicadas em 2026-11-15 (mesma sessão)
- **NTP ✅ validado ao vivo.** Causa raiz: `ONLINE_STATE=offline` em `/run/systemd/netif/state` — o `wlan0` é gerido pelo dhcpcd (`unmanaged` no networkd), então o `systemd-timesyncd` acha que está offline e nunca consulta servidor (0 pacotes, mesmo com DNS/internet OK e com servidores do NTP.br). Solução: `chrony` (independe do networkd) com `a/b/c/d.st1.ntp.br` + `br.pool.ntp.org`, `makestep 1.0 -1`, `rtcsync`. Evidência: `chronyc tracking` → offset 0,000000059 s, ref `200.20.186.76` (NIC.br); `timedatectl` → `System clock synchronized: yes`. Persistido em `distro/01-build-image-7.0.sh` (pacote `chrony`, `/etc/chrony.conf`, `chronyd` habilitado, `timesyncd` desabilitado).
- **smartd ✅** `/etc/smartd.conf` agora monitora o HDD interno `/dev/sda` (o `sdb` virou o SSD USB de boot, que não expõe SMART). `smartd` active, `systemctl --failed` vazio. Persistido no script da distro.
- **hwclock -r — causa raiz achada:** o core do RTC liga `RTC_FEATURE_UPDATE_INTERRUPT`+`ALARM` por padrão; com isso `RTC_UIE_ON` usa o caminho de alarme por IRQ, que o `rtc-ps4-icc` não tem, e o `hwclock` estoura o timeout. Fix: `clear_bit(RTC_FEATURE_UPDATE_INTERRUPT, rtc->features)` no probe → o core cai na emulação por polling (`CONFIG_RTC_INTF_DEV_UIE_EMUL=y`). Patch regenerado por `git diff`, compilado isolado e validado com `git apply --check`. **Pendente: validar ao vivo** (tag `20261115-ntp-hwclock-fix`). Histórico: o git NÃO mostra `hwclock -r` validado em nenhum momento (commit `68cf7c0` diz "ainda depende de UIE emulation").
- **Idempotência:** `clocksource-baikal-hpet.patch` e `baikal-wdt.patch` existiam mas nunca eram aplicados pelo `00-build-kernel-7.0.sh` (só entravam por estarem commitados na árvore local). Agora o script os aplica com `--check`+`exit 1`. Prova: os 8 patches aplicam em sequência, 2 ciclos de reset limpo, 0 falhas. Base da árvore do kernel: `9c260fc53`.

### ✅ Validado ao vivo 2026-11-15 — tag `20261115-hwclock-min` (config idêntico ao boot bom + fix do RTC)
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
| SSD `sdb` (rootfs USB) | 🔴 ainda 1 erro de leitura CRC (`ASC=0x47`) aos 97 s — trocar o SSD/cabo (P0) |

### ✅ lightdm ativo ao vivo (2026-11-15)
Causa da falha: o pacote `lightdm` estava instalado sem greeter (`Failed to find session configuration lightdm-gtk-greeter`), então o serviço caía e atingia `start-limit-hit`. Correção: `pacman -S lightdm-gtk-greeter` (2.0.9-2), `systemctl reset-failed` e `enable --now`. Estado: `lightdm` active, Xorg em `vt7` e `lightdm-gtk-greeter` rodando. Persistido em `distro/01-build-image-7.0.sh` (pacotes `lightdm`, `lightdm-gtk-greeter` e `systemctl enable lightdm`). Obs.: os `(EE)` de DEGAMMA_LUT/CTM/GAMMA_LUT nos CRTCs são só de color management, não impedem o uso. Pendente: login de usuário e validação de glamor no display do greeter.

### ✅ Mesa/Xorg validados ao vivo 2026-11-15 (tag `20261115-hwclock-min`)
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

### 🔴 Incidente 2026-11-15: tela preta em 2 boots — tag `20261115-ntp-hwclock-fix`
UART parou em `kexec: About to relocate and jump to kernel`, sem nenhum byte do kernel (nem earlycon). Diferenças de config vs. o último boot bom (`20261115-rtc-mem-restore`): `CONFIG_WATCHDOG=y`/`WATCHDOG_CORE=y` (embutidos), `CLKSRC_MMIO=y` (embutido, `select` do driver HPET), `CLKSRC_BAIKAL_HPET=m`, `BAIKAL_WDT=m`; bzImage +8 KB. Cabeçalhos do bzImage (`init_size`, align, pref) idênticos → não é formato. **Causa não confirmada.** Mitigação: WATCHDOG e CLKSRC_BAIKAL_HPET desligados por padrão no `00-build-kernel-7.0.sh` (patches continuam aplicados); tag `20261115-hwclock-min` tem config **idêntico** ao boot bom (diff vazio) e bzImage do mesmo tamanho (16135168). HPET e WDT precisam de teste isolado, um por vez.

Pendências derivadas: (1) trocar o SSD/cabo USB (erros CRC no `sdb`); (2) validar `hwclock -r` na tag nova; (3) congelamento por ociosidade (acima).

## 🔴 Regressão registrada (2026-11-15)
O build `20261113-full-rebuild` final saiu SEM `rtc-ps4-icc` e SEM `baikal-memory` (edições minhas removeram os patches do script). `hwclock` sem acesso e data errada. **Revertido**: script oficial restaurado; árvore do kernel fixada em `9c260fc53` (base onde os 8 patches aplicam). Rebuild em andamento com a tag `20261115-rtc-mem-restore`. Os opcodes ICC `0x51/0x52` escritos à mão **não têm RE**: não usar; o RTC continua semeado pelo relógio do sistema (sem fonte de tempo real legível validada).

---

## 🚨 PRIORIDADE MÁXIMA — Testes ao vivo para amanhã (2026-11-14) — **EXECUTADOS EM 2026-11-15**

**Tag testada:** `20261113-full-rebuild` (HD USB `/dev/sda`, kernel 7.0.8-Strawberry-ThinLTO-Baikal-+)
**Deploy:** MD5 origem→destino verificado (3/3 OK). Rootfs `psxitarch` intacto.

### Resultados dos Testes (2026-11-15 08:30-08:40)

| # | Teste | Resultado | Detalhes |
|---|-------|-----------|----------|
| 1 | **Boot completo + vídeo HDMI** | ✅ **PASS** | Kernel carrega, SSH ativo, vídeo 1080p@60 |
| 2 | **SSH via WiFi** | ✅ **PASS** | `192.168.6.128`, root/ps4 |
| 3 | **eth0 cabeada** | ⚠️ **PARCIAL** | mts.ko carrega (após strip BTF), MAC `2c:cc:44:3f:69:5f` correto, **NO-CARRIER** (PHY não linka — bloqueador de firmware Sony, não solucionável via driver) |
| 4 | **RTC via ICC** | ✅ **PASS** (funcional) | `/dev/rtc0` existe, `/proc/driver/rtc` mostra hora correta (2026-11-15), system clock semado no boot. `hwclock -r` timeout (driver não implementa UIE emulation), mas RTC **funciona para timekeeping** |
| 5 | **Baikal Memory v0.2** | ⚠️ **PARCIAL** | Módulo carrega, BARs mapeados, MAC lido em **offset 0x52f000** (`2c:cc:44:3f:69:5f`), ICC em 0x52c000. Sysfs não expõe `bar5_0x2f000`/`bar5_0x2c000` (offsets no device file diferem do esperado) |
| 6 | **Áudio HDMI** | ✅ **PASS** | `plughw:0,3` (HDMI 0) e `plughw:0,7` (HDMI 1) funcionam com `speaker-test`/`aplay` |
| 7 | **SATA interno a 6 Gbps** | ✅ **PASS** | `ata1.00: configured for UDMA/100`, 931.51 GiB, `dd` 27 MB/s, **zero `disable device`** |
| 8 | **CIFS mount** | ⚠️ **PARCIAL** | cifs.ko no rootfs tem BTF mismatch. Após strip BTF, falha symbols desconhecidos. Precisa rebuild do módulo contra kernel atual. Autofs configurado mas mountpoint some. |
| 9 | **pacman (SSL/clock)** | ✅ **PASS** | `pacman -Sy` sincroniza sem erro de certificado/clock |
| 10 | **S5 power-off (luz azul)** | ⏭️ **NÃO TESTADO** | Requer power-cycle dedicado, não testado para não perder estado atual |

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
- [x] `systemd-modules-load` tenta carregar `crypto_user`, mas `CONFIG_CRYPTO_USER is not set`
  (origem: `/usr/lib/modules-load.d/bluez.conf`). Habilitado `CONFIG_CRYPTO_USER=y` em
  `kernel/00-build-kernel-7.0.sh` (linha ~667).
- [x] `mitigations=off` no cmdline era inócuo — removido do heredoc de bootargs em
  `distro/01-build-image-7.0.sh` (herdados `drm.debug`, `loglevel`, `keep_bootcon`, `earlyprintk`,
  `audit`, `netconsole` também removidos).
- [x] `netconsole` nunca ativa (`eth0` só nasce aos ~44 s) — removido do cmdline do bootargs.
- [x] `/etc/dhcpcd.conf` tem `denyinterfaces eth0` **duplicado** — corrigido para append idempotente
  (`grep -q` antes do `echo >>`) em `distro/01-build-image-7.0.sh` (linhas ~416-420).
- [ ] **Persistir o acesso do usuário `anderson` no build** (hoje é tudo alteração viva no PS4, some
  num rebuild do rootfs): criar o usuário (uid 1001), `/etc/sudoers.d/zz-anderson`
  (`NOPASSWD`, nome com `zz-` porque o sudo aplica a última regra que casa e `%wheel` ordena depois),
  `/home/anderson/.bashrc` com `PATH` do OpenCode e as chaves autorizadas. Decidir se a chave
  pública do host vai no build (aceitável) e **não** embutir chave privada. O `opencode` em si
  (247 MB) deve continuar sendo instalado em runtime, não no rootfs.
- [x] `PermitEmptyPasswords yes` no `sshd_config` (em duplicidade): cada conexão SSH gerava uma
  falha no `pam_faillock` e travava a conta em 3 logins. Corrigido em 2026-11-12 — `PermitEmptyPasswords no`
  no PS4 e o build agora usa o drop-in `/etc/ssh/sshd_config.d/00-ps4-baikal.conf` (idempotente)
  em vez de reescrever o `sshd_config`.
- [x] `pam_faillock` × `audit=0`: o cmdline tem `audit=0`, mas o kernel tem `CONFIG_AUDIT=y` e o
  `pam_faillock.so` está no `system-auth`; cada login SSH gera
  `pam_faillock(sshd:auth): Error sending audit message: Protocol not supported`.
  Removido `audit=0` do bootargs (`distro/01-build-image-7.0.sh`) — o `journald` já tem `Audit=no`,
  então o ruído não volta.
- [ ] **Fix módulos com BTF mismatch no rootfs** — **ALTA PRIORIDADE**: `mts.ko`, `cifs.ko`, `baikal-dmac.ko`, `baikal_wdt.ko`, `baikal-hpet.ko`, `rtc-ps4-icc.ko` no rootfs têm BTF do build anterior e falham ao carregar. Solução: no `01-build-image-7.0.sh`, após `modules_install`, recompilar esses módulos contra o kernel atual ou fazer strip BTF + fix symbols. Necessário para CIFS, Ethernet, DMA, WDT, HPET, RTC funcionarem sem intervenção manual.

**P2 — otimização de boot (44 s → meta ~15-20 s):**
- [x] **33 s** de `systemd-modules-load` eram o `mts.ko` — auto-carregamento DESATIVADO em 2026-11-12
  (decisão do usuário: Ethernet fica para o futuro):
  `distro/01-build-image-7.0.sh` agora só cria `/etc/modules-load.d/mts.conf` quando
  `ENABLE_MTS=1`; no PS4 o arquivo foi renomeado para `mts.conf.disabled`. O `mts.ko` continua
  instalado e pode ser carregado à mão (`modprobe mts`, usa `stage=4` do `modprobe.d`).
  **Reativar:** `ENABLE_MTS=1 sudo ./01-build-image-7.0.sh <TAG>`, ou no rootfs vivo
  `mv /etc/modules-load.d/mts.conf{.disabled,}`. Quando retomar o trabalho de Ethernet: mover o
  carregamento para uma unit própria depois de `multi-user`/`network-pre`, em vez de
  `modules-load` (para não bloquear o boot).
- [x] `drm.debug=0x06` + `loglevel=8`: 257 das 1321 linhas do dmesg eram `drm`. Removidos do
  bootargs de produção (mantém `drm.debug=0` implícito e `loglevel` padrão).
- [x] `keep_bootcon earlyprintk=efi,keep` — removido do bootargs de produção.
- [x] `ldconfig.service` gasta 1,0 s; com `ld.so.cache` já pronto — mantido como `static` (condition-based), só roda quando necessário. Funciona corretamente, não requer ação.
- [x] Console serial UART custa 2,4-7 s no probe do `ata1` — mantido no bootargs (obrigatório para
  diagnóstico via `earlycon=uart8250,mmio32,0xC890E000`; ver convenções de bootargs no AGENTS.md).

**P3 — runtime (pendências validadas ou descobertas nos testes 2026-11-15):**
- [x] `/etc/fstab` gerado com raiz + CIFS — `distro/01-build-image-7.0.sh` (linhas ~701-705):
  `LABEL=psxitarch / ext4 rw,noatime,errors=remount-ro 0 1` +
  `//192.168.6.101/dados_aux /mnt/hdauxiliar cifs credentials=...,uid=1001,gid=1001,..._netdev,nofail,x-systemd.automount 0 0`
  + `mkdir -p /mnt/hdauxiliar`.
- [x] Sem `smartd` (instalado, serviço `disabled`) e sem `paccache`: o cache do pacman está em
  **767 MB / 413 pacotes** num SSD que está falhando. Implementado no build de
  `distro/01-build-image-7.0.sh`:
  - `pacman-contrib` adicionado ao `PKGS` (linha ~209);
  - `/etc/smartd.conf` gerado com `/dev/sdb -d sat -a -m root` (SMART via bridge USB JMicron);
  - `smartd.service` e `paccache.timer` habilitados via `systemctl enable` no chroot.
- [x] **`fstrim` não é suportado** por este enclosure: `/sys/block/sdb/queue/discard_max_bytes=0`
  (`fstrim /` → "the discard operation is not supported"). **Não** habilitar `fstrim.timer`;
  tratar junto do P0 (cabo/enclosure) — sem TRIM o SSD degrada mais rápido. Item
  considerado resolvido: não há ação a tomar além de não habilitar o timer.
- [x] `/etc/mkinitcpio.conf.pacnew` — resolvido: o script `distro/01-build-image-7.0.sh`
  já gera `/etc/mkinitcpio.conf` diretamente (linha ~538) com `MODULES` e `HOOKS`
  específicos do PS4 (`ext4 ahci sd_mod ... mts usbhid uas usb_storage`, HOOKS
  `base udev modconf block filesystems keyboard fsck set-time-from-cmdline`), então
  não há `.pacnew` pendente.
- [x] `archlinux-keyring-wkd-sync.service` gastou **2min13s** no boot atual — implementado override no build (`distro/01-build-image-7.0.sh` linhas ~419-427): `OnBootSec=10min`, `Persistent=false`, `RandomizedDelaySec=30min`. **Validado ao vivo 2026-11-13** — timer ativo com trigger atrasado, não roda no boot.
- [x] Sem swap e sem uso de zram: `/dev/zram0` existe, `SwapTotal=0`, mas `zswap.enabled=1` — zswap sem swap não faz nada. Implementado no build (`distro/01-build-image-7.0.sh`):
  - `zram-generator` adicionado ao `PKGS` (linha ~237);
  - `/etc/systemd/zram-generator.conf` gerado com `zram-size = ram/2`, `compression-algorithm = zstd`, `swap-priority = 100`;
  - `zswap.enabled=1` removido do bootargs.
  **Validado ao vivo 2026-11-13:** zram0 3.4 GiB ativo como swap (zstd), zswap desabilitado (`N`).
- [~] Sem `cpufreq`: `amd_pstate` falha (`the _CPC object is not present in SBIOS`) e `CONFIG_X86_ACPI_CPUFREQ` não estava setado. **Implementado no build do kernel** (`kernel/00-build-kernel-7.0.sh` linha ~538): `scripts/config --enable CONFIG_X86_ACPI_CPUFREQ` (driver ACPI legado para Jaguar, fallback). **Pendente:** rebuild kernel + deploy + power-cycle para validar `cpupower frequency-info`.
- [~] `libata.force=1.00:3.0Gbps` limita o SATA interno (drive é 6 Gbps); testar remoção. **Removido do bootargs** no build (`distro/01-build-image-7.0.sh` linha ~727). `ahci.mobile_lpm_policy=1` também removido. O quirk `ATA_QUIRK_NOLPM | ATA_QUIRK_NONCQ` para `TOSHIBA MQ04ABF100` continua hardcoded em `libata-core.c`. **Pendente:** rebuild distro + deploy + power-cycle para testar SATA a 6 Gbps.
- [~] `systemd.unified_cgroup_hierarchy=0` + `CONFIG_CGROUP_V2` desligado: legado; reavaliar. **Removidos do bootargs** no build (`distro/01-build-image-7.0.sh` linha ~727): `systemd.unified_cgroup_hierarchy=0` e `systemd.legacy_systemd_cgroup_controller=yes`. Kernel tem `CONFIG_CGROUP_V2=n` (cgroup v1). **Pendente:** rebuild distro + deploy + power-cycle para confirmar cgroup v1 funcionando sem warnings.
- [x] `usb usb3-port1/usb4-port1: over-current condition` com as duas portas vazias — ruído
  esperado do xhci_aeolia, ignorar. Item considerado resolvido: não há ação a tomar.
- [ ] **Baikal Memory: ajustar offsets sysfs** — offsets no device file (`/dev/baikal-memory`: MAC em 0x52f000, ICC em 0x52c000) divergem dos atributos sysfs (`bar5_0x2f000`, `bar5_0x2c000`). Corrigir driver para expor offsets corretos.
- [ ] **RTC: implementar UIE emulation** — `hwclock -r` timeout por falta de UIE emulation no `rtc-ps4-icc.c`. `CONFIG_RTC_INTF_DEV_UIE_EMUL=y` já está no kernel; falta tratar interrupção de update no driver.
- [ ] **Adicionar `alsa-utils` ao `PKGS`** do `01-build-image-7.0.sh` — necessário para áudio HDMI funcionar out-of-the-box.
- [ ] **S5 power-off (luz azul)**: testar tag `20260730-s5-poweroff-fix` com captura UART.
- [ ] **Mesa patchado (Gladius/Liverpool)**: rodar `mesa/01-build-mesa.sh` + rebuild distro + `promote-release`.
- [ ] **Rebuild kernel + deploy + power-cycle** para validar `cpufreq` (`CONFIG_X86_ACPI_CPUFREQ` já habilitado).
- [ ] **Rebuild distro + deploy + power-cycle** para testar SATA a 6 Gbps (removido `libata.force=1.00:3.0Gbps` do bootargs).
- [ ] **Rebuild distro + deploy + power-cycle** para confirmar cgroup v1 sem warnings (removidos `systemd.unified_cgroup_hierarchy=0` e `systemd.legacy_systemd_cgroup_controller=yes` do bootargs).

**P0 (bloqueador, já decidido):** o **SSD Kingston SV300 120 GB** do root (via bridge USB
**JMicron**, driver `usb-storage`; UAS não suportado pelo xhci do PS4) está corrompendo dados em
lote — em 2026-11-12, 330 arquivos do `/usr` divergiam (355 MB), com blocos fisicamente zerados,
enquanto tar e `arch_build_7.0/rootfs` conferem. O `pacman` foi **reparado em 2026-11-12**
(`libxml2` restaurado, 58 pacotes reinstalados, `-Qkk` = 0 divergências de sistema, `-Dk` limpo),
mas o disco continua com **27 erros de I/O neste boot** (`Sense Key 0xB / ASC 0x47` = parity
error), **2 ECC não corrigidos**, **2.027 desligamentos inesperados**, SMART geral `PASSED` e
**`discard_max_bytes=0` (sem TRIM)**. O usuário vai **trocar o disco**; até lá, evitar operações
pesadas e manter backup. Ação imediata: trocar cabo/porta e, se possível, enclosure com fonte;
depois `smartctl -t long` + `badblocks`.

---

### [ ] 🔍 Investigação de travamento do Xorg / SDDM pós-restart (hipótese: autostart do Steam)
**Contexto (2026-08-01):** Na primeira reinicialização do SDDM via SSH a interface gráfica subiu perfeitamente (`Session started true`, PID 1716). Na segunda tentativa de reinicialização do SDDM/Xorg, a rede/interface gráfica travou.
**Hipótese do Usuário:** O travamento pode ter sido causado por autostart/inicialização em background do cliente Steam durante o re-login do SDDM. Validar e analisar logs em sessão posterior.

---

### [x] 🔒 GBE Ethernet — PHY nunca sai de power-down — INVESTIGAÇÃO ENCERRADA 2026-07-30 (bloqueador de firmware, não solucionável via driver Linux)

**Contexto:** MAC ligado com sucesso via ICC (`0x004=0xb19`), TX por software funcional (~95%, doorbell corrigido em 2026-07-25). Mas o PHY nunca responde a MDIO — Clause 45 (MMD1/MMD7) e Clause 22 (BMCR, scan completo endereços 0-31) sempre retornam zero/timeout. RX permanece morto (`MTS_CNT_PKTS=0`, ping 100% perda).

**Já descartado:** `MTS_MAC_EN2` como causa; hipótese de IRQ real (`IMR=0x7d`) reproduzindo full-duplex; correção do efuse (BAR4 em vez de BAR2) foi necessária mas insuficiente sozinha.

**Próximo passo exato:** validar pós-power-cycle os fixes de `mts_mac_stop()`/doorbell TX, depois varredura read-only da janela Glue BAR2 `0x140000`-`0x180000+` e reordenar o diagnóstico MDIO para rodar após o release do hold.

**Documentos:** plano consolidado ATIVO (2026-07-29, revisão de UART+SQLite+código) em [`../../kernel/drivers_mts/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](../../kernel/drivers_mts/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md) — substitui o plano de 07-25 como fonte de próximos passos (o de 07-25 fica só como histórico); histórico de RE em [`../../kernel/drivers_mts/RE_KERNEL_GBE_ATTACH.md`](../../kernel/drivers_mts/RE_KERNEL_GBE_ATTACH.md) e [`../../kernel/drivers_mts/ICC_GBE_TEST_LOG.md`](../../kernel/drivers_mts/ICC_GBE_TEST_LOG.md).

**Status 2026-07-30:** bug de polaridade MDIO Clause 22 corrigido em `mts.c` (ver `memory/mdio-clause22-bug-polaridade-corrigido-2026-07-29.md`) e testado ao vivo — eliminou o falso-positivo de dado residual, mas PHY continua sem link. **🏆 Tag `20260730-sata-reverted` CONFIRMADA ao vivo como o novo BASELINE OFICIAL/ponto de rollback** (boot completo, SSH ok, `eth0` sobe com MAC real) — ver `memory/baseline-oficial-20260730-sata-reverted.md`.

**Fase 2 do plano consolidado (MSI/IMR) — CONCLUÍDA E REFUTADA 2026-07-30, com evidência direta (`test_history` id 72):** o achado "`RX_CLEAN ... cleaned=N`" de ontem era só o contador de chamadas de NAPI poll, não atividade de hardware real (confirmado lendo `mts.c:1608-1685`). Testado ao vivo, sem rebuild:
1. `lspci -vv 00:14.1` (GBE) mostra MSI `Enable+ Count=1/1 Maskable+ Masking=00000000` — **NÃO mascarado em hardware**, diferente do caso AHCI (`Masking=000000fe`). Refuta a hipótese de mascaramento MSI análogo ao SATA.
2. Recarregado `mts.ko` com `irq_mask=0x7d` (IMR real desmascarado, era `0x0`=tudo mascarado por padrão) — confirmado via `mts_regs` (`0x54=0x0000007d`). Mesmo assim, `/proc/interrupts` ficou em **`irq_count=0`** por 5+s, ping continuou 100% perda, `eth0` continuou `NO-CARRIER`. Refuta também a hipótese de que o IMR default estava simplesmente mascarando eventos reais que já estavam acontecendo.
3. **Conclusão:** não é bug de MSI/demux nem de IMR — o PHY genuinamente nunca gera nenhuma condição de IRQ (nem link change, nem RX). Fecha esta via de investigação por evidência direta, conforme critério da Fase 3 do plano (`PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`): o bloqueador é anterior a qualquer coisa que o driver Linux possa fazer — energia/clock físico do PHY, ou sequência de bring-up da Sony fora do alcance replicável via software puro.
4. **Bug novo, não-bloqueante, achado de bônus:** `rmmod mts` sempre gera um `WARNING: kernel/irq/msi.c:294 at msi_device_data_release` (sistema não trava, fica só `tainted (O)`) — bug real no cleanup de MSI do driver, nunca documentado antes. Não impede reload (`insmod` funcionou normalmente na sequência).

**🔒 FECHAMENTO FORMAL 2026-07-30 — RE completa da thread `gbe_phy_ctrl` (`dc5a44c0`):** 11 funções extraídas via Ghidra Java headless (Docker), árvore de chamada inteira analisada. **Nenhuma chamada ICC ou SAMU encontrada** — a thread só monitora o PHY via MDIO packed reads e dorme esperando eventos. Varredura binária do `kmem_dump_1252.bin` confirma: 0 cross-refs para `dc5a44c0`, 0 referências a ICC major=5 (SAMU) no range GBE, 0 referências a MMIO de mailbox SAMU no range GBE. **Conclusão: o power-on físico do PHY é feito pelo firmware/bootloader Sony antes do kernel Orbis assumir — não há sequência replicável via MDIO, ICC, SAMU ou RMU que um driver Linux possa executar.** Esta via de investigação está **esgotada com os dados disponíveis** — não reabrir sem fonte de dados nova (ex: vazamento de firmware, dump de SAMU, documentação de terceiros sobre o PHY Baikal). Detalhes em `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` e `memory/sessao-ghidra-java-passo1-2026-07-30.md`. Prioridade do projeto redirecionada para as frentes já ativas (S5 shutdown, KVM).

---

### [~] S5 incompleto no `poweroff -f` (luz azul não apaga)

**Contexto:** `sync && poweroff -f` encerra o SO e derruba a rede, mas o console fica com a luz azul acesa/pulsando — desligamento total da fonte (S5) não ocorre.

**Já feito:**
1. [x] RE no dump Orbis 12.52 (disassembly de `icc_power_shutdown`, offset `0x1d8a3c`): estrutura real do payload ICC S5 tem **32 bytes** (`cause` em `+0x0E`, `depth` em `+0x0F`, `hand` em `+0x10`) — o driver Linux enviava só 6 bytes truncados.
2. [x] Patch aplicado em `ps4-bpcie-icc.c` e `ps4-apcie-icc.c`: monta o payload de 32 bytes e loga o hex dump da resposta do MCU.

**Build + teste 2026-07-25 (tag `s5-poweroff-fix-20260725`):**
- `bzImage-7.0-s5-poweroff-fix-20260725` (15.84 MB) compilado e deployed via `deploy-boot-7.0.sh`
- **Teste ao vivo:** `sync && poweroff -f` → SO desliga (SSH cai), mas **luz azul permanece acesa/pulsando + fan ligado** = S5 **não** atingido
- dmesg pós-boot não mostrou log do ICC S5 shutdown (verificar se payload foi enviado)

**Status 2026-07-30 (EM ANDAMENTO, pausado, retomar daqui):** achado novo — o payload de 32 bytes de 07-25 tinha **framing errado** (deveria ser 20 bytes de payload real, não 32; `_bpcie_icc_cmd()` já soma o header de 12 bytes ao `length`). Corrigido em `ps4-bpcie-icc.c` + implementada a sequência pré-sync (major=4/minor=4) + final (major=4/minor=1) nunca antes aplicada. Build da tag `20260730-s5-poweroff-fix` **concluído**, artefatos prontos em `boot_referencia/`. **Falta:** conectar o HD USB ao PC, `deploy-boot-7.0.sh 20260730-s5-poweroff-fix`, captura UART (não netconsole — a rede cai junto com o shutdown), power-cycle físico, `sync && poweroff -f`, ler o log UART. Ver `memory/s5-poweroff-fix-framing-corrigido-2026-07-30-aguardando-teste.md` (o plano detalhado ficou fora do repositório, em `~/.claude/plans/`, e não é versionado — a memória acima é a fonte disponível no projeto).

---

## Prioridade média

### [x] 🌐 Habilitar o cliente CIFS/SMB no kernel do PS4 para montar o `[dados_aux]` do `adsv2` como se fosse local

**Contexto (2026-11-12):** o fluxo de trabalho do PS4 usa `/mnt/hdauxiliar` do host `192.168.6.101`
(`adsv2`) como diretório de trabalho. As rotas disponíveis hoje têm limitações:
- **NFSv3** funciona, mas o servidor **não exporta raiz NFSv4 com `fsid=0`** — `vers=4.0/4.1/4.2`
  retorna `mount.nfs: Protocol not supported`. O NFSv3 não faz mapeamento de UID: os arquivos
  aparecem com **UID 1000 (`ps4` local)** e o usuário `anderson` (local, UID **1001**) **não
  consegue escrever** em subpastas 755 (ex.: `/mnt/hdauxiliar/downloads` → `Permissão negada`).
- **sshfs** resolve o UID (`uid=1001,gid=1001`), mas é camada FUSE, mais lento em metadados e não
  preserva tudo (hardlinks, alguns atributos).
- **CIFS** é a rota mais limpa: o `adsv2` **já compartilha exatamente `path = /mnt/hdauxiliar`**
  como `[dados_aux]` (`guest ok = Yes`, `force user = anderson`, `read only = No`,
  `create/directory mask = 0777`), e `mount.cifs` mapeia dono/grupo local nativamente
  (`uid=1001,gid=1001`), **sem alterar nada no servidor**.

**Bloqueio (histórico — sendo resolvido na tag `20261112-cifs`):** o kernel 7.0 do projeto estava com **`# CONFIG_CIFS is not set`** (confirmado no
`.config` do build e em `/proc/config.gz`) e **não há módulo `cifs.ko`** para carregar sob demanda —
por isso a rota CIFS foi descartada na sessão de 2026-11-12 e caiu-se no NFSv3/sshfs.

**Objetivo:** habilitar o cliente CIFS no kernel do projeto e montar o `[dados_aux]` de forma
persistente, com ownership `1001:1001`, substituindo NFSv3/sshfs no uso diário.

**Resultados (2026-11-12):**
1. [x] Config adicionada ao `kernel/00-build-kernel-7.0.sh` (bloco `scripts/config`, logo após
   "Async I/O"). Decisão: **`CONFIG_CIFS=m` (módulo), não `=y`** — o `bzImage` atual já tem
   **~16 MiB** (acima do aviso de ~10 MB de alguns loaders kexec do PS4) e o
   `distro/01-build-image-7.0.sh:~431` já roda `modules_install` no rootfs, então `cifs.ko` vai
   para `/lib/modules/<kver>/` sem inflar o kernel. Bônus: com `CONFIG_MODVERSIONS` e
   `CONFIG_MODULE_SIG` desligados (confirmado no `.config`), o mesmo `cifs.ko` carrega no kernel
   **já em execução** (mesma `UTS_RELEASE` `7.0.8-Strawberry-ThinLTO-Baikal-+`), o que permite
   validar o mount antes de reiniciar.
   ```sh
   scripts/config --module CONFIG_CIFS
   scripts/config --enable CONFIG_CIFS_XATTR   # xattrs (Samba)
   scripts/config --enable CONFIG_CIFS_POSIX   # extensões POSIX: modo/ACL
   ```
   (`CONFIG_CIFS` é `tristate` e puxa `INET`, `NLS`, `KEYS`, `DNS_RESOLVER`, `NETFS_SUPPORT`.)
2. [x] Compilado no `adsv2` com TAG `20261112-cifs` em **41m11s**, sem erros: `bzImage` 16M,
   `config` 137K, `cifs.ko` 32M (árvore) / 1,1M (rootfs), `netfs.ko`, `cifs_md4.ko`,
   `nls_ucs2_utils.ko`. `vermagic=7.0.8-Strawberry-ThinLTO-Baikal-+ SMP preempt mod_unload`.
   `.config` publicado com `CONFIG_CIFS=m`, `CONFIG_CIFS_XATTR=y`, `CONFIG_CIFS_POSIX=y`,
   `CONFIG_SMBFS=m`, `CONFIG_NETFS_SUPPORT=m`, `CONFIG_NLS=y`. Snapshot salvo em
   `kernel/snapshots/kernel-src-20261112-20261112-cifs.tar.zst` (559M).
3. [x] Teste ao vivo **sem reboot** (2026-11-12 ~12:00): 4 módulos copiados para
   `/lib/modules/7.0.8-Strawberry-ThinLTO-Baikal-+/`, `depmod -a`, `modprobe cifs` OK,
   `/proc/filesystems` lista `cifs`. Mount em `/mnt/cifs-test` OK, `stat` reporta
   `1001:1001 anderson:anderson`, escrita sem `sudo` em `ps4-linux-baikal/` (775).
4. [x] Rootfs rebuilad em container Arch (`distro/scripts/build-image-docker.sh 20261112-cifs
   --incremental`): `cifs.ko` + dependências em
   `arch_build_7.0/rootfs/lib/modules/7.0.8-Strawberry-ThinLTO-Baikal-+/kernel/fs/smb/client/`,
   initramfs + bootargs da tag gerados em `distro/boot_referencia/`.
5. [x] Persistido no `/etc/fstab` do PS4 (backup em `/tmp/fstab.bak-*`) **e na receita de build**
   `distro/01-build-image-7.0.sh` (geração de `/etc/fstab` + `mkdir -p /mnt/hdauxiliar`, antes
   de "Copiando vram.txt"):
   ```
   //192.168.6.101/dados_aux /mnt/hdauxiliar cifs credentials=/etc/samba/credentials,uid=1001,gid=1001,forceuid,forcegid,vers=3.0,iocharset=utf8,file_mode=0644,dir_mode=0755,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=10s 0 0
   ```
6. [x] Opção (b) implementada — autenticação Samba real:
   - `adsv2`: `smbpasswd -a anderson` (adicionado ao banco Samba) e removidas
     `guest ok = Yes` + `guest only = Yes` da share `[dados_aux]` em
     `/etc/samba/smb.conf`; `smbd` recarregado.
   - PS4: mount com `credentials=/etc/samba/credentials` (arquivo em `/etc/samba/credentials`,
     modo 600, root-only) em vez de `guest`; `/etc/fstab` atualizado e a receita
     `distro/01-build-image-7.0.sh` gera a mesma entrada.
   - Resultado: escrita em dirs 755 do servidor (incl. `downloads`) agora funciona
     como `anderson` **sem `sudo`** (sessão autenticada roda como uid 1000 no servidor,
     que é dono dos arquivos).

**Critério de aceite (parcialmente atingido):**
- [x] `findmnt /mnt/hdauxiliar` mostra `FSTYPE cifs`;
- [x] `stat` reporta `1001:1001 anderson:anderson` nos arquivos remotos;
- [x] `anderson` cria/apaga arquivo em dirs 775/777 **sem `sudo`**;
- [x] `anderson` cria/apaga arquivo em `/mnt/hdauxiliar/downloads` (755) **sem `sudo`** —
      resolvido com autenticação Samba real (opção b);
- [x] montagem sobrevive a reboot via `x-systemd.automount` no `/etc/fstab` (opcional
      `deploy-boot-7.0.sh 20261112-cifs` para implantar a tag no boot do PS4).

**Flags do git sobre CIFS (obrigatórias):** `git -c core.fileMode=false status
--ignore-submodules=all` (~1,5 s). Sem `--ignore-submodules=all` o `git status` desce no
gitlink `kernel/kernel_build_7.0` e trava >90 s. `core.fileMode=false` evita falsos
"mode change 100755 => 100644" nos 32 arquivos rastreados com bit executável.

**Fallback documentado até resolver os dirs 755:** NFSv3
(`vers=3,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2`) para leitura e `sshfs` com
`uid=1001,gid=1001` para escrita com UID correto. Nenhum dos dois altera o servidor.

### [ ] 🔴 Teste ao vivo da tag `20261111-preflight-test` (HD USB do PS4 plugado neste PC)

**Estado:** build + deploy testados em loopback; falta o teste no console real.
**Próximo passo exato:** `cd distro && sudo ./deploy-boot-7.0.sh 20261111-preflight-test`
(HD USB plugado, partição BOOT montada), plugar o HD no PS4, power-cycle, e conferir:
vídeo HDMI, SSH em `192.168.6.128`, `eth0` com MAC real em `192.168.0.2/24` (ping do host
`192.168.0.1` **na subnet cabeada**, nunca `192.168.6.x`), e `dmesg | grep -i 'ata1\|disable'`
(SATA interno).
**Atenção:** a imagem foi gerada **sem o Mesa patchado** (Gladius/Liverpool) — a corrupção
visual conhecida continua valendo até rodar `distro/mesa/01-build-mesa.sh` e refazer o build.

### [ ] 🔴 Gerar o Mesa patchado (Gladius/Liverpool) e refazer o build da distro

**Estado:** `distro/01-build-image-7.0.sh` procurou
`distro/mesa/mesa-ps4-gladius-liverpool-latest.tar.xz` e **não achou** → a imagem da tag
`20261111-preflight-test` usa o Mesa oficial do Arch (que não reconhece
`CHIP_GLADIUS`/`CHIP_LIVERPOOL` → corrupção visual em qualquer coisa renderizada).
**Próximo passo exato:** `cd distro/mesa && ./01-build-mesa.sh` (produz o tar), depois refazer
`./scripts/build-image-docker.sh <TAG>` e só então promote-release. A chave do patch está em
`distro/mesa/`; ver `outros/docs/MESA_GLADIUS_LIVERPOOL_FIX.md`.

### [x] 🔵 Decidir a estrutura da fonte do driver MTS (`drivers_mts/mts.c` × patch)

**Decisão (2026-11-13):** `drivers_mts/` é a **fonte única autoritativa** (mts.c, mts.h).
O patch `kernel/patches/mts-baikal-kconfig.patch` contém **apenas** Kconfig/Makefile do
vendor Sony (drivers/net/ethernet/sony/Kconfig + Makefile). O driver em si vem de
`drivers_mts/` copiado direto para a árvore do kernel no build.

**Mudanças implementadas:**
- Patch antigo `mts-baikal-gbe-driver.patch` (3.200+ linhas com driver) → **substituído** por
  `mts-baikal-kconfig.patch` (apenas Kconfig/Makefile, ~50 linhas).
- Build script (`kernel/00-build-kernel-7.0.sh` linhas ~376-427): aplica patch Kconfig/Makefile,
  depois copia `drivers_mts/mts.c` e `drivers_mts/mts.h` para `drivers/net/ethernet/sony/`.
- Elimina duplicação ~3.200 linhas; mantém idempotência (patch = Kconfig/Makefile, source = drivers_mts/).


### [x] 🏆 SATA interno (HD Toshiba MQ04ABF100) — FEATURE CONCLUÍDA 2026-07-30, funcional pela primeira vez

**Resolvido via Fase B (polling timer de 1ms) do `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md`, testado ao vivo na tag `20260730-sata-polling-fase-ab`:**
- `ata1.00: configured for UDMA/100`, zero exceções/`disable device` em todo o dmesg (1322 linhas).
- Leitura real confirmada: `dd if=/dev/sda bs=1M count=50` → 71.2 MB/s sem erro. `fdisk -l /dev/sda` retorna a tabela completa (931.51 GiB).
- `PxIE` ficou em `0x7840007f` após o único `thaw()` do probe (t=3.02s) e nunca mais zerou (antes reincidia ~37s e desabilitava ~84s).
- **Novo baseline oficial/ponto de rollback:** tag `20260730-sata-polling-fase-ab` (kernel do baseline GBE `20260730-sata-reverted` + fix de SATA). Ver `memory/marco-sata-interno-funcional-2026-07-30.md` e `test_history` id 73.
- **Ressalva 2026-08-01 (importante para não superestimar o estado):** o patch foi **perdido e reconstruído** naquele dia (ver `memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md`), e a reconstrução inicial colocou o timer na PCI function errada (`.2`, AHCI genérico) — `ata1` pertence à function `.7` (`xhci_aeolia`), ver `memory/sata-polling-device-errado-14-2-vs-14-7-2026-08-01.md` e `test_history` id 78. O patch atual (`patches/ahci-baikal-polling-fallback.patch`) já contém as duas pontas (`.2` e `.7`) e compila/aplica limpo, mas **não há registro de boot validando a tag `20260801-kvm-rtc-sata-final`** (a base do `RELEASE/v1.0.0`). A validação ao vivo documentada é a de `20260730-sata-polling-fase-ab`. Antes de tratar o `v1.0.0` como "SATA comprovado", um boot com `dmesg | grep 'polling timer started on xhci-aeolia'` + `ata1.00: configured for UDMA/100` por 90s+ é obrigatório.

### [~] 🔑 Obter a chave EAP real via EAPDumper (payload ao vivo) — **CONCLUÍDO 2026-07-31: chave obtida, estável; tweak/IV em aberto**

**Status 2026-07-31:** base do kernel 12.52 resolvida (`0xffffffffdc350000`) e a chave EAP
lida pelo kernel (`0xffffffffdea14cf0`) cai no BSS do dump — **zerada, não extraível deste dump**.
O ERK `7fcf0536...` que temos é cópia de debug/rodata (label `SCE_EAP_HDD__KEY`), não
confirmado como chave ativa. **EAPDumper v0.2.0 compilado em 2026-11-13**
(`outros/tools/ps4_hdd_tools/build_eapdumper.sh` → `EAPDumper/EAPDumper.bin`,
sha256 `52e6617e...`; release oficial idêntica em tamanho, sha256 `73f9306d...`); envio no console
descrito em [`ENVIO_DE_PAYLOADS.md`](ENVIO_DE_PAYLOADS.md) (GoldHEN BinLoader `:9090`);
suporta FW 5.03–13.50, e 12.52 cai no scanner cego (`0x2600000`–`0x2900000`,
cobre o offset `0x26C4CF0`), já aplica `reverse_16_byte_blocks` e grava
`/data/hddeap/eap_hdd_key.{bin,hex,txt}` + `/mnt/usb0/`.

**Chave EAP canônica obtida ao vivo (5 dumps, 3 boots):** sha256 `990c1aa3…c8bf` — **estável entre 3 boots** (entropia 4.88 constante no offset real `0x026C4CF0`). A chave em si **não** é registrada em documento (só em `.env.keys`, gitignored). Scanner do EAPDumper sofre de **falso-positivo** (`0x0283A8C0` top em 4/5 dumps, conteúdo muda entre boots).

**🔴 DESCOBERTA CRÍTICA 2026-07-31:** `pycryptodome 3.23.0` **não tem `MODE_XTS`** — todos os testes XTS anteriores (96/504/380 combos) foram **falso-negativo total** (AttributeError silencioso → `None`). Refiz com `cryptography 49.0.0` (XTS real, vetores NIST OK): **ZERO hits** em TODOS os testes (Full 8MB absLBA, IV=0, byte-offset, varredura ±500k, 4 chaves × variantes). **Chave EAP `edf3f4d3...` está CORRETA** (kernel, offset validado por RE, estável 3 boots). O XTS funciona (vetores NIST OK). **Falta o tweak/IV correto** — hipótese principal: `ivoffset_field` (`iVar2[0x20]`) ≠ 0 no `g_crypt_create_provider` (vem de `g_provider.ivoffset` setado por `g_part`/EAP boot).

**✅ RESOLVIDO em 2026-11-13 (não repita o teste abaixo):** o offset correto **não** é o LBA e sim o
IV offset `(dev_no - 1) << 32` (`sda27` → `111669149696`), aplicado via `dmsetup` porque o `cryptsetup`
não tem opção de `iv_offset`. Ver `MONTAGEM_HD_INTERNO.md` §2 e `LICOES_APRENDIDAS.md` #76.
_(Registro histórico do plano antigo, mantido só para contexto)_ **Próximo passo (obsoleto):** boot no Linux 7.0 (tag `20260730-sata-polling-fase-ab`) + `cryptsetup open -c aes-xts-plain64 --key-file keys/eap/eap_hdd_key.bin --key-size 256 --offset <LBA> /dev/sda27` testando `--offset` (ajusta IV) vs `--skip`. RE do `ivoffset_field` — traçar `*(iVar2+0x20)` no `g_crypt_create_provider` (vem de `g_provider.ivoffset` setado por `g_part`/EAP boot). Ver `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md` Seção 22 (⚠️ os arquivos `keys/TESTES_EAPDUMPER_2026-07-31.md` e `keys/INDEX.md` vivem em `keys/`, que é **gitignored** — só existem na máquina que rodou os testes, não neste clone).

---

### [x] 🏆 Montagem Nativa do HD Interno (/dev/sda) — **RESOLVIDO E VALIDADO AO VIVO (2026-11-13)**
> ✅ **`sda27` (user) MONTA read-only com a chave EAP** — 884 GiB, 485 GiB usados, `app/` com 44 títulos, `savedata`, `trophy`, `appmeta`, `bgft`. Também montam `sda29` (`eap_user`, UFS2) e `sda25` (`update`, FAT32).
>
> **Causa raiz do bloqueio histórico:** o IV do dm-crypt nestes consoles (CUH-1100+/Baikal) é **`iv_offset = (dev_no - 1) << 32`** — com IV=0 o mapper decifra lixo (`bad magic number`). O `cryptsetup` não sabe aplicar isso (`--offset`/`--skip` são *data offset*), então o mapper é criado com `dmsetup create -r`. **Premissa errada corrigida:** `sda27` não é PFS, é **UFS2** (o PFS é o formato dos containers `app/<TITLE>/app.pkg` dentro dela); `sda13` **não é montável** (é o swap antigo, chave versioned_key + OpenPsId).
>
> Detalhes técnicos: [`MONTAGEM_HD_INTERNO.md`](MONTAGEM_HD_INTERNO.md) §2. Tarefas/pendências: [`BACKLOG_MOUNT.md`](BACKLOG_MOUNT.md) (MOUNT-01/02/03 fechados; MOUNT-06 virou opcional — só para ler containers PFS).
> Histórico do diagnóstico antigo: `/usr/local/bin/pfsfuse` era um binário de **PS2** (não PS4) e a busca pelo `magic 0x1332A0B` era baseada em valor errado — o magic UFS2 correto é `0x19540119` em `0x1055C`.
- **Concluídas as 3 fases do `PLANO_MONTAGEM_NATIVA_HD_INTERNO_SDA.md`**:
  1. Inspeção completa das 29 partições (`sda1` a `sda29`), extração da chave EAP da NOR (`nor_sflash0.bin`), derivação da chave XTS (`data` + `tweak`), e validação de `cryptsetup` com `-o ro`.
  2. Desenvolvidos os scripts modulares `/usr/local/bin/monta_particao.sh`, `/usr/local/bin/desmonta_particao.sh` e `/usr/local/bin/automount.sh` (chave hoje em `/etc/ps4-keys/eap_hdd_key.bin`, provisionada pelo usuário com `distro/scripts/provisiona-chave.sh`). **Resolvido em 2026-11-13:** o `sda27` monta com `iv_offset = 26 << 32` via `dmsetup` (ver `BACKLOG_MOUNT.md`, MOUNT-01).
  3. Integrada a cópia automática dos scripts e utilitários (`monta_particao.sh`, `desmonta_particao.sh`, `automount.sh`, `pkg_pfs_tool` compilado para a CPU Jaguar `btver2` do PS4 e `config.ini`) no gerador de imagens da distro customizada `01-build-image-7.0.sh` para o Arch Minimal v2. Adicionado o pacote `sleuthkit` na lista de instalação automática `PKGS` do pacman.
  4. Configurado acesso total sem senha (`NOPASSWD: ALL` em `/etc/sudoers.d/ps4-hdd`) e regra udev `/etc/udev/rules.d/99-ps4-disk-permissions.rules` (permissão `0666` direta para `/dev/sda*`, `/dev/dm-*` e `/dev/mapper/`) para o usuário `ps4` operar os utilitários de montagem, mappers e criptografia. Integrado na receita de build `01-build-image-7.0.sh`.
  5. Desenvolvido o driver FUSE **`ps4_pfs_fuse`** (`/usr/local/bin/ps4_pfs_fuse`) com I/O sob demanda via `pread` (super leve, zero consumo de RAM pré-alocada) para montagem e navegação transparente no VFS/Nemo/Nautilus das partições PFS. Integrado ao gerador de imagens `01-build-image-7.0.sh` e documentado no plano `PLANO_MONTAGEM_NATIVA_NEMO_NAUTILUS_FUSE.md`.

**Limpeza pendente (não bloqueante):** remover a instrumentação de debug (`ahci_dbg:` em `freeze()`/`thaw()`/`ahci_error_handler()`, já marcada "REMOVER quando a investigação terminar" no código) num próximo rebuild.

<details>
<summary>Histórico da investigação (hipóteses refutadas antes da solução) — clique para expandir</summary>

### [~] 🔴 SATA interno (HD Toshiba MQ04ABF100) — **PRIORIDADE ALTA: custa 78s no boot e desabilita dispositivo aos 84s**

**Resultado do teste ao vivo (2026-07-29, tag `20260728-sata-ackfix-ehdump`, log `video_001_20260729_124629.bin`):**
- ❌ **HIPÓTESE DO FIX DE DEMUX ACK REFUTADA:** A tag `20260728-sata-ackfix-ehdump` **não resolveu** o SATA interno.
- **Leitura estrita de timestamps do log `video_001` (4159 linhas):**
  - `t = 3.18s`: `sda` é detectado e tabela de partições lida.
  - `t = 7.37s`: `/init` é chamado pelo systemd **a partir do HD Externo USB (`sdb2`)**, dando falsa impressão inicial de boot rápido.
  - `t = 37.00s`: Exceção ATA estoura no HD interno: `ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6 frozen` (`READ DMA tag 26`). `SErr 0x0` e status `{ DRDY }` confirmam PHY 100% íntegro.
  - `t = 84.11s`: O kernel esgota as 3 tentativas de `IDENTIFY (cmd 0xec)` e desabilita o dispositivo (`ata1.00: disable device`).
- **Conclusão:** O HD interno (`sda`) continua inoperante sob o Linux. A interrupção `PxIS=0x2` é gerada pelo AHCI, mas o sinal MSI do Baikal deixa de ser entregue à CPU pelo driver de interrupções.

**Análise de Engenharia Reversa & Teste ao Vivo (2026-07-29, tag `20260729-sata-globallock`, log `sata_teste_20260729_145146.bin`):**
- **Implementação:** Spinlock estático global (`bpcie_ack_lock`) aplicado no `ps4-bpcie.c` cobrindo o par de leitura/escrita do ACK do Glue (`0x110084`/`0x110088`), reproduzindo o mutex global do Orbis (`dc718b40`).
- ❌ **HIPÓTESE DO SPINLOCK GLOBAL REFUTADA:** O spinlock funcionou sem travar o kernel, mas a falha do SATA permaneceu idêntica: 10 despachos de interrupção iniciais até `t = 4.89s`, parada de sinalização no Glue, estouro de exceção em `t = 36.80s` (`READ DMA EXT tag 5`) e desativação em `t = 83.90s` (`disable device`).
- **Achado Factual Medido no EH:** No momento da exceção em 36.80s, o AHCI reporta `PxIS=0x2` (interrupção de conclusão pendente na porta) e `IS=0x1` (porta 0 assinalando IRQ global no AHCI), porém o registrador do Glue `BAR2+0x110088` lê `0x001e0103` (apenas subfunção 0/USB pendente, subfunção 1/SATA zerada).
- **Conclusão:** O sinal de interrupção entre a lógica da porta do AHCI e o registrador do Glue deixa de transitar a partir dos 4.89s de boot (provável transição de power/idle da porta ou falta de rearme explícito).

---




- Validado: `__ksymtab_ps4_icc_sata_power_on` + `__kstrtab_ps4_icc_sata_power_on` e string `TOSHIBA MQ04ABF100` presentes no `vmlinux` (built-in, não módulo)
- Compilação isolada pré-build: `drivers/ata/libata-core.o` e `drivers/ps4/ps4-bpcie-icc.o` OK

**Build combinado SATA + S5 poweroff (2026-07-25 18:55):**
- Tag `s5-poweroff-fix-20260725` (15.84 MB, Clang/ThinLTO) — `bzImage-7.0-s5-poweroff-fix-20260725`
- MD5 diferente do `20260725-full-build` → build novo com patches SATA + S5 poweroff

---

### **SMOKE TEST AO VIVO 2026-07-25 (tag s5-poweroff-fix-20260725) — RESULTADO**

**✅ O que FUNCIONOU (patches validados):**

| Patch | Evidência no dmesg (PS4 uptime ~4min) |
|-------|----------------------------------------|
| ICC power-on SATA | `[0.623518] icc: SATA power-on OK (reply 20 bytes)` |
| Quirk NOLPM aplicado | `[1.158248] ata1.00: Model 'TOSHIBA MQ04ABF100', rev 'JU0G0A', applying quirks: nolpm` |
| LPM totalmente desligado | `[1.205] ata1.00: LPM support broken, forcing max_power` + sysfs `max_performance` |
| Disco visível por >4min | `sda 931.5G TOSHIBA MQ04ABF1` em `lsblk` com uptime 4min+ |
| PS4 estável | SSH ativo, rootfs USB OK, uptime >4min |

**❌ HIPÓTESE HIPM/DIPM REFUTADA — CAUSA RAIZ NÃO É LPM:**

Mesmo com **LPM 100% desligado** (quirk NOLPM + sysfs `max_performance`), o colapso aconteceu **exatamente no mesmo momento do baseline**:

| Evento | Timestamp | Comentário |
|--------|-----------|------------|
| `ata1.00: exception Emask 0x0 SAct 0x400000 SErr 0x0 action 0x6 frozen` | **t=31.849479s** | IDÊNTICO ao histórico (31.8s) |
| `ata1: hard resetting link` (1º) | t=31.854s | |
| `ata1: SATA link up 3.0 Gbps` | t=32.333s | |
| `ata1.00: qc timeout after 5000 msecs (cmd 0xec)` | t=37.473s | IDENTIFY timeout |
| `ata1: limiting SATA link speed to 1.5 Gbps` | t=47.974s | Downshift |
| `ata1.00: disable device` | **t=78.951907s** | IDÊNTICO ao histórico (~79s) |

**⚠️ DESCOBERTAS NOVAS CRÍTICAS:**

1. **Drive é Drive-managed SMR** (confirmado em dmesg): `sd 0:0:0:0: [sda] Drive-managed SMR disk` — drives SMR gerenciados pelo firmware têm latência oculta de garbage collection que explode timeouts.

2. **NCQ NÃO está sendo desligado pelo bootargs:** `libata.force=1.00:3.0Gbps,noncq` está no cmdline mas o comando que trava é `READ FPDMA QUEUED` (NCQ) com tag 22 → o `noncq` não está fazendo efeito neste controlador Baikal.

3. **Link físico permanece up** — o PHY SATA nunca cai (`SStatus 123/113` sempre presente), o drive para de responder a comandos SCSI.

4. **NÃO é LPM** — LPM 100% off, quirk aplicado, `max_performance`, mas o colapso é **byte-a-byte idêntico** ao baseline.

5. **⚠️ HARDWARE FIXO:** O Toshiba MQ04ABF100 é o **HD interno do PS4** (conectado diretamente na placa-mãe, sem cabo SATA removível) — não dá para trocar por outro drive para isolar hardware vs firmware.

---

### **PRÓXIMOS CAMINHOS DE INVESTIGAÇÃO (causa raiz real):**

| Hipótese | Por que vale testar | Ação |
|----------|---------------------|------|
| **NCQ efetivo não desligado** | O comando que trava é `READ FPDMA QUEUED` (NCQ tag 22). Se `ATA_QUIRK_NONCQ` for aplicado ao mesmo modelo, o kernel não emitirá FPDMA QUEUED. | Adicionar quirk `ATA_QUIRK_NONCQ` (ou `ATA_QUIRK_BROKEN_FPDMA_AA`) junto ao `NOLPM` em `libata-core.c`. |
| **Timer de spin-down do drive SMR** | Drive-managed SMR (Toshiba MQ04ABF100) tem timer interno de idle → spindown → firmware trava comandos subsequentes. Em 31s sem I/O no disco, ele entra "deep idle". | 1. `hdparm -S 0 /dev/sda` para desligar standby timer. 2. Ou forçar I/O periódico (cron a cada 10s). 3. Testar quirk `ATA_QUIRK_NO_IDLE` se existir. |
| **Calibração PHY SATA Baikal incompleta** | Colapso em **exatos 31.85s** sugere timer de PHY/efuse. `bpcie_baikal_sata_phy_init` portou `dc72bfb0` mas pode faltar etapa. | Rever `ps4-bpcie.c:549` vs `decompiled/baikal_sata_phy_init_dc72bfb0.txt` — conferir trace length, efuse, hold/pulse. |
| **Timeout EH do libata** | Kernel aborta em 5000ms → 10000ms → 30000ms. Se a latência SMR (garbage collection) excede 5s, o EH acha que travou. | Aumentar `ata1.eh_timeout` se exposto, ou patchar `libata-eh.c` (sem rebuild completo: via `sysfs` se exposto). |
| **Power domain separado do PHY** | ICC power-on SATA liga o MAC mas o PHY pode ter domínio separado (como GBE). | Procurar no Orbis ICC minor para PHY SATA power-on (além do major=5 minor=0x20). |

---

### **Próximo passo imediato (baixo risco, alto impacto):**
Aplicar quirk `ATA_QUIRK_NONCQ` (ou `ATA_QUIRK_BROKEN_FPDMA_AA`) junto ao `NOLPM` no `libata-core.c:4194` para o modelo `"TOSHIBA MQ04ABF100"`. Isso desabilita NCQ no nível do driver (não via bootargs) e evita que `READ FPDMA QUEUED` seja emitido — o comando que sempre falha em tag 22.

**✅ APLICADO (2026-07-25, pós-smoke-test):**
- `ATA_QUIRK_NOLPM | ATA_QUIRK_NONCQ` adicionado em `libata-core.c:4194` para `"TOSHIBA MQ04ABF100"`
- Backup preservado: `libata-core.c.orig-backup`

**Build + teste 2026-07-28 (tag `sata-noncq-fix-20260728`):**
- Kernel `bzImage-7.0-sata-noncq-fix-20260728` compilado (ThinLTO, 15.8 MB)
- Deploy via `deploy-boot-7.0.sh` — bootargs mantido `libata.force=1.00:3.0Gbps,noncq ahci.mobile_lpm_policy=1`
- **SMOKE TEST AO VIVO (2026-07-28):**
  - ✅ Quirk aplicado: `[1.158248] ata1.00: Model 'TOSHIBA MQ04ABF100', rev 'JU0G0A', applying quirks: nolpm noncq`
  - ✅ NCQ desabilitado no driver: `1953525168 sectors, multi 16: LBA48 NCQ (not used)`
  - ❌ **FALHA PERSISTE** — o colapso ocorreu **idêntico ao baseline**, só mudou o comando:
    - Antes: `READ FPDMA QUEUED` (NCQ tag 22)
    - Agora: `READ DMA` (legacy, cmd 0xc8) → IDENTIFY timeout 5s → 10s → 30s → disable device
    - Timestamps: exception 31.8s → hard reset → link up 3.0Gbps → IDENTIFY timeout 5000ms (37.5s) → 10000ms (47.9s) → downshift 1.5Gbps → disable device (78.9s)

**Testes adicionais 2026-07-28 (sem rebuild):**
| Teste | Resultado |
|-------|-----------|
| `hdparm -S 0 /dev/sda` (desligar standby timer) | **Erro I/O** — drive já falhando no momento do comando |
| `dd` periódico 4K/5s (evitar deep idle SMR) | **Não impediu** — erros contínuos no setor 0, drive morre mesmo com I/O |

**⚠️ DESCOBERTAS CRÍTICAS 2026-07-28:**
1. **Drive é Drive-managed SMR** (confirmado): `sd 0:0:0:0: [sda] Drive-managed SMR disk` — latência oculta de garbage collection explode timeouts
2. **NCQ desabilitado no driver funciona** — não há mais `READ FPDMA QUEUED`, mas `READ DMA` legacy também falha
3. **Link físico permanece up** — PHY SATA nunca cai (`SStatus 123/113` sempre), drive para de responder comandos SCSI
4. **NÃO é LPM/NCQ** — 100% off, mas colapso **byte-a-byte idêntico** ao baseline (31.8s exception → 79s disable)
5. **⚠️ HARDWARE FIXO:** O Toshiba MQ04ABF100 é o **HD interno do PS4** (conectado diretamente na placa-mãe, sem cabo SATA removível) — **não dá para trocar por outro drive para isolar hardware vs firmware**. Isolamento de hardware **não é possível**.

---

### ⚠️ **DIAGNÓSTICO PARCIAL (2026-07-28) — corrigido após o teste ao vivo**

> 🔴 **ERRATA:** a versão original desta seção afirmava que "o AHCI não tem handler de interrupção
> registrado". **Isso estava errado.** O AHCI sempre teve handler — ele se chama
> **`xhci_aeolia[0000:00:14.7]`**, não `ahci[...]`, porque `ata_host_activate()`
> (`libata-core.c:6206`) usa `dev_driver_string(host->dev)` e o AHCI interno é instanciado de
> dentro do `xhci_aeolia`. Procurar por `ahci[0000:00:14.7]` nesta função é falso negativo
> garantido. Também estava errada a tese de que a falha era específica de NCQ — ver abaixo.

**O que continua verdadeiro:** o AHCI *compartilhava* a IRQ 32 com os dois xHCI, e o vetor que lhe
caberia é o hwirq **5345** (função 7, subfunção 1).

Em 100% dos logs a falha é um `READ FPDMA QUEUED` (NCQ) que nunca completa, com **`SErr 0x0`**
(zero erro de link), `Emask 0x0` e `status { DRDY }`, e o link permanece estável em 3.0 Gbps
antes e depois. Uma conclusão de comando NCQ depende exclusivamente do SDB FIS — sem
interrupção, o tag fica pendente até o timeout de 30s do SCSI estourar.

**Causa:** `bpcie_assign_irqs()` (`ps4-bpcie.c`) clampava `nvec = 1` para toda função != 4,
apesar de `subfuncs_per_func[7]=3`, do ramo de demux `func == 7` já existente em
`bpcie_handle_edge_irq()`, do `MSI_FLAG_MULTI_PCI_MSI` no domínio e de
`xhci_aeolia_skip_index()` já reservar o índice 1 para o AHCI. Toda a infraestrutura existia;
uma linha a desativava.

| Hipótese anterior | Status |
|-------------------|--------|
| Calibração PHY SATA Baikal incompleta | ❌ **REFUTADA** — `SErr 0x0` em 100% das falhas, link estável; registradores AHCI confirmam `PxSERR=0` |
| Power domain separado do PHY | ❌ **REFUTADA** — mesma razão; MAC responde, PHY inicializa, link sobe |
| Timeout EH do libata | ❌ **REFUTADA** — mascararia o sintoma; o comando nunca completaria de todo jeito |
| Firmware drive SMR bug | ❌ **REFUTADA** — drive nunca reportou erro; falha em `dmesg.log` foi no LBA 0 |
| "Colapso em exatos 31.85s = timer de PHY/efuse" | ❌ **FALSO** — falhas em 31.84s, 36.58s e 44.76s |
| "AHCI sem handler de IRQ registrado" | ❌ **FALSO (erro meu)** — o handler chama-se `xhci_aeolia[0000:00:14.7]` |
| "A falha é específica de NCQ" | ❌ **REFUTADA pelo teste** — com `noncq` ativo falha como `READ DMA` (`0xc8`, `SAct 0x0`), não-enfileirado |
| Interrupção mascarada | ❌ **REFUTADA** — `GHC=0x80000002` (IE on), `PxIE=0x7840007f`, `PxIS=0`, `IS=0` |

### Resultado dos dois testes ao vivo (2026-07-28)

**Teste 1 — tag `20260728-sata-irq-dedicada` (`test_history` id 64, PARCIAL).** A alocação de 3
vetores funcionou no nível de alocação: `/proc/interrupts` passou a mostrar hwirq 5344/5345/5346 e
`ata1 ... irq 33`, sem regressão em USB/`mmc0`/`mts`/Blu-ray. **Mas o HD continuou falhando**, agora
com `READ DMA` (não-enfileirado), o que já refutou a tese de NCQ.

**Teste 2 — tag `20260728-sata-demux-diag` (`test_history` id 65, REFUTADO).** Instrumentação com
contadores no demux. Resultado decisivo:

```
chamadas no vetor f7 sub0 (hwirq 0x14e0):  4096+
chamadas no vetor f7 sub1 (hwirq 0x14e1):     0   <- o "dedicado" ao AHCI, NUNCA dispara
invocações do demux sem nada a despachar:     0
```

🔴 **A hipótese da corrida no ACK compartilhado está REFUTADA** — não há disputa porque só existe
um vetor na prática. **O hardware Baikal agrega todas as IRQs da função 7 numa única mensagem MSI**
(a da subfunção 0); o demux não é contorno, é a forma correta de lidar com esse hardware. Todas as
14 entregas ao AHCI vieram com `origem sub0`.

🔴 **Consequência: a correção da Fase B é inútil e deve ser revertida.** Alocar 3 vetores não faz o
hardware usar 3 mensagens. Não regride nada, mas é complexidade sem benefício.

**Decodificação nova do `BPCIE_ACK_READ`** (BAR2 do glue, `0x110088`; write em `0x110084`): para a
função 7 os bits **18:16** são flags de pendência por subfunção, **ativos em nível baixo** —
`0x001e0103` = só sub0; `0x001c0103` = sub0 + **sub1 (SATA)**; `0x001a0103` = sub0 + sub2.

**PISTA PRINCIPAL:** a última interrupção do AHCI chegou aos **4,907s** e nunca mais. A falha aos
36,78s é só o timeout de 30s do SCSI estourando sobre um comando emitido por volta dos 6,8s.
Depois dos 4,9s o bit 17 do ACK **nunca mais volta a zero**.

**Pergunta real agora:** por que o glue para de sinalizar a subfunção 1 como pendente? Falta
determinar se o AHCI chega a *pedir* a interrupção (levantar `PxIS`) e o glue não propaga, ou se o
próprio controlador para de pedir. Próxima instrumentação deve ler `PxIS` no instante em que um
comando está pendurado — não depois do dispositivo desabilitado, como foi feito. Vale também
consultar `outros/rea/INDEX.md` (e o `INDEX.md` do subsistema) e a tabela `decompiled_functions` para ver como o driver
Orbis trata o rearme dessas subfunções.

Detalhes em `PLANO_SATA_INTERNO_100PCT_2026-07-28.md`; memórias
`memory/baikal-func7-um-unico-vetor-msi-2026-07-28.md` e
`memory/sata-interno-falha-e-ncq-irq-compartilhada-2026-07-28.md`.

**Correção editada em 2026-07-28 (build em andamento, tag `20260728-sata-irq-dedicada`):**
clamp virou `nvec = min(nvec, bpcie_max_vectors(PCI_FUNC(dev->devfn)))`, com helper que
devolve `subfuncs_per_func[func]` só para funções com ramo de demux (4, 5, 7). Efeito prático:
só a função 7 muda (1 → 3 vetores); `mmc0`, `mts` e o AHCI do Blu-ray ficam idênticos.

⚠️ **Ao validar, REMOVER `noncq` do bootargs** — com NCQ desligado o teste não prova nada.
Critério de aceitação: `/proc/interrupts` passar a mostrar `Baikal-MSI 5345-edge ahci[0000:00:14.7]`.

Registro no banco: `test_history` id **63**. Memória:
`memory/sata-interno-falha-e-ncq-irq-compartilhada-2026-07-28.md`.

**Análise do Log UART (2026-07-29):**
- Confirmado via captura UART (`sata_teste_20260729_113413.log`): `sda` reconhecido aos 3.13s; exception estoura aos 36.79s (`READ DMA` opcode `0xc8`, tag 15); descarte final aos 83.89s; `/init` chamado apenas aos 84.60s (atraso medido de 78s).
- `SErr 0x0` e status `{ DRDY }` confirmados: link físico SATA está 100% íntegro. A falha é a perda do ACK de interrupção no demux do Glue (`0x110084`).
- **Deploy realizado (2026-07-29):** Tag `20260728-sata-ackfix-ehdump` gravada com sucesso no HD USB (gravado `bzImage` com o fix no ACK do demux, `bootargs` com console UART e `rootwait`). Pronto para teste ao vivo pós-power-cycle.

---

### **Plano detalhado — SATA interno 100% funcional:**
Ver documento dedicado: ~~`obsoleto/PLANO_SATA_INTERNO_100PCT_2026-07-28.md`~~ (plano histórico, apagado em 2026-11-11 junto com a pasta `obsoleto/`; a solução final está em `patches/ahci-baikal-polling-fallback.patch`)


**Custo restante (muito menor que o estimado antes):**
- Não requer mais RE de PHY nem troca de hardware — ambas as linhas foram refutadas
- Falta: build (em andamento) + montar tag + 1 deploy + 1 power cycle + teste de carga
- Rootfs no USB (`sdb`) já funciona — SATA interno é **storage extra**, não bloqueador de boot

---

### **Impacto no projeto:**
- 🔴 **BLOQUEIA O BOOT — corrigido 2026-07-28.** A afirmação anterior ("não bloqueia boot") estava
  **errada**. Medição ao vivo com `systemd-analyze`: o boot leva **2min 15s** (101s kernel + 34s
  userspace), e **~78s disso é a cascata de EH do SATA** — o `sda` é detectado em 1,28s, falha em
  31,84s, e o `Freeing unused kernel image` (fim da init do kernel) acontece **50 ms depois** do
  `EH complete` em 79,44s. São **58% do tempo de boot** parados esperando a leitura da tabela de
  partição do `sda` fracassar. Resolver isto sozinho derruba o boot de 135s para ~57s.
- Os outros dois custos de boot (fora do escopo deste item): `systemd-modules-load` carregando o
  `mts` = **32,0s** (24%), e `rootdelay=10` = 10s fixos (7%). Ver item próprio.
- **Bloqueia uso do HD interno** como armazenamento confiável
- **Prioridade média mantida** — foco principal continua GBE Ethernet (RX morto)

</details>

---

### [x] Testar renderização 3D ao vivo (glxgears/vulkaninfo) — **VALIDADO ao vivo 2026-07-25**

**Resultados:**
- **OpenGL:** 4.5 Core Profile, Mesa 26.1.5, renderizador `AMD DG1501SML87LB (radeonsi, kaveri, ACO)`, 1024MB VRAM dedicada
- **glxgears:** ~54 FPS (1920x1080@60 via HDMI, sincronizado com refresh)
- **Vulkan:** 1.3.354, driver RADV KAVERI 26.1.5, device `AMD DG1501SML87LB`, `INTEGRATED_GPU`, todas features 1.3 habilitadas
- **Direct rendering:** sim, acelerado por hardware
- **Comprovado:** GPU Gladius 100% funcional — OpenGL 4.5 + Vulkan 1.3 + aceleração 3D real

### [x] RTC via ICC no PS4 Linux — driver `rtc-ps4-icc` **FUNCIONAL PARA TIMEKEEPING** (2026-11-15)

✅ **TESTADO AO VIVO EM 2026-11-15** (tag `20261113-full-rebuild`):
- `/dev/rtc0` aparece após `modprobe rtc-ps4-icc`
- `/proc/driver/rtc` mostra hora correta (`rtc_time: 11:37:50`, `rtc_date: 2026-11-15`)
- System clock semeado no boot pelo driver (`setting system clock to 2026-11-13T17:29:57 UTC`)
- `pacman -Sy` funciona sem erro de SSL/clock
- `date` estável entre boots (RTC persiste via ICC)

⚠️ **Limitação conhecida:** `hwclock -r` dá timeout (`select() to /dev/rtc to wait for clock tick timed out`) — o driver não implementa UIE emulation (`CONFIG_RTC_INTF_DEV_UIE_EMUL=y` está no kernel mas o driver não trata a interrupção de update). Para timekeeping funciona; para `hwclock` direto não.

**Status das Fases:**
1. [x] Fase 1 — `CONFIG_RTC_CLASS=y`, `CONFIG_RTC_INTF_DEV=y`, `CONFIG_RTC_DRV_CMOS=y`, `CONFIG_RTC_HCTOSYS=y`, `CONFIG_RTC_DRV_PS4_ICC=m`
2. [x] Fase 2 — Wrapper `ps4_icc_rtc_cmd()` com retry loop em `ps4-bpcie-icc.c` + patch `ps4-icc-rtc-wrapper.patch`
3. [x] Fase 3 — `drivers/rtc/rtc-ps4-icc.c` corrigido (leitura MMIO `0x5180000`, escrita `0x5140000`)
4. [x] Fase 4 — **VALIDADO AO VIVO** (timekeeping OK, hwclock -r timeout conhecido)
5. [ ] Fase 5 (opcional) — NTP no boot + `fake-hwclock`

**Critérios de sucesso ATENDIDOS (timekeeping):** `/dev/rtc0` existe, hora correta em `/proc/driver/rtc`, system clock semeado no boot, `pacman -Sy` sem erro SSL, `date` persistente entre boots.

**FEATURE ENTREGUE:** PS4 Linux tem relógio de sistema real e persistente entre power cycles, sem depender de rede no boot — TLS (`pacman`, `curl https://`) e timestamps de log funcionam desde o primeiro segundo.

**Documentos:** [`acpi/decompiled/baikal_rtc_mvl.txt`](../rea/acpi/decompiled/baikal_rtc_mvl.txt); [`outros/rea/INDEX.md`](../rea/INDEX.md) e [`acpi/INDEX.md`](../rea/acpi/INDEX.md).

---

## Prioridade baixa

### [~] KVM-AMD para VMs QEMU (uso como ambiente de desenvolvimento)

**Objetivo:** habilitar `CONFIG_KVM`/`CONFIG_KVM_AMD` no kernel 7.0 Baikal para rodar máquinas
virtuais QEMU aceleradas por hardware diretamente no PS4, como ambiente de desenvolvimento.

**Contexto:** estudo de viabilidade já feito em 2026-07-24 — veredito **tecnicamente viável**.
O SoC Jaguar do PS4 (`DG1501SML87LB`, AMD family 0x16 model 0x67) expõe todo o conjunto
SVM/NPT necessário (`svm npt lbrv svm_lock nrip_save tsc_scale flushbyasid decodeassists
pausefilter pfthreshold vmmcall` em `/proc/cpuinfo`), `lscpu` confirma `Virtualization: AMD-V`,
~5.1 GB de RAM disponível. Única barreira real identificada: `# CONFIG_KVM is not set` no
`.config` atual — o código KVM já está presente na árvore do kernel, só falta habilitar via
Kconfig e reconstruir.

**Status:** Fase 1 (levantamento/build estático) concluída — ver `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md`
para o roadmap técnico completo (Kconfigs necessárias, ordem de habilitação, riscos).

**Próximo passo:** habilitar `CONFIG_KVM`/`CONFIG_KVM_AMD` no `.config`, rebuild via
`00-build-kernel-7.0.sh`, testar `/dev/kvm` aparece e `qemu-system-x86_64 -enable-kvm` sobe uma
VM básica.

---

### [ ] Enxugar o kernel: remover tudo que não é específico do PS4 nem tem uso prático

**Objetivo:** reduzir o `.config` ao que o console realmente usa. Ganhos esperados: builds mais rápidos, menor pico de memória (hoje um build chega a exigir mais RAM do que a máquina tem), `bzImage` menor e menos superfície para bug/regressão.

**Caso exemplar já identificado — `CONFIG_DEBUG_INFO_BTF`:**
- Gera metadados de tipos para **BPF CO-RE** (bpftrace, BCC, libbpf). Nada disso é usado aqui: o debug do projeto é `dmesg` + telnet + leitura de MMIO.
- Custo medido em 2026-07-21: o passo `pahole` consome **10,9 GB de RSS** e roda depois do link, sobre o `vmlinux` pronto. Foi o maior consumidor de memória do build inteiro — maior que o próprio link ThinLTO.
- Desabilitar **não desabilita BPF** (`CONFIG_BPF_SYSCALL` continua funcionando); só remove os metadados.
- O projeto já roda cgroup v1 (`systemd.unified_cgroup_hierarchy=0`), então nem os usos de BPF do systemd pesam.
- Implementação: `scripts/config --disable CONFIG_DEBUG_INFO_BTF` (e provavelmente `CONFIG_DEBUG_INFO_BTF_MODULES`) no `00-build-kernel-7.0.sh`, junto dos outros `scripts/config` que já estão lá.

**Outros candidatos a avaliar** (não verificados ainda — levantar antes de desabilitar):
- Drivers de hardware que o console não tem (o `.config` vem de um defconfig genérico).
- Sistemas de arquivos não usados — hoje só precisamos de ext4 (rootfs), vfat (partição BOOT) e o necessário ao initramfs.
- Subsistemas de virtualização já parcialmente desligados no script (`KVM`, `PARAVIRT`, `HYPERVISOR_GUEST`) — conferir se sobrou algo.
- `CONFIG_DEBUG_INFO` em si: se ninguém for abrir o `vmlinux` em debugger/Ghidra, é muito peso morto. **Cuidado:** hoje ele é útil para inspecionar o binário compilado, então avaliar caso a caso.

**Cuidado ao executar esta tarefa:** mudar o `.config` dispara recompilação ampla (~40 min nesta máquina). Vale agrupar todas as remoções em **uma única** rodada e testar o boot depois, em vez de ir removendo aos poucos. E manter a tag anterior em `boot_referencia/` para rollback — cada teste ao vivo custa um power cycle completo.

### [ ] WiFi — manufacture data (NVRAM) ausente → movido para `outros/rea/wifi/`

Pendência e plano de correção (NVRAM `/data/nvram/APCFG/APRDEB/WIFI`, país BR, MAC do eFUSE) agora vivem em [`outros/rea/wifi/plans/PLANO_DRIVER_WIFI_BAIKAL.md`](../rea/wifi/plans/PLANO_DRIVER_WIFI_BAIKAL.md). Índice da pasta: [`outros/rea/wifi/INDEX.md`](../rea/wifi/INDEX.md).

### [ ] Power Management — reativar DPM

`radeon.dpm=0 amdgpu.dpm=0` está fixo hoje por instabilidade de clocks dinâmicos. Reativar com testes de estresse quando houver tempo, não é bloqueador.

---

## Concluídos recentemente (referência — não repetir)

### [x] ✅ Reorganização do repo em duas frentes + **build da distro testado de ponta a ponta** (2026-11-11)

**Reorg (frente 1 / frente 2):** `kernel/` ficou só com build+patches; documentação do driver MTS
consolidada em [`../../kernel/drivers_mts/`](../../kernel/drivers_mts/); acervo de RE em [`../rea/`](../rea/);
harnesses e ferramentas em [`../tools/`](../tools/); `boot_referencia/` migrou para
`distro/boot_referencia/` (fonte única, consumida pelas duas frentes).

**Build da distro validado de ponta a ponta** (tag `20261111-preflight-test`):
- `kernel/00-build-kernel-7.0.sh 20261111-preflight-test` → bzImage 16.122.880 B,
  versão `7.0.8-Strawberry-ThinLTO-Baikal-+`, snapshot 559 MB.
- `distro/scripts/build-image-docker.sh 20261111-preflight-test` → rootfs Arch + initramfs
  (14.771.321 B) + bootargs (578 B) + tar do rootfs (3,2 GB), **sem** Mesa patchado (o
  `mesa/01-build-mesa.sh` não foi rodado — ver item pendente abaixo).
- `distro/deploy-boot-7.0.sh 20261111-preflight-test` testado contra uma partição **vfat de
  loopback** (label `BOOT`, 200 MB, `/dev/loop0p1`): sanity de tamanho, cópia, **MD5
  origem→destino OK nos 3 arquivos**, `active-tag.txt` gravado, desmontagem automática OK.

**Bugs achados e corrigidos na revisão (todos com lição registrada):**
1. **61 dos 62 `.sh` versionados como `100644`** → todo comando documentado
   (`sudo ./deploy-boot-7.0.sh <TAG>`) falhava com "Permission denied" num clone novo.
   Corrigido: `chmod +x` + modo `100755` no git (lição #29).
2. **Build da distro exige host Arch** (`pacstrap`/`pacman`/`arch-chroot`): em Debian o build
   morria. Criado `distro/scripts/build-image-docker.sh`, que roda **o mesmo script oficial**
   em `archlinux:latest` (lição #30).
3. **`mkinitcpio` aborta o build inteiro** se qualquer nome de `MODULES=()` não existir nem
   como módulo nem como built-in (foi o caso de `uas`, que é `CONFIG_USB_UAS=y` — validado
   contra `modules.builtin.modinfo`).
4. **initramfs gerado com modo 600** (umask do mkinitcpio) → ilegível por usuário normal
   (`promote-release.sh` quebraria). Corrigido com `chmod 644`.
5. **Divergência silenciosa `drivers_mts/mts.c` × patch**: o build copia `drivers_mts/` por
   cima do patch, escondendo editions não regeradas. Agora o build **compara e aborta**
   (falhando alto) se os dois divergirem.
6. `02-burn-image-7.0.sh`: `vram.txt` deixa de ser requisito (criado com default 1024, igual
   ao `deploy-boot`) e ganhou aviso quando o bzImage da tag é mais novo que o tar do rootfs.
7. Documentação corrigida: o initramfs atual é do **mkinitcpio** (resolve `root=LABEL=psxitarch`
   via blkid/udev), não um init busybox com `mount LABEL=... /newroot` literal.

### [x] ✅ `rootwait` no lugar de `rootdelay=10` — **10,5s de boot economizados, validado ao vivo 2026-07-28**

Medição isolando a fase de initramfs (fim da init do kernel → start do systemd), que é onde o
`rootdelay` atua:

| Boot | Fase initramfs | Bootarg |
|------|----------------|---------|
| tag `20260728-sata-irq-dedicada` | 79,5s → 101,2s = **21,7s** | `rootdelay=10` |
| tag `20260728-sata-demux-diag` | 84,5s → 95,7s = **11,2s** | `rootwait` |

Ganho de **10,5s**, batendo exatamente com os 10s removidos. E o ganho real é **maior** que o
medido, porque o boot com `rootwait` carregava também console UART e instrumentação de debug,
ambos custosos. `dmesg | grep -ic "Waiting for root"` = **0** — o rootfs (`/dev/sdb2`, USB) foi
encontrado de imediato, sem espera.

`rootdelay=N` é espera cega (dorme N segundos mesmo com o disco pronto); `rootwait` espera o
dispositivo *aparecer* e segue na hora. **Usar `rootwait` em todo bootargs novo.** Modelo:
`boot_referencia/bootargs-7.0-20260728-sata-diag.txt`. Registrado em `AGENTS.md` (convenções de
bootargs), `test_history` id **66**, memória
`memory/rootwait-substitui-rootdelay-ganho-10s-2026-07-28.md`.

- [x] **GPU amdgpu/Gladius (GFX/CP)** — `ring gfx test failed (-110)` resolvido em 2026-07-23 com firmware genuíno extraído via `kexec`; 32 CUs ativos, OpenGL 55 FPS, Vulkan 1.3 disponível. Ver `MARCO_HISTORICO_GPU_GLADIUS_REAL.md`.
- [x] **Migração para kernel 7.0 Baikal** — concluída em 2026-07-22 (baseline `v7.0-20260722-clean-video-ok`), superou de vez a necessidade de "migrar para 6.x" (item removido do roadmap).
- [x] **Rootfs completo via systemd (RELEASE, sem debug loop)** — validado ao vivo 2026-07-23 com `bzImage-7.0-20260723-RELEASE`.
- [x] **Ethernet GBE — MAC core e TX por software** — interface `eth0` sobe, MAC ligado via ICC, TX ~95% funcional (RX ainda pendente, ver item ativo acima).
- [x] **Kernel Dump 12.52 via TCP** — concluído em 2026-07-20 (32.2 MB em 3s, zero corrupção).

### [x] ✅ Testes ao vivo completos na tag `20261113-full-rebuild` (2026-11-15)

**Build testado:** kernel 7.0.8-Strawberry-ThinLTO-Baikal-+ (tag `20261113-full-rebuild`), HD USB `/dev/sda`, deploy MD5 verificado.

| Componente | Status | Detalhes |
|---|---|---|
| **Boot + Vídeo HDMI** | ✅ | Kernel carrega, vídeo 1080p@60, SSH WiFi ativo |
| **SSH WiFi** | ✅ | `192.168.6.128`, root/ps4 |
| **SATA interno (Toshiba MQ04ABF100)** | ✅ | `ata1.00: configured for UDMA/100`, 931.51 GiB, `dd` 27 MB/s, zero `disable device` |
| **RTC via ICC** | ✅ (timekeeping) | `/dev/rtc0`, `/proc/driver/rtc` hora correta, system clock semeado no boot, `pacman -Sy` OK. `hwclock -r` timeout (UIE emulation faltando) |
| **Baikal Memory v0.2** | ✅ (device) / ⚠️ (sysfs) | Módulo carrega, MAC `2c:cc:44:3f:69:5f` em offset 0x52f000, ICC em 0x52c000. Sysfs offsets desalinhados |
| **Áudio HDMI** | ✅ | `plughw:0,3` (HDMI 0) e `plughw:0,7` (HDMI 1) funcionam, `speaker-test` confirmado |
| **Ethernet GBE (mts.ko)** | ⚠️ | MAC `2c:cc:44:3f:69:5f` correto, TX pronto, **NO-CARRIER** (PHY firmware) |
| **CIFS** | ⚠️ | cifs.ko BTF mismatch no rootfs; autofs configurado. Precisa rebuild módulo contra kernel atual |
| **pacman (SSL/clock)** | ✅ | `pacman -Sy` sincroniza sem erro |
| **S5 power-off** | ⏭️ | Não testado (requer power-cycle dedicado) |

**Próximos builds devem corrigir:**
1. Rebuild módulos (mts, cifs, baikal-dmac, baikal_wdt, baikal-hpet) contra kernel atual no `01-build-image-7.0.sh`
2. Ajustar offsets sysfs do `baikal-memory` (alinhar device file ↔ sysfs)
3. Adicionar `alsa-utils` ao `PKGS` do build
4. Implementar UIE emulation no `rtc-ps4-icc` para `hwclock -r`

---

### Achado do RE (2026-07-28) — lock do ACK do glue diverge do Orbis

Consultando **apenas o corpus já decompilado**, o `baikal_pcie_neighborhood.txt` continha (sem
estar catalogada) a função `dc718b40`, equivalente Orbis do nosso `bpcie_handle_edge_irq()`.
Agora catalogada em `decompiled_functions`, status `revisado`.

**Confirmações úteis:** os valores mágicos do nosso demux **estão corretos** (func 4 →
`w=2/mask=-1/shift=0`; func 7 → `w=3/mask=7/shift=0x10`; func 5 → `w=3/mask=3/shift=0`), e o
cálculo `mask & ~(valor >> shift)` bate com o `andn` do Orbis. Diferença estrutural: a função da
Sony só **devolve** a máscara — o dispatch fica no chamador; a nossa faz as duas coisas juntas.

**Divergência a corrigir:** `0x110084` é um **seletor compartilhado** entre func 4 (`icc`),
func 5 (DMAC) e func 7 (xHCI + AHCI), e o acesso é um par não-atômico (escreve o seletor, lê a
máscara). O Orbis serializa com um **mutex global único** (objeto `0xde615a80`, lock `dc6c8710`
linha 318 / unlock `dc6c88b0` linha 321). Nós usamos `raw_spin_lock(&desc->lock)` — **por
descritor**, sem exclusão mútua entre descritores diferentes. Dois handlers em CPUs distintas
podem interleavar e um ler a máscara do grupo errado.

⚠️ **Provavelmente NÃO é a causa da falha do SATA:** se a corrida fosse frequente veríamos
invocações com máscara zerada (`VAZIO`) e a instrumentação mediu **zero**; o `icc`, principal
candidato a colidir, disparou só 26 vezes no boot inteiro. Corrigir mesmo assim, por ser bug real.

**O corpus decompilado não tem nada de AHCI/SATA no lado da interrupção** — só `dc72bfb0` (PHY
init) e helpers de leitura do glue. A resposta para "por que o glue deixa de sinalizar a
subfunção 1" não está no material já decompilado. Memória:
`memory/glue-ack-lock-global-divergencia-orbis-2026-07-28.md`.

---

## Hardware — pendentes (re-verificação 2026-11-12)

Itens abaixo são exclusivamente de hardware/driver. Para cada componente sem driver ou não funcional, a tarefa é conseguir ou desenvolver o suporte no kernel Linux 7.0 Baikal.

### [x] ⚡ Ethernet GBE eth0 (00:14.1) — **MAC FUNCIONAL, PHY NÃO LINKA** (bloqueador de firmware) — validado 2026-11-15

✅ **TESTADO AO VIVO EM 2026-11-15** (módulo `mts.ko` carregado após strip BTF):
- Driver `mts` carrega e registra `eth0` com MAC correto `2c:cc:44:3f:69:5f` (lido da SPM)
- Anéis DMA programados, TX por software funcional
- **NO-CARRIER** — PHY não responde a MDIO, link não sobe
- Ping 100% perda (esperado sem link físico)

⚠️ **Módulo no rootfs tem BTF mismatch** — precisa rebuild contra kernel atual ou strip BTF + fix symbols. Carregado ao vivo via `insmod /tmp/mts-no-btf.ko stage=4`.

**Causa raiz confirmada:** power-on físico do PHY é feito pelo firmware/bootloader Sony **antes** do kernel assumir. Não há sequência replicável via MDIO, ICC, SAMU ou RMU que um driver Linux possa executar (RE da thread `gbe_phy_ctrl` concluída 2026-07-30).

**Status:** Driver funcional, MAC correto, TX pronto. **PHY não linka** — bloqueador de firmware, não solucionável via driver Linux. Reabrir só com nova fonte de dados (vazamento firmware, dump SAMU, docs terceiros).

**Documentos:** `outros/rea/ethernet/plans/PLANO_DRIVER_ETHERNET_BAIKAL.md`, `outros/rea/ethernet/docs/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`, `outros/rea/ethernet/docs/RE_KERNEL_GBE_ATTACH.md`, `outros/rea/ethernet/docs/ICC_GBE_TEST_LOG.md`, `outros/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md`

---

### [x] 📶 Bluetooth — **FUNCIONANDO** (validado 2026-11-13)

**Estado:** Driver `btmtksdio` (MediaTek MT7668) carregado e bound ao SDIO function 2. Controlador `hci0` detectado (MAC: `E8:D8:19:93:CC:AE`). Bluetooth daemon rodando, descoberta de dispositivos funcionando (testado: "L3250 Series" detectado).

**O que estava faltando:** apenas instalar `bluez-utils` (já está no PKGS do build) e habilitar o serviço `bluetooth.service`. O driver `btmtksdio` já estava compilado no kernel (`CONFIG_BT_MTKSDIO=y`) e funcionando — bound ao SDIO device `mmc0:0001:2` (MT7668).

**Validado ao vivo:**
- `lsmod | grep btmtk` → driver bound (built-in kernel)
- `dmesg | grep -i bluetooth` → hci0 setup OK, firmware downloaded
- `systemctl enable --now bluetooth` → service ativo
- `bluetoothctl scan on` → descobre dispositivos (ex: "L3250 Series")

**Teste do usuário (2026-11-13):** Bluetooth, **áudio via Bluetooth em caixa de som** e **joystick** testados e funcionando perfeitamente. (Relato do usuário; não medido por mim. Modelo do joystick e forma de conexão não foram informados.)

**Pendente:** parear DualShock 4 (testar se funciona com o profile HIDP já habilitado no kernel). Fechar esta pendência só se o joystick testado pelo usuário era o DualShock 4; se era outro controle, ela continua aberta.

---

### [~] 🔌 Baikal ACPI (00:14.0) — sem driver · HPET/WDT da glue (00:14.4) — driver inexistente

**Estado (revisado 2026-11-13):** duas coisas distintas.

**a) Função ACPI `00:14.0` (`104d:90d7`) — SEM DRIVER (mantido).**
MMIO `fdf8000000` (32M) + I/O `1000`, nenhum driver carregado — e está correto assim:
- PM1a_EVT `0x1000`, PM1a_CNT `0x1004`, PM_TMR `0x1008`, GPE0 `0x1014` já são reclamados pelo núcleo ACPI
  (FACP tem corpo ACPI 1.0 legado; confere com `/proc/ioports`).
- DSDT com 396 bytes: nenhum objeto de dispositivo a parsear.
- Power button já implementado (`ps4-apcie-pwrbutton.c` / `icc_pwrbutton_init()` → `KEY_POWER` via ICC).
- Shutdown já implementado (`icc_shutdown` → `pm_power_off`).
- **Sleep/wake NÃO está implementado** (`bpcie_icc_suspend()`/`bpcie_icc_resume()` são stubs vazios).

**b) HPET/WDT da glue `00:14.4` (`104d:90db`, subfunção ICC 22) — REABERTO, leitura ao vivo feita, driver inexistente.**
O hardware **existe** (confirmado ao vivo) e **não há driver Linux público**:

**Leitura pontual executada (2026-11-13, autorizada):**
- Endereço: `BAR2(00:14.4) + 0x109000` = `0xc8909000` (BAR2 base `0xc8800000`, tamanho 2 MiB — offset cabe dentro da janela)
- Valor lido (8 bytes, CAP/TIMCAP do HPET): `0x05f5e10000002301`
  - REV_ID (bits 0-7): `1`
  - NUM_TIM_CAP (bits 8-12): `3` (controlador com múltiplos timers)
  - LEG_RT_CAP (bit 13): `1`
  - vendor ID (bits 16-31): `0x0000` (**atípico**, não `0xA808` como esperado — peculiaridade da
    implementação Baikal/Sony, não invalida a existência do controlador)
  - bits 32-63: `0x05f5e100` (não-zero, fora do padrão HPET que reserva esses bits)
- **PS4 permaneceu ligado** — leitura pontual é segura. Nenhuma escrita foi feita.
- Registrado em `readonly_verification` (id 893) e `hardware_registers` (id 1339/1340).

Evidências de existência:
- `drivers/ps4/baikal.h`: `BPCIE_SUBFUNC_HPET = 22 //Baikal Timer/WDT`, `BPCIE_HPET_BASE = 0x109000`,
  `BPCIE_HPET_SIZE = 0x400`, `stop_hpet_timers()` com layout HPET padrão.
- Kernel Orbis (`kmem_dump_1252.bin`): device `"Baikal Timer/WDT"` para vendor `0x104d`,
  device `0x90db`, função 4, subfunção `0x16` (=22); driver HPET com `"Baikal High Precision Event Timer"`.
- Nenhum kernel Linux público (5.4 whitehax0r/DFAUS-git/noob404yt, 6.15 crashniels, 7.0) expõe esse bloco.

**Correção de lógica (importante):** as evidências negativas usadas para fechar o item em 2026-11-13 eram
**nulas** — `CONFIG_HPET` e `CONFIG_WATCHDOG` estão desligados (logo `/dev/hpet` e `/dev/watchdog`
**não poderiam existir** mesmo com o hardware presente), e o FADT **não tem campo HPET em nenhuma
revisão da especificação** (a ausência era tautológica). A DSDT/SSDT também não declara o timer porque
o Orbis o expõe via PCI+ICC, não via ACPI.

**Próximas tarefas (b):**
1. ✅ **Validar a leitura em 2 boots (CONCLUÍDO 2026-11-13):** leitura de `0xc8909000` após reboot =
   `0x05f5e10000002301` — **IDÊNTICA** à 1ª leitura. Valor estável confirmado. Registrado em
   `readonly_verification` id 893. **Nenhuma escrita** feita.
2. `drivers/watchdog/baikal_wdt.c` (ou clocksource HPET) como `pci_driver` da glue, ligando
   `CONFIG_WATCHDOG`/`CONFIG_HPET` (hoje desligados).
3. **Nenhuma escrita** em `0xc8909000` ou `0xc8909010` até driver pronto e validado.

**Especificação completa de implementação:** `outros/rea/acpi/plans/PLANO_DRIVER_ACPI_BAIKAL.md` §3.3–3.9
(hardware confirmado, mapa de registradores, restrições críticas, estrutura do driver, configs, passos
de validação, checklist de merge).

**Plano:** `outros/rea/acpi/plans/PLANO_DRIVER_ACPI_BAIKAL.md` (revisão crítica completa em §0).

**Documentos:** `outros/rea/acpi/plans/PLANO_DRIVER_ACPI_BAIKAL.md`, `outros/rea/acpi/decompiled/`, `outros/rea/acpi/scans/`, `outros/rea/acpi/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md`, `outros/rea/dumps/kmem_dump_1252.bin`

---

### [~] 🔄 Baikal DMA (00:14.5) — driver `dmaengine` `baikal-dmac` v0.1 **validado ao vivo** (dmatest 3000/0 falhas)

**Estado (2026-11-13):** dispositivo `104d:90dc`, dois controladores idênticos: BAR0 `ca000000` (DMAC1?) e BAR2 `ca800000` (DMAC2?), 4K cada, registradores em `+0x70` e `+0x80…+0xac`. **Memcpy por descritor validado nos dois** (cadeia de descritores, até 1 MiB, alinhamentos 4–64 B, ~900 MB/s), via harness `outros/rea/dma/harness/baikal_dmac_test/`. **Interrupção MSI funciona no BAR0 e NÃO chega no BAR2.** Decisão do usuário: o driver começa com IRQ no DMAC1 e **polling no DMAC2**.

**Tarefas:**
- [x] Driver `dmaengine` escrito (`drivers/dma/baikal-dmac.c`, v0.1): memcpy, 2 canais, `virt-dma`, descritores de 16 B encadeados, endereços de 32 bits e múltiplos de 4 B. Compila sem avisos (inclusive `W=1`). Patch: `kernel/patches/baikal-dmac.patch` (`git apply --check` validado em estado pristino).
- [x] Integrado ao `00-build-kernel-7.0.sh` (aprovado pelo usuário em 2026-11-13): aplica o patch com `--check` + `exit 1`; liga `CONFIG_DMA_ENGINE=y`, `CONFIG_DMA_VIRTUAL_CHANNELS`, `CONFIG_BAIKAL_DMAC=m`, `CONFIG_DMATEST=m`. **Nota:** `DMA_VIRTUAL_CHANNELS` não tem prompt, então resolve para `m` (derivado do `BAIKAL_DMAC=m`); é um `virt-dma.ko` a carregar antes do driver.
- [x] Build oficial da tag `20261113-dmaengine` **concluído** (2026-11-13 13:30): `bzImage` 16,1 MB e `config` em `distro/boot_referencia/`; `baikal-dmac.ko`, `virt-dma.ko` e `dmatest.ko` construídos (`vermagic` idêntico ao do PS4); snapshot salvo. Config da tag: `DMA_ENGINE=y`, `DMA_VIRTUAL_CHANNELS=m`, `BAIKAL_DMAC=m`, `DMATEST=m`.
- [x] **Deploy da tag `20261113-dmaengine` no PS4 feito e validado ao vivo (2026-11-13).** `initramfs` e `bootargs` reaproveitados da tag `20261113-baikal-memory-fase5` por cópia explícita; só o kernel mudou. O HD caiu no meio do primeiro deploy (ver `LICOES_APRENDIDAS.md`); o segundo foi conferido relendo o disco.
- [x] **`baikal-dmac` v0.1 carregou:** `virt-dma` → `baikal-dmac`; `dma0chan0` e `dma0chan1`; IRQ 37 (DMAC1); sem erro. **`dmatest` (padrão do kernel): 3000 testes, 0 falhas**: canal 0 (IRQ) 200/200; canal 1 (polling) 200/200; **dois canais ao mesmo tempo, 4 threads cada**, 2400/2400; buffers de 256 KiB 200/200. 3 ciclos de `rmmod`/`insmod` sem problema (ver "Achado lateral" abaixo para o `WARNING`).
- [ ] **Falta:** persistir os módulos no rootfs (item "Módulos do rootfs" abaixo), `CON` fora do alinhamento, `len=0`, erro induzido, e a IRQ do DMAC2.

**Documentos:** `outros/rea/dma/plans/PLANO_DRIVER_DMA_BAIKAL.md`, `outros/rea/dma/decompiled/baikal_dmac_mtk_registers_20261113.md`, `outros/rea/dma/scans/dmac_bars_full_20261113.json`. Banco: `test_history` 80–83.

**⏸️ FRENTE PAUSADA em 2026-11-13 (decisão do usuário).** Estado de retomada: driver `baikal-dmac` v0.1 validado ao vivo; falta persistir os módulos no rootfs e os itens "Falta" acima.

**Para iterar versões do driver sem rebuild do kernel:** `outros/rea/dma/harness/build_dma_modules.sh <dir_saida>` recompila `virt-dma`, `baikal-dmac`, `dmatest` e `rtc-ps4-icc` fora da árvore (sem BTF, `vermagic` conferido), a partir do `baikal-dmac.patch` (fonte única). No PS4: `insmod virt-dma.ko && insmod baikal-dmac.ko`; validar com `dmatest`.

**Utilidade do driver (avaliação honesta, 2026-11-13):**
- **Prática hoje: modesta.** É cópia memória→memória por hardware (~900 MB/s isolada, medida no harness), provavelmente **mais lenta que o `memcpy` da CPU**. Só serve a quem pedir pela API `dmaengine`; hoje ninguém pede.
- **Onde o valor deve estar (hipóteses, NÃO verificadas):** o Orbis usa esse DMAC no caminho do HDD e da memória do southbridge (`aeolia_dmac_xfer_upstream/downstream` em logs de swap e escrita em HDD). Se ele move dados entre a RAM e a SPM de 256 MB (a do `baikal-memory`), daria acesso em bloco à SPM em vez de leitura/escrita direta.
- **Já entregue de valor:** núcleo do `dmaengine` no kernel, driver em módulo com ciclo rápido de iteração, `dmatest` como teste de regressão, mapa de registradores e formato do descritor documentados.
- **Limites:** endereços de 32 bits e múltiplos de 4 B; DMAC2 sem IRQ (conclui por polling); módulos ainda não persistidos no rootfs.

**Próximo passo sugerido (não feito):** testar se o DMAC lê a SPM (`0x80000000`, abaixo de 4 GiB, portanto endereçável). **Só leitura.** Cuidado: o DMA **ignora a proteção `allow_write=0`** do `baikal-memory`, então não escrever na SPM por DMA sem decisão explícita.

#### [ ] 🔎 PENDENTE (executar assim que possível): por que o DMAC2 (BAR2) não gera interrupção

Com o hardware concluindo a transferência (`INT_FLAG = 1`), **nenhum vetor MSI é chamado** para o BAR2, nem com 1 vetor compartilhado (`bpcie_assign_irqs`) nem com 2 vetores (`pci_alloc_irq_vectors(pdev,2,2,MSI)`). O BAR0 entrega normalmente pelo vetor 0.

Investigação a fazer, em ordem de custo:
1. **RE do attach do `dmac_mtk.c` no Orbis** (estático, sem risco): achar a rotina que referencia `Can't allocate IRQ` (`0xffffffffdcb55ecd`) e `failed to set up interrupt`; ver como cada controlador obtém a IRQ (rid, `bus_setup_intr`) e se há passo extra para o segundo. Endereço = `0xffffffffdc350000` + offset do arquivo no `kmem_dump_1252.bin`.
2. **Ler o demux** `bpcie_handle_edge_irq()` (`ps4-bpcie.c:88`): confirmar se o ACK/`irq_find_mapping(initial_hwirq + 1)` cobre a sub-função 1 (`DMAC2`), e se o `BPCIE_ACK_READ` reflete o DMAC2.
3. **Confirmar o mapeamento** BAR0↔DMAC1 / BAR2↔DMAC2 (hipótese pelo `baikal.h`).
4. Se for preciso, instrumentar o demux (leitura do `ACK_READ` durante uma transferência do BAR2) — **só depois** dos passos estáticos, por tocar a glue.

**Enquanto isso:** o canal do DMAC2 conclui por polling (`hrtimer`). Quando resolvido, trocar para IRQ.

**Achado lateral (causa NÃO resolvida):** no primeiro `rmmod` após o boot aparece um `WARNING` em `msi_device_data_release` (`kernel/irq/msi.c:294`, `WARN_ON_ONCE(!xa_empty(...))`). **Persiste mesmo com `pci_free_irq_vectors()`** no `remove` do driver `baikal-dmac`. *(Correção: uma versão anterior deste item dizia que `pci_free_irq_vectors()` "resolvia". Estava errada: o `WARN_ON_ONCE` só imprime uma vez por boot, e os testes seguintes do harness rodaram no mesmo boot, então a ausência do aviso lá não provava nada.)* Lado PCI limpo: MSI volta a `Enable-`, a IRQ é liberada e reutilizada nos 3 ciclos de recarga, sem vazamento de vetores. Hipótese (não verificada): entradas deixadas pelo domínio MSI customizado do `bpcie` (`ps4-bpcie.c`). Sem impacto funcional observado. Investigar o domínio do `bpcie`.

#### [ ] Módulos do rootfs ficam inválidos quando o kernel é rebuildado (BTF)

Depois do deploy da tag `20261113-dmaengine`, o `rtc-ps4-icc.ko` que está em `/lib/modules/…` no rootfs **não carregou** (`failed to validate module [rtc_ps4_icc] BTF: -22`) e o PS4 ficou **sem `/dev/rtc0`**. O módulo era de um build anterior; o BTF dele não valida contra o do kernel novo. O `baikal_memory.ko` do rootfs carregou normalmente. Mesmo problema que o projeto contorna no `mts.ko` removendo o BTF.
- **Contorno aplicado (só ao vivo, não persiste):** módulo recompilado fora da árvore, sem BTF (`objcopy --remove-section=.BTF --remove-section=.BTF.base`), carregado com `insmod`; o RTC voltou (`registered as rtc0`, relógio acertado).
- **Pendente:** persistir no rootfs, atualizando os módulos de `/lib/modules/$(uname -r)/` a cada kernel novo (e/ou removendo o BTF no passo do `01-build-image-7.0.sh`). Alterar o rootfs e o script de build exige decisão do usuário.

---

### [x] 💾 Baikal Memory (00:14.6) — Fases 1–5 **VALIDADAS AO VIVO** (2026-11-15); Fase 6 pendente

✅ **TESTADO AO VIVO EM 2026-11-15** (tag `20261113-full-rebuild`, módulo v0.2):
- Módulo carrega (`baikal_memory` v0.2, vermagic OK)
- BARs mapeados: BAR0 (4 KiB), BAR2 (1 GiB endereçado, 256 MB real), BAR4 (1 MiB), BAR5 (256 KiB)
- `/dev/baikal-memory` expõe BAR0 @ 0x0, BAR2 (4 MiB) @ 0x1000, BAR5 @ 0x500000
- **MAC real lido em offset 0x52f000**: `2c:cc:44:3f:69:5f` ✅
- **Região ICC (spm.icc) em offset 0x52c000**: dados válidos ✅
- Escrita controlada (`allow_write=0`) ativa por padrão

⚠️ **Sysfs offsets:** os atributos `bar5_0x2c000` e `bar5_0x2f000` **não expõem os dados** — o mapeamento do device file (`/dev/baikal-memory`) usa offsets diferentes do esperado (MAC em 0x52f000 vs 0x2f000). O driver funciona via `/dev/baikal-memory` mas sysfs precisa ajuste.

**Status das Fases:**
- Fase 1–5: ✅ Implementadas e testadas ao vivo
- Fase 6 (estresse 30+ min + catalogação SQLite): ⏳ Pendente
- S5 power-off via ICC: ⏳ Pendente (item separado)

**Próximos passos:**
1. Ajustar offsets do sysfs no driver (alinhar com device file)
2. Fase 6: teste de estresse contínuo + catalogação no `ps4_hardware_memory.db`
3. S5: investigar `icc_power_shutdown` via região `spm.icc` (BAR5+0x2c000)

**Documentos:** `outros/rea/spm/HANDOFF.md`, `outros/rea/spm/decompiled/`, `outros/rea/spm/docs/`, `outros/rea/spm/plans/`, `outros/docs/ACHADOS_MEMORIA_BAIKAL_FASE1.md`, `outros/docs/ACHADOS_MEMORIA_BAIKAL_FASE2.md`, `outros/docs/PLANO_DRIVER_MEMORIA_BAIKAL.md`

---

### [x] 🔊 Áudio HDMI (00:01.1) — **FUNCIONAL** (validado 2026-11-15)

✅ **TESTADO AO VIVO EM 2026-11-15:**
- `snd_hda_intel` carregado, dispositivos: `controlC0`, `hwC0D0`, `pcmC0D3p` (HDMI 0), `pcmC0D7p` (HDMI 1)
- `aplay -D plughw:0,3` (HDMI 0) → **áudio sai pelo HDMI** ✅
- `aplay -D plughw:0,7` (HDMI 1) → **áudio sai pelo HDMI** ✅
- `speaker-test -t sine -D plughw:0,3` → tom 440Hz estéreo confirmado ✅
- Dispositivo default (`default`) tem problema de dmix, mas hardware específico funciona

**Nota:** `alsa-utils` instalado via `pacman -S alsa-utils` no teste. Deve ser adicionado ao `PKGS` do `01-build-image-7.0.sh` para builds futuros.

**Documentos:** `outros/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md` (seção Áudio)

---

### [ ] ⏱️ RTC — sem /dev/rtc (já tem item próprio no BACKLOG)

**Estado:** `CONFIG_RTC_CLASS=n` → sem `/dev/rtc`, sem `/sys/class/rtc`. Clock travado na build epoch (2026-06-26), bloqueia `pacman` por validação SSL. Driver `drivers/rtc/rtc-ps4-icc.c` existe mas nunca foi testado ao vivo (bug de leitura MMIO corrigido 2026-07-31, mas Fase 4 pendente de power-cycle físico).

**Tarefa:** ligar o PS4 fisicamente, `modprobe rtc-ps4-icc`, validar `/dev/rtc0`, `hwclock -r`, `date` estável entre boots, `pacman -Sy` sem erro SSL/clock.

**Item no BACKLOG:** linha ~591 (`### [ ] RTC via ICC no PS4 Linux — implementar driver rtc-ps4-icc`)

---

### [x] 💾 Swap — desabilitado

**Estado:** `SwapTotal=0`, `zram0` presente sem swap configurado, `zswap.enabled=1` mas sem swap zswap não faz nada. Risco de OOM em builds de kernel (pico de 10,9 GB de RSS no `pahole` já observado).

**Tarefa:** configurar zram-generator (zstd) no build: adicionar pacote `zram-generator` ao `PKGS` + `/etc/systemd/zram-generator.conf`, ou remover `zswap.enabled=1` do cmdline. **IMPLEMENTADO 2026-11-13 no build** (`distro/01-build-image-7.0.sh`):
- `zram-generator` no `PKGS` (linha ~237)
- `/etc/systemd/zram-generator.conf` com `zram-size = ram/2`, `compression-algorithm = zstd`, `swap-priority = 100`
- `zswap.enabled=1` removido do bootargs
**Validado ao vivo 2026-11-13:** zram0 3.4 GiB ativo como swap (zstd), zswap desabilitado (`N`).

---

## ✅ Concluídos em 2026-11-15 — Full build `20261113-full-rebuild` COM SUCESSO

### Build completo executado e validado:
| Etapa | Status | Detalhes |
|-------|--------|----------|
| **ETAPA 1 - Kernel** | ✅ | Kernel 7.0.8-Strawberry-ThinLTO-Baikal-+ compilado com todos os patches (AHCI polling, RTC ICC, Baikal Memory, DMA, WDT, HPET, MTS, etc.) |
| **ETAPA 2 - Distro** | ✅ | Rootfs Arch via Docker, initramfs, bootargs limpos, Mesa patchado, módulos copiados (sem rebuild BTF), initramfs gerado |
| **ETAPA 3 - Burn** | ⚠️ | Falhou: `/dev/sda` não encontrado (HD USB não plugado — esperado) |

### Testes ao vivo executados no PS4 (2026-11-15, tag `20261113-full-rebuild`):
| # | Teste | Resultado |
|---|-------|-----------|
| 1 | Boot + Vídeo HDMI | ✅ PASS |
| 2 | SSH WiFi (192.168.6.128) | ✅ PASS |
| 3 | SATA interno (Toshiba 1TB) | ✅ PASS — UDMA/100, zero `disable device` |
| 4 | RTC via ICC (timekeeping) | ✅ PASS — `/dev/rtc0`, system clock semeado, `pacman -Sy` OK |
| 5 | Áudio HDMI | ✅ PASS — `plughw:0,3` e `plughw:0,7` funcionam |
| 6 | Baikal Memory v0.2 | ⚠️ PARCIAL — device OK, sysfs offsets desalinhados |
| 7 | eth0 (mts.ko) | ⚠️ PARCIAL — MAC OK, NO-CARRIER (PHY firmware) |
| 8 | CIFS | ⚠️ PARCIAL — BTF mismatch no rootfs |
| 9 | pacman SSL/clock | ✅ PASS |
| 10 | S5 power-off | ⏭️ Não testado |

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

**Itens pendentes para próximos builds/testes:**
- [ ] BTF mismatch módulos no rootfs (CIFS, MTS, DMA, WDT, HPET, RTC)
- [ ] Baikal Memory sysfs offsets (alinhar device file ↔ sysfs)
- [ ] RTC UIE emulation (`hwclock -r` funcionar)
- [ ] S5 power-off (luz azul) — testar tag `20260730-s5-poweroff-fix`
- [ ] Mesa patchado (Gladius/Liverpool) + rebuild distro
- [ ] SSD Kingston trocar fisicamente (P0)

---

### Critério de aceite geral (hardware)

- Cada item `[ ]` acima só fecha quando o driver está carregado **e** o dispositivo é utilizável ao vivo no PS4 (não apenas "compila").
- Para itens sem solução via software (ex: GBE PHY), a tarefa fecha quando há documentação/fonte de dados que justifique o fechamento permanente ou quando uma nova abordagem viável é encontrada.
- Qualquer novo hardware descoberto deve ser adicionado aqui como `[ ]`, não em outros documentos do projeto.

