# Instruções para Agentes — PS4 Linux Baikal

> **Fonte única de regras e procedimentos deste projeto.** O `CLAUDE.md` na raiz é apenas um stub que importa este arquivo (`@AGENTS.md`), porque o Claude Code carrega `CLAUDE.md` automaticamente e não lê `AGENTS.md`. Edite SEMPRE aqui, nunca no stub.

## Regras de Conduta
1. **Atualização Contínua de Documentação:** A cada nova descoberta técnica, acerto ou falha em testes, os arquivos de documentação (como `CLAUDE.md` e artefatos de progresso) DEVEM ser atualizados IMEDIATAMENTE. Isso garante que não correremos o risco de repetir testes falhos ou testar hipóteses já descartadas.
2. **Sincronia:** Sempre garanta que o contexto da sessão (o que tentamos, o que falhou, o que causou Kernel Panic) esteja fielmente refletido na documentação antes de encerrar o turno ou mudar de estratégia.
3. **Kernel Linux 7.0 Baikal: a tag `v7.0-20260722-clean-video-ok` (e a baseline pré-compilada `20260720-sky2len-fix`) são as BASELINES OFICIAIS confirmadas (vídeo OK, boot completo, telnet OK)**. Artefatos em `distros/arch_minimal_v2/boot_referencia/*-7.0-20260722-clean-video-ok*` e `config-7.0-20260720-sky2len-fix` **NUNCA podem ser sobrescritos/descartados**.
   - **Descoberta do Gap de Rebuild (2026-07-22):** O patch `sky2-baikal-gbe.patch` forçava o driver `sky2` (built-in) a fazer probe na GBE Baikal (`104d:90d8`), que NÃO é Marvell Yukon. Isso congelava o barramento PCIe e o vídeo no boot.
   - **Solução Validada no PS4:** Removido o `sky2-baikal-gbe.patch` do script `00-build-kernel-7.0.sh` e garantidas as opções `CONFIG_MFD_SYSCON=y` e `CONFIG_REGMAP_MMIO=y`. Reconstrução limpa do zero testada e aprovada ao vivo com vídeo OK e telnet OK. O repositório do kernel em `/mnt/hdauxiliar/temp/kernel_build_7.0` foi commitado (commit `811184c1f`) e etiquetado com a git tag `v7.0-20260722-clean-video-ok`. Ver `memory/baseline-oficial-sky2len-fix.md`.
   - **MARCO HISTÓRICO GBE ETHERNET (2026-07-22):** Carregamento do driver `mts.ko stage=4` via Telnet registrou com SUCESSO ABSOLUTO a interface **`eth0`** com o endereço MAC real lido da SPM (`2c:cc:44:3f:69:5f`), anéis DMA programados (TX `0x010dd000`, RX `0x010de000`) e 0 erros ou travamentos!
   - **NETCONSOLE PRONTO PARA OS PRÓXIMOS BUILDS:** Configurado `bootargs` com `netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff` (IP PS4 `192.168.0.2` -> Host PC `192.168.0.1:6666/UDP`). Script de recepção ao vivo disponível em `scripts/netconsole_listener.py`.
   - **BUILD AUTOMÁTICO ETH0 + NETCONSOLE (2026-07-23):** Criada e implantada no HD a tag `20260723-mts-autoeth0`. O driver `mts.ko` agora possui o padrão `stage=4` e auto-carregamento no boot, subindo a interface `eth0` automaticamente sem necessidade de intervenção via Telnet. Netconsole ativado por padrão no boot.
   - **DESLIGAMENTO REMOTO VIA TELNET (2026-07-22):** O comando `sync && poweroff -f` (ou `echo o > /proc/sysrq-trigger`) encerra o sistema operacional e a rede limpos (ping cai 100%), porém o console permanece em **luz azul (luz azul acesa/pulsando)** pois o desligamento de energia total da fonte (S5) exige comando ICC dedicado ou desligamento manual no botão.
   - **🏆 NOVO BASELINE OFICIAL (2026-07-30), tag `20260730-sata-reverted` — MELHOR VERSÃO ATÉ AGORA, PONTO DE ROLLBACK:** kernel `7.0.8-Strawberry-ThinLTO-Baikal-+ #23` com o fix de polaridade MDIO Clause 22 (`mts.c`) ativo e as mudanças de SATA polling-timer da noite de 2026-07-29 revertidas (só instrumentação não validada). Boot completo confirmado ao vivo: `kexec` → shutdown normal da Orbis → `Run /init as init process` → `systemd[1]` sem erros, vídeo HDMI OK, **SSH via WiFi confirmado**, `eth0` sobe com MAC real (PHY ainda sem link, bug conhecido, não é regressão). Artefatos em `distros/arch_minimal_v2/boot_referencia/*-7.0-20260730-sata-reverted*` **NUNCA podem ser sobrescritos/descartados** — em caso de regressão futura, restaurar com `sudo ./deploy-boot-7.0.sh 20260730-sata-reverted` (boot-only, mantém rootfs). Ver `memory/baseline-oficial-20260730-sata-reverted.md` (checksums MD5 e detalhes completos).
   - **🏆🏆 NOVO BASELINE OFICIAL, MAIS RECENTE (2026-07-30), tag `20260730-sata-polling-fase-ab` — SUPERA O ANTERIOR, SATA INTERNO FUNCIONAL PELA PRIMEIRA VEZ:** mesmo kernel do baseline acima + Fase A/B do `docs/planos/PLANO_SATA_POLLING_CORRECAO_2026-07-29.md` (polling timer de 1ms) reaplicada e validada ao vivo. `ata1.00: configured for UDMA/100` sem nenhuma exceção, `dd`/`fdisk` confirmam leitura real do HD interno (931.51 GiB), zero `disable device` em todo o dmesg. **Este é o baseline mais completo/recomendado a partir de agora** — GBE (com PHY ainda mudo, bug conhecido) + SATA interno funcional juntos. Artefatos em `distros/arch_minimal_v2/boot_referencia/*-7.0-20260730-sata-polling-fase-ab*` **NUNCA podem ser sobrescritos/descartados**. Rollback: `sudo ./deploy-boot-7.0.sh 20260730-sata-polling-fase-ab` (boot-only). Ver `memory/marco-sata-interno-funcional-2026-07-30.md`.

