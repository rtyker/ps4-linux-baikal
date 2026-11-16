# Plano — S5 Power-Off via ICC (PS4 Baikal)

**Data:** 2026-11-16 (revisado em 2026-11-16, contra o código-fonte e o acervo de RE)
**Status:** ✅ **RESOLVIDO (2026-11-16):** `sync && poweroff -f` com o kernel `20261116-s5-dma` desliga o console por completo (luz azul apaga, fan para). Patch `kernel/patches/ps4-icc-s5-poweroff-prepare.patch` (§11), validação em §12.
**Tag alvo (só se a Fase 2 for necessária):** `20261116-s5-poweroff-fix`
**Critério de aceite final:** depois de `sync && poweroff -f`, a luz azul **apaga** e o fan **para**. Precisa haver também evidência no log UART do que o kernel/MCU fez.

---

## 0. Correções desta revisão (o que estava errado na versão anterior)

| # | Afirmação anterior | O que o código/RE mostra de fato |
|---|---|---|
| 1 | "o payload atual tem 6 bytes **truncados**" | `_bpcie_icc_cmd()` (`ps4-bpcie-icc.c:~205`) **preenche com zeros até `ICC_MIN_PAYLOAD`**. `ICC_MIN_SIZE`=0x20 e `ICC_HDR_SIZE`=0x0C (`aeolia-baikal.h`), logo `ICC_MIN_PAYLOAD` = **0x14 = 20 bytes**. A MCU **já recebe 20 bytes** de payload hoje: os 6 explícitos mais 14 zeros. |
| 2 | "`cause`/`depth`/`hand` ficam em `+0x0E/+0x0F/+0x10` **do payload**" | O mais provável é que esses offsets sejam **da mensagem inteira, cabeçalho incluído**. O cabeçalho ICC tem 0x0C bytes: `magic@0 major@1 minor@2 unknown@4 cookie@6 length@8 checksum@0xA`, o que a descompilação Orbis `dc528600` confirma (`length` em +8, primeiro byte de payload em +0xC). Então `msg+0x0E/0x0F/0x10` = `payload[2]/[3]/[4]`, e o payload atual `{0,0,2,0,1,0}` **já põe `cause=2, depth=0, hand=1` exatamente nesses offsets**. O patch proposto antes (`command[0x0E]=1 …` dentro do payload) escreveria em `msg+0x1A`, **fora da estrutura**, e ainda trocaria `cause` de 2 para 1. |
| 3 | "pré-sync = ICC 4/4 **sem payload**" | Em `dc528600` (`icc_power` dispatcher), o Orbis envia 4/4 com **`payload[0]=1`**, e isso acontece **na inicialização do serviço de power** (junto do registro dos handlers), **não no shutdown**. Não existe evidência de que 4/4 faça parte da sequência de S5. |
| 4 | "3ª etapa: 4/1 de finalização/confirmação" | Não há evidência no acervo. O pseudocódigo da versão anterior **nem implementava** essa etapa, então seção 1 e seção 3 se contradiziam. |
| 5 | "apcie usa `{0,1,2,0,1,0}` no shutdown" | Errado. `icc_shutdown` do apcie também usa `{0,0,2,0,1,0}`. `{0,1,2,0,1,0}` é o **`icc_reboot`** (`ps4-apcie-icc.c:421`). Ou seja, `payload[1]` é que escolhe off (0) ou reboot (1). |
| 6 | BACKLOG: "o código do driver ICC **já tem** o payload corrigido (20 B + pré-sync + final)" | **Falso para a árvore atual**: `icc_shutdown` continua com o código original de 6 bytes nos dois arquivos. O patch de 2026-07-25 nunca virou `.patch` e foi perdido num `git reset --hard`, o mesmo padrão do incidente do SATA. |
| 7 | "dmesg pós-boot não mostrou log do S5" (usado como indício) | Isso é esperado: o `dmesg` do boot seguinte **não guarda** o log do boot anterior. Não serve de evidência de nada. |
| 8 | A fonte do RE (`icc_power_shutdown` @ `0x1d8a3c`) | **Não existe nenhum arquivo** no repo com essa descompilação: `grep` por `1d8a3c` só acha o BACKLOG e este plano, e não há linha correspondente em `decompiled_functions`. `others/rea/acpi/INDEX.md` aponta `icc_power_dc528760.txt` como "icc_power_shutdown", mas esse arquivo é o dispatcher de init (`dc528600`), não o shutdown. **A evidência dos 20 bytes/offsets é inverificável hoje.** |
| 9 | Patch nos dois arquivos (bpcie + apcie) | No Baikal só o `bpcie` faz probe (`ps4-apcie.c:368` só aceita Aeolia/Belize), então só o `icc_shutdown` do bpcie vira `pm_power_off`. Mexer no apcie é risco sem como testar, já que não há hardware Aeolia/Belize. |

