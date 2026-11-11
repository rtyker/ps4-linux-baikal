# Estado e Histórico do Projeto — PS4 Linux Baikal

> **Este arquivo NÃO é carregado automaticamente em toda sessão.** Ele guarda o estado
> narrativo e o histórico das sagas técnicas do projeto, que antes moravam no `CLAUDE.md`
> e o inflavam para 32 KB — reduzindo a aderência às regras que realmente precisam estar
> em contexto sempre.
>
> **Onde procurar cada coisa a partir de 2026-07-28:**
>
> | Você quer | Vá para |
> |-----------|---------|
> | Regras de conduta e procedimentos (build, deploy, SSH, UART, banco de hardware) | `AGENTS.md` (auto-carregado via `CLAUDE.md`) |
> | O que está pendente / próximos passos | `consolidado/BACKLOG.md` |
> | Lições imperativas (REGRA #0) | `consolidado/LICOES_APRENDIDAS.md` |
> | Memórias curtas e indexadas do assistente | `memory/MEMORY.md` |
> | **Histórico narrativo e estado detalhado (payloads, dumper, sagas)** | **este arquivo** |
>
> Conteúdo migrado do `CLAUDE.md` em 2026-07-28, sem alteração de texto.

---

## Estado Atual do Projeto (Resumo Rápido) — ATUALIZADO 2026-07-23 NOITE (causa raiz RX confirmada: PHY não acorda)

**🎯 STATUS:** Módulo `mts.ko` estável (crash eliminado), TX funcional (~95%), RX bloqueado — causa raiz é o PHY nunca sair de power-down (não é mais bug de software/anéis). Próxima pista: reabilitar IRQ real (`IMR` não-zero), já que a única sessão com duplex genuinamente correto (`Full duplex`, `memory/teste-5-...md`) tinha IRQ habilitada.

✅ **KERNEL LINUX 7.0 BAIKAL — FUNCIONAL E ESTÁVEL**

- **Versão Ativa:** `bzImage-7.0-20260723-RELEASE` (compilado 2026-07-23 11:37, initramfs RELEASE — better-initramfs/systemd, monta rootfs, deploy+burn validados ao vivo 2026-07-23)
- **Kernel Anterior (DEBUG):** `bzImage-7.0-20260723-mts-autoeth0` (initramfs busybox debug loop)
- **Tag Baseline:** `v7.0-20260722-clean-video-ok` (vídeo OK, boot completo, telnet OK, rebuild limpo)
- **Validação Ao Vivo:** ✅ Vídeo HDMI funcional, ✅ Ethernet `eth0` detectada, ✅ GPU Gladius acelerada (55 FPS OpenGL), ✅ SSH remoto ativo e validado no ambiente **RELEASE** (sem DEBUG LOOP) em 2026-07-23.


### Tipos de Initramfs (FUNDAMENTAL — ler antes de qualquer deploy)

> **RELEASE** = `initramfs-7.0-20260723-RELEASE.cpio.gz`
> - `/init` do tipo `better-initramfs` (psxitarch): monta `LABEL=psxitarch` → `switch_root` → systemd
> - **SEM** DEBUG LOOP. **COM** symbols de debug no kernel (BTF, loglevel=8, drm.debug=0x06)
> - Firmware: `gladius_*.bin` (GPU correta) + `edid/ps4_tv_edid.bin`
> - Deployar com: `sudo ./deploy-boot-7.0.sh 20260723-RELEASE`
>
> **DEBUG** = `initramfs-7.0-20260723-mts-autoeth0.cpio.gz` (e todas as tags anteriores)
> - `/init` é um script busybox com `while true; do DEBUG LOOP; done`
> - **NUNCA** monta o rootfs nem faz switch_root — fica preso em RAM
> - Útil para: diagnóstico de kernel, telnet de emergência, testes de driver

### Subsistemas Funcionais
- **Kernel 7.0 Baikal:** Compila sem erros, boot até prompt root
- **Vídeo HDMI:** Tela inicializa, legível, zero crashes
  - `amdgpu` é **built-in** (`CONFIG_DRM_AMDGPU=y`) — não depende do initramfs
  - EDID lido do hardware (NOR flash PS4 via `ps4_bridge`) — não depende de arquivo em `/lib/firmware`
  - WiFi MediaTek MT7668 **embutido no bzImage** via `CONFIG_EXTRA_FIRMWARE`
- **Rede:** WiFi automática + Ethernet via `mts.ko stage=4` (MAC `2c:cc:44:3f:69:5f`, DMA OK)
- **SSH/Telnet:** Acesso remoto funcionando (systemd service auto-start)
- **GPU Gladius:** `amdgpu` 32 CUs ativos, OpenGL 4.5 @ 55 FPS, Vulkan 1.3 disponível
- **Armazenamento:** USB disco montado em `/`, ext4 estável
  - `CONFIG_USB_STORAGE=y`, `CONFIG_BLK_DEV_SD=y`, `CONFIG_EXT4_FS=y` — todos built-in

### Pendências Abertas
- 🔴 **RX Ethernet não recebe frames — causa raiz confirmada 2026-07-23 noite:** anéis RX/TX e lógica de software (bit OWN, tail pointers) estão corretos e testados; TX funciona (~95%). RX permanece em zero (`MTS_CNT_PKTS=0`, ping 100% perda em `192.168.0.1↔192.168.0.2`) porque **o PHY nunca sai de power-down** — nem Clause 45 (MMD1/MMD7, todos `0x0000`) nem Clause 22 (BMCR, scan completo `phy_addr` 0-31: 0-15 timeout, 16-31 residual zero) conseguem tirar sinal real do chip. O registrador de status do MAC (`0x04`, "Link UP 1000Mbps Half duplex") é MAC-interno e não reflete negociação física real (escrita forçada nele é no-op comprovado). `MTS_MAC_EN2` (0x38) descartado como suspeito — não retém o bit desde a primeira escrita, independente de calibração. Ver `memory/mac-en2-descartado-phy-nunca-acorda-2026-07-23.md`.
  - **Hipótese IRQ real (`IMR=0x7d`) testada e REFUTADA (2026-07-23 noite):** reabilitar IRQ real com o valor histórico não reproduziu o Full-duplex do `teste-5` — resultado foi Link DOWN e zero interrupções disparadas. A correlação daquela sessão era coincidência, não causada pelo IMR. Guarda de tempestade de IRQ corrigida e commitada (`a948b4e`) mesmo assim, por ser bug real de código.
  - **CAUSA RAIZ REAL ENCONTRADA E CORRIGIDA, MAS INSUFICIENTE SOZINHA (2026-07-23 noite, commit `ce145b8`):** `mts_phy_calibration()` lia os parâmetros de calibração do PHY de `BAR2+offset` (`0xc8800000`), mas o efuse real (confirmado por RE e por comparação com `bpcie_baikal_sata_phy_init()` do driver SATA, já em produção) fica em `BAR4+0xC000+offset` — recurso PCI totalmente separado da mesma função glue `00:14.4`. Corrigido: `BAR4` mapeado (`0xc9000000`, confirmado presente), `p0` agora lê `0xbfbf8787` (bits 31/23 setados) em vez do valor de BAR2 que nunca batia a condição. Confirmado ao vivo que o bloco de ~18 escritas MDIO de tuning analógico do PHY **agora executa de fato** pela primeira vez. **Mas o PHY continua retornando zero** em Clause 45/22 mesmo assim — a correção era necessária mas não suficiente. Ver `memory/bar4-efuse-corrigido-mas-phy-continua-mudo-2026-07-23.md`. Próximo passo: revisar ordem das operações no wakeup (diagnostic MDIO roda antes do tuning — pode estar testando cedo demais) ou buscar mais alguma etapa faltante em `consolidado/RE_KERNEL_GBE_ATTACH.md`.
- 🔴 **HD interno SATA (`ata1`, TOSHIBA MQ04ABF100) morre ~4,9s após o boot — EM ABERTO, e custa 78s (58%) do tempo de boot.** Não é PHY, não é EFUSE, não é garbage collection do SMR: `SErr 0x0` em 100% das falhas e status `{ DRDY }` (disco energizado, os primeiros ~10 comandos DMA completam). Histórico completo de tentativas, todas refutadas (`test_history` ids 63-68):
  - **id 63/64** (2026-07-28, IRQ dedicada): o AHCI *compartilhava* a IRQ 32 com os dois xHCI; corrigido em `bpcie_assign_irqs()` (clamp `nvec=1` → `min(nvec, bpcie_max_vectors(func))`), tag `20260728-sata-irq-dedicada` deu vetor dedicado hwirq **5345** (`ata1 ... irq 33`). **Falha persistiu** — contador da IRQ 33 parou em 7 contra 8.212 do USB.
  - **id 65** (2026-07-28, REFUTADO): a hipótese de corrida entre os 3 vetores dedicados foi **refutada** — só existe de fato **1 vetor MSI** compartilhado (`FUNC7_USA_UM_UNICO_VETOR_MSI`), o vetor "dedicado" nunca disparou (0 chamadas). **A correção de 3 vetores do id 64 é considerada inútil e candidata a reversão.**
  - **id 67** (2026-07-28, `20260728-sata-ackfix-ehdump`, REFUTADO): fix no demux do ACK do glue (`bpcie_handle_edge_irq`) + dump de registradores no `ahci_error_handler`. Não resolveu — exceção em `t=37,00s`, `disable device` em `t=84,11s`.
  - **id 68** (2026-07-29, `20260729-sata-globallock`, REFUTADO): spinlock global (`bpcie_ack_lock`) reproduzindo o mutex do Orbis (`dc718b40`) protegendo o par `0x110084`/`0x110088`. Funcionou sem travar, mas falha idêntica: sinalização cessa aos **4,89s**, exceção em `t=36,80s`, `disable device` em `t=83,90s`.
  - 🔴 **Descoberta central (id 68, RECONCILIADA 2026-07-29 com o log UART bruto `tests/uart_logs/sata_teste_20260729_145146.log`):** os 3 EH entries reais do `ata1` são `t=2,504898s` (probe: `PxIS=0x00400040 PxIE=0x00000000`), `t=36,777086s` (falha: `IS=0x00000001 PxIS=0x00000001 PxIE=0x00000000`, link 3.0Gbps) e `t=83,916040s` (pós-`disable device`/hard-reset: `PxIS=0x00000002 PxIE=0x7840007f`, link caído para 1.5Gbps). **Esses valores confirmam os dados de `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md`** — no momento da falha, `PxIE=0x00000000` (interrupções da porta desligadas no próprio registrador AHCI). A entrada anterior desta memória e de `memory/MEMORY.md` (linha 16) tinha uma transcrição imprecisa (`PxIS=0x2`/"Glue não propaga interrupção ativa") — já corrigida.
  - ✅ Diagnóstico correto (confirmado pelo log bruto, fonte da verdade): o AHCI genuinamente desliga `PxIE` antes da falha — não é caso de Glue bloqueando uma interrupção ativa. `PxIE` só volta ao valor esperado (`0x7840007f` = `DEF_PORT_IRQ` menos `BAD_PMP`) no 3º EH entry, tarde demais. Revisão técnica do código (2026-07-29) mostrou que `ahci_freeze()`/`ahci_thaw()` são stock upstream, sem patch PS4 — a Fase A do plano de polling (investigar quem zera `PxIE` fora do ciclo normal freeze→thaw) tem fundamento real e é o próximo passo de investigação.
  - ⚠️ **Três erros de diagnóstico já cometidos, não repetir:** (1) "o AHCI não tem handler de IRQ" — **falso**, ele se chama `xhci_aeolia[0000:00:14.7]`, não `ahci[...]`, porque `ata_host_activate()` usa `dev_driver_string(host->dev)`; (2) "a falha é específica de NCQ" — **falso**, com `noncq` ativo falha como `READ DMA` (`0xc8`/`0x25`), não-enfileirado; (3) "3 vetores MSI dedicados resolvem a corrida" — **falso** (id 65), só existe 1 vetor MSI real.
  - ⚠️ **`noncq` não sai pelo bootargs** — o quirk é hardcoded em `libata-core.c:4199` (`ATA_QUIRK_NOLPM | ATA_QUIRK_NONCQ` para `TOSHIBA MQ04ABF100`).
  - Plano ativo: `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md` (Fase A instrumentação exploratória + Fase B polling timer fallback, revisado tecnicamente em 2026-07-29 — API `hrtimer_setup`, ack de `HOST_IRQ_STAT`, guarda contra EH incluídos).
  - **🔧 EM ANDAMENTO (2026-07-29, `test_history` id 69):** Fase A e Fase B implementadas em `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ata/{libahci.c,ahci.c,ahci.h}` (ainda não compiladas/testadas em hardware). Fase A: log de `PxIE` dentro de `ahci_freeze()`/`ahci_thaw()`. Fase B: `ahci_poll_timer_fn()` (hrtimer 1ms) + wrappers exportados `ahci_start_poll_timer()`/`ahci_stop_poll_timer()`, ativados em `ahci_init_one()`/`ahci_remove_one()` sob `CONFIG_X86_PS4_BAIKAL` + `vendor==SONY && device==BAIKAL_AHCI`. Próximo passo: build oficial (`00-build-kernel-7.0.sh`) com tag `20260729-sata-polling-fase-ab`, deploy e teste ao vivo com captura UART.
- 🟡 **S5 desligamento:** `poweroff -f` encerra SO mas deixa luz azul (requer ICC ou toque manual)

### Contexto de Payloads (Ainda Válido)
- **Firmware Alvo:** 12.52 (GoldHEN) — kernel dumping completado com sucesso (32.2 MB em 3s via TCP)
- **Limitações do 12.52 mapeadas:**
  - `jailbreak()` da libPS4 original corrompe `rootvnode`, bloqueando USB. **NÃO usar.**
  - `/dev/kmem` bloqueado para leitura em userland (GoldHEN).
  - Leituras diretas de MSR ou em páginas não-mapeadas causam Kernel Panic.
  - **ARQUIVO FALSO:** `ps4-linux-payloads/kernel-dumper-1252.bin` (9 bytes) é resposta HTTP 404. Não usar.

## Estado do Dumper TCP (scene-kmem-dumper) — ATUALIZADO 2026-07-19
- **O binário original perdido está CONFIRMADO QUEBRADO.** Testado ao vivo 2x no console real: em ambas as vezes morre logo após a notificação `"kmem-dumper: iniciado"` e nunca chega a `"escutando na porta 9020"` (o `receive_kmem_dump.py` esgota os 10 min de espera sem conectar). O PS4 NÃO trava/reinicia nos dois testes (ping continua respondendo) — não é Kernel Panic, é o processo do payload morrendo/saindo cedo demais.
- **Causa provável identificada:** o binário original NÃO linkava `get_kernel_base()`/`get_memory_dump()` da SDK (confirmado via `strings`: zero ocorrências de `kpayload_dump`/`kpayload_kbase`, únicas nesse binário quando essas funções da SDK estão presentes) — ou seja, ele calculava `kernel_base` com o truque de MSR direto (`__readmsr(0xC0000082) - 0x1C0`, sem passar por `kexec`) E MUITO PROVAVELMENTE também tentava ler a memória do kernel sem `kexec`. Essa técnica nunca teve nenhuma prova de funcionar de ponta a ponta (nenhum `kmem_dump_*.bin` jamais foi gerado, nem antes nem nos testes de hoje).
- **CORRIGIDO: `fw_defines.h` da SDK C (`ps4-payload-sdk/libPS4`) TEM offsets específicos para 12.52** (`K1252_XFAST_SYSCALL=0x1C0`, `K1252_COPYOUT=0x2BD5C0`, etc.), selecionados automaticamente por `get_firmware()` via o macro `build_kpayload()`. A hipótese antiga ("os offsets são do 11.00") estava ERRADA para essa SDK. `K1252_PRISON_0`/`K1252_ROOTVNODE` (usados só por `jailbreak()`) são suspeitos — valor idêntico em 1252..1352, provável offset não verificado — por isso `jailbreak()` continua banido, mas `get_kernel_base()`/`get_memory_dump()` (que usam `K1252_COPYOUT`, não `PRISON_0`/`ROOTVNODE`) têm prova real de funcionar: o Smart Dumper leu 3.9MB de kernel real com eles, zero chunks corrompidos (só morreu depois, na escrita USB — já eliminada).
- **`scene-kmem-dumper/source/main.c` foi RECONSTRUÍDO em 2026-07-19** usando `get_kernel_base()`/`get_memory_dump()` (via `kexec`, comprovado) + TCP na porta 9020 (protocolo idêntico: `[u64 start][u64 size]` LE relativo a `kernel_base` → stream cru em chunks de `PAGE_SIZE`=0x4000, chunk ilegível vira zeros). Compila limpo com `make` usando `PS4SDK=ps4-payload-sdk`.
- **Ainda não existe nenhum dump capturado via TCP** (nenhum `kmem_dump_*.bin` no projeto). Os parciais em `consolidado/dumps_orbis/kernel_partial_*.bin` são do método antigo por USB (comprovadamente quebrado, mas prova que `get_kernel_base()`/`get_memory_dump()` leem kernel real corretamente).

### Sessão de testes ao vivo 2026-07-19 (fim de tarde/noite) — resultado
1. **v1 do reconstruído** (com `initPthread()`+`initSysUtil()` copiados do `scene-kernel-dumper`, sem necessidade real): injetado, **NENHUMA notificação apareceu**, nem `"iniciado"`. PS4 não travou (ping OK). Suspeita: `initSysUtil()` carrega `libSceSysUtil.sprx`+`libSceSystemService.sprx`, módulos extras que travam/falham nesse contexto de payload injetado via BinLoader.
2. **Correção:** removidas as duas chamadas — `sceKernelSendNotificationRequest` (usado por `printf_notification`) só precisa de `initKernel()`, confirmado lendo `source/kernel.c`. `initPthread()`/`initSysUtil()` eram desnecessárias (não uso threads nem sysutil). Recompilado, `strings` confirma que as referências a `libSceSysUtil`/`libSceSystemService` sumiram do binário.
3. **v2 (sem initPthread/initSysUtil), 1º teste:** injetado, apareceu só `"kmem-dumper: iniciado"`, sem chegar em `"escutando"`. PS4 não travou.
4. **Entre tentativas: o PS4 travou sozinho SÓ AO ABRIR o menu "Payload Server" do GoldHEN**, antes de qualquer injeção nossa — não parece relacionado ao nosso payload. Usuário reiniciou o console.
5. **v2, 2º teste (pós-reboot):** progrediu mais — apareceu `"kmem-dumper: iniciado"` **e depois** `"kmem-dumper: FALHA ao abrir /dev/kmem"` (mensagem esperada/não-fatal, é só uma sondagem informativa). **Mas parou exatamente aí** — nunca apareceu `"FALHA ao obter kernel_base"` nem `"FALHA no socket()"` nem `"escutando na porta 9020"`, e o `receive_kmem_dump.py` nunca conectou (10 min esgotados). PS4 continuou respondendo ping o tempo todo — não é Kernel Panic, é o processo do payload parando de progredir logo depois da sondagem de `/dev/kmem`, ou seja, dentro (ou logo antes) da chamada a `get_kernel_base()`.
6. **Suspeita aberta ao pausar a sessão — MISMATCH DE TOOLCHAIN:** o build local usado nos testes 1-5 foi feito com o `gcc` do HOST desta sandbox, que reportou **versão 16.1.1** (extremamente recente/incomum) — bem diferente do que a SDK realmente espera. O `ps4-payload-sdk/Dockerfile` oficial usa `ubuntu:latest` + `apt-get install gcc` (resultou em **gcc 15.2.0** ao construir a imagem `ps4sdk` nesta sessão). Payloads freestanding de baixo nível (`-nostdlib -nostartfiles -fpie -fPIC -mcmodel=small`, `crt0.s` próprio, relocação manual) são sensíveis a mudanças de codegen entre versões de gcc — um `gcc` novo demais pode gerar binário sutilmente incorreto mesmo com fonte C correto. **A imagem Docker `ps4sdk` já foi construída nesta sessão (`docker build -t ps4sdk .` dentro de `ps4-payload-sdk/`, sucesso)**, mas AINDA NÃO recompilamos o `scene-kmem-dumper` dentro dela nem testamos esse binário no console.

### PRÓXIMO PASSO EXATO (retomar daqui)
1. Recompilar dentro do Docker oficial (toolchain correto), não com o `gcc` do host:
   ```bash
   cd /mnt/t/downloads/PS4/linux_in_ps4
   docker run --rm -v "$PWD/scene-kmem-dumper":/app -w /app ps4sdk make clean
   docker run --rm -v "$PWD/scene-kmem-dumper":/app -w /app ps4sdk sh -c 'PS4SDK=/lib/ps4-payload-sdk make'
   ```
   (confirmar que o `PS4SDK` dentro do container aponta pra `/lib/ps4-payload-sdk`, conforme o `ENV` do Dockerfile).
2. Testar ao vivo de novo com o mesmo protocolo já rodado hoje (injetar via `send_payload_loop.py` porta 9090, `receive_kmem_dump.py` esperando na 9020, usuário observando a tela).
3. **Se AINDA parar depois de `"FALHA ao abrir /dev/kmem"`** (ou seja, não é o toolchain): isso aponta pra `get_kernel_base()`/`kexec()` travando de fato nesse console/firmware — próximo passo aí seria um payload mínimo de diagnóstico que só faz `initKernel();initLibc();printf_notification("A");uint64_t kb=get_kernel_base();printf_notification("B base=0x%llx",kb);` pra isolar exatamente se o `kexec()` retorna ou trava, sem nenhuma complexidade de socket junto.
4. Regra permanente já registrada na memória do assistente: **nunca fazer probe TCP manual nas portas 9090/9020** (só `ping`, nunca `connect()`) — consome o `accept()` único do servidor.

### Sessão de testes ao vivo 2026-07-20 — nova abordagem dinâmica (kern_base_finder.c)
1. **Teste 1 — método LSTAR apenas (versão anterior):** injetado → `LSTAR=0x0 base=0x0 size=0x0` → `rdmsr` retorna 0 no contexto `kexec`. Payload abre porta 9020 mas dumper envia 0 bytes (base 0).

2. **Teste 2 — fallback scan com copyout (versão com debug, recompilada Docker ps4sdk):**
   - **Testado ao vivo 2026-07-20:** injetado via `inject.sh`
   - **TV mostrou:**
     ```
     kern-dumper: iniciado
     kern-dumper: achando kernel base via kexec...
     kern-dumper: LSTAR=0x0 base=0x0 size=0x0
     kern-dumper: escutando na porta 9020
     kern-dumper: enviando 0x2034af0 bytes de +0x0
     ```
   - **Análise:** LSTAR=0 (rdmsr falha), scan ELF **não achou** o magic `\x7fELF` — `method_used` não impresso mas base=0 indica que ambos métodos falharam
   - **Receiver:** conectou na 9020, pediu dump, timeout (0 bytes salvos) — payload enviava zeros por base=0

3. **Teste 3 — versão com debug de scan (recompilada Docker ps4sdk, aguardando power cycle)**
   - Novos campos de debug em `kern_base_result_t`: `scan_addr_found`, `magic_found`, `phnum_found`, `min_vaddr_found`, `max_vaddr_found`
   - **Próximo teste:** aguardando power cycle completo

### Novos scripts auxiliares criados 2026-07-20 (`scene-kmem-dumper/`)
- **`build_diag.sh`** — análogo ao `rebuild.sh`, mas compila só o target `diag.bin` do `Makefile` (payload mínimo `source/diag.c`: `initKernel()`+`initLibc()`+notificação+`get_kernel_base()`+notificação, sem TCP/socket). Já executado com sucesso via Docker `ps4sdk`: gerou `diag.bin` (9356 bytes), build limpo sem erros.
- **`inject_diag.sh`** — análogo ao `inject.sh`, mas roda `send_payload_loop.py` apontando pro `diag.bin` em vez do `app.bin`. **Ainda NÃO foi executado/injetado no console** — aguardando autorização explícita do usuário ("pronto"), conforme Regra de Ouro da Injeção (item 1 acima).
- Objetivo desses dois scripts: viabilizar o passo 3 do "PRÓXIMO PASSO EXATO" (payload mínimo de diagnóstico) sem precisar montar/desmontar manualmente comandos Docker/injeção toda vez — só isolar `get_kernel_base()`/`kexec()` travando ou não, sem a complexidade do dumper TCP completo junto.
- Resumo dos scripts do diretório `scene-kmem-dumper/` até aqui: `rebuild.sh`/`inject.sh` (dumper completo, `app.bin`) vs. `build_diag.sh`/`inject_diag.sh` (diagnóstico mínimo, `diag.bin`).

### Instrumentação de Debug Ultra-Verbosa 2026-07-20 (CORRIGIDO)
- **Ambos `kern_dumper_main.c` e `kern_base_finder.c` foram re-instrumentados com contador incremental `[step++]` em cada notificação.** Objetivo: rastrear exatamente até que ponto a execução chegou e onde trava (se travar). Ver `scene-kmem-dumper/DEBUG_INSTRUMENTATION.md` para sequência esperada de notificações e cenários de falha.
- **ERRO NA V1:** primeira versão (14:10) colocava notificações ANTES de `initKernel()`/`initLibc()`, o que causava falha silenciosa porque essas libs precisam estar carregadas antes de `printf_notification()` funcionar.
- **V2 CORRIGIDA (14:17):** `initKernel()`, `initLibc()`, `initNetwork()` agora rodam SEM notificações (como era no original), e primeira notificação é `[0] inicializacoes OK` DEPOIS disso. Binário novo: 25356 bytes.
- **Próximo teste ao vivo:** injetar este novo `app.bin` (v2 corrigida, 14:17) e anotar a sequência de numbers `[0] [1] [2] ...` que aparecem nas notificações da TV até aonde chega antes de travar/suceder. Isso vai definir o rumo exato da investigação.

### Teste ao vivo `diag.bin` — 2026-07-20 (RESULTADO IMPORTANTE)
- Injetado via `inject_diag.sh` (toolchain Docker `ps4sdk` correta, não o gcc do host).
- **TV mostrou apenas:** `"diag: iniciado"` (payload recebido de `192.168.6.100`, conforme log do `send_payload_loop.py`).
- **NUNCA apareceu** `"diag: kernel_base = 0x..."` nem `"diag: get_kernel_base FALHOU (-1)"` — ou seja, a execução para dentro (ou logo antes de retornar) de `get_kernel_base()`.
- **Console NÃO travou** — confirmado pelo usuário: continuou respondendo normalmente (sem Kernel Panic, sem reboot, sem tela preta) mesmo com o payload nunca progredindo além dessa notificação.
- **Conclusão:** isso REPETE exatamente o comportamento já visto no `main.c` (versão antiga, 2026-07-19 — que também chamava `get_kernel_base()` da SDK, antes da reescrita para `kern_base_finder.c`) — mesmo com um payload minúsculo e a toolchain oficial, o que **descarta definitivamente a hipótese de mismatch de toolchain** (item 6 da sessão 2026-07-19 acima) como causa raiz.
- **CORREÇÃO IMPORTANTE (apontada pelo usuário):** `app.bin` — o dumper ATUAL em uso, compilado a partir de `kern_dumper_main.c` + `kern_base_finder.c` — **NÃO usa `get_kernel_base()` da SDK**. Ele usa o método próprio via `kexec()` (LSTAR/MSR 0xC0000082 + fallback scan ELF, ver sessão `kern_base_finder.c` abaixo). E esse método **NÃO trava**: no Teste 2 de 2026-07-20, o `kexec()` do `kern_base_finder` RETORNOU normalmente (imprimiu `LSTAR=0x0 base=0x0 size=0x0`, seguiu até abrir a porta 9020 e tentar enviar bytes). Ou seja, o mecanismo `kexec()` em si funciona e retorna nesse console/firmware.
- **Nova conclusão principal (corrigida):** o hang é ESPECÍFICO da função `get_kernel_base()` da SDK original (`ps4-payload-sdk/libPS4`, offsets `K1252_*`), usada só em `diag.c` (e no antigo `main.c` de 2026-07-19) — não é um problema do `kexec()` em geral, nem afeta o `kern_base_finder.c` customizado que o `app.bin` usa hoje. `get_kernel_base()` da SDK trava/hangs (não causa panic, só não retorna nem imprime nada); a rotina customizada `kern_base_finder.c` via LSTAR retorna sempre, mas até agora só com valores zerados (LSTAR lido como 0, magic ELF não encontrado no scan) — problema diferente, de "retorna dado errado" e não de "trava".
- **Portanto:** a linha ativa de investigação continua sendo o `kern_base_finder.c`/`app.bin` (por que LSTAR retorna 0 dentro do `kexec()`, por que o scan ELF não acha o magic) — não há mais motivo para investigar `get_kernel_base()` da SDK, já que o dumper atual não depende dela. `diag.c`/`diag.bin` cumpriu seu papel de isolar e descartar a hipótese de toolchain; não precisa de mais testes a menos que se volte a cogitar usar `get_kernel_base()` da SDK no futuro.

### Resolução de Bug Crítico & Diagnóstico — 2026-07-20 (Antigravity)
- **Descoberta do Bug de Corrupção de Stack no `kexec`:** 
  Identificamos que o kernel passa um ponteiro para a estrutura de argumentos do syscall `kexec` (que contém o ponteiro da função no offset 0 e o argumento de usuário no offset 8) como o segundo parâmetro da função executada em Ring 0. 
  A assinatura de `kern_base_finder` estava incorretamente interpretando esse ponteiro de argumentos da stack do kernel como se fosse diretamente o ponteiro de resultado de usuário (`kern_base_result_t *`). Isso causava escrita fora dos limites da estrutura de argumentos na stack do kernel, corrompendo o frame do chamador e provocando o **Kernel Panic e desligamento imediato** ao retornar, além de impossibilitar a gravação dos dados no buffer de usuário real (daí os valores zerados `base=0x0`).
- **Ações Realizadas:**
  1. **Ajuste da Assinatura:** Definimos a struct `kern_base_finder_args` para desempacotar corretamente o ponteiro `result` no kernel.
  2. **Unificação da Struct:** Sincronizamos a definição de `kern_base_result_t` em `kern_dumper_main.c` com a de `kern_base_finder.c` para evitar incompatibilidades de tamanho.
  3. **Comentário de Função Suspeita:** Conforme solicitado, comentamos a execução de `try_scan_method()` em `kern_base_finder.c`. Esse escaneamento linear de memória por `copyout` em Ring 0 era extremamente perigoso e propenso a causar Kernel Panic ao encostar em páginas não mapeadas. O método LSTAR (`rdmsr`) é seguro e será o único executado.
  4. **Compilação de Teste:** O binário foi recompilado com sucesso via Docker (`./rebuild.sh`) gerando um novo `app.bin` estável.
- **Prevenção de Kernel Page Fault & Assembly Cleanup (2026-07-20):**
  Identificamos que o buffer `result` alocado com `mmap` em userland é mapeado como "demand-zero" (não residente na memória física). Quando a função de Ring 0 tentava escrever os resultados nele, ocorria um page fault em modo kernel que não podia ser resolvido com segurança, travando/congelando a thread do payload sem exibir o resultado. 
  Adicionamos um `memset` em userland logo após a alocação `mmap` para forçar a paginação (page-in) do buffer de resultados antes de chamar `kexec`.
  Também substituímos a implementação customizada de `rdmsr` pela função `__readmsr(0xC0000082)` integrada na SDK para garantir que as instruções assembly geradas sejam perfeitamente equivalentes às utilizadas no `diag.bin`.
- **SUCESSO E MARCO ALCANÇADO (2026-07-20):**
  Após as correções, o teste de injeção obteve sucesso absoluto na detecção do Kernel Base e na comunicação de rede!
  O fluxo de notificações na TV foi:
  ```
  kern-dumper: iniciado
  kern-dumper: [1] alocando result
  kern-dumper: [2] paginando result
  kern-dumper: [3] chamando kexec
  kern-dumper: [4] kexec ret=0 err=0
  kern-dumper: [5] LSTAR =base=0xffffffff948dc000 size=0x2034af0
  kern-dumper: [6] abrindo socket
  kern-dumper: [7] binding na porta 9020
  kern-dumper: [8] aguardando accept na porta 9020
  kern-dumper: [9] conexao aceita, recebendo pedido
  kern-dumper: [10] pedido recvd: +0x0/0x2034af0
  kern-dumper: [11] enviando dados...
  ```
  Isso valida a integridade da leitura em Ring 0 e a comunicação TCP! Criado o git tag `milestone-kbase-found-and-sending` para gravar este estado.
  Adicionamos um `memset` em `buf` imediatamente após a alocação `mmap` em userland para forçar sua paginação física.
- **Resolução do Travamento no kexec do get_memory_dump (2026-07-20):**
  Identificamos que o travamento silencioso no início da transmissão (iter=0, pos=0x0) ocorria porque a função original `get_memory_dump()` da SDK C também sofria do mesmo bug crítico de corrupção de stack por desempacotamento incorreto de argumentos no kernel (interpretava o bloco de argumentos do syscall kexec como sendo diretamente a struct de argumentos de usuário `kpayload_dump_info`). Isso corrompia o registrador de retorno no kernel e travava a thread do payload antes de qualquer dado ser transmitido.
  Substituímos o `get_memory_dump` da SDK por uma implementação própria chamada `direct_memory_dump()`, a qual utiliza um descompactador correto de argumentos em Ring 0 (`kpayload_direct_dump`) e chama diretamente a função `copyout` cujo endereço já foi obtido com sucesso em Ring 0.
- **SUCESSO TOTAL DO DUMP COMPLETO (2026-07-20):**
  Com o `direct_memory_dump()` em uso, a transmissão rodou de ponta a ponta sem falhas:
  ```
  ❯ ../listen.sh
  [16:48:25] Alvo: kernel_base+0x0, 0x2034af0 bytes (32.2 MB) -> kmem_dump_0.bin
  [16:48:25] Aguardando o payload abrir a porta 9020 em 192.168.6.130...
  [16:48:25] Conectado. Enviando pedido...
  [16:48:28] Recebidos:   32.21 MB / 32.2 MB  (11634 KB/s)  proximo offset: 0x2034af0
  [16:48:28] 33770224 bytes salvos em kmem_dump_0.bin
  ```
  O kernel completo do 12.52 foi extraído via rede TCP em **apenas 3 segundos** a uma taxa de **11.3 MB/s**! O marco foi registrado com a tag `milestone-dump-success`.
- **Sessão 2026-07-21 (orbis-hw-dumper no FW 12.52):**
  - **Correção da ABI `kexec`:** Ajustada a desestruturação de `struct kexec_sys_args` em Ring 0 e a passagem de ponteiros do userland, resolvendo a falha `ret=0 st=0 base=0x0`. Kernel base encontrado em `0xffffffff86284000`.
  - **Espinha dorsal TCP 100% estável:** kexec (base+copyout), socket, bind, accept, send funcionam sem Kernel Panic.
  - **GBE desalimentado no FW 12.52:** O driver `gbe0` do Orbis não inicializa a rede em modo de jogo. BAR0 (`0xc2000000`) e BAR2 (`0xc8800000`) são MMIO PCI sem PTE no DMAP — todos os métodos de mapeamento falharam (sceKernelMapDirectMemory=EINVAL, pmap_mapdev=sleep/panic, DMAP direto=Page Fault, copyout=EFAULT).
  - **Lições técnicas:** (1) NUNCA chamar funções que dormem em kexec; (2) DMAP só cobre RAM; (3) copyout bloqueia endereços < 0xffffffff80000000; (4) sceKernelMapDirectMemory só aceita RAM direta Orbis.
  - **Commits locais** em `orbis-hw-dumper/.git`: `9132150`, `76dafb6`, `7a64215`.
  - Ver histórico completo em `memory/sessao-2026-07-21-orbis-hw-dumper-sucesso.md`.