---

## 🔴 REGRA CRÍTICA — Montagem de dispositivos

**NUNCA monte nada diretamente em `/mnt`.** Sempre crie um subdiretório dedicado (ex: `/mnt/ps4_rootfs_7.0`, `/mnt/temp_build`) e monte lá. Montar em `/mnt` raiz conflita com outros mounts do sistema, esconde diretórios existentes e quebra scripts que esperam estrutura previsível.

---

## 🔴 REGRA CRÍTICA — Build & deploy passam SEMPRE pelos scripts oficiais

**NUNCA rodar `make bzImage` direto. NUNCA usar `deploy-boot-7.0.sh` sem antes ter rodado `00-build-kernel-7.0.sh`.** Toda compilação e todo deploy do kernel 7.0 devem passar pela sequência oficial em `distros/arch_minimal_v2/`:

| Script | Função |
|--------|--------|
| `00-build-kernel-7.0.sh [TAG]` | Compila kernel (ThinLTO, profile General, Baikal). Gera `boot_referencia/bzImage-7.0-<TAG>` + `config-7.0-<TAG>`. Aplica `scripts/config` do projeto (zstd, zswap, RTC_CLASS, etc). Faz `make modules`. |
| `01-build-image-7.0.sh` | Cria rootfs Arch + initramfs. Gera `boot_referencia/initramfs-7.0-<TAG>.cpio.gz`. |
| `02-burn-image-7.0.sh /dev/sda` | Particiona + grava rootfs (label **`psxitarch`** obrigatório) + boot. Use quando refazer rootfs do zero. |
| `deploy-boot-7.0.sh <TAG> [MNT]` | Apenas reescreve boot no HD já particionado, mantém rootfs intacto. Mais leve. Exige tag completa: bzImage, config, bootargs.txt, initramfs (reaproveitável de outra tag via cp explícito). |
| `rebuild-initramfs-7.0.sh` | Reconstrói initramfs em rootfs já montado em `/mnt/ps4_rootfs_7.0` após mudar hooks. |

**Por que isso é regra:**

1. **Label `psxitarch` é hardcoded no initramfs.** O script `init` do busybox no initramfs faz `mount LABEL=psxitarch /newroot` literalmente — se a partição root não tiver exatamente esse label (e não `arch_base_v2`, `arch_minimal_v2`, etc), o mount falha e o boot cai no rescue shell com "The 'root' variable is empty". Só `02-burn-image-7.0.sh` garante `mkfs.ext4 -L psxitarch` na partição correta. Ver lição #7 do `consolidado/LICOES_APRENDIDAS.md`.

