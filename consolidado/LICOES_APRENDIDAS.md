# Lições Aprendidas

## REGRA ABSOLUTA: Sem jamais interferir na rotina de boot/quiesce do FreeBSD (2026-07-22)

**É estritamente proibido alterar o fluxo nativo de shutdown/detach do FreeBSD ou injetar rotinas de IO/printf dentro da fase de quiesce do kexec (`cpu_quiesce_gate` em `linux_boot.c`).**

- **Motivo:** O subsistema NewBus do FreeBSD e a transição de registradores da ponte PCIe não toleram alterações em tempo de desligamento. Injetar `kern.printf()` com IRQs desativadas causa Deadlock/Spinlock Panic imediato. Injetar acessos de MMIO/ECAM desestabiliza o barramento.
- **Diretriz:** Toda e qualquer intervenção em hardware (desbloqueio de clocks, registradores de hold/pulse da BAR2, reset da Yukon) deve ser feita **EXCLUSIVAMENTE via Linux já bootado** (seja via userspace com Telnet e `/dev/mem`, seja através do driver do kernel `ps4-bpcie`). O kexec e o FreeBSD devem permanecer 100% originais e intocados durante a transição.

## "Não escrever" ≠ "seguro", e código de diagnóstico no caminho de boot é cego (2026-07-21)

No teste M7 (ver `ICC_GBE_TEST_LOG.md`), uma função nova no `sky2_probe` travou o console por completo. Foi criada uma "válvula de segurança" (`ps4_bpcie.gbe_release=0`) para desativar as escritas sem recompilar — e **o console travou exatamente igual com ela ligada**, porque a válvula só pulava as escritas: as **leituras** de registradores da BAR2 aconteciam antes de a flag ser testada.

**Duas lições distintas:**

1. **Leitura de MMIO não é operação inofensiva.** Este projeto já tinha dois precedentes registrados: `cat` no config space do `00:14.1` trava o console de forma reproduzível (teste A/B, 2026-07-16), e a varredura cega da região pervasive da BAR2 chegou a **desligar** o console. Ao desenhar um "modo somente leitura", tratar leitura como segura é uma suposição — não um fato.

2. **Diagnóstico no caminho de boot perde justamente a observabilidade que motivou o diagnóstico.** O plano original era ler os registradores de userspace via `/dev/mem`, com o sistema de pé e telnet ativo. A operação foi movida para dentro do `probe` "para o log sair automático no dmesg" — e, quando travou, não sobrou log nenhum, nem console, nem rede: só um power cycle e zero informação sobre qual dos seis registradores causou o problema.

**Regra prática:** operação de risco desconhecido em hardware roda **primeiro em userspace, com o sistema já bootado, um acesso por vez**, começando pelos endereços já comprovadamente seguros para validar o método. Só depois de mapeado o comportamento é que vale embutir no kernel. O ganho de conveniência de "sai automático no boot" não compensa perder a capacidade de observar a falha — ainda mais quando cada iteração custa um power cycle completo.

**Corolário útil:** quando um teste tem duas variantes (com e sem a ação de risco) e **ambas falham igual**, isso é informação valiosa — aqui provou que a causa não eram as escritas. Vale sempre desenhar o experimento para que o modo "desativado" seja de fato inerte.

## Build do kernel: OOM no link e o pico escondido do `pahole` (2026-07-21)

O build da tag `20260721-gbe-hold-release` morreu após 41 minutos com `Error 137` (= SIGKILL, OOM killer) no passo `LD vmlinux.o`. Duas causas distintas, ambas de memória:

**1. Link ThinLTO sem limite de threads.** O kbuild não passa `--thinlto-jobs`, então o `ld.lld` usa todos os núcleos (8 aqui) e cada thread segura estado do módulo. Solução aplicada:
```bash
make ... vmlinux-o-ld-args-y="--thinlto-jobs=2" bzImage
```
`vmlinux-o-ld-args-y` é a variável que `scripts/Makefile.vmlinux_o` injeta na linha do link. **Conferir antes que ela esteja vazia** (só é alimentada por `CONFIG_BUILTIN_MODULE_RANGES`, desligado neste config) — se estivesse em uso, passá-la na linha de comando sobrescreveria o valor original em vez de somar.

**2. `pahole` (geração de BTF) é o verdadeiro vilão de memória: 10,9 GB de RSS.** Roda *depois* do link, sobre o `vmlinux` pronto. Sobreviveu só porque havia swap livre.

