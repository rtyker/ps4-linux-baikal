---
name: orbis-payload-sequencia-boot-capturada-live-2026-07-28
description: Sequência completa e real (capturada via UART ao vivo) do boot payload Orbis original — arm do kexec, kill/unmount do SceSysCore, handshake ICC de shutdown, fix_acpi_tables() e quiesce de hardware — antes não tínhamos essa ordem confirmada em execução real, só por leitura de código-fonte.
metadata:
  type: project
---

# Sequência completa do boot payload Orbis→Linux (capturada ao vivo, 2026-07-28)

Durante um power cycle de rotina (recuperando de erros `Fatal fail(-6)`/`Fatal fail(-4)` do
GoldHEN, não relacionados ao conteúdo desta memória), foi capturado via UART TTL um log
completo do boot padrão via payload Orbis (`linux-1024mb.bin`, NÃO é `kexec` nativo — é o
mecanismo original de `ps4-linux-payloads`). É a primeira vez que temos essa sequência
confirmada em execução real, não só por leitura de `linux_boot.c`/`acpi.c`. Arquivo bruto
não preservado (log de rotina, mas o texto relevante foi extraído e está documentado
abaixo).

## Fase 1 — "Arm" (equivalente a `kexec -l`, mas dispara na hora que o payload roda)

```
kernel_init()
Kernel base = ffffffff8c248000
Direct map base = ffff871100000000
Installing sys_kexec to system call #153
sys_kexec invoked
```

Payload carregado pelo GoldHEN a partir de `/data/payloads/linux-1024mb.bin` (nome do
arquivo confirma variante "1024mb" de VRAM). Banner do payload:
```
PS4 Linux Payloads AIO
FW 12.52 (1252)
VRAM 1024 MB
Southbridge: Baikal
```

**Firmware do GPU é extraído/copiado NESTA fase** (antes do shutdown do Orbis, ainda com
o SO rodando normalmente):
```
firmware_extract: Extract lib/firmware/amdgpu/gladius_pfp.bin  → NOP handler at 0xff0
firmware_extract: Extract lib/firmware/amdgpu/gladius_me.bin
firmware_extract: Extract lib/firmware/amdgpu/gladius_ce.bin   → NOP handler at 0x7f0
firmware_extract: Extract lib/firmware/amdgpu/gladius_mec.bin  → NOP handler at 0xff0
firmware_extract: Extract lib/firmware/amdgpu/gladius_mec2.bin → NOP handler at 0xff0
firmware_extract: Extract lib/firmware/amdgpu/gladius_rlc.bin
firmware_extract: Extract lib/firmware/amdgpu/gladius_sdma.bin
firmware_extract: Extract lib/firmware/amdgpu/gladius_sdma1.bin
```
(Complementa a descoberta já registrada em `marco-2026-07-23-gpu-gladius-firmware-real.md`
— agora com a ordem exata de extração e os offsets de "NOP handler" usados no patch de
cada blob.)

Depois: `kernel_hook_install(...)`, mensagem final de "armado":
```
kexec successfully armed. Please shut down the system.
```
Ou seja, **o payload não faz o kexec na hora** — ele só prepara tudo e espera o Orbis
desligar normalmente (via `reboot(4000)` do próprio SO), que é quando o hook realmente
dispara o jump. Isso explica por que o processo é "shutdown normal do Orbis" e não um
salto instantâneo.

## Fase 2 — Shutdown normal do Orbis (SceSysCore mini)

```
[SceSysCore mini] killall timeout 5[sec]...
[SceSysCore mini] forcibly unmount 2 nullfses
[SceSysCore mini] forcibly unmount /mnt/usb0
[SceSysCore mini] call reboot(4000)
```
Sequência de `REGMGR` e espera pelos processos de sistema pararem (com timeout de 60s
cada): `SceVnlru`, `SceBufdaemon0/1/2`, `SceSyncer` — com `sched_sync: flush softdep`
aparecendo no meio. Termina em `All buffers synced.` e `Uptime: 3m42s` (tempo de vida do
Orbis antes desse shutdown específico).