**Consequência:** o teste de 2026-07-25 (payload "de 20 bytes") já **falhou** com o mesmo sintoma. Repetir a mesma ideia sem saber por que falhou viola a regra "não iniciar nova tentativa até entender completamente por que a anterior falhou" (AGENTS.md). O payload provavelmente **não** é a causa raiz. Ver a hipótese principal abaixo.

---

## 1. Contexto e Problema

| Componente | Estado após `poweroff -f` |
|---|---|
| Linux OS | ✅ Para (SSH/ping caem) |
| Luz azul | ❌ Acesa/pulsando |
| Fan | ❌ Ligado |
| S5 | ❌ Não atingido |

Código atual (`kernel/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c:404`):
```c
static void icc_shutdown(void)
{
	uint8_t command[] = { 0, 0, 2, 0, 1, 0 };
	if (bpcie_status() != 1)
		return;                       // retorna em silêncio, sem log
	bpcie_icc_cmd(4, 1, command, sizeof(command), NULL, 0);
	mdelay(3000);
	WARN_ON(1);
}
```
Ele é registrado em `pm_power_off` (`ps4-bpcie-icc.c:547`).

---

## 2. Hipóteses (ordenadas por evidência)

### H1 — o `icc_shutdown` roda num contexto onde o ICC não funciona (PRINCIPAL)
Caminho real no kernel 7.0: `kernel_power_off()` → `machine_power_off()` → `native_machine_power_off()` → `machine_shutdown()` → `do_kernel_power_off()` → `atomic_notifier_call_chain` → `legacy_pm_power_off()` → `icc_shutdown()`.

`native_machine_shutdown()` (`arch/x86/kernel/reboot.c:719`) faz, **antes** de chegar no `pm_power_off`:
- `clear_IO_APIC()`
- `local_irq_disable()` + `stop_other_cpus()`
- `lapic_shutdown()`, que desliga o Local APIC: **nenhuma interrupção é entregue, nem a de timer**
- `hpet_disable()`

E o handler é chamado por uma **atomic** notifier chain, mas `bpcie_icc_cmd()` faz:
- `mutex_lock()`, que **pode dormir** em contexto atômico;
- `wait_event_timeout(..., HZ*15)`, que espera a IRQ de reply do ICC. Essa IRQ **nunca chega** porque o LAPIC está desligado, e com o timer parado o `jiffies` **não avança**, então o timeout de 15 s pode **nunca expirar**.

Resultados possíveis: `BUG: scheduling while atomic`, travamento dentro do `wait_event_timeout`, ou o `mdelay`/`WARN_ON` nunca alcançados. **Isso bate com o sintoma**: o SO "some", mas a CPU fica presa e a plataforma continua energizada.

Ressalva: o doorbell (`BPCIE_ICC_SEND`) é escrito **antes** da espera, então a MCU talvez receba o comando mesmo assim. Se ela recebe e **não** desliga, então H2/H3 passam a ser relevantes. A Fase 0 separa os dois casos.