**Não precisamos de BTF neste projeto.** `CONFIG_DEBUG_INFO_BTF` serve a BPF CO-RE (bpftrace/BCC/libbpf); o debug aqui é `dmesg`/telnet/MMIO. Desabilitá-lo remove o pico de ~11 GB e o passo inteiro, **sem desabilitar BPF** (`CONFIG_BPF_SYSCALL` continua) — e o projeto já roda cgroup v1 (`systemd.unified_cgroup_hierarchy=0`), então nem os usos de BPF do systemd pesam. Candidato a `scripts/config --disable CONFIG_DEBUG_INFO_BTF` no `00-build-kernel-7.0.sh`.

**Armadilha de diagnóstico:** o build foi lançado com `| tail -45`, então o exit code observado foi o do `tail` (0) e a notificação reportou **sucesso** para um build que falhou. **Nunca julgar resultado de build pelo exit code de um pipeline** — conferir a última linha do log (`Kernel: arch/x86/boot/bzImage is ready`) ou usar `set -o pipefail`.

**Verificação que vale sempre fazer depois de compilar:** confirmar que o código novo realmente entrou no binário, em vez de assumir:
```bash
strings vmlinux | grep "Baikal GBE glue"
```

## REGRA: no HD (sda1) fica APENAS o bzImage ativo (2026-07-21)

A partição BOOT tem ~197 MB e cada kernel pesa ~16 MB. Acumular histórico ali lotou a partição (chegou a 454 KB livres), e partição cheia faz `cp` truncar **em silêncio** — foi assim que um "backup" de 15,8 MB virou um arquivo de 462 KB sem nenhum erro visível.

**Não há motivo para manter histórico no HD:** `boot_referencia/` é a fonte de verdade e guarda todas as tags (`bzImage-7.0-<tag>`, `config-7.0-<tag>`, `bootargs-7.0-<tag>.txt`, `initramfs-7.0-<tag>.cpio.gz`). Antes de aplicar a regra, foi verificado por MD5 que **todos** os `bzImage-*` do HD tinham cópia idêntica no repositório.

**Automatizado no `deploy-boot-7.0.sh`:**
- remove todos os `bzImage-7.0-*` do HD a cada deploy (o deploy virou idempotente: rodar duas vezes deixa o mesmo estado);
- **não copia mais** o kernel anterior para o HD — ele já está em `boot_referencia/` sob o nome da tag;
- ainda guarda o `bootargs` anterior no HD (~400 bytes, custo irrelevante e útil como histórico local).

Resultado da primeira limpeza: **454 KB → 173 MB livres** (13% de uso).

**Achado colateral:** os 601 arquivos `PS4_DMESG_*.txt` (54 MB) que estavam no HD **não existiam em lugar nenhum do projeto**. Foram arquivados em `consolidado/dmesg_ps4/PS4_DMESG_ate_20260721.tar.gz` (13 MB, integridade conferida) antes de serem removidos do HD.

**Inconsistência pré-existente detectada (não corrigida, só registrada):** em `boot_referencia/`, `bzImage-7.0-20260720-gbe-bpcie-init` e `bzImage-7.0-20260720-sky2len-fix` são **byte a byte idênticos**. Ou seja, o kernel do teste M4 — o que causou tela preta — **não está preservado**; aquele nome guarda o kernel do `sky2len-fix`. Se algum dia for preciso reexaminar o binário do M4, ele não existe mais.

## INCIDENTE: "testar" um script de deploy destruiu o boot do HD (2026-07-21)

**O que aconteceu:** para validar mensagens de erro do `deploy-boot-7.0.sh`, foram criados arquivos de tag falsos com `touch` (0 byte) e o script foi executado **sem passar destino explícito**. O HD estava conectado e montado, o script auto-detectou a partição BOOT real e sobrescreveu `bzImage`, `bootargs.txt` e `initramfs.cpio.gz` com os arquivos vazios — deixando o HD não-bootável.

**Agravante:** a partição estava com apenas ~25 MB livres, então o backup automático do `bzImage` anterior **truncou silenciosamente** (462 KB gravados de 15.8 MB) por falta de espaço, sem erro visível, porque o `cp` estava sob `|| true`.

**Recuperação:** possível apenas porque `boot_referencia/` tinha os artefatos íntegros. Restaurados `bzImage` e `initramfs.cpio.gz` a partir da tag `20260720-sky2len-fix`, MD5 conferidos, `active-tag.txt` corrigido.

**Regras que ficam:**
1. **Nunca rodar `deploy-boot-7.0.sh` "só para ver a mensagem".** Se precisar testar o script, passe SEMPRE um diretório de destino explícito e descartável: `./deploy-boot-7.0.sh <TAG> /tmp/algum_dir_falso`. Sem o 2º argumento ele auto-detecta a partição BOOT **real**.
2. **Verifique se o HD está montado antes de qualquer comando que possa escrever nele** (`mount | grep sda`), mesmo achando que está desconectado.
3. Ferramenta de deploy é ferramenta destrutiva: não existe execução "de mentira".

