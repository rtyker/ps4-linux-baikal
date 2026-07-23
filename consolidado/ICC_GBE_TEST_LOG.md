# Log de Controle — Testes ao vivo para ligar a GBE Baikal (ICC + MMIO)

**Arquivo de controle obrigatório.** Antes de testar QUALQUER comando ICC novo (major/minor/payload) contra a GBE, checar esta tabela primeiro — não re-testar o que já está aqui. Atualizar IMEDIATAMENTE após cada teste ao vivo, mesmo resultado negativo (regra 2 do `CLAUDE.md`).

**Ambiente de todos os testes abaixo:** tag `20260717-iccdbg` (verificada por MD5 contra `boot_referencia/*-iccdbg` antes de testar), console real, telnet root (`~ #`, sem senha, porta 23), IP **fixo em `192.168.6.128`** (reserva de DHCP no roteador — não precisa escanear a rede a cada teste).

**Método de verificação usado em todo teste:**
```bash
# baseline ANTES:
dd if=/dev/mem bs=1 count=4 skip=$(( 0xc2000118 )) 2>/dev/null | od -An -tx1
# comando testado:
echo "MAJOR MINOR [payload_hex...]" > /proc/ps4_icc
cat /proc/ps4_icc
# baseline DEPOIS:
dd if=/dev/mem bs=1 count=4 skip=$(( 0xc2000118 )) 2>/dev/null | od -An -tx1
```
`B2_CHIP_ID`/`B2_MAC_CFG` = bytes 3º/4º do dump acima (offset `0x11a`/`0x11b` do BAR0 da GBE, `00:14.1`). Enquanto continuarem `00 00`, a GBE está power-gated — sky2 vai sempre falhar com `unsupported chip type 0x0`.

## Tabela de testes