### H2 — o conteúdo do comando está errado para o Baikal
O payload `{0,0,2,0,1,0}` vem do driver fail0verflow (Aeolia). No Baikal pode ser diferente. Hoje **não há** RE verificável do shutdown do Orbis (ver correção #8).

### H3 — o Orbis faz mais coisa antes do 4/1 (ex.: desligar subsistemas via ICC, avisar a EAP)
Não há evidência no acervo. Só vale investigar se H1 for descartada e H2 não resolver.

---

## 3. Plano revisado

### Fase 0 — Diagnóstico com o baseline atual (sem build, sem patch)
Objetivo: descobrir **onde** o shutdown para. Custo: um power cycle.

1. Fazer deploy do baseline `20261116-keep-mode-aplicado`. O bootargs dele **já tem** `console=uart8250,mmio32,0xC890E000`, e o console 8250 é síncrono, então funciona com IRQ desligada.
2. No host: `./others/scripts/uart_start.sh 300 s5-fase0`.
3. Bootar, entrar por SSH (`192.168.6.128`), subir o nível de log: `echo 8 > /proc/sys/kernel/printk`.
4. `sync && poweroff -f`.
5. Ler o log UART e classificar:
   - Aparece `icc: interrupted or timeout` / `scheduling while atomic` / `WARNING ... icc_shutdown`? Isso diz se o código chegou ao `WARN_ON` (3 s depois do envio) ou travou antes.
   - Não aparece nada depois de `reboot: Power down`? Então trava no `mutex_lock`/`wait_event_timeout` (H1) ou `bpcie_status()!=1` (improvável).
   - **Observar o LED/fan logo depois do envio**: se mudam de estado, a MCU recebeu o comando.

### Fase 1 — Testar o comando ICC pelo userspace (sem build)
O driver expõe o chardev `icc` (`register_chrdev(ICC_MAJOR, "icc")`, ioctl `ICC_IOCTL_CMD`, `ps4-bpcie-icc.c:554`). Nesse caminho o comando roda **com IRQs e LAPIC vivos**, então o reply da MCU chega normalmente.

1. Ferramenta pronta (2026-11-16): `others/tools/icc_cmd/` (`./build.sh`, binário estático). Primeiro `icc_cmd selftest` (2/6, versão do FW), depois `icc_cmd s5 --yes`. O layout de `struct icc_cmd` é conferido por `_Static_assert` (40 bytes, igual ao kernel x86_64). Ver o README da ferramenta.
2. No PS4: `sync; mount -o remount,ro /` e então rodar a ferramenta (o console pode desligar na hora: é o objetivo).
3. Interpretação:
   - **Desliga (luz apaga, fan para)** → o payload está **certo**. H1 confirmada, e a correção é **só de contexto** (Fase 2A).
   - **Não desliga e o reply chega** → registrar o reply (código de status), porque H2 ganha força. Só então vale investigar o payload: recuperar/refazer a RE real do shutdown Orbis, gravar o `.txt` em `others/rea/acpi/decompiled/` e registrar em `decompiled_functions`.
   - **Timeout** → problema no próprio canal ICC 4/x. Comparar com os comandos 4/0x38 (GBE) que funcionam e exigem retry.
4. Registrar o resultado em `test_history` (`ps4_hardware_memory.db`).

⚠️ Não varrer valores de `payload` às cegas (ver a regra "NUNCA varrer ICC minors com data=1"). Testar só payloads com origem conhecida (driver fail0verflow, RE).

### Fase 2A — Patch de contexto (se a Fase 1 desligar o console)
Trocar o envio feito no `pm_power_off` por um que funcione em contexto atômico. Opções, da menos para a mais invasiva:

1. **Registrar o power-off cedo**, enquanto IRQs e scheduler ainda estão vivos: `register_sys_off_handler(SYS_OFF_MODE_POWER_OFF_PREPARE, …)`. Ordem conferida em `kernel/reboot.c`: `kernel_power_off()` → `kernel_shutdown_prepare()` (reboot notifiers + **`device_shutdown()`**, que faz o flush dos discos) → **`do_kernel_power_off_prepare()`** (*blocking* chain, pode dormir, IRQs/LAPIC vivos) → `migrate_to_reboot_cpu()` → `syscore_shutdown()` → `machine_power_off()`. O `bpcie` **não tem `.shutdown`** (`ps4-bpcie.c:526`, só `.remove`), então o `device_shutdown()` não derruba o ICC. Esse ponto é, portanto, depois do flush e antes do LAPIC desligar. **Não** usar `register_reboot_notifier`: ele roda **antes** do `device_shutdown()`, ou seja, antes do flush.
2. **Envio por polling** no `pm_power_off`: uma variante `bpcie_icc_cmd_atomic()` que não pega o mutex (o sistema já está single-CPU), escreve request + doorbell e faz poll de `REPLY + BUF_FULL` com `udelay`, com timeout em iterações em vez de `jiffies`. Mais robusto, porém mais código.

Recomendação: **opção 1** (menos código, contexto correto). Deixar a opção 2 como fallback, e manter o `pm_power_off` antigo só como rede de segurança.

Escopo: **só `ps4-bpcie-icc.c`**. Manter o `apcie` intacto (sem hardware para validar).

Toda variante deve logar com `pr_emerg` (para garantir a saída na UART) antes e depois do envio, além do código de retorno e do reply.

### Fase 2B — Payload (só se a Fase 1 mostrar que o comando é rejeitado)
Bloqueada até existir RE verificável no repo. **Não** usar o layout "cause em payload+0x0E" da versão anterior deste plano (ver correção #2).

### Fase 3 — Patch, build e deploy (procedimento oficial do AGENTS.md)
1. `git reset --hard` na árvore, aplicar os patches que o build já aplica (em especial o `ps4-icc-rtc-wrapper.patch`, que **também mexe em `ps4-bpcie-icc.c`**: o novo patch tem de ser gerado **depois** dele e aplicado **depois** dele no script, senão o contexto falha), editar, compilar isolado:
   `make CC="ccache clang" LLVM=1 ARCH=x86_64 drivers/ps4/ps4-bpcie-icc.o`
2. `git diff HEAD -- drivers/ps4/ps4-bpcie-icc.c > kernel/patches/ps4-icc-s5-shutdown.patch` (nunca escrever à mão), excluindo os hunks do RTC wrapper.
3. Resetar, reaplicar a cadeia e `git apply --check` no patch novo.
4. No `kernel/00-build-kernel-7.0.sh`, **depois** do bloco `PATCH_RTC`, seguir o padrão existente:
   ```bash
   PATCH_S5="$SCRIPT_DIR/patches/ps4-icc-s5-shutdown.patch"
   [ -f "$PATCH_S5" ] || { echo "❌ ERRO: $PATCH_S5 não encontrado"; exit 1; }
   if ! git apply --check "$PATCH_S5" 2>/tmp/s5_patch_check.log; then
       echo "❌ Falha no --check do patch S5"; cat /tmp/s5_patch_check.log; exit 1
   fi
   git apply "$PATCH_S5" || exit 1
   ```
5. `sudo ./00-build-kernel-7.0.sh 20261116-s5-poweroff-fix`. A tag precisa dos 4 artefatos: reaproveitar o initramfs/bootargs de `20261116-keep-mode-aplicado` **por `cp` explícito**, conferindo que o bootargs mantém a UART.
6. `sudo ./deploy-boot-7.0.sh 20261116-s5-poweroff-fix` (seguir o checklist pré-deploy do AGENTS.md).

### Fase 4 — Validação
```bash
./others/scripts/uart_start.sh 300 s5-poweroff-test   # antes de ligar o PS4
# boot → SSH 192.168.6.128
sshpass -p ps4 ssh root@192.168.6.128 "echo 8 > /proc/sys/kernel/printk; sync && poweroff -f"
# observar LED e fan; depois:
./others/scripts/uart_stop.sh
```

| Verificação | Esperado |
|---|---|
| Log UART | Linhas `pr_emerg` do patch: envio, retorno ≥ 0 e reply, sem `scheduling while atomic` |
| Luz azul | Apagada (não pulsando) |
| Fan | Parado |
| Boot seguinte | Liga normal pelo botão. Na Orbis: sem aviso de "desligamento incorreto" (anotar se aparecer) |
| `shutdown -h now` (via systemd) | Mesmo resultado do `poweroff -f` |
| `reboot` | Não regrediu (o Baikal não tem `icc_reboot` no bpcie; registrar o comportamento atual) |

---

## 4. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| A ferramenta de userspace (Fase 1) desliga o console com o FS montado rw | `sync` + `mount -o remount,ro /` antes. O HD é de teste. |
| O comando 4/1 com payload desconhecido provoca um estado ruim na MCU | Só payloads de origem conhecida. Se acontecer, puxar o cabo de força resolve o power cycle. |
| Enviar o comando "cedo" (Fase 2A.1) corta a energia antes do flush do disco | Usar `POWER_OFF_PREPARE`, que roda depois do `device_shutdown()` (conferido). Nunca usar o reboot notifier. |
| Patch novo conflita com `ps4-icc-rtc-wrapper.patch` | Gerar o patch depois do RTC e aplicar na mesma ordem (Fase 3.1/3.4). |
| A UART não mostra nada no final do shutdown | Usar `pr_emerg`. Console 8250 MMIO é síncrono. Conferir `console=uart8250,…` no bootargs da tag. |

## 5. Rollback
`sudo ./deploy-boot-7.0.sh 20261116-keep-mode-aplicado` (só boot, mantém o rootfs). Artefatos confirmados em `distro/boot_referencia/` em 2026-11-16.

## 6. Depois da validação
1. Commit real no git (patch + script + docs). Ver a regra dos gatilhos de commit.
2. `distro/scripts/promote-release.sh 20261116-s5-poweroff-fix`.
3. `MARCOS_CONSOLIDADOS.md`: marco "S5 Power-Off funcional", com a causa raiz real (contexto ou payload).
4. `BACKLOG.md`: fechar o item `[~] S5 incompleto` e corrigir as linhas que dizem que o código "já tem o payload de 20 bytes" (178, 237, 276, 389, 491).
5. `test_history` no SQLite: resultados das Fases 0, 1 e 4.

## 7. Referências
- Driver: `kernel/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c` (`_bpcie_icc_cmd` ~170, `icc_shutdown` 404, `pm_power_off` 547, chardev 554)
- Cabeçalho/limites ICC: `kernel/kernel_build_7.0/drivers/ps4/aeolia-baikal.h` (`icc_message_hdr`, `ICC_MIN_SIZE`, `ICC_TIMEOUT`)
- Caminho de poweroff: `kernel/kernel_build_7.0/kernel/reboot.c` (`do_kernel_power_off`, `legacy_pm_power_off`), `arch/x86/kernel/reboot.c:719` (`native_machine_shutdown`)
- RE: `others/rea/acpi/decompiled/icc_power_dc528760.txt` (`dc528600`: init do serviço de power, 4/4 com `payload[0]=1`). **Não há** descompilação do shutdown (`0x1d8a3c`) no repo.
- BACKLOG: `### [~] S5 incompleto no poweroff -f`
- UART: `others/scripts/uart_start.sh`, `uart_stop.sh`

---

## 9. Execução de 2026-11-16 — resultado e crítica

**Tag:** `20261116-btf-disabled-s5` (bzImage/config 15:39, initramfs/bootargs 16:25). Patch: `kernel/patches/ps4-icc-s5-shutdown.patch` (**não commitado**).

**Resultado ao vivo (relato do usuário):** `poweroff -f` → Linux desligou normalmente, monitor apagou, **luz azul continuou acesa e fan continuou ligado**. É o mesmo sintoma do teste de 2026-07-25. **S5 não atingido.**

**Por que o resultado não ensina nada sobre o payload:**
1. **Fase 0 sem dado:** `others/tests/uart_logs/s5-fase0_20261116_145019.bin` = 296.137 bytes `0x20` + 1 `0x00`. É a UART censurada do Orbis, **nenhuma linha do Linux**. A captura `s5-test-btf-disabled_20261116_162844` tem **0 bytes**. Sem log, não dá para saber se o `icc_shutdown` rodou, travou ou retornou cedo.
2. **O patch implementou a versão refutada na §0:** campos em `payload[0x0E..0x10]` (= `msg+0x1A`), deixando zerados `payload[2..4]`, onde o código original punha `cause=2, depth=0, hand=1`. `depth` mudou de 0 para 1 sem fonte. Adicionou o 4/4 "pré-sync" e um 4/1 "ack" (`payload[0]=1`) sem evidência. Também mexeu no apcie.
3. **Possível regressão de envio:** o patch faz `return` se o 4/4 falhar. No contexto do `pm_power_off` (LAPIC desligado, cadeia atômica, ver H1), o 4/4 tende a dar timeout ou travar, e então **o 4/1 nem chega a ser enviado**. O código antigo sempre tocava o doorbell do 4/1. Ainda adicionou `msleep()` em contexto atômico.
4. ~~Config fora do script / sem snapshot~~ — **CORREÇÃO:** essa afirmação estava errada. O `00-build-kernel-7.0.sh` **desliga o BTF** (`scripts/config --disable CONFIG_DEBUG_INFO_BTF`/`_MODULES`, linhas ~804-805; o comentário acima delas, que diz "BTF LIGADO", está desatualizado). O config da tag é reproduzível e o snapshot existe (`kernel/snapshots/kernel-src-20261116-20261116-btf-disabled-s5.tar.zst`). **BTF desligado é o estado atual do projeto.**
5. Os comentários do patch afirmam "per Orbis RE (2026-07-30)" e "6 bytes truncated". **Ambos não se sustentam** pelo repo (ver §0).

**Decisões:**
- **Não promover** `20261116-btf-disabled-s5`. **Não commitar** o patch como está. Remover o bloco `PATCH_ICC_S5` do `00-build-kernel-7.0.sh` (ou trocá-lo por um patch da Fase 2A) antes do próximo build oficial.
- **Próximo teste:**
  1. Fase 0 refeita: iniciar a captura UART **já no Linux**, depois do SSH subir, com uns 60 s. Antes, conferir que a UART mostra o Linux (`echo s5-teste > /dev/kmsg` precisa aparecer no log).
  2. Fase 1: 4/1 com `{0,0,2,0,1,0}` pelo ioctl do `/dev/icc`, com IRQs vivas. É o teste que separa H1 (contexto) de H2 (payload).

---

## 10. Fase 1 — 2026-11-16: ✅ SUCESSO (H1 confirmada)

**Procedimento:** kernel em execução `20261116-btf-disabled-s5` (irrelevante, o ioctl não passa pelo `icc_shutdown`). Ferramenta `others/tools/icc_cmd/` (sha256 `c1487a6f…c533`).
1. `icc_cmd selftest` (2/6, versão do FW) → `ioctl ok`, reply de 46 bytes. O canal ICC pelo chardev funciona.
2. `sync` (o `mount -o remount,ro /` **falhou**: "mount point is busy") → `icc_cmd s5 --yes` → 4/1 com `00 00 02 00 01 00`.

**Resultado (relato do usuário):** **desligou totalmente**: luz azul apagada e fan parado. O ioctl nem chegou a retornar, porque a energia caiu antes do reply.

**Conclusões:**
- **O payload original está certo para o Baikal.** Os offsets `+0x0E/+0x0F/+0x10` "do payload" e a sequência 4/4 → 4/1 → 4/1 ficam **refutados** em definitivo (§0 #2–#4).
- **Causa raiz = H1:** o `icc_shutdown` roda no `pm_power_off`, depois de `lapic_shutdown()` e numa cadeia atômica. Lá o `bpcie_icc_cmd` (mutex + `wait_event_timeout` por IRQ) não funciona.
- **Correção = Fase 2A, opção 1:** enviar o mesmo 4/1 num handler `SYS_OFF_MODE_POWER_OFF_PREPARE` (depois do `device_shutdown()`, com IRQs vivas, cadeia *blocking*). Nenhuma mudança de payload. Manter o `pm_power_off` antigo como rede de segurança.

**Pendências deste teste:**
- A captura UART `s5-fase1-ioctl_20261116_164511` teve **0 bytes**. O adaptador não recebeu nada. Conferir cabo/porta antes da validação da Fase 2A.
- O rootfs desligou montado `rw` (o `sync` foi feito antes). Conferir no próximo boot se o `fsck` passou limpo.

---

## 11. Fase 2A — patch `ps4-icc-s5-poweroff-prepare.patch` (2026-11-16)

**Arquivo:** `kernel/patches/ps4-icc-s5-poweroff-prepare.patch`. Só `drivers/ps4/ps4-bpcie-icc.c`; apcie intocado.

**O que faz:** registra `icc_poweroff_prepare()` com `register_sys_off_handler(SYS_OFF_MODE_POWER_OFF_PREPARE, SYS_OFF_PRIO_DEFAULT, …)` no `bpcie_icc_init()` (e o desregistra no `bpcie_icc_remove()`). O handler manda o **mesmo** 4/1 `{0,0,2,0,1,0}` validado na Fase 1, loga com `pr_emerg` antes e depois e espera 5 s com `msleep`. Se a energia não cair, segue para o `pm_power_off`/`icc_shutdown` antigo, que fica **intocado** como rede de segurança.

**Validação (procedimento do AGENTS.md):**
- Compilação isolada `drivers/ps4/ps4-bpcie-icc.o` com `W=1`: **0 warnings**, `register_sys_off_handler`/`unregister_sys_off_handler` referenciados.
- Patch gerado por `git diff` (base = HEAD + `ps4-icc-rtc-wrapper.patch`, o único outro patch que toca esse arquivo).
- `git apply --cached --check` num índice temporário, a partir de HEAD, na ordem do build (`ps4-icc-proc-debug` → `ps4-icc-rtc-wrapper` → este): **OK**. O conteúdo final é **idêntico** ao arquivo compilado.

**Pendente:**
1. Incluir o patch no `00-build-kernel-7.0.sh` (lista do preflight + bloco `git apply --check`/`exit 1`, **depois** do `PATCH_RTC`). Adiado porque havia um build oficial (`20261116-dma-test`) rodando: editar um script bash em execução pode corromper o run.
2. Build oficial pelo `00-build-kernel-7.0.sh` (BTF **desligado**, como o script já faz) → tag única `20261116-s5-dma`, junto com o harness DMA→SPM. Deploy, UART conferida (`echo s5-teste > /dev/kmsg` visível), `sync && poweroff -f`, `shutdown -h now` e `reboot`.
3. Aceite: luz apaga e fan para, e a UART mostra `icc: S5 (power-off prepare): enviando ICC 4/1`.

---

## 12. Validação da Fase 2A — 2026-11-16: ✅ SUCESSO

- **Kernel:** `20261116-s5-dma` (build oficial pelo `00-build-kernel-7.0.sh`, com o patch `ps4-icc-s5-poweroff-prepare.patch`). Módulos instalados por `install-modules-7.0.sh`, initramfs por `rebuild-initramfs-7.0.sh`, deploy por `deploy-boot-7.0.sh`.
- **Teste:** `sync; poweroff -f` via SSH às 17:56:57. `Powering off.`, SSH caiu em ~7 s, ping parou.
- **Resultado (confirmado pelo usuário):** **desligamento total**: luz azul apagada e fan parado. Primeiro S5 completo do Linux no PS4 Baikal. `test_history` id 91.
- **Causa raiz, para registro:** o comando ICC 4/1 `{0,0,2,0,1,0}` sempre esteve certo. O `icc_shutdown` original rodava no `pm_power_off`, depois do `lapic_shutdown()` e numa cadeia atômica, onde o `bpcie_icc_cmd()` (mutex + espera por IRQ) não funciona. Enviar o mesmo comando em `SYS_OFF_MODE_POWER_OFF_PREPARE` resolve.
- **Não verificado:** a UART não mostrou as linhas `pr_emerg` do handler. O console serial do Linux se desliga com 0,63 s de boot (só o `tty0` fica como console), problema anterior e independente deste.
- **Pendente:** testar `shutdown -h now` (systemd) e `reboot`; promover a tag.