**Correções aplicadas no script para que isso não se repita:**
- **Sanidade da origem:** rejeita `bzImage` < 4 MB, `initramfs` < 1 MB, `bootargs` < 32 bytes. Um artefato vazio agora aborta o deploy antes de tocar no destino (testado).
- **Checagem de espaço livre** antes de copiar, já contabilizando o backup do kernel anterior; lista os `bzImage-*` antigos a apagar se faltar espaço.
- **Backup do anterior falha alto:** removido o `|| true`; além disso o tamanho origem/destino é comparado e o backup truncado é apagado com erro, em vez de ficar como um "backup" inútil.

## Fallback silencioso em ferramenta de debug é armadilha (2026-07-21)

`deploy-boot-7.0.sh` tinha um fallback: se `initramfs-7.0-<TAG>.cpio.gz` não existisse, ele usava o genérico `initramfs-7.0.cpio.gz` **sem avisar**. Descobrimos que os dois divergem — o genérico tem 14MB (16/jul) e o realmente em uso tem 9.4MB (tag `20260720-sky2len-fix`). Um deploy que caísse nesse fallback trocaria **duas** variáveis de uma vez (kernel *e* initramfs), e o teste seguinte — que custa um power cycle completo — produziria uma conclusão errada sem nenhum sinal de que algo mudou.

**Corrigido:** o fallback foi removido. O script agora **falha alto** quando falta o initramfs da tag, explica o porquê e lista os disponíveis com o comando pronto para copiar de outra tag.

**Regra geral:** em ferramental de debug, prefira **falhar ruidosamente a adivinhar**. Um default conveniente economiza segundos e pode custar uma sessão inteira de investigação — especialmente aqui, onde cada iteração exige tirar o console da tomada.

**Também adicionado no mesmo script:** conferência automática de MD5 origem→destino dos três arquivos (`bzImage`, `bootargs.txt`, `initramfs.cpio.gz`) ao fim do deploy, abortando se algum divergir. A documentação já mandava validar por MD5 antes de cada teste ao vivo; agora isso é automático em vez de manual.
 — Arch Base v2

## Erros Cometidos e Por Que Não Repetir

### 16. Rede + SSH pré-configurados no rootfs para debug remoto

**Setup**:
- **WiFi**: wpa_supplicant@wlan0, credenciais em `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`
- **Rede cabeada**: eth0 com IP estático em `/etc/systemd/network/20-wired.network`
- **IP**: 192.168.6.150/24, gateway 192.168.6.1, DNS 192.168.6.1 + 8.8.8.8
- **SSH**: sshd habilitado, PermitRootLogin yes, PasswordAuthentication yes
- **Senhas**: root/ps4, ps4/ps4

**Comandos para conectar**:
```bash
ssh root@192.168.6.150    # senha: ps4
ssh ps4@192.168.6.150     # senha: ps4
```

**Como aplicar**: Montar rootfs, fazer chroot com pacman -S wpa_supplicant iw dhcpcd openssh, configurar arquivos, systemctl enable.

---

### 0. Kernel DFAUS vs Neocine — DFAUS prioritario para testes de monitor

**Decisao**: Vamos insistir no kernel **DFAUS 5.4.247-DFAUS-blkscrn_Fix_mt7668_hdmia** para todos os testes de monitor. O Neocine fica de lado por enquanto.

**Razoes**:
- O DFAUS tem fixes especificos de HDMI (`hdmia`) e WiFi MT7668 (`mt7668`) no nome da build
- O Neocine (5.4.247-neocine-1.1) causou `failed to set mode on CRTC` com 720p@60e e **desligou o PS4** com 1080p@60e
- O DFAUS bootou completamente com 720p@60e e 1080p@60 (sem desligar)
- O DFAUS funcionou perfeitamente na TV com `video=HDMI-A-1:1920x1080@60` (sem `e`)

**Resultados de video com DFAUS neste monitor LG**:
- `1920x1080@60` (sem `e`) → DP link training FAILED (`amdgpu_atombios_dp_link_train: clock recovery failed`)
- `1920x1080@60e` (com `e`) → **TESTAR** (proximo teste)
- `1280x720@60e` (com `e`) → `drm_bridge_chain_mode_set: attempted to set non-CEA mode` (sem `e`) ou `failed to set mode on CRTC` (com `e` no Neocine)