## Fase 3 — Handshake ICC de shutdown (NOVO, relevante para o bug de S5/poweroff)

Logo antes de `fix_acpi_tables()`/quiesce, aparece uma sequência de comandos ICC que
**não tínhamos documentada com esse nível de detalhe antes** (só tínhamos o código-fonte
do lado Linux em `icc-shutdown-s5-incompleto.md`, que é um handler DIFERENTE —
`icc_shutdown()` do driver `ps4-bpcie-icc.c`, chamado por `poweroff -f` DENTRO do Linux
já rodando). Esta aqui é a sequência do **lado Orbis**, native, antes do kexec:
```
icc post sync:Thermal alert LED off
Change memory pstate to MM failed(19)
[REGMGR] 000007 @2@ ...
icc08-4001 0802
icc:failed to disabled reset button notification: 0005
icc:disabled thermal notification
eth0: link state changed to DOWN
ICC: howto:00004000 depth:2 cause:00 hand:01
ICC: Shutdown.
hook_icc_query_nowait called
ICC 05-00 polling
```
Notas:
- `Change memory pstate to MM failed(19)` é um erro não-fatal que aparece sempre nesse
  ponto (não impede o boot) — vale ter isso registrado para não confundir com sintoma
  novo em testes futuros.
- `icc08-4001 0802` e `ICC 05-00` são comandos ICC com formato `major-minor payload`
  (mesmo padrão de `major=4,minor=1` documentado em `icc-shutdown-s5-incompleto.md`, mas
  aqui são comandos DIFERENTES: `08-4001` e `05-00` — sugere um protocolo mais amplo de
  handshake do que só o comando de power-off, com pelo menos "desabilitar notificação de
  botão reset" e "desabilitar notificação térmica" como passos deste handshake ANTES do
  desligamento real.
- `hook_icc_query_nowait called` confirma em execução real o nome de função já lido em
  `linux_boot.c` — é aqui que, segundo o código-fonte, `fix_acpi_tables()` é disparado
  (ver próxima seção).
- **Relevância para o bug de S5 pendente:** esse handshake ICC do lado Orbis (que
  desliga notificações de botão/térmica e faz um "ICC: Shutdown." antes do kexec) é bem
  mais rico que o único comando `major=4/minor=1` que o driver Linux `icc_shutdown()`
  envia em `poweroff -f`. É bem possível que o `poweroff -f` do Linux não complete o S5
  real (luz azul persiste) justamente por pular esses passos intermediários (desabilitar
  notificações de reset/térmica primeiro) que o Orbis faz antes do comando final. **Vale
  investigar se o driver ICC do Linux (`ps4-bpcie-icc.c`) tem comandos equivalentes a
  `major=8,minor=0x40`-ish e `major=5,minor=0` disponíveis**, e testar enviá-los antes do
  comando de shutdown final.

## Fase 4 — `fix_acpi_tables()` e quiesce de hardware (confirma código-fonte já lido)

```
Fixing ACPI tables at 0xe0000 (0xffffffffffffffff)
RSDT at 0xe0024
XSDT at 0xe0088
FACP at 0xe016c
FACS at 0xe012c
DSDT at 0xe0430
APIC at 0xe0298
MCFG at 0xe0304
SSDT at 0xe0730
ACPI tables fixed
kexec: Waiting for secondary CPUs...
kexec: Secondary CPUs quiesced
kexec: Setting up GDT...
kexec: Relocating stub...
kexec: Setting up boot params...
kexec: Cleaning up hardware...
Current sb_id: 3
SB_BAIKAL constant: 3
kexec: Detected Baikal Southbridge, disabling IOMMU...
kexec: Reconfiguring VRAM...
kexec: Resetting GPU...
kexec: About to relocate and jump to kernel
```

Confirma em execução real a ordem já lida em `linux_boot.c`/`acpi.c`
(`cpu_quiesce_gate()`): quiesce de CPUs secundárias → GDT/stub → boot params → limpeza de
hardware (com detecção dinâmica de southbridge, `sb_id=3` confirmado = Baikal) →
desabilita IOMMU → reconfigura VRAM → reset da GPU → jump.

**Detalhe notável para a investigação do `kexec` nativo travando (~120s pós-Ethernet,
hipótese xHCI/MSI):** nenhuma linha de log menciona `MSI` ou `xHCI` explicitamente nesta
sequência — `disableMSI()` (visto em `acpi.c`) não imprime nada quando executa, então essa
ausência de log NÃO prova que ele não rodou (é esperado ser silencioso). Não adiciona nem
remove evidência à hipótese de `kexec-nativo-mecanismo-funciona-mas-v5-trava-pos-console-handoff-2026-07-27.md`;
só confirma que a via de boot normal (payload Orbis) sempre passa por esse quiesce
completo antes do jump, o que o `kexec -e` nativo nunca faz — dado já conhecido, agora com
confirmação de execução ao vivo.

## Fase 3 (detalhe adicional) — `eth0: link state changed to DOWN` no meio do handshake ICC

Dentro da Fase 3 acima, entre `icc:disabled thermal notification` e
`ICC: howto:00004000 depth:2 cause:00 hand:01`, aparece:
```
eth0: link state changed to DOWN
```
Esse `eth0` é a interface GBE nativa do **próprio Orbis** (driver Sony `mts`, FreeBSD —
mesma interface que o `netconsole=` do cmdline usa do lado Linux). É a primeira vez que
temos confirmação ao vivo de que essa interface desce exatamente entrelaçada com comandos
ICC (`icc 08-4001 0802`, depois `ICC 05-00 polling` mais adiante) durante o shutdown
controlado do Orbis, antes do quiesce de hardware do kexec.

**Ressalva importante, para não repetir investigação já descartada:** já existe uma
refutação registrada em `baikal-gbe-e-sky2-nao-stmmac.md` (seção "Bloqueio atual") de que
o power-gate da GBE seria feito via `icc_device_power` do EMC (**major=5**) — foi varrido
ao vivo minor a minor (`0x01,0x11,0x21,0x31,0x41...0xf1`) e o candidato GBE (`5 0x41`)
respondeu **NAK idêntico a minor inválido**; a conclusão já registrada é que a rail da GBE
é gerenciada pelo **Syscon**, não pelo EMC via ICC major=5. Os comandos vistos aqui
(`08-4001` e `05-00`) usam majors **diferentes** (`08` e `05`, mas minor `00`, não
`0x41`) — **não é o mesmo comando já testado e descartado**, mas também não há prova aqui
de que estes sejam os comandos que gateiam a rail da GBE; pode perfeitamente ser só o
stack de rede do FreeBSD derrubando a interface administrativamente (down lógico) sem
necessariamente cortar o clock/power físico do PHY.

**Não conclusivo, mas é uma pista nova e barata de seguir:** vale RE (no dump do kernel
Orbis 12.52, `consolidado/dumps_orbis/kmem_dump_1252.bin`, já disponível) em volta do
handler que processa o comando ICC `major=8` (visto aqui como `08-4001`) e o
`major=5,minor=0` (visto como `05-00`, diferente do `5,0x41` já descartado) — se algum
dos dois disparar a queda do `eth0` fisicamente (não só logicamente), seria o comando
real de power-gate da rail Syscon que falta replicar no lado Linux para religar a GBE.

## Referências cruzadas
- [[kexec-nativo-mecanismo-funciona-mas-v5-trava-pos-console-handoff-2026-07-27]] — a
  investigação do `kexec` nativo que motivou esta captura.
- [[icc-shutdown-s5-incompleto]] — o comando ICC equivalente do lado Linux
  (`poweroff -f`), que parece bem mais simples que este handshake do lado Orbis.
- [[marco-2026-07-23-gpu-gladius-firmware-real]] — descoberta original do firmware
  Gladius real; esta memória complementa com a ordem exata de extração/patch.