2. **A primeira lição (#7) já documenta exatamente esse incidente.** Ele aconteceu de novo em 2026-07-25 por eu ter rodado `make bzImage` direto e depois reaproveitado `initramfs-7.0-20260725-full-build.cpio.gz` (que estava OK, mas sem o `01-build-image` rodando não houve auditoria de integridade entre `bootargs.txt` / `initramfs` / novo kernel).

3. **Bootargs e initramfs são parte do artefato.** Não basta mexer no kernel. Toda tag em `boot_referencia/` precisa de 4 arquivos: `bzImage-7.0-<TAG>`, `config-7.0-<TAG>`, `bootargs-7.0-<TAG>.txt`, `initramfs-7.0-<TAG>.cpio.gz`. `deploy-boot-7.0.sh` falha alto se algum faltar — sem fallback silencioso (lição: "fallback silencioso em ferramenta de debug é armadilha").

4. **Limite de ~10 MB do bzImage em alguns loaders de kexec do PS4 (lição #23).** A build padrão do projeto mantém o kernel abaixo desse limite. Um `make` fora dos parâmetros pode inflar sem perceber — o `00-build-kernel` tem as opções certas já validadas.

### 🔴 REGRA CRÍTICA — Idempotência de Alterações no Kernel

**TODA alteração no kernel ou módulos DEVE ser idempotente e reproduzível através de patches. O script de build kernel naturalmente reseta `--hard`, e isso é normal/desejado.**

**Por quê:**
- Builds limpos garantem **reprodutibilidade**: clonar kernel + rodar script = resultado idêntico sem depender do working directory do dev
- `git reset --hard` é NECESSÁRIO para descartar mudanças não-commitadas e estado contaminado
- Mudanças **uncommitted são perdidas** no reset — não é bug, é design
- Alterações que dependem de "changes not staged" desaparecem silenciosamente e causam regressões sem aviso

**Regra na prática:**
- Alterações **podem ser commitadas** no repositório (git commit + push), OU
- Alterações **devem ser integradas via patches `.patch` confiáveis** aplicados **após** o `git reset --hard`.
- **PROIBIDO usar heredocs (`cat << 'EOF'`), `sed` ou `echo >>` inline no script de build** para injetar código ou modificar `Makefile`/`Kconfig` do kernel. Toda modificação deve estar encapsulada em um arquivo `.patch` limpo em `patches/`.
  - Motivo: injeções inline (heredocs/sed) alteram o contexto dos arquivos do kernel e fazem com que patches subsequentes falhem silenciosamente ao tentar aplicar no mesmo arquivo.
  - Exemplo: `patches/ps4-icc-rtc-wrapper.patch` contém 100% da implementação do RTC (`rtc-ps4-icc.c`, `Kconfig`, `Makefile` e wrappers) de forma autocontida.
  - Exemplo: `patches/ahci-baikal-polling-fallback.patch` (SATA polling) é aplicado via `git apply --check` + `exit 1` em caso de falha (falha alta é obrigatória).

**Implementação (procedimento obrigatório, nesta ordem — não pular etapas):**
1. Editar source em `/mnt/hdauxiliar/temp/kernel_build_7.0/`, a partir de uma árvore recém resetada (`git reset --hard origin/$BRANCH`) para garantir base limpa.
2. Compilar ISOLADAMENTE só o(s) arquivo(s) tocado(s) (`make CC="ccache clang" LLVM=1 ARCH=x86_64 <arquivo>.o`) — nunca considerar uma mudança "pronta" sem essa validação. Um patch escrito à mão sem essa etapa quase certamente tem bugs de contexto/compilação que só aparecem no build oficial completo, horas depois.
3. Gerar o patch **real** via `git diff HEAD -- <arquivos> > patches/<nome>.patch` — nunca escrever o `.patch` à mão.
4. Resetar a árvore de novo (`git reset --hard origin/$BRANCH`) e validar `git apply --check patches/<nome>.patch` a partir do estado pristino.
5. Adicionar/atualizar a lógica no `00-build-kernel-7.0.sh` para aplicar o patch após o reset, seguindo o padrão `git apply --check` + `exit 1` em caso de falha — **nunca** `|| echo AVISO` ou qualquer forma de engolir erro silenciosamente (isso já causou uma falha real: o patch RTC `ps4-icc-rtc-wrapper.patch` ficou meses aplicando silenciosamente errado).
6. Só commitar no git do projeto principal depois que os passos 2-4 passarem sem erro.

**Consequência da quebra desta regra:** Baseline fica não-reproduzível, próximo build sem a mudança reintroduzida sofre regressão silenciosa (exemplo: 2026-08-01, tag `20260801-kvm-rtc-ok` perdeu SATA polling — ver `memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md`).

### 🔴 REGRA CRÍTICA — Snapshot de Segurança Obrigatório Pós-Build

Todo build bem-sucedido executado por `00-build-kernel-7.0.sh` DEVE obrigatoriamente gerar um snapshot bruto da árvore fonte já patcheada em `/mnt/hdauxiliar/kernel_source_snapshots/kernel-src-<YYYYMMDD>-<TAG>.tar.zst` (via `tar -I 'zstd -T0 -9'`, excluindo artefatos `.o`/`.ko`/`vmlinux` mas **incluindo o `.git`** do clone raso, ~300MB). Isso garante redundância absoluta contra perda de alterações efêmeras no repositório do kernel. Falhas de snapshot geram alerta no terminal.

### 🔴 REGRA CRÍTICA — Gatilhos de linguagem que exigem commit real no git

Quando o usuário disser **"alteração aprovada"**, **"grave na memória e commite"**, ou **"registre e atualize os documentos"**, isso significa **COMMITAR NO GIT** — não apenas escrever/editar arquivos. Documentar em prosa sem nunca commitar já causou perda real de trabalho (o patch de SATA polling de 2026-07-30 foi descrito em detalhe em `memory/marco-sata-interno-funcional-2026-07-30.md`, mas o código-fonte em si nunca virou patch nem commit — foi apagado num `git reset --hard` de build posterior em 2026-08-01, exigindo reconstrução do zero). Git é a rede de segurança; memória em prosa não é.

### 🔴 REGRA CRÍTICA — Menos velocidade, mais responsabilidade em mudanças de kernel

Para mudanças de kernel/módulos (e por extensão, qualquer mudança técnica de risco/irreversibilidade não-trivial): priorizar responsabilidade sobre velocidade. Analisar patches com cuidado antes de aplicar, evitar ciclos de build/teste/desfazer repetidos sem plano claro, verificar cada mudança isoladamente (compilação isolada, `git apply --check`) antes de escalar para o build completo. **Não iniciar uma nova tentativa até entender completamente por que a anterior falhou.** Motivo: a sessão de 2026-08-01 teve múltiplos ciclos de tentativa-erro sem disciplina (patch escrito à mão com bugs reais de compilação, builds iniciados e cancelados repetidamente), o que gerou frustração e retrabalho evitável.

### Sequência típica de modificação de kernel

```bash
cd /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2

# 1. Editou source em /mnt/hdauxiliar/temp/kernel_build_7.0/ (com sudo)

# 2. Compila e gera tag (r(run~20-45 min):
sudo ./00-build-kernel-7.0.sh 20260725-sata-fix

# 3. Se mudou algo no rootfs/initramfs (hooks mkinitcpio, modules-load):
#    sudo ./01-build-image-7.0.sh
#    (se só mudou bzImage/bootargs, pode pular e usar initramfs de outra tag)

# 4. HD USB do PS4 plugado neste PC:
sudo ./deploy-boot-7.0.sh 20260725-sata-fix
# (grava só o boot, mantém rootfs psxitarch intacto, confere MD5 origem→destino)

# 5. Plugar HD de volta no PS4, ligar, SSH em 192.168.6.128, smoke test.

# 6. Depois que a tag passou no teste ao vivo, promover para RELEASE/:
../../scripts/promote-release.sh 20260725-sata-fix
```

**Rollback:** rodar `deploy-boot-7.0.sh <tag-anterior>` restaura em 1 power cycle — todo histórico fica em `boot_referencia/`.

### 📦 RELEASE/ — vitrine dos artefatos compilados (2026-08-05)

O pipeline oficial NÃO muda: `00/01/02/deploy` continuam gravando em
`distros/arch_minimal_v2/boot_referencia/`. `RELEASE/` é montado por
`scripts/promote-release.sh <TAG>` (copiar artefatos + symlink do tarball da
distro + `sha256sums.txt`) — demais tags são gitignored; apenas o `README.md`
e a **versão de distribuição `v1.0.0/`** (4 artefatos de boot + README, origem
`20260801-kvm-rtc-sata-final`) são versionados no git.

- **Kernel mainline:** NUNCA fica dentro do projeto (é NTFS). Só existe o symlink
  `kernels/ps4-baikal-7.0.8-kernel -> /mnt/hdauxiliar/temp/kernel_build_7.0`
  (ext4). `kernels/patches -> ../distros/arch_minimal_v2/patches` é symlink —
  fonte única dos patches, que vivem versionados em `distros/arch_minimal_v2/patches/`
  e são referenciados pelo `00-build-kernel-7.0.sh`.
- Baseline atual promovido: `20260730-sata-polling-fase-ab`.

### Convenções de bootargs (validadas ao vivo)

| Use | Nunca use | Por quê |
|-----|-----------|---------|
| `rootwait` | `rootdelay=N` | **Ganho medido de 10,5s de boot** (fase de initramfs: 21,7s → 11,2s), sem nenhuma espera por root device. `rootdelay` dorme os N segundos completos mesmo com o disco pronto. Validado 2026-07-28, `test_history` id 66. |
| `earlycon=uart8250,mmio32,0xC890E000` + `console=uart8250,mmio32,0xC890E000` + `console=tty0` | `console=ttyS0,115200n8` | `ttyS0` é a porta 8250 legada x86, sem hardware real no PS4 — causa tela preta. |

⚠️ **O bootargs do baseline `sata-noncq-fix-20260728` NÃO tem console serial** (só `console=tty0`).
Derivar dele deixa a UART cega ao kernel. Para diagnóstico use
`bootargs-7.0-20260728-sata-diag.txt` como modelo (UART + `rootwait`).

⚠️ **Console serial custa tempo de boot.** Com UART ativa o `ata1` proba em 2,4-7s; sem ela, em
0,68s. Não confundir com regressão — só comparar tempos entre boots com a mesma configuração de console.

⚠️ **`libata.force=...,noncq` no cmdline NÃO desliga NCQ neste projeto** — o quirk está hardcoded em
`drivers/ata/libata-core.c:4199` para o `TOSHIBA MQ04ABF100`. Remover do bootargs não reativa NCQ.

✅ **Corrigido 2026-07-30:** o heredoc de `bootargs-7.0.txt` dentro de `01-build-image-7.0.sh`
(gerado a cada `01-build-image-7.0.sh`/`02-burn-image-7.0.sh`, **não** o arquivo tageado em
`boot_referencia/`) estava desatualizado — usava `console=tty0` sem UART e `rootdelay=10`. Como
`02-burn-image-7.0.sh` grava esse `bootargs.txt` genérico direto no HD (não passa pela tag
validada), um `01-build-image` + `02-burn-image` sem revisão manual regravava o boot com a
configuração errada. O heredoc já foi atualizado para UART + `rootwait` por padrão — não precisa
mais corrigir manualmente após um burn completo, mas **confira sempre** (`cat` no `bootargs.txt`
da partição BOOT) antes de considerar um burn como definitivo.

### Procedimento OBRIGATÓRIO antes de qualquer deploy

Antes de rodar `deploy-boot-7.0.sh <TAG>`:

1. Confirmar que o HD USB `psxitarch` está plugado e a partição `BOOT` montou (`lsblk | grep BOOT`).
2. Confirmar que a tag existe completa em `boot_referencia/` (4 arquivos: bzImage, config, bootargs, initramfs).
3. Confirmar MD5 dos arquivos da tag (script já faz automaticamente origen→destino, mas vale uma checagem prévia).
4. Em incidente — caiu no rescue shell: NÃO tentar "remediar" comandos ad-hoc pelo shell do initramfs. Desligar, puxar o HD, plugar neste PC, restaurar tag anterior via `deploy-boot-7.0.sh <tag-velha>`, refazer o build corretamente com os scripts oficiais.

### Referências

- `consolidado/LICOES_APRENDIDAS.md` — lições #7 (label psxitarch), #17/22/23 (boot/stabilidade), #24 (não compilar em NTFS), "REGRA: no HD (sda1) fica APENAS o bzImage ativo", "INCIDENTE: 'testar' um script de deploy destruiu o boot do HD", "Fallback silencioso em ferramenta de debug é armadilha".
- `consolidado/FULL_BUILD.md` — procedimento de build completo do Arch Minimal v2.

---

## 🔴 PRIORIDADE ALTA — Banco de Varreduras de Hardware (SEMPRE consultar antes de varrer de novo)

**Antes de fazer qualquer varredura de registradores/MMIO ao vivo (BAR0/BAR2/BAR4, ICC, glue), consultar primeiro `consolidado/ps4_hardware_memory.db` (SQLite)** — é a fonte única de leituras já feitas em hardware real, para não repetir teste (cada teste ao vivo custa um power cycle inteiro).

```bash
sqlite3 consolidado/ps4_hardware_memory.db ".tables"
```

Tabelas principais:
- `readonly_verification` — leituras confirmadas de registradores (endereço, valor baseline/atual, se mudou, notas). Contém, por exemplo, a varredura completa da janela Glue BAR2 `0x140000`-`0x180000` (2026-07-25).
- `hardware_registers` — catálogo de registradores conhecidos (device, BAR, offset, nome, safe_to_read/write, risk_level).
- `bar_regions` — mapeamento de BARs por dispositivo PCI.
- `write_sweep_results` — resultados de testes de escrita (valor antes/depois, se ping/telnet sobreviveram).
- `decompiled_functions` — catálogo de funções decompiladas do kernel Orbis (`kmem_dump_1252.bin`) no escopo MTS/GBE/ICC/glue. Cada linha: addr_hex, short_name (ex `dc5a0070`), category, role, file_path do .txt, status (`revisado`/`bruto`/`pendente`/`refutado`), validated_by_test_id (FK → test_history.id). View `v_decompiled_summary` agrega contagens. Para verificar o que já foi decompilado antes de pedir RE nova:
  ```bash
  sqlite3 consolidado/ps4_hardware_memory.db "SELECT addr_hex, role, file_path, status, validated_by_test_id FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"
  ```
- `test_history` — histórico cronológico de testes ao vivo (inclui os testes de RMU/loopback da GBE de 2026-07-25).

Os dumps brutos/análise textual de varreduras grandes (ex: a janela Glue BAR2) também ficam em `consolidado/glue_140000_180000_raw.txt`/`_analise.txt`, mas o SQLite é sempre a referência estruturada e consultável.

## 🔴 PRIORIDADE ALTA — Topologia de Rede (NUNCA confundir)

- **WiFi (`wlan0`, subnet `192.168.6.0/24`) é SÓ PARA SSH/acesso administrativo ao console.** IP típico do PS4: `192.168.6.128`. Porta SSH: 22 (root/ps4). Porta telnet 23 está fechada (telnetd não iniciado).
- **Rede cabeada (`eth0`, driver `mts.ko`) é a rede sob teste — IP FIXO `192.168.0.2`.** Host do PC no Ethernet: `192.168.0.1` (interface `enp60s0`).
- **NUNCA testar o `eth0` usando a subnet do WiFi (`192.168.6.x`).** Um ping "funcionando" para `192.168.6.100`/`192.168.6.128` passa pelo `wlan0`, não prova nada sobre o `eth0`.
- **Todo teste de RX/TX do driver `mts.ko` deve usar a subnet `192.168.0.0/24`**: `ping -c N 192.168.0.2` do lado do host, ou `ping -I eth0 -c N 192.168.0.1` do lado do PS4.
- SSH (WiFi) e eth0 (cabeada) são canais independentes — pode-se usar ambos simultaneamente.

## Conexão via SSH

**Preferência do usuário:** Use SSH diretamente (sshpass) — o telnetd não está rodando no PS4.

```bash
sshpass -p ps4 ssh root@192.168.6.128 "<cmd>"
```

---

## Captura de UART TTL (console serial físico)

**Hardware validado 2026-07-27:** solda do usuário na UART Baikal (MMIO `0xC890E000`) funcional. Esquema de pinagem do adaptador USB-TTL (PL2303):

| Fio (cor do usuário) | Vai para |
|---|---|
| AMARELO | GND do adaptador |
| VERMELHO | RX do adaptador (recebe o TX do PS4) |
| LARANJA | TX do adaptador (opcional, só para enviar) |

**NUNCA usar `stty` + `cat` direto** — o adaptador PL2303 re-enumera no USB (visto em `dmesg`) e o termios volta ao padrão (9600 + modo canônico), fazendo o `cat` engolir tudo no buffer sem entregar nada. Os scripts abaixo usam `stty raw -icanon` + `dd bs=1` (método comprovado pelo usuário), com detecção automática de porta e reabertura se o adaptador cair.

### Scripts

| Script | Função |
|--------|--------|
| `scripts/uart_start.sh [duracao_s] [nome]` | Inicia UMA captura em background, grava em `tests/uart_logs/<nome>_<timestamp>.{bin,log}`. Recusa iniciar se já houver captura rodando (evita duas capturas disputando a porta — isso corrompe/trava a leitura). |
| `scripts/uart_stop.sh` | Encerra toda captura em andamento (via pid file + varredura de processos órfãos `dd`/`xxd`/`uart_capture.sh`). Sempre rodar antes de iniciar uma nova se não tiver certeza do estado. |
| `scripts/uart_capture.sh` | Motor interno (chamado pelos dois acima) — não rodar direto, usar `uart_start.sh`. |

```bash
scripts/uart_start.sh 900 s5-shutdown-test   # captura de 15 min
tail -f tests/uart_logs/s5-shutdown-test_*.log   # acompanhar ao vivo
scripts/uart_stop.sh                          # encerrar quando terminar
```

### Bootargs necessário

`console=ttyS0,115200n8` **NÃO funciona** — é a porta 8250 legada x86 (`0x3F8`), sem hardware real no PS4 (`/proc/tty/driver/serial` mostra `uart:unknown`). O log para de sair pela UART assim que o kernel troca do `earlycon` para esse console fantasma (~0.7s de boot). Usar:
```
earlycon=uart8250,mmio32,0xC890E000 console=uart8250,mmio32,0xC890E000 console=tty0
```
(console real apontando para o mesmo MMIO do earlycon, não para `ttyS0`). Teste ao vivo desse fix em andamento — ver `memory/console-ttys0-bootargs-causa-tela-preta-2026-07-27.md` e `memory/uart-ttl-pinagem-corrigida-2026-07-27.md`.

**Consoles CEX/retail (firmware oficial, antes do kexec) censuram a UART com bytes `0x20` (espaço) puros** — isso é esperado e não indica falha de captura.

## Compilação de Módulos

Use `sudo scripts/build_mts_module.sh` (já validado) para compilar o driver `mts.ko`.

Não criar `Makefile` ad-hoc nem comandos `gcc` diretos — o script já encapsula opções de cross-compile e flags corretas.

---

## Deploy do mts.ko

Script: `./scripts/deploy_mts.sh [push|test]` (usa sshpass)

- **push**: Compila (se necessário), copia mts.ko via SCP, insmod stage=4
- **test**: Configura eth0 (192.168.0.2), ping -I eth0 192.168.0.1, captura dmesg + mts_regs

Uso:
```bash
./scripts/deploy_mts.sh push
./scripts/deploy_mts.sh test
```

Para passar module params:
```bash
sshpass -p ps4 scp drivers_mts/build/mts.ko root@192.168.6.128:/tmp/mts.ko
sshpass -p ps4 ssh root@192.168.6.128 "rmmod mts 2>/dev/null; insmod /tmp/mts.ko stage=4 hold_val=0x10 enable_phy_calib_table=0"
```

Requer: sshpass, scp no host. PS4 precisa ter SSH rodando.

## ⚠️ REGRAS CRÍTICAS DO DRIVER mts.ko

### MAC Enable/Stop (descobertas 2026-07-24/25)
- **NUNCA escrever 0 em BAR0+0x34/0x38** — corrompe estado permanentemente
- Para **STOP** (rmmod/ifconfig down): escrever **2** (bit 1 = soft-reset) em 0x34 e 0x38, poll bit 1 até zerar (ACK)
- Para **ENABLE** (insmod): escrever **1** (bit 0) DIRETO com `mts_write()`, NUNCA `mts_set()` (RMW escreve 0x09 que é rejeitado)
- **NUNCA re-escrever** MAC enable depois de ativado — é one-shot por power cycle
- Sequência stop correta (Orbis dc5a3060): IMR=0x7ffffa → 0x34=2 (poll bit1) → 0x38=2 (poll bit1) → drain TX/RX → 0x1c8 &= ~0x440

### 0x200 (descoberta 2026-07-24)
- Escrever 0 em BAR0+0x200 TRAVA o MAC enable permanentemente
- O Orbis escreve 0x200=0 na calibração (dc5a0ba0), mas ativa o MAC DEPOIS (dc5a31f0, ifconfig up)
- **NÃO tocar em 0x200** no driver Linux — a calibração e o enable já não escrevem lá

### PHY MDIO
- GBE hold/pulse usa bit 4 (hold_val=0x10), NÃO bit 0 como SATA
- Clock config (0x10A030) necessário: `(reg & 0xfffffe07) | 0xd8` — persiste entre reloads
- Clause 45 MDIO retorna 0x0000 (PHY power-gated) — Clause 22 sempre timeout
- PHY não acorda mesmo com hold=0x10 + clock config + soft-reset via MDIO + hold/pulse no offset correto (ver correção abaixo, testado ao vivo 2026-07-25)

### ICC GBE Power (descobertas 2026-07-24)
- ICC `bpcie_icc_cmd(4, 0x38, &on=1, 1, &reply, 1)` confirma GBE MAC power-on (reply=0x01)
- Requer LOOP de retry (até 100x, 50ms delay) — não funciona na primeira tentativa
- ICC acorda o MAC core (BAR0+0x004 muda de 0 para 0xb19), mas NÃO o PHY
- **PHY tem domínio de power SEPARADO** (`SceGbeMtsPhyCtrl`) — ICC 4 0x38 não liga o PHY
- **NUNCA varrer ICC minors com data=1** — causa crash/reboot do PS4
- `bpcie_icc_cmd` é built-in: `ffffffff821db120 T`

### Hold Registers são WRITE-ONLY (2026-07-24)
- Hold registers sempre leem 0 após escrita — padrão Baikal confirmado: write-only por design.
- ⚠️ **CORREÇÃO 2026-07-25 (a linha abaixo estava com os offsets trocados):** a label "GBE hold=0x180034" **estava errada** — veio de inferência por padrão (hold = pulse - 0x40) nunca cruzada com a descompilação real. A descompilação de `fcn.ffffffffdc6df850` (`consolidado/decompiled/baikal_glue_block_reset_dc6df.txt`) mostra `fcn.dc59fe10()` (rotina de STOP do MAC da GBE, já confirmada por RE) chamada **imediatamente antes** de `dc6dfb60(0x2000)` + `dc718710(0x20,1)` + `dc718710(0x74,1)` — ou seja, **GBE hold = `0x180020`, pulse = `0x180074`** (bloco `0x2000`, confirmado). `0x180034` pertence a um bloco DIFERENTE e não identificado (`0x3c00`), que sequer tem par hold/pulse (só uma chamada `dc718710`). SATA é `0x18002c`/`0x18006c` (nunca foi `0x180020`). `drivers_mts/mts.c` corrigido para usar `0x180020`; testado ao vivo 2026-07-25 sem incidente (console permaneceu estável), mas o PHY continuou mudo mesmo com o offset correto — toggling hold/pulse sozinho não é suficiente. Ver `test_history` no `ps4_hardware_memory.db`.

### BAR0+0x004 Link Status (2026-07-24)
- STABLE_ZERO antes do ICC power-on; muda para 0x00000b19 após ICC+clock+calibração
- Bits: 0 (link?), 3, 4 (speed?), 8, 9 (duplex?) — reflete estado do MAC, não do PHY
- Valor difere do 0x61 que forçamos na calibração — o registrador está vivo

## 🔴 PRIORIDADE ALTA — Funções Decompiladas do Kernel Orbis (panorama MTS/GBE/ICC/glue)

**Antes de pedir nova descompilação ao vivo ou tentar inferir comportamento de uma função do kernel Orbis**, consultar:
- `consolidado/decompiled/INDEX.md` — catálogo canônico (~50 funções indexadas por papel/status).
- `ps4_hardware_memory.db` → tabela `decompiled_functions` — mesmo catálogo, consultável: `addr_hex`, `category`, `role`, `status` (`revisado`/`bruto`/`pendente`/`refutado`), `validated_by_test_id` (FK → test_history.id), `file_path` do `.txt` decompilado.

Processo para nova RE:
```bash
# 1. Lista o que já existe no escopo MTS:
sqlite3 consolidado/ps4_hardware_memory.db "SELECT addr_hex, role, status FROM decompiled_functions WHERE category LIKE 'MTS%' ORDER BY addr_hex;"

# 2. Lista as lacunas pendentes (ainda não decompiladas):
sqlite3 consolidado/ps4_hardware_memory.db "SELECT addr_hex, role FROM decompiled_functions WHERE status='pendente' ORDER BY addr_hex;"

# 3. Antes de pedir RE de uma função, ver se já foi validada/refutada em testes ao vivo:
sqlite3 consolidado/ps4_hardware_memory.db "SELECT t.id, t.phase, t.status FROM decompiled_functions d JOIN test_history t ON d.validated_by_test_id = t.id WHERE d.addr_hex = 'dc5a44c0';"
```

Os dumps brutos/análise textual de varreduras grandes (ex: a janela Glue BAR2) também ficam em `consolidado/glue_140000_180000_raw.txt`/`_analise.txt`, mas o SQLite e o `INDEX.md` são sempre a referência estruturada e consultável.

Ghidra headless está instalado em `/mnt/hdauxiliar/ghidra_12.1.2` e os scripts de extração em `consolidado/tools/ghidra_scripts/`. Para extrair novas funções:
```bash
/mnt/hdauxiliar/ghidra_12.1.2/support/analyzeHeadless consolidado/tools/ghidra_project orbis_mts \
  -process kmem_dump_1252.bin \
  -postScript consolidado/tools/ghidra_scripts/ExtractMtsNamespaceNoAnalysis.py \
  -scriptPath consolidado/tools/ghidra_scripts \
  -readOnly
```
Adicionar novo endereço em `TARGET_ADDRS` do `ExtractMtsNamespaceNoAnalysis.py` antes de rodar. Saídas em `consolidado/decompiled/extracted/`.

---

## Localização da Documentação
- **Fonte única de documentação do projeto a partir de 2026-07-19: `consolidado/`.** Ignorar qualquer coisa em `old_project/` para fins de documentação (inclusive `old_project/distros/arch_minimal_v2/LICOES_APRENDIDAS.md`, que tinha lições extras #24-27, mas foi descontinuado por decisão do usuário).
- O arquivo de lições imperativas (REGRA #0, ler antes de qualquer ação) é `consolidado/LICOES_APRENDIDAS.md`.
- **Memórias do assistente movidas para o projeto (2026-07-20):** os arquivos de memória foram relocados de `/home/anderson/.claude/projects/-mnt-t-downloads-PS4-linux-in-ps4/memory/` para `./memory/` (pasta na raiz do projeto) para que múltiplos agentes/sessões possam acessá-los. O índice está em `memory/MEMORY.md`.

### Mapa de arquivos (reorganizado em 2026-08-05 — fonte única)

Antes desta data havia planos e scripts espalhados na raiz, o que poluía o repositório no GitHub. Layout atual:

| Arquivo / Pasta | Papel | Auto-carregado? |
|-----------------|-------|-----------------|
| `AGENTS.md` | **Fonte única de regras e procedimentos.** Escreva aqui. | Sim, via import do stub |
| `CLAUDE.md` | Stub de uma linha (`@AGENTS.md`). **Não escrever regras aqui.** | Sim (o Claude Code só lê este nome) |
| `docs/planos/` | Planos de investigação, descobertas e arquitetura (`PLANO_*.md`, `DESCOBERTA_*.md`) | Não |
| `docs/relatorios/` | Relatórios de testes, sessões de debug e resultados (`TESTE_*.md`, `PHY_DEBUG_*.md`, etc.) | Não |
| `consolidado/` | Documentação técnica consolidada, banco de RE (SQLite), scripts Ghidra, `BACKLOG.md` e `LICOES_APRENDIDAS.md` | Não |
| `memory/` | Registro cronológico de descobertas e memórias de sessão (`MEMORY.md`) | Não |
| `tools/harness/` | Scripts Python de diagnóstico, varredura de registradores e testes de hardware | Não |
| `tools/ps4_hdd_tools/` | Ferramentas de manipulação de disco e utilitários PS4 HDD | Não |
| `RELEASE/` | Releases de boot/kernel compiladas e consolidadas para distribuição (`v1.0.0/`) | Não |

**Por que o stub existe:** a documentação oficial do Claude Code diz textualmente *"Claude Code
reads `CLAUDE.md`, not `AGENTS.md`"* e recomenda exatamente este padrão — um `CLAUDE.md` que
importa o `AGENTS.md`, para que os dois mundos leiam as mesmas instruções sem duplicá-las.
Outros agentes (opencode, em `.opencode/`) leem o `AGENTS.md` direto.

⚠️ **Regra prática:** regra nova ou procedimento novo vai em `AGENTS.md`. Pendência vai em
`BACKLOG.md`. Histórico vai em `ESTADO_E_HISTORICO.md`. Nada volta para o `CLAUDE.md`.