**Logs de referencia**:
- `/var/log/boot_debug/dmesg_drm.log` mostra os erros do bridge e link training

---

### 1. bootargs.txt — `video=@60e` causa tela preta
**Erro:** Usar `video=HDMI-A-1:1920x1080@60e` (com sufixo `e`).
**Causa:** O sufixo `e` força o estado "sempre ativo" no handshake HDMI. Em TVs reais, isso quebra o handshake e a tela fica preta.
**Correção:** Usar `video=HDMI-A-1:1920x1080@60` (SEM o `e`).

### 2. bootargs.txt — `console=uart8250` some com a saída HDMI
**Erro:** Incluir `console=uart8250,mmio32,0xC890E000`.
**Causa:** Esse parâmetro redireciona o console do kernel para a porta serial UART do PS4 (debug). Sem um cabo serial ligado, todas as mensagens de boot vão para o nada — o usuário não vê nada na tela.
**Correção:** Remover. Só usar `console=ttyS0,115200n8 console=tty0`.

### 3. bootargs.txt — `drm.edid_firmware` sem o firmware
**Erro:** Incluir `drm.edid_firmware=edid/1920x1080.bin`.
**Causa:** O initramfs padrão (`distros/initramfs.cpio.gz`) não contém esse arquivo EDID. O kernel tenta carregar e falha silenciosamente, potencialmente travando a inicialização do vídeo.
**Correção:** Remover. Só usar se o firmware EDID estiver explicitamente presente no initramfs.

### 4. bootargs.txt — Faltando `systemd.unified_cgroup_hierarchy=0`
**Erro:** Não incluir `systemd.unified_cgroup_hierarchy=0` e `systemd.legacy_systemd_cgroup_controller=yes`.
**Causa:** O kernel 5.4 (Neocine) usa cgroup v1. Systemd >= 250 tenta usar cgroup v2 por padrão. Sem forçar cgroup v1, o systemd trava com "Failed to mount early API filesystems".
**Correção:** SEMPRE adicionar `systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes` ao bootargs quando usar kernel 5.x com systemd moderno.

### 5. bootargs.txt — Faltando parâmetros de estabilidade
**Erro:** Não incluir `quiet amdgpu.audio=1 usbcore.autosuspend=-1 amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1`.
**Causa:** Esses parâmetros previnem problemas comuns no PS4: áudio HDMI mudo, teclado/mouse com lag, GPU travada sem recuperação, performance penalizada por mitigações de CPU, swap lento.
**Correção:** Copiar os bootargs EXATOS do `boot_referencia/` que foram validados na TV.

### 6. systemd versão >= 260 trava com kernel 5.4
**Erro:** Instalar a versão mais recente do systemd via pacman.
**Causa:** Systemd >= 260 exige funcionalidades do kernel que não existem no 5.4. O erro exato é "Failed to mount early API filesystems" e o boot morre antes do login.
**Correção:** SEMPRE fazer downgrade do systemd para `258.1-1` após instalar pacotes. Os pacotes estão disponíveis no Arch Linux Archive:
```
https://archive.archlinux.org/packages/s/systemd/systemd-libs-258.1-1-x86_64.pkg.tar.zst
https://archive.archlinux.org/packages/s/systemd/systemd-258.1-1-x86_64.pkg.tar.zst
https://archive.archlinux.org/packages/s/systemd/systemd-sysvcompat-258.1-1-x86_64.pkg.tar.zst
```
Usar `pacman -U --nodeps` para forçar o downgrade.

### 7. Label da partição root DEVE ser `psxitarch`
**Erro:** Formatar a partição root com label diferente (ex: `arch_base_v2`).
**Causa:** O initramfs (`distros/initramfs.cpio.gz`) tem hardcoded `mount LABEL=psxitarch /newroot` no script `init`. Se o label não for `psxitarch`, o mount falha, a variável `root` fica vazia e o sistema cai no rescue shell com a mensagem "The 'root' variable is empty, set to false or zero but shouldn't be".
**Correção:** SEMPRE formatar com `mkfs.ext4 -L psxitarch`. Não importa o nome da distro, o label do initramfs é fixo.

### 8. O initramfs.cpio.gz é fixo (não regenerável no chroot)
**Erro:** Tentar rodar `mkinitcpio` dentro do chroot para gerar um initramfs novo.
**Causa:** O kernel Neocine 5.4.247 não tem módulos de kernel no projeto (`/lib/modules` vazio). O mkinitcpio falha porque não encontra os módulos. Além disso, o initramfs que funciona tem customizações específicas para PS4 (hardcoded `LABEL=psxitarch`, firmware AMDGPU, etc.).
**Correção:** Sempre usar o initramfs de fallback (`distros/initramfs.cpio.gz`). Não tentar regenerar.