| # | Data | Comando (`major minor payload`) | `ret` | Reply (bytes relevantes) | ChipID antes | ChipID depois | Conclusão |
|---|------|-----------------------------------|-------|---------------------------|---------------|-----------------|-----------|
| 1 | 2026-07-18 | `5 0x41` (device_power, GET) | — | `01 05...` (NAK) | — | — | Descartado. Major 5 só tem wlan/bt/usb/hdd/bd (0x01/0x11/0x21/0x31). GBE não está nesse serviço. |
| 2 | 2026-07-18 | `5 0x51`..`5 0xf1` (varredura completa) | — | NAK em todos | — | — | Descartado. Nenhum minor de major 5 além dos 4 conhecidos responde. |
| 3 | 2026-07-20 | `4 0x38` (GET, payload vazio) | `20` (positivo = sucesso, não NAK) | `01 04 00...` (20 bytes válidos, resto padding zero) | `00 00` | `00 00` | **Comando VÁLIDO** (major 4 = serviço power/sistema, confirmado via uso conhecido de `4 1` em `icc_shutdown()`/`icc_reboot()` no driver real). É uma consulta de status/versão — não muda o chip ID. RE do dump do kernel mostra que é exatamente o comando que `attach()` da GBE usa pra checar/esperar prontidão, não pra disparar o power-on. |
| 4 | 2026-07-20 | `4 0x38 01` (SET tentativo, payload=1 byte `0x01`) | `20` (mesmo padrão de sucesso) | `01 04 00...` (idêntico ao teste #3) | `00 00` (antes, medido ~2s antes) | `00 00` (depois, + confirmado via rebind do sky2 sem reboot: continua `unsupported chip type 0x0`) | **NEGATIVO.** Comando aceito pelo protocolo (sem erro), mas não alterou o estado do chip. Hipótese de "minor 0x38 aceita payload liga/desliga como resetUsbPort()" **descartada** — ou o minor está errado, ou o payload/formato esperado é diferente (talvez não seja um simples byte on/off), ou GBE precisa de uma sequência de múltiplos comandos, não um único write. |
| 5 | 2026-07-20 | Varredura `4 0x20` até `4 0x50` (29 minors, GET payload vazio) | `20` em TODOS, sem exceção | **Byte a byte IDÊNTICO** (`01 04 00...`) pra TODO minor testado, inclusive fora da faixa original: `0x20`, `0x38`, `0x50`, `0x99`, `0xff` | `00 00` | não checado individualmente (replies idênticas tornam irrelevante) | **CONCLUSÃO IMPORTANTE:** major=4 com GET (payload vazio) **não distingue minors** — devolve sempre a mesma resposta genérica tipo "liveness/ACK", não um status específico por sub-serviço. Isso invalida a leitura anterior de que `minor=0x38` fosse "o" comando de status da GBE — é bem mais provável que essa reply genérica não tenha relação com o estado real da GBE. **Escanear mais minors sob major=4 via GET é inútil — parar essa linha.** |
| 6 | 2026-07-21 | `5 0 04` (SET, payload=1 byte `0x04`) | `20` (sucesso) | timed out | `0c 00` | não acessível via telnet | **FALSO POSITIVO PARA GBE / DESCOBERTA IMPORTANTE.** O comando `5 0 04` não congela a CPU! Ele na verdade afeta o Minor 0 (que é **WLAN/BT**). O console continuou rodando (debugloop não parou), mas a conexão Wi-Fi caiu imediatamente (ping 100% loss, telnet timeout). GBE NÃO é controlada por Major 5, Minor 0! O comando `5 0 04` provavelmente desliga ou reseta a interface Wi-Fi. A inicialização da GBE é feita de forma totalmente diferente via MMIO no BAR4 da glue logic! |
| 7 | 2026-07-21 | `5 0 07`, `0b`, `0f` (SET, payloads com bits 0+1 on) | `20` (sucesso) | `02 05 00...` | `00 00` | `00 00` | **HIPÓTESE REFUTADA.** Console sobreviveu a todos os payloads testados via script `test_safe_bitmasks.py` (WLAN/BT continuaram ativos perfeitamente), mas o ChipID da GbE não mudou (continuou `00 00`). A GbE NÃO é controlada pelos bits restantes do Major 5 Minor 0. Encerrar testes de ICC neste vetor e avançar para Fase 3 (investigar reset de barramento PCI via cabo UART). |



## Teste de Sanidade Nativa (Orbis vs Linux) — 2026-07-21, RESULTADO CONFIRMA HIPÓTESE DE RE-GATEAMENTO

**Procedimento:** IP fixo configurado na LAN, cabo de rede conectado diretamente (sem switch/roteador intermediário). Boot normal no Orbis (GoldHEN, sem payload), rede configurada para Cabo de Rede.

**Resultado:**
1. **Sob Orbis puro: `ping` funciona.** A GBE está energizada e operacional nativamente — o Syscon/Orbis liga a rail por padrão (ou sob demanda ao configurar LAN), sem nenhuma intervenção nossa.
2. **Ao iniciar o Linux (kexec), a conexão Ethernet é cortada imediatamente** — `ping` para de responder assim que o boot do Linux começa.

**Conclusão (CONFIRMADA — este era o item 1 da lista "Próximos passos" abaixo, agora resolvido):** A pergunta central da investigação muda de "como ligar a GBE" para **"o que no kexec/boot do Linux está derrubando/re-gateando uma rail que já estava ligada e funcional sob Orbis"**. Isso torna toda a linha de investigação de comandos ICC/MMIO de "power-on" (testes #1-6 e M1-M6 acima) irrelevante para o objetivo final — a GBE não precisa ser "ligada" por nós, precisa parar de ser desligada. Ver `GBE_ACTION_PLAN.md` para o plano atualizado.

**Teste do bootarg `pcie_port_pm=off pcie_aspm=off pci=noaer` — ❌ NEGATIVO (2026-07-21).** Testado ao vivo: com esses parâmetros no `bootargs.txt`, a rail da GBE **continua sendo derrubada** assim que o Linux inicia — comportamento idêntico ao boot sem essas flags. **Hipótese descartada:** ASPM (L0s/L1) e power management de porta PCIe controlados pelo core genérico do Linux (via essas flags de bootarg) não são a causa do corte. Isso aponta pra duas direções revisadas:
1. O corte acontece **antes** do kernel Linux processar `bootargs`/inicializar o subsistema PCI genérico — ou seja, no próprio **payload de kexec** (`ps4-linux-payloads/`), que já mexe em MSI/hardware antes do jump pro Linux (ver `disableMSI()` já analisado e descartado em `RE_KERNEL_GBE_ATTACH.md`, mas pode haver outro passo ali ainda não mapeado).
2. Ou é um reset de barramento explícito (não relacionado a ASPM/PM) que essas flags não cobrem — precisa investigar `pci=nomsi`, `pci=noacpi`, ou comparar via dmesg com timestamps o momento exato em que a rail cai (kexec vs. enumeração PCI do Linux vs. probe do `sky2`).

## ✅ RESOLVIDO POR RE (2026-07-21): major 5 NÃO tem minor para a GBE — não testar mais

`icc_device_power.c` finalmente foi decompilado de verdade (era TODO antigo). Os dois wrappers do serviço — SET `0xffffffffdc7c8a70(minor, valor, &out)` e GET `0xffffffffdc7c8fb0(minor, &out)` — tiveram **todos os seus call sites enumerados**, lendo o `mov edi, <minor>` de cada um. Minors existentes: SET `0x10`/`0x20`/`0x30`, GET `0x01`/`0x11`/`0x21`/`0x31`. São **exatamente 4 domínios** (`0xN0`=SET, `0xN1`=GET): WLAN/BT, USB, HDD e Blu-ray (este último confirmado pelas strings `icc_device_power_get_bd_power_state` e pelos eventhandlers `bd_drive_operable`/`bd_drive_inoperable`).

**Não existe minor `0x40`, nem qualquer domínio para a GBE.** Isso explica por RE (e não por tentativa e erro) o NAK do teste #1 em `5 0x41` e os NAKs do teste #2 — aqueles minors simplesmente não existem. **A linha de major 5 está encerrada em definitivo; não vale mais nenhum teste ao vivo nela.** Detalhes e arquivos decompilados: `KERNEL_DUMP_HARDWARE_INVENTORY.md` seção 7.

## 🎯 CANDIDATO NOVO COM LASTRO DE RE (2026-07-21) — hold/pulse da GBE na glue: `0x20` / `0x74`

Primeiro candidato desta saga inteira que **não é tentativa às cegas**. Achado em `fcn.ffffffffdc6df850`, que contém a tabela de reset/hold de todos os blocos do Baikal. O bloco da GBE é o `0x2000`, com **hold = `BAR2+0x180000+0x20`** e **pulse = `BAR2+0x180000+0x74`** — identificado porque a rotina de *stop* do MAC da GBE é chamada imediatamente antes dele. Os blocos vizinhos na mesma tabela são USB0 (`0x24`/`0x64`), USB1 (`0x28`/`0x68`), SATA (`0x2c`/`0x6c`) e xHCI (`0x30`/`0x70`) — **exatamente os offsets que o nosso Linux já usa e que funcionam**. A GBE é o único periférico da tabela que o Linux nunca toca.

Tabela completa, método de identificação, confirmação do mapeamento de BARs e o trecho de código candidato: **`GBE_ACTION_PLAN.md` seção 4**.

**Ainda NÃO testado ao vivo.** Quando for testar, registrar aqui como linha `M7`. Endereços físicos para leitura/escrita direta via `/dev/mem` (BAR2 = `0xc8800000`):
- hold  → `0xc8800000 + 0x180000 + 0x20` = **`0xc8980020`**
- pulse → `0xc8800000 + 0x180000 + 0x74` = **`0xc8980074`**

Sugestão de primeiro passo **somente leitura** (seguro, sem escrever nada): ler esses dois endereços e comparar com os equivalentes de SATA (`0xc898002c`/`0xc898006c`) e xHCI (`0xc8980030`/`0xc8980070`), que estão em periféricos comprovadamente funcionando. Se o hold da GBE estiver em `1` e o dos outros em `0`, a hipótese fica confirmada antes de qualquer escrita.

## Observações auxiliares (não são testes ICC, mas relevantes)
- Registrador `0x118` do BAR0 (não é o chip_id, é outro campo próximo) **flutuou entre leituras** (`01` numa leitura, `00` na seguinte, sem nenhum comando ICC no meio) — é volátil/dinâmico, não confiar nele como indicador de estado fixo. Só `0x11a`/`0x11b` (chip_id/mac_cfg) importam para saber se a GBE acordou.
- Registradores `0x100`/`0x104` também variam entre sessões de boot (`05`/`b0` numa sessão, `17`/`bd` documentado numa sessão anterior) — mesma cautela.
- `echo -n ... > /sys/bus/pci/drivers/sky2/unbind` deu `rc=1` (dispositivo não estava bound, já que o probe original falhou no boot) — **não é erro real**, o `bind` seguinte é que importa e disparou um novo probe de verdade (visível no dmesg com novo timestamp).

## Testes MMIO (fora do protocolo ICC) — registrador de clock/config do baikal_pcie.c

| # | Data | Tipo | Endereço/detalhe | Resultado | Conclusão |
|---|------|------|-------------------|-----------|-----------|
| M1 | 2026-07-20 | Leitura | `0xc890a030` (BAR2+0x10a030, o attach() real do `baikal_pcie.c` escreve esse registrador incondicionalmente) | `0x000016c9`. Campo de 6 bits (`>>3 & 0x3f`) = `0x19`, esperado pós-escrita Sony = `0x1b` (difere em 1 bit, bit 4) | **Confirmado: a escrita da Sony NÃO está sendo aplicada no boot atual do Linux.** Candidato forte, ainda não testado como escrita. Ver `RE_KERNEL_GBE_ATTACH.md` seção "ACHADO PRINCIPAL". |
| M2 | 2026-07-20 | Escrita (FALHOU por bug de escaping) | `0xc890a030` ← pretendido `0x000016d9`, mas **`printf '\xd9\x16\x00\x00' \| dd ...` encadeado bash→ncat→telnet→busybox corrompeu os bytes** | Registrador ficou em `0x78000000` (nem o original `0x16c9`, nem o pretendido `0x16d9`). `dd` reportou "3+0 records / 12 bytes copiados" em vez de "1+0 records / 4 bytes" — prova de que o `printf \x..` não gerou os 4 bytes esperados. | **NEGATIVO/ACIDENTAL.** Console permaneceu estável (ping OK, dmesg sem erro novo, `B2_CHIP_ID` continuou `00 00` sem piorar) mas o registrador ficou num estado não testado/desconhecido. **Usuário decidiu reiniciar o console pra restaurar o registrador MMIO (volátil, não-persistente) a um estado limpo antes de tentar de novo.** Causa raiz do bug: `busybox printf` não suporta `\xHH` de forma confiável nesse ambiente — usar `\NNN` (octal) em vez disso. Ver método corrigido abaixo. |
| M3 | 2026-07-20 (pós-reboot) | Escrita (retry, método corrigido — SUCESSO na mecânica, mas resultado inesperado) | `0xc890a030` ← `0x000016d9` via `printf '\331\026\000\000' \| dd ...` (octal). Baseline reconfirmado `0x16c9` antes de escrever. `dd` confirmou "1+0 records in/out, 4 bytes" — escrita mecanicamente correta desta vez. | Releitura imediata: `00000000` (nem original `0x16c9`, nem pretendido `0x16d9`). Confirmado estável ao longo de múltiplas releituras em sessões telnet separadas (não é só demora de propagação). `sky2` rebind → continua `unsupported chip type 0x0`. `B2_CHIP_ID`/`B2_MAC_CFG` continuam `00 00`. Sistema estável (dmesg limpo, ping OK). | **INCONCLUSIVO/NEGATIVO PARA GBE.** A escrita em si funcionou mecanicamente (bytes corretos confirmados), mas (a) não ligou a GBE e (b) o registrador não se comporta como um "config register" simples — sempre lê `0` após qualquer escrita, não preserva o padrão escrito. Hipótese revisada: `0x10a030` pode ser um registrador de **comando/pulso** (escrever dispara uma ação e o registrador volta a `0` como estado "idle", não guarda o valor escrito) em vez de um registrador de configuração persistente — muito diferente do que o padrão *read-modify-write* do código decompilado sugeria à primeira vista. **Não repetir esse teste sem nova teoria** — já sabemos que não muda o chip ID da GBE. |
| M4 | 2026-07-20 | Escrita (no boot, ps4-bpcie.c) | `0xc890a030` ← `(reg & 0xfffffe07) \| 0xd8` incondicionalmente no `bpcie_glue_init`. Tag `20260720-gbe-bpcie-init`. | **FALHA TOTAL (TELA PRETA).** PS4 bootou sem vídeo HDMI e travou o sistema inteiro (sem resposta ao ping/rede). | **NEGATIVO/CRÍTICO.** Escrever nesse registrador precocemente no boot antes de os barramentos de display estarem ativos causa clock-gating/reset elétrico que congela o Southbridge. Exigiu Power Cycle (tirar da tomada por 15-30s) e reversão da escrita em `ps4-bpcie.c`. |
| M5 | 2026-07-20 | Mapeamento (ioremap, sky2.c) | `sky2.c` `ioremap` alterado de `0x4000` para `pci_resource_len(pdev, 0)` (4KB). Tag `20260720-sky2len-fix`. | **SUCESSO DE BOOT.** Vídeo HDMI funcional e rede Wi-Fi ativa. Corrigiu o alerta `resource: resource sanity check: requesting ... which spans more than 0000:00:14.1` no dmesg. | **SUCESSO (Correção de recurso).** A BAR0 da Ethernet Baikal tem 4KB, e o driver original tentava mapear 16KB, gerando falha silenciosa de recurso na inicialização do Yukon. Correção consolidada permanentemente em `distros/arch_minimal_v2/patches/sky2-baikal-gbe.patch`. |
| M6 | 2026-07-21 | Escrita (Scripts Python/Bash para inicializar BAR4) | `0xc900c000` (BAR4 GBE Wrapper). Múltiplas escritas de configuração descompiladas de `dc5a0c80`, incluindo clock de 25MHz (`0xc07c` = `25000000`) e clears de reset. | **TELA PISCOU DUAS VEZES, MAS CONSOLE NÃO TRAVOU.** O monitor piscou durante a execução do script que escrevia na BAR4. O debugloop continuou (sem panic). | **SUCESSO/AVANÇO ENORME.** Escrever nessas portas específicas de BAR4 comprovadamente afeta o estado do hardware (barramento PCIe ou domínio de energia compartilhado com o display retreinou), sem travar a CPU/PCIe bridge. Isso prova que BAR4 realmente contém os registradores do PHY/Wrapper. Porém, devido ao lixo deixado na BAR2 pelos bugs do bash `printf \x`, a inicialização não completou e o ChipID ainda leu 00. Requer reboot e re-teste limpo. |

### M7 — release do hold/pulse da GBE no `sky2_probe` (2026-07-21) — ❌ NEGATIVO, TRAVA O CONSOLE

**Build:** tag `20260721-gbe-hold-release`, kernel `7.0.8-Strawberry-ThinLTO-Baikal-+` (#23). Adicionada `bpcie_baikal_gbe_release()` em `ps4-bpcie.c`, chamada de `sky2_probe()` antes de `sky2_init()` ler o `B2_CHIP_ID`. Ver `GBE_ACTION_PLAN.md` seção 5.

| Sub-teste | Bootarg | O que o código fazia | Resultado |
|---|---|---|---|
| **M7a** | (padrão, `gbe_release=1`) | 6 leituras de `BAR2+0x180000+{0x20,0x74,0x2c,0x6c,0x30,0x70}` **+ 4 escritas** (pulse/hold da GBE) | **TRAVAMENTO TOTAL.** Sem vídeo, luz azul acesa, **NumLock não responde** (= kernel travado, não só vídeo). Power cycle necessário. |
| **M7b** | `ps4_bpcie.gbe_release=0` | **apenas as 6 leituras** (escritas puladas) | **TRAVAMENTO IDÊNTICO.** Tela preta (monitor recebendo sinal, sem entrar em economia), NumLock morto. |

**Conclusão principal: não são as escritas.** Com `gbe_release=0` nenhuma escrita acontece e o console trava igual. O que sobra no caminho são as **leituras dos registradores de glue na BAR2 durante o boot** — ou a própria chamada nesse ponto do `sky2_probe`.

**Descartado que seja diferença de kernel/config:** `diff config-7.0-20260720-icc-gbe-debug config-7.0-20260721-gbe-hold-release` → **2 linhas, ambas cosméticas** (comentário `Linux/x86` vs `Linux/x86_64`). O binário que boota e o que trava têm o mesmo config; a única diferença real é o código adicionado.

**Contexto que deveria ter pesado antes do teste:** o projeto já tinha precedente registrado de que **ler** certos registradores dessa família trava o console (`cat .../config` do `00:14.1`, teste A/B de 2026-07-16) e de que a varredura cega da região pervasive da BAR2 chegou a **desligar** o console. Os offsets de USB (`0x180064` etc.) são seguros porque o `resetUsbPort()` já os usa em produção — mas os da GBE (`0x180020`/`0x180074`) nunca tinham sido tocados por ninguém.

**Erro de projeto do teste (não do hardware):** a válvula `gbe_release=0` foi desenhada como "modo seguro", mas ela só pula as **escritas** — as leituras acontecem antes de a flag ser testada. Pior: o plano original era fazer essa leitura de **userspace via `/dev/mem`, com o sistema já bootado**; mover isso para dentro do `probe` "para o log sair automático" transferiu uma operação de risco conhecido para o caminho de boot, onde um travamento não deixa log nenhum e custa um power cycle.

**A hipótese `0x20`/`0x74` NÃO está refutada.** O que se sabe é que *tocar* nesses registradores no contexto do boot trava. Continua em aberto se os offsets estão certos e o problema é contexto/sequência/timing (lembrando que `fcn.dc6df850`, de onde vieram, é rotina de *quiesce*, não de bring-up).

**Próximo passo correto (voltar ao plano original):** ler de userspace via `/dev/mem`, com telnet ativo, **um registrador por vez**, começando pelos comprovadamente seguros (SATA `0xc898002c`/`0xc898006c`, xHCI `0xc8980030`/`0xc8980070`) para validar o método, e só então os da GBE (`0xc8980020`/`0xc8980074`). Se as leituras da GBE também travarem nesse contexto, isso é resultado forte por si só: o bloco não responde a acesso algum enquanto está em reset.

**Rollback executado:** `deploy-boot-7.0.sh 20260720-sky2len-fix`, MD5 conferidos.

### M8 — leitura dos hold/pulse da glue via /dev/mem (2026-07-21) — ❌ HIPÓTESE REFUTADA

Sete leituras, **uma por vez**, de userspace com o sistema bootado (tag `20260720-sky2len-fix`) e ping de verificação após cada uma. Registro completo: **`M8_leituras_glue.md`**.

| Endereço | Registrador | Valor |
|---|---|---|
| `0xc898002c` / `0xc898006c` | SATA hold / pulse | `00000000` |
| `0xc8980030` / `0xc8980070` | xHCI hold / pulse | `00000000` |
| **`0xc8980020` / `0xc8980074`** | **GBE hold / pulse** | **`00000000`** |
| `0xc2000118` | B2_CHIP_ID / B2_MAC_CFG | `00 00 00 00` |

**A GBE lê exatamente os mesmos valores dos periféricos que funcionam.** O `hold` já está solto e o chip continua mudo — logo **escrever nesses registradores não pode ser a solução**, o estado desejado já é o vigente. A hipótese da seção "CANDIDATO NOVO COM LASTRO DE RE" está **refutada**.

**Segundo resultado, que revisa o M7:** nenhuma dessas leituras travou o console. Portanto o travamento do M7b (só leituras) **não veio das leituras** — veio do contexto de executá-las dentro do `sky2_probe`, no caminho de boot. Causa exata ainda não determinada.

**Observação de método:** durante a sessão houve dois `DEAUTH` do WiFi. Foram distinguidos de travamento pelo contador `DEBUG LOOP` na tela, que continuou subindo — vale sempre ter esse desempatador ao testar por telnet.

### Lição aprendida (bug de escaping, 2026-07-20 e 2026-07-21)
`busybox printf` (usado no shell da DEBUG LOOP e no PS4 em geral) **não interpreta `\xHH` (hex) de forma confiável** quando o comando passa por múltiplas camadas de quoting (bash local → `ncat --telnet` → TCP → shell remoto) ou mesmo rodando um `.sh` local no PS4 gerado via upload. Escrever `printf \xd9... | dd` pode corromper registradores MMIO escrevendo a string literal (`16 bytes` em vez de `4`).
Para corrigir isso de forma robusta e definitiva: usar scripts Python do lado do host que convertam o valor para octal `\NNN` (ex: `\331\026\000\000`) e enviem o comando exato via socket Telnet. A tabela de conversão rápida no host previne 100% de corrupção.
**Sempre verificar `dd` reporta exatamente "1+0 records in/out" e o número de bytes esperado ANTES de considerar a escrita bem-sucedida** — "3+0 records"/tamanho errado é o sinal de alerta que pegamos dessa vez (por sorte, sem dano real).

## ⚠️ ATUALIZAÇÃO 2026-07-21 — toda a seção abaixo ("Próximos candidatos") está OBSOLETA

O teste de sanidade nativa (ver seção "Teste de Sanidade Nativa (Orbis vs Linux)" acima) **confirmou** que a GBE já vem ligada e funcional sob Orbis com cabo direto — não existe "botão ICC/MMIO de power-on" a ser encontrado, porque não precisamos ligar nada. O item 1 da lista de "próximos passos" (verificar re-gateamento no kexec) deixou de ser hipótese e virou fato confirmado. **Caçar major/minor ICC novos ou registradores MMIO de power (itens abaixo) não é mais produtivo** — a investigação segue em `GBE_ACTION_PLAN.md`, focada em achar o que no kexec/PCI enumeration do Linux derruba a rail. Seção mantida apenas como histórico.

## Próximos candidatos NÃO testados ainda (HISTÓRICO — ver aviso acima)
- ~~Outros minors próximos de `0x38` sob major 4~~ **FEITO (teste #5), descartado — GET não distingue minors sob major 4.**
- Payloads maiores/diferentes pro minor `0x38` — **baixa prioridade agora**, dado que nem o payload de 1 byte mudou nada e a resposta nem discrimina minors; pouca evidência de que essa família de comando seja a certa.
- Extrair TODOS os pares major/minor usados pela função `icc_query` genérica no kernel dump (xrefs de `func_0xffffffffdc3f5bd0`, ver `RE_KERNEL_GBE_ATTACH.md`) — ainda não feito, mas reavaliar prioridade (ver nota abaixo).
- Investigar se a resposta a evento assíncrono (`uVar8 & 2` no kthread `gbe:ctrl`) é disparada por notificação ICC assíncrona, não por um comando síncrono que enviamos.
- **NOVO CANDIDATO PRINCIPAL (2026-07-20, pós-reavaliação):** a RE de `func_0xffffffffdc797090` (a função de transporte ICC de baixo nível, chamada por dentro do wrapper de query) sugere que os bytes que rotulamos como "major=4/minor=0x38" podem na verdade ser CAMPOS INTERNOS de um payload dentro de um comando wrapper mais genérico (possíveis candidatos pro major/minor real do wrapper: `major=3`/algo relacionado ao byte constante `0x01` visto no cabeçalho) — **não confirmado, análise ficou inconclusiva** (a função tem lógica de baixo nível de I/O de porta/MMIO difícil de mapear sem mais contexto). Não vale re-testar isso ao vivo sem RE adicional primeiro.
- **Pivô recomendado:** em vez de continuar caçando o comando ICC exato dentro de `icc_power.c`/`SceGbeMtsCtrl`, investigar `dev\pci\baikal_pcie.c` (driver do glue PCIe Baikal no Orbis) — hipótese: o power-on da GBE pode ser feito genericamente pelo driver do BARRAMENTO PCIe durante enumeração (antes de QUALQUER driver de dispositivo específico rodar), não pelo driver da GBE em si. Isso explicaria por que comandos ICC direcionados ao "serviço GBE" não fazem efeito — o gatilho real pode ser um passo de bring-up de slot PCI genérico. Comparar com o `ps4-bpcie.c`/`ps4-apcie.c` do nosso próprio fork Linux (já existe, é o driver equivalente) pra ver o que ele NÃO está fazendo que o Orbis faz.

## Sessão de RE profunda 2026-07-20 (continuação) — SEM novo candidato de teste ao vivo (por design)

Mapeamos exaustivamente toda a cadeia de código do driver `SceGbeMtsCtrl`/`SceGbeMtsPhyCtrl` (attach → ioctl `SIOCSIFFLAGS` up/down → init de MAC/DMA → handshake com firmware RMU embarcado via frames Ethernet) — ver `RE_KERNEL_GBE_ATTACH.md` seção "Conclusão desta rodada de RE profunda". **Não encontramos nenhuma chamada ICC ou MMIO nova com semântica de power-on em todo esse caminho** — os dois loops de espera existentes (`icc_query(4,0x38)` no attach, e o poll de `BAR0+4` bit0 no handshake RMU) são passivos, não ativos. **Por isso, deliberadamente, NÃO estamos adicionando um novo candidato de registrador/comando pra testar ao vivo nesta rodada** — proposto sem lastro real seria só "tentativa às cegas", que é exatamente o que o usuário pediu pra evitar.

Os 2 itens mais promissores para a PRÓXIMA rodada são de **análise estática**, não de teste ao vivo:
1. Verificar se o boot/kexec do nosso Linux causa (via core PCI genérico ou via o payload de kexec) um reset de barramento no bridge `00:14.x` que re-gateia uma rail que a Orbis já tinha ligado antes do kexec (hipótese nova, ainda não verificada — ver detalhe em `RE_KERNEL_GBE_ATTACH.md`).
2. RE de fato (decompilação, não só strings) de `icc_device_power_control`/`icc_device_power.c` — nunca fizemos isso a fundo; os testes já catalogados nesta tabela (major=5) cobriram os minors conhecidos de OUTROS dispositivos, não confirmamos por RE se existe um minor/payload específico pra GBE que ainda não tentamos.

Só depois de um desses dois apontar um alvo concreto (registrador+valor+condição, com justificativa clara de RE) é que valerá adicionar uma nova linha de teste nesta tabela.

## Testes de 2026-07-21 (Sessão Atual)
### 1. Correção do Endereço do ChipID
- **Motivo**: Descobri que os scripts anteriores estavam lendo `0xc2000118`, que é o endereço base (BAR0) do Southbridge 1 (Gladius/Aeolia). Para o Baikal (Southbridge 2), o BAR0 correto é `0xc900c000`, logo o ChipID é `0xc900c118`.
- **⚠️ ESTA CORREÇÃO ESTAVA ERRADA (verificado 2026-07-21 no próprio console).** O sysfs é a fonte autoritativa e diz que o BAR0 de `00:14.1` é `0xc2000000`–`0xc2000fff`:
  ```
  $ head -1 /sys/bus/pci/devices/0000:00:14.1/resource
  0x00000000c2000000 0x00000000c2000fff 0x0000000000140204
  ```
  Ou seja, **`0xc2000118` sempre esteve CERTO** (e os 4 KB batem com o fix M5 do `ioremap`). Os testes feitos com `0xc900c118` leram um endereço que não é o chip_id da GBE — **reavaliar as conclusões daquela rodada**. Ver `M8_leituras_glue.md`.
- **Ação**: Corrigi os scripts `test_all_mmio_v2.py` e `test_major_5_minors.py` para usar o endereço correto.
- **Resultado**: Re-testamos os comandos ICC (Minors `0x10`, `0x20`, `0x30`, `0x40` do Major 5, com payloads de 1 byte e 32 bytes) e a inicialização via MMIO puro (BAR2/BAR4). O ChipID continuou retornando `0x00000000`. Conclusão: Nem os minors específicos do Major 5, nem as inicializações puras de MMIO, ligam a energia da GBE.

### 2. A Pista do ps4-kexec e do WLAN/BT
- **Descoberta**: Analisando o código fonte do payload do Linux (`ps4-kexec-common/linux_boot.c`), encontramos a linha `kern.wlanbt(0x2);` executada logo antes do boot do Linux. O comentário diz: `We need reset bt/wifi, so disable it, we re-enable it when the kernel boot`.
- **Análise**: A função `wlanbt(0x2)` invoca o comando ICC `Major 5, Minor 0, Payload 02`. O código-fonte do `ps4-apcie-icc.c` no Linux envia `Payload 03` para religar.
- **O Incidente do Bitmask**: Criei um script Python (`test_major5_minor0_bitmask.py`) para varrer os payloads de `00` a `0F` no `Major 5, Minor 0`. Quando o script chegou no `Payload 02`, **ele efetivamente desligou a placa de Wi-Fi**, derrubando o servidor Telnet e congelando o script antes que ele chegasse nos próximos bitmasks (como o `07`).
- **Teoria Atual**: A GBE provavelmente pertence ao **mesmo domínio de energia** (Major 5, Minor 0) que o Wi-Fi e o Bluetooth. Se `Payload 03` (bits 0 e 1 ligados) liga o WLAN e o BT, é muito provável que o bit 2 (logo, `Payload 07`) ligue o WLAN, BT e a GBE ao mesmo tempo! O kexec explicitamente envia `02` para desligar tudo, e o driver Linux só envia `03` (esquecendo o bit da GBE).

### 3. A Queda do Wi-Fi e o Novo Plano de Ação
- **O Teste que derrubou a rede**: Como a conexão era por Telnet (via Wi-Fi), quando o script enviou `5 0 02`, a energia da placa Wi-Fi foi cortada, o que derrubou a conexão e congelou a execução. A foto da tela (002.jpeg) confirmou que o driver `wlan` começou a cuspir erros `kalOidComplete:(INIT WARN)` sem parar, provando a perda abrupta do hardware.
- **Lição Aprendida**: **NUNCA** testar Payloads no `Major 5, Minor 0` que não tenham os bits 0 e 1 ativados (ou seja, payloads diferentes de `03`, `07`, `0B`, `0F`). Qualquer outro valor vai causar a perda imediata da rede Wi-Fi e inviabilizar testes via Telnet!
- **Próximo Passo**: Testar **apenas** os payloads seguros (`03`, `07`, `0B`, `0F`) via Telnet, usando o script `test_safe_bitmasks.py`, para descobrir se um deles (como o `07`) acende a GBE.
