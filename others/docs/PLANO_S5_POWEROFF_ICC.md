# Plano — S5 Power-Off via ICC (PS4 Baikal)

**Data:** 2026-11-16 (revisado em 2026-11-16, contra o código-fonte e o acervo de RE)
**Status:** 🟡 Em revisão. **Nada implementado.** Antes de qualquer patch é preciso rodar a Fase 0 (diagnóstico, sem build).
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

1. Escrever uma ferramenta mínima de userspace (em `others/tools/harness/`) que envia `major=4, minor=1, payload={0,0,2,0,1,0}` via `ICC_IOCTL_CMD` e imprime o reply. Antes de rodar, conferir o layout de `struct icc_cmd` em `aeolia-baikal.h`.
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