### 9. Permissões quebradas ao extrair em NTFS
**Erro:** Extrair o tar diretamente em partição NTFS.
**Causa:** NTFS não suporta permissões Unix (755, 600, setuid, etc.). Todos os arquivos perdem metadados.
**Correção:** Sempre extrair em ext4 (nativo Linux). Se precisar manipular o rootfs antes de gravar, fazer em `/mnt/hdauxiliar/temp` (ext4, 119G livre), nunca em `/tmp` (tmpfs 7.7G cheio) nem em NTFS.

### 10. mount --bind antes de arch-chroot
**Erro:** Entrar no chroot sem `mount --bind`.
**Causa:** O `arch-chroot` verifica se o diretório alvo é um mountpoint. Se não for, o pacman falha com "não há espaço livre suficiente em disco" mesmo havendo espaço sobrando. Isso acontece porque o pacman calcula espaço livre baseado no filesystem do mountpoint.
**Correção:** Sempre fazer `mount --bind "$WORKDIR" "$WORKDIR"` antes de `arch-chroot`.

### 11. DisableSandbox no pacman.conf (PS4 kernels)
**Erro:** Esquecer de ativar `DisableSandbox` no `/etc/pacman.conf`.
**Causa:** Kernels PS4 não têm suporte completo a namespaces/sandboxing. O pacman falha ao executar hooks pós-transação.
**Correção:** Sempre adicionar `DisableSandbox` no `[options]` do pacman.conf.

### 12. IgnorePkg para kernel/drivers
**Erro:** Não proteger o kernel e drivers de vídeo contra atualizações.
**Causa:** Um `pacman -Syu` inadvertido pode atualizar o kernel, mesa, vulkan-radeon para versões incompatíveis com o hardware PS4, quebrando o sistema.
**Correção:** SEMPRE adicionar ao `IgnorePkg`:
```
IgnorePkg = linux linux-headers mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon systemd systemd-libs systemd-sysvcompat
```

### 13. Downgrade do systemd NÃO pode usar `--dbonly` + `--nodeps`
**Erro:** Rodar `pacman -U --dbonly` primeiro e depois `pacman -U --nodeps` para fazer downgrade do systemd.
**Causa:** O `--dbonly` atualiza o banco de dados pacman para marcar a versão 258 como instalada, MAS NÃO remove os arquivos da versão 261. Quando o `--nodeps` roda depois, o pacman acha que não há nada a substituir (pois o DB já diz 258). Resultado: symlinks críticos ficam apontando para arquivos .so da versão antiga (ex: `libsystemd.so.0 → .so.0.44.0` em vez de `.so.0.41.0`), e arquivos .pacnew são gerados. O systemd não consegue carregar as bibliotecas corretas e o boot falha.
**Correção:** Usar APENAS `pacman -U --noconfirm --nodeps` (sem `--dbonly`). Isso força a substituição direta dos arquivos, corrigindo symlinks e removendo arquivos da versão antiga. Depois, remover `.pacnew`: `rm -f /etc/systemd/*.pacnew`.

### 15. Sistema de logging offline para debug sem vídeo

**Contexto**: Quando o monitor fica preto e não há SSH (rede não sobe), não temos como saber o que ocorreu no boot. Solução: gravar logs diretamente no disco durante o boot.

**Setup no rootfs**:
1. **systemd service** (`boot-debug.service`): Roda no `multi-user.target`, captura dmesg, journalctl, mounts, rede, blkid, cmdline.
2. **Script manual** (`/root/log_boot_early.sh`): Fallback se systemd falhar.
3. **`.bashrc` do root**: Coleta automática de logs no primeiro login interativo (SSH ou console).

**Arquivos gerados em `/var/log/boot_debug/`**:
- `boot_summary.log` — resumo (uname, mounts, rede, systemd failed units, cmdline, blkid)
- `dmesg_full.log` — dmesg completo
- `dmesg_drm.log` — grep por drm, hdmi, bridge, hpd, amdgpu, connector, edid, video, mode, display, fb, console
- `dmesg_net.log` — grep por eth, wlan, net, wifi, mt76, ip, dhcp, link
- `dmesg_errors.log` — grep por error, fail, warn, bug, panic, oops, trace
- `journal_last.log` — journalctl -n 200
- `journal_errors.log` — journalctl -p 3 -n 100
- `dmesg_auto.log`, `cmdline_auto.txt`, `blkid_auto.txt`, `mounts_auto.txt`, `ip_auto.txt` — coletados via .bashrc no primeiro login

**Como usar após o teste**: Plugar HD de volta no PC, montar sda2, ler `/mnt/root/var/log/boot_debug/`.

---

### 14. Symlinks do systemd devem apontar para a versão correta
**Erro:** Após downgrade, symlinks como `libsystemd.so.0` e `libudev.so.1` apontam para arquivos da versão antiga (261) em vez da nova (258).
**Causa:** Consequência do erro #13 (--dbonly + --nodeps).
**Correção:** Verificar após downgrade:
```bash
ls -la /usr/lib/libsystemd.so.0      # Deve apontar para .so.0.41.0
ls -la /usr/lib/libudev.so.1         # Deve apontar para .so.1.7.11
ls /usr/lib/systemd/libsystemd-core-261*  # NÃO deve existir
ls /usr/lib/systemd/libsystemd-shared-261* # NÃO deve existir
ls /usr/lib/libsystemd.so.0.44*      # NÃO deve existir
ls /usr/lib/libudev.so.1.7.14*       # NÃO deve existir
```

### 17. Acesso Local Bloqueado por VPN no Host (Erro: Host de destino inalcançável)
**Erro:** O ping ou SSH do PC Host para o PS4 falha com `Destination Host Unreachable` ou a tabela ARP do host diz `FAILED` para o IP do PS4, mesmo com o Wi-Fi do PS4 conectado e obtendo IP.
**Causa:** Se o PC Host estiver com uma conexão VPN ativa (ex: interface `tun0`), a VPN pode bloquear a descoberta ARP local ou redirecionar o tráfego do PC Host, impedindo que ele encontre o PS4 diretamente.
**Correção:** Adicionar manualmente o endereço MAC do PS4 à tabela ARP do PC Host (desvio de ARP local) associando-o à interface de rede física (ex: `wlp0s20f3`):
```bash
sudo ip neigh replace <IP-DO-PS4> lladdr <MAC-DO-PS4> dev <INTERFACE-WIFI-DO-HOST>
# Exemplo real:
sudo ip neigh replace 192.168.6.127 lladdr 00:0c:43:26:60:48 dev wlp0s20f3
```

---

### 18. UART console (`console=uart8250...`) CONFLITA COM VÍDEO HDMI

**Erro:** Adicionar `console=uart8250,mmio32,0xC890E000` ao `bootargs.txt` junto com `video=HDMI-A-1:1920x1080@60`.

**Sintoma:** PS4 para de dar vídeo na TV/Monitor (tela preta), mas SSH/netconsole podem continuar funcionando.

**Causa:** O kernel PS4 (amdgpu + ps4_bridge) não consegue inicializar ambos os consoles simultaneamente. O driver de vídeo Baikal (ps4_bridge + DCE v8.0) parece travar ou redirecionar a saída quando o console UART é registrado como ativo.

**Teste:** Remover o parâmetro UART → vídeo volta ao normal.

**Correção:** 
- **NÃO USAR** `console=uart8250,mmio32,0xC890E000` junto com saída de vídeo.
- UART só deve ser usado **isolado** (sem `video=` no cmdline) para debug headless.
- Para debug com vídeo, usar `netconsole` (já configurado) ou cabo serial só APÓS boot confirmado funcional.

**Parâmetros atuais FUNCIONAIS (sem UART):**
```
console=ttyS0,115200n8 console=tty0
video=HDMI-A-1:1920x1080@60
drm.edid_firmware=edid/ps4_tv_edid.bin
netconsole=6665@192.168.0.2/eth0,6666@192.168.0.1/...
```

### 19. mkinitcpio ausente na lista de pacotes do rootfs 7.0
**Erro:** O script `01-build-image-7.0.sh` tentava rodar `mkinitcpio` no chroot para gerar o initramfs, mas o pacote não estava na lista de instalação (`PKGS`).
**Correção:** Adicionar `mkinitcpio` explicitamente em `PKGS`. Suas dependências (como `mkinitcpio-busybox`, `kmod`, etc.) são resolvidas e instaladas automaticamente pelo pacman.

### 20. Checagens com grep/find falhando sob `set -e`
**Erro:** Ao rodar `01-build-image-7.0.sh` com `set -e` ativo, comandos de substituição como `cfg_val=$(grep "^${cfg}=" "$KERNEL_CONFIG")` abortavam o script caso a flag não estivesse definida no `.config` (grep retorna 1).
**Correção:** Proteger as checagens de informações/avisos com `|| true` para reportar que uma flag ou módulo está `FALTANDO` sem derrubar o script de build.

### 21. Limite de tamanho de partição de boot de 50MB
**Erro:** O tamanho tradicional da partição de boot (`sda1`) de 50MB é insuficiente para o Kernel 7.0 (onde bzImage + initramfs somam ~56.5MB devido ao driver amdgpu na initramfs), resultando em erro de falta de espaço em disco ao rodar o script de gravação.
**Correção:** O script `02-burn-image.sh` foi atualizado para automatizar a criação da tabela de partição do disco `/dev/sda` via `fdisk`, definindo a partição de boot (`sda1`) com um tamanho de **200 MB** (`+200M`).

### 22. Reset de controladores USB do PS4 após pânico de boot
**Sintoma:** Após um Kernel Panic que desliga o console, as tentativas subsequentes travam na tela do Payload Guest com o HD `/dev/sda` sem atividade e luz azul piscando/acesa no PS4.
**Causa:** O Southbridge/controlador USB entra em estado de travamento após o desligamento repentino e não é reiniciado ligando o PS4 normalmente.
**Correção:** Realizar um ciclo de desligamento completo (tirar o cabo de força do PS4 da tomada por 15 a 30 segundos) para descarregar a energia e reiniciar o barramento USB física e logicamente.

### 23. Limite de tamanho do bzImage nos payloads de kexec do PS4
**Causa:** Muitos loaders de Linux (kexec) no PS4 têm limites rígidos de buffer para o arquivo `bzImage` (normalmente de ~10 MB). Kernels maiores causam estouro de memória, resultando em desligamento imediato ou congelamento do console.
**Correção:** Compilar o kernel com compressão mais eficiente (como `XZ` em vez de `ZSTD`) e evitar embutir firmwares desnecessários (como drivers de GPU) diretamente no binário do kernel para mantê-lo abaixo de 9.5 MB.

### 24. Erro de Permissão ao Compilar Kernel (NTFS/fuseblk)
**Erro:** O processo de compilação (`build.sh` ou `make`) falha repentinamente com mensagens de `Operação não permitida` (Operation not permitted) ao tentar dar chown/chmod ou instalar módulos e headers.
**Causa:** O código fonte do kernel estava em uma partição montada via FUSE (NTFS ou exFAT, como `/mnt/t`). O processo de compilação exige manipulação estrita de permissões Linux que esses sistemas de arquivos não suportam nativamente sem configurações de montagem muito específicas.
**Correção:** Sempre compilar o Kernel dentro de uma partição nativa do Linux (ext4, btrfs), como `/mnt/hdauxiliar/temp/`. O script automatizado já foi ajustado para clonar e compilar obrigatoriamente neste diretório seguro.

### 25. `printf '\xHH'` não é confiável pra escrever bytes em `/dev/mem` via telnet encadeado
**Erro (2026-07-20):** Tentativa de escrever 4 bytes específicos em um registrador MMIO via `printf '\xd9\x16\x00\x00' | dd of=/dev/mem bs=4 seek=N conv=notrunc`, executado através de uma cadeia bash local → `ncat --telnet` → TCP → shell remoto (`busybox ash`) no PS4.
**Causa:** `busybox printf` não interpreta `\xHH` (hex) de forma confiável quando o comando atravessa múltiplas camadas de quoting/encaminhamento dessa cadeia — o `dd` reportou 12 bytes copiados (3 blocos de 4) em vez dos 4 esperados, e os bytes reais gravados não corresponderam ao valor pretendido. O registrador MMIO alvo ficou num estado não-intencional (mas não causou pane no console — registrador volátil, resolvido com power cycle).
**Correção:** Usar escapes **octais** (`\NNN`, sempre 3 dígitos) em vez de `\xHH`: `printf '\331\026\000\000' | dd ...` (onde `\331`=0xd9, `\026`=0x16). **Sempre conferir que o `dd` reportou exatamente "1+0 records in / 1+0 records out"** (ou o número de blocos esperado) antes de considerar a escrita bem-sucedida — qualquer contagem diferente é sinal de bytes corrompidos/escaping quebrado, não confiar no resultado. Detalhe completo: `consolidado/ICC_GBE_TEST_LOG.md` (teste M2).

### 26. Injeção direta de leituras MMIO não testadas em `linux_boot.c` causa Kernel Panic cego (2026-07-21)
**Erro:** Adicionar loops de leitura de 256 bytes da MMConfig do `00:14.1` (GBE) e regiões pervasivas da BAR2 no `linux_boot.c` durante o caminho de kexec.
**Causa:** Leituras não alinhadas (8-bit) ou leituras em dispositivos PCIe em estado de economia de energia/D3 causam *Target Abort / MCE (Machine Check Exception)* no processador Jaguar. Como o kexec roda com interrupções desativadas e sem manipuladores de exceção, o console trava em tela preta sem logs, forçando um power cycle manual.
**Correção:** NUNCA alterar o `linux_boot.c` com acessos experimentais a registradores de hardware. Operações de risco desconhecido devem ser executadas primeiramente via payload Orbis em userspace ou via `/dev/mem` no Linux bootado, um registrador por vez.

### 28. `cat .../config` do `00:14.1` via sysfs trava o PS4 mesmo do Linux rodando (2026-07-22)
**Erro:** Enviei o comando `cat /sys/bus/pci/devices/0000:00:14.1/config` via telnet para ler o PCI config space da GBE, e o console travou imediatamente (ping parou de responder).
**Causa:** O PCI config space do dispositivo `00:14.1` (GBE Baikal) é inacessível enquanto o chip está power-gated (ChipID=0x00). Tentar ler o config space de um dispositivo PCIe em estado de energia cortado causa Target Abort / MCE que desliga o console inteiro (power-off, não só freeze) — mesmo em userspace, com o kernel Linux já bootado.
**Aplicação Útil:** Esse comportamento pode ser usado como **mecanismo controlado de power-off** para o PS4 a partir do Linux. Se precisarmos desligar o PS4 de forma abrupta (ex: após um payload que travou o sistema, para economizar power cycle manual), ler o config space do `00:14.1` via sysfs é um "kill switch" por software. Útil para scripts de automação que precisam desligar e religar o console.
**Correção:** NUNCA ler o config space de `00:14.1` via `cat .../config` (sysfs) ou `lspci -xxx` enquanto o ChipID estiver `0x00`, A MENOS QUE o objetivo seja desligar o console intencionalmente. A única forma segura de ler registradores da GBE é via `/dev/mem` nos endereços MMIO conhecidos (BAR0=`0xc2000000`, BAR2 via glue em `0xc8800000+`).
**Precedente:** já documentado no teste M7 do `ICC_GBE_TEST_LOG.md` (2026-07-16): "cat no config space do 00:14.1 via sysfs trava o console de forma reproduzível". Também coberto superficialmente pela lição #26, mas esta lição específica existe porque o erro se repetiu — da próxima vez, verificar o arquivo de lições e o ICC_GBE_TEST_LOG.md ANTES de enviar qualquer comando de leitura de PCI config space.

### 27. SMAP Kernel Page Fault em Payloads Ring 0 no Orbis OS (FW 12.52) (2026-07-21)
**Erro:** Escrita direta de valores de registradores em ponteiros de Userland (`vr->chip_id = ...`) dentro de uma função invocada via `kexec` em Ring 0 (`orbis-hw-dumper`).
**Sintoma:** O payload congela o PS4 na notificação exata em que o `kexec` é chamado (`hw-dumper: [2] kexec verificar chip_id`).
**Causa:** No FW 12.52 (PS4 Pro / Jaguar), a proteção **SMAP (Supervisor Mode Access Prevention)** está ativa no kernel Orbis. Ela impede que o código executando em Ring 0 acesse/escreva diretamente em memórias com sinalizador de espaço do usuário.
**Correção:** Usar obrigatoriamente a rotina de kernel `copyout` (`kernel_base + 0x2BD5C0`) para transferir dados de Ring 0 para buffers de Userland.

---

## Checklist de Verificação Pré-Boot

Antes de desconectar o HD e testar no PS4, verificar:

- [ ] `bootargs.txt` — igual ao `boot_referencia/bootargs.txt` (com `systemd.unified_cgroup_hierarchy=0`)
- [ ] `label` da partição root → `psxitarch` (conferir com `blkid /dev/sda2`)
- [ ] `systemd` no rootfs → versão `258.1-1` (conferir com `strings /mnt/root/usr/lib/systemd/systemd | grep '^[0-9]\+\.[0-9]' | head -1`)
- [ ] Symlinks corretos: `libsystemd.so.0 → .so.0.41.0`, `libudev.so.1 → .so.1.7.11`
- [ ] Sem arquivos .so do systemd 261: `libsystemd.so.0.44.0`, `libudev.so.1.7.14`, `libsystemd-core-261*`, `libsystemd-shared-261*`
- [ ] Sem `.pacnew` em `/etc/systemd/`
- [ ] `DisableSandbox` ativo em `/etc/pacman.conf`
- [ ] `IgnorePkg` configurado em `/etc/pacman.conf`
- [ ] Permissões corrigidas (shadow 600, ssh_host_* 600, binários 755, etc.)

