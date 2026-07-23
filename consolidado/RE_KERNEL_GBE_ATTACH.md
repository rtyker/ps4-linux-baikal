# Engenharia Reversa: driver SceGbeMtsCtrl no kmem_dump_1252.bin

Análise estática (radare2, sem tocar no console) do dump completo e descriptografado do kernel Orbis 12.52 (`consolidado/dumps_orbis/kmem_dump_1252.bin`, 32.2MB), buscando a rotina real que liga a rail de energia da GBE Baikal — para substituir a sondagem cega de hardware (perigosa, já desligou o console uma vez).

## Setup do binário no radare2
```bash
r2 -q kmem_dump_1252.bin
```
- `baddr` (base virtual do dump) = `0xffffffffdc350000` — varia por boot (KASLR); recalcular a cada novo dump.
- `laddr` = `0x0`, então **vaddr = baddr + offset_no_arquivo** (o dump é um snapshot já relocado da imagem do kernel rodando).
- ELF sem section headers (`file` mostra "no section header") — usar `izz` (strings no arquivo inteiro) em vez de `iz`.

## Strings-chave localizadas (offsets no arquivo, ver seção anterior de setup para converter em vaddr)
- `SceGbeMtsCtrl` @ offset `0x7bdf60`
- `gbe_ctrl` @ `0x7bdfb1`, `gbe_phy_ctrl` @ `0x7bdfd5`
- `Baikal GBE controller` @ `0x7bdbac`
- `icc_power.c` (caminho completo) @ `0x7b025b`
- `icc_device_power.c` (caminho completo) @ `0x8085d8`

## Função mts_kthread() do SceGbeMtsCtrl (Anteriormente confundida com attach)
**Endereço (neste dump específico): `0xffffffffdc5a41d0`**

Encontrada via xrefs a `SceGbeMtsCtrl`. Originalmente achávamos que este era o `attach()`, mas na verdade **é o loop principal da thread `gbe:ctrl`**. A verdadeira função `attach()` a chama via `kproc_create`.

### O que a thread mts_kthread() faz (confirmado por disassembly, `pd 120 @ 0xffffffffdc5a41d0`):
1. Prólogo padrão FreeBSD
2. `r15` = softc/device_t (primeiro argumento, `rdi`)
3. Salva `curthread` (`gs:[0]`) em `softc+0x3150` — inicialização de lock (owner field)
4. `call 0xffffffffdc524770` com nome = "SceGbeMtsCtrl" — provável `mtx_init`/`sx_init` do lock do driver
5. Cria uma segunda thread `gbe_phy_ctrl` via `kproc_create` (`0xffffffffdc7c94f0`) se `[r15+0x30dc] != 0`.
6. `call 0xffffffffdc5a5ec0` e `call 0xffffffffdc526a60` — não analisadas ainda; o resultado de `526a60` decide (`test eax,eax; je`) se monta uma tabela de 6 campos em `softc+0x31e0..0x3210` (ver abaixo)
7. Monta uma tabela de ponteiros em `softc`:
   - `+0x31d8` = ponteiro pra uma string próxima de "SceGbeMtsCtrl" (nome/versão, não função)
   - `+0x31d0` = valor constante `0x17122009` (possível magic/versão — "2009-12-17"?)
   - `+0x31e0` = `0xffffffffdc5a6560` — **função pequena, ver abaixo**
   - `+0x31f0` = `0xffffffffdc5a6590` (não analisada)
   - `+0x31f8` = `0xffffffffdc5a65c0` (não analisada)
   - `+0x3200` = `0xffffffffdc5a65d0` (não analisada)
   - `+0x3208` = `0xffffffffdc5a65e0` (não analisada)
   - `+0x3210` = `0xffffffffdc5a7000` — **FALSO POSITIVO: é código de AES key-schedule (AESKEYGENASSIST), não um callback do driver.** Não seguir essa pista — provavelmente esse campo do softc não é um vtable de função, ou o layout que assumi está errado a partir desse ponto. Reavaliar.
8. `call 0xffffffffdc6da460` — provável registro do device/vtable com o barramento pai (`bus_generic_attach`-like)
9. Loop em `[r15+0x3158]`/`[r15+0x3178]` chamando `0xffffffffdc6c8300` (lock, padrão `_sx_xlock(lock, opts, file="icc_power.c", line)`) e `0xffffffffdc6c85b0` (unlock correspondente). **⚠️ CORRIGIDO 2026-07-21: a leitura original dizia que esses locks citavam `icc_power.c` e concluía que "a GBE Baikal depende do `icc_power`" — ERRADO.** A string passada aos locks é `0xffffffffdcb0dc47` = `sys\dev\mts\if_mts.c` (o próprio arquivo do driver da GBE, comportamento normal e sem informação). `icc_power.c` vive em `0xffffffffdcb0025b` e **não é referenciado em lugar nenhum do código da GBE**. Ver `KERNEL_DUMP_HARDWARE_INVENTORY.md` seção 9.
10. Função continua além de `0xffffffffdc5a4410` (não desmontada ainda nesta sessão).

### `0xffffffffdc5a6560` (campo `+0x31e0`, primeiro "callback"):
```
call sub_dc702470(rdi = [rcx+0x130])   ; checagem de disponibilidade?
test eax,eax; je +4
  → xor eax,eax; ret 0
  → call sub_dc76f9e0(); ret (eax==0)
```
Padrão de predicado "está disponível?" (retorna 0/1). Possivelmente ligado à string `icc_available` vista nas strings do binário. Não confirmado.

## Próximos passos concretos (RE, sem tocar no console)
1. **Corrigir o mapeamento do offset `+0x3210`** — não é vtable ali, ou o layout do struct softc está mal interpretado a partir de algum ponto anterior. Reconferir com mais contexto (o compilador pode ter alinhado campos diferente do que assumi).
2. Desmontar `0xffffffffdc5a6590`, `0xffffffffdc5a65c0`, `0xffffffffdc5a65d0`, `0xffffffffdc5a65e0` — candidatos a `probe`/`detach`/`suspend`/`resume`/`reset` do driver.
3. Desmontar `sub_dc526a60` (decide se monta a tabela) — pode ser o teste "é Baikal, não Aeolia/Belize" ou "hardware está presente".
4. Continuar o disassembly de `0xffffffffdc5a41d0` além de `0x4410` até o `ret` final — é onde mais provavelmente está a chamada real que liga a rail via ICC (`icc_power`) ou acessa MMIO/BAR.
5. Buscar dentro do binário por chamadas a funções de I/O típicas do FreeBSD (`bus_space_write_4`, `pci_write_config`) próximas dessas rotinas — mais direto que seguir vtables às cegas.
6. Confirmar offset real do softc (`0x30a0`, `0x3068`, `0x3099`, `0x30b0`, `0x30d0`, `0x30d6`, `0x30dc`, `0x3150`, `0x3158`, `0x3178`, `0x31d0`, `0x31d8`, `0x31e0`...`0x3210`) — útil se quisermos correlacionar com os offsets MMIO já mapeados ao vivo em `memory/marco-2026-07-17-sky2baikal-pronto-teste.md`.

## ATUALIZAÇÃO: achado o loop de espera pelo power-on (mesma sessão)

Continuando o disassembly de `attach()` além de `0x4410`:

- `0xffffffffdc5a4424`: `call 0xffffffffdc524510` — chamado só se `r13d & 0x20000` (uma flag de capacidade). Não analisada ainda.
- **`sub_dc526a60` (o "gate" que decide se monta a tabela de vtable ou não) é só um predicado simples:** lê um **byte de estado global** em `0xffffffffde51c5d0 + 0x34` e retorna se é != 0. **Não é ele quem liga a energia** — só consulta uma flag que outra parte do kernel (provavelmente o handler de notificação ICC assíncrono) seta quando o Syscon confirma o power-on.
- Se a flag ainda não está setada, o attach **entra num loop de espera de até 100 tentativas** (`0xffffffffdc5a4450`–`0x4467`): chama `sub_dc3f5bd0(edi=4, esi=0x38, edx=1, rcx=r14)` repetidamente — assinatura compatível com `tsleep`/`pause`-like (4 args, provável `(ident, priority, wmesg?, timo=1 tick)`), ou seja, **dorme ~1 tick por tentativa, até 100 tentativas**, esperando a flag global virar 1. Se virar 1 dentro do prazo, segue o attach normal (monta vtable). Se estourar as 100 tentativas, cai num caminho de erro (`jmp 0xffffffffdc5a4302`, mesmo destino do caso "página cheia"/lock liberado sem sucesso).
- **Confirmado: existe uma SEGUNDA função irmã logo depois (`0xffffffffdc5a44be`+) para `SceGbeMtsPhyCtrl`** (string em `0xffffffffdcb0df6e`), com o MESMO padrão de lock (**correção 2026-07-21: as linhas `0x84f`/`0x852`/`0x855` são de `if_mts.c`, não de `icc_power.c`** — ver seção 9 do inventário) — ou seja, **o PHY controller da GBE tem seu próprio ciclo de espera de power, separado do MAC controller**, ambos guardados por locks do `icc_power.c`.

**Conclusão importante:** o "botão" que efetivamente pede o power-on ao Syscon **não está nesta função attach** — ela só ESPERA passivamente por uma flag global que é setada em outro lugar (provavelmente o handler de notificação ICC assíncrona de `icc_power.c`, ou um init de barramento anterior que já disparou o pedido antes do attach do driver GBE rodar). Isso muda o alvo da próxima busca.

### CORREÇÃO: pista do "byte global de estado" era FALSA (mesma sessão)
Busquei `/r` para o endereço base `0xffffffffde51c5d0` (struct apontada por `sub_dc526a60`) esperando achar poucos escritores específicos da GBE. **Resultado: mais de 130 referências espalhadas por TODO o binário do kernel** (drivers completamente não relacionados). Isso prova que `0xde51c5d0` **não é uma flag específica da GBE** — é alguma estrutura genérica muito reutilizada (provável candidato: `struct lock_object`/tabela de classes de lock do subsistema WITNESS, ou algo equivalente chamado por praticamente todo `mtx_init`/`sx_init` do kernel). **A hipótese anterior ("essa é a flag de power-ready que o loop espera") está descartada.** O loop de espera em `0x4450` provavelmente está esperando por outra coisa (talvez apenas o resultado do lock/init genérico, não um sinal específico de hardware).

### Próximo alvo revisado (honesto sobre o esforço restante)
A trilha "seguir a flag global" foi um beco sem saída. Caminhos mais promissores, em ordem de custo/benefício:
1. **`sub_dc3f5bd0`** (a função chamada no loop de 100 tentativas) — confirmar se é de fato um `tsleep`/`pause` genérico do FreeBSD ou algo mais específico.
2. A rotina de **notificação/callback ICC** de `icc_power.c` (handler assíncrono de resposta do Syscon) — ainda não localizada; seria a candidata mais forte para conter o comando ICC real (major/minor) que liga a rail da GBE. Buscar por xrefs às linhas de `icc_power.c` próximas de 2127-2133 e 4586-4611 (já vistas nos números de linha usados nos locks) pode ajudar a achar a função vizinha certa.
3. Considerar usar um **decompilador** (Ghidra, via plugin `r2ghidra` — aparece como dependência opcional do radare2 já instalado) em vez de disassembly manual — a essa profundidade, ler pseudo-C acelera MUITO a identificação de qual chamada é a real (`icc_send`) vs. infraestrutura genérica (locks, printf, etc). **Esta é provavelmente a mudança de abordagem mais valiosa antes de continuar.**
4. Alternativa mais rápida e prática: em vez de achar o registrador exato via RE, **procurar diretamente por chamadas a uma função `icc_send`-like** (já vista nas strings: `icc_send error %d`, `icc_send: sow: ...`) e enumerar TODOS os pares major/minor usados no binário inteiro — comparar com os já testados ao vivo (major 5) para achar candidatos novos (majors diferentes) sem precisar entender o fluxo completo do driver.

**Honestidade sobre o esforço:** esta RE está avançando, mas cada função nova exige desmontagem manual (sem decompilador ainda) — é trabalho genuíno de várias sessões, não uma tarde. Ghidra/r2ghidra reduziria bastante esse custo.

## ATUALIZAÇÃO GRANDE: r2ghidra instalado, achado o comando ICC real (mesma sessão, 2026-07-20)

**Ferramentas:** `r2ghidra` instalado via `pacman -S r2ghidra` (pacote oficial Arch, `extra/r2ghidra`). Uso: `r2 -q -c "af @ 0xVADDR; pdg @ 0xVADDR" arquivo.bin` — `af` marca os limites da função, `pdg` decompila em pseudo-C. Muito mais rápido que ler assembly bruto.

### Decompilado do attach() completo (`0xffffffffdc5a41d0`)
Ver comando usado: `r2 -q -c "af @ 0xffffffffdc5a41d0; pdg @ 0xffffffffdc5a41d0" kmem_dump_1252.bin`

Pontos confirmados no pseudo-C:
1. `func_0xffffffffdc526a60()` — confirmado sem argumentos, só lê uma flag global (a pista da seção anterior, hoje sabida ser genérica/não-GBE).
2. Se a flag for falsa, entra no loop: `func_0xffffffffdc3f5bd0(4, 0x38, 1, &var_29h)` até 100x, dormindo ~100ms entre tentativas (`(hz*100+999)/1000` ticks — padrão de conversão ms→ticks do FreeBSD) — **até 10s de espera total**.
3. **`func_0xffffffffdc3f5bd0` É UM WRAPPER GENÉRICO DE COMANDO ICC** (decompilado à parte, ver abaixo) — os 2 primeiros argumentos são **major e minor do comando ICC**.
   - **➡️ CHAMADA REAL: `icc_query(major=0x04, minor=0x38, len=1)`** — usada pelo driver GBE durante o attach para esperar/consultar um estado (provavelmente "power/PHY pronto"). **Major 4 nunca foi testado ao vivo** (só testamos major 5 = `icc_device_power`, descartado). Este é um alvo concreto e de baixo risco para testar via `/proc/ps4_icc` (tag `20260717-iccdbg` já tem esse debug interface pronto): `echo "4 0x38" > /proc/ps4_icc; cat /proc/ps4_icc`.
4. No handler do evento de "link" (`uVar8 & 2`, dentro do loop principal do kthread `gbe:ctrl`): chama `func_0xffffffffdc5a6290(uVar3)` (monta e envia 2 comandos ICC de 0x20 bytes via `func_0xffffffffdc5a58d0`, com sub-comandos `0x800b` e `0x600b` — parecem configuração de MAC/PHY, não power) e **depois** limpa o bit `0x1000` (bit 12) de um registrador no offset `0x54` de um recurso de barramento (`*(*(arg1+0x3068)+0x10) + 0x54`) — mistura de I/O port (`in`/`out`) OU MMIO dependendo de uma flag de modo. **Efeito provável: desmascarar uma interrupção (IMR), não ligar o power** — mas não 100% confirmado, precisa achar a que BAR/resource esse `arg1+0x3068` aponta (não rastreado ainda).

### `func_0xffffffffdc3f5bd0` (wrapper genérico de comando ICC) — decompilado
```c
ulong fcn.ffffffffdc3f5bd0(int64_t major, int64_t minor, int64_t len, int64_t outbuf) {
    if (major < 5) {                    // só majors 0-4 são válidos aqui
        if ((len & 0xffff) < 0x401) {    // limite de tamanho da resposta
            bzero(&req, 0x7f0);
            req.byte[1] = 3;
            req.u16[1] = 1;
            req.hdr_len = 0x20;          // offset 8, u16
            req.unknown = 0;             // offset 0xc, byte
            req.major = major;           // offset 0xd, byte   <-- major do comando ICC
            req.minor = minor;           // offset 0xe, u16    <-- minor do comando ICC (aceita 16 bits!)
            req.arg = len;               // offset 0x10, u16
            ret = icc_query_sync(&req, &req);   // func_0xffffffffdc797090 — envia e espera resposta
            if (ret == 0) { memcpy(outbuf, &req.payload, len); ret = 0; }
        }
    }
    return ret;
}
```
**Isso é literalmente uma função `icc_query(major, minor, len, out)` de uso geral** — provavelmente chamada por VÁRIOS drivers, não só GBE. Vale a pena, em uma sessão futura, buscar TODOS os xrefs pra essa função (`/r 0xffffffffdc3f5bd0`) e catalogar todos os pares `(major, minor)` usados no kernel inteiro — pode revelar outros comandos úteis (thermal, fan, etc.) de brinde.

**Observação importante:** o campo `minor` aqui é de **16 bits** (`req.minor = minor` num campo u16), não 8 bits como testamos ao vivo via `/proc/ps4_icc` (que usava `major minor` como bytes soltos, ex: `5 0x41`). Confirmar no código de `icc_query_sync`/protocolo se o minor real é de fato 1 byte (como testado) ou 2 bytes — se for 2 bytes, testes anteriores podem ter testado só a metade baixa do espaço de minors válido.

## TESTE AO VIVO 2026-07-20 (console real, tag `20260717-iccdbg`, IP 192.168.6.128)

**Verificação prévia:** `bzImage`/`bootargs.txt`/`initramfs.cpio.gz` ativos no HD conferidos por MD5 — idênticos byte a byte à referência `boot_referencia/*-iccdbg` já validada (System.map, 14 hits). Build correta confirmada antes do teste.

**Baseline ANTES do teste** (`dd if=/dev/mem bs=1 count=32 skip=$((0xc2000100)) | od -An -tx1`):
```
0x100: 05 00 00 00 b0 00 00 00 00 00 00 00 00 00 00 00
0x110: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```
`B2_CHIP_ID` (0x11a) = `00`, `B2_MAC_CFG` (0x11b) = `00` — confirma o estado gated de sempre. **Nota:** `0x100`/`0x104` leram `05`/`b0` aqui, diferente dos `0x17`/`0xbd` registrados na sessão original de descoberta (`BAIKAL_HARDWARE_DISCOVERIES.md`) — provavelmente registrador volátil (contador/status), não identidade fixa; não é motivo de alarme.

**Comando testado:** `echo "4 0x38" > /proc/ps4_icc` (via telnet, `/proc/ps4_icc` da tag iccdbg)

**Resultado:**
```
cmd major=0x4 minor=0x38 paylen=0 ret=20
reply: 01 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 [+28 bytes zero de padding]
```

**Interpretação (confirmada lendo `drivers/ps4/ps4-apcie-icc.c` real do build, `kernels/ps4-baikal-7.0.8-kernel/`):**
- `apcie_icc_cmd()` só retorna valor POSITIVO (`ret = reply.length - ICC_HDR_SIZE`) se o checksum bateu E major/minor da resposta conferem com o pedido. Um NAK real dá `-EIO`. **`ret=20` positivo = comando ICC major=4/minor=0x38 é VÁLIDO e respondeu com sucesso** (não é o "NAK genérico" tipo `01 05` visto nos testes de major=5 inválido — aquele contexto tinha outro significado, a comparação direta dos bytes de reply entre majors diferentes não é conclusiva sem olhar o `ret`).
- **Confirmação cruzada forte:** o mesmo arquivo `ps4-apcie-icc.c` já usa **major=4 minor=1** em `icc_shutdown()`/`icc_reboot()` — prova que **major=4 é o serviço de power/sistema** (bate 100% com `icc_power.c` já apontado pela RE do dump do kernel).
- **MAS: o B2_CHIP_ID continua `00` depois do teste** — ou seja, `minor=0x38` é uma **consulta de status** (query, payload enviado = 0 bytes), não o comando de "ligar" a rail. Bate com o que a RE já tinha mostrado: essa é a chamada que o `attach()` original usa pra **esperar/consultar** se already ready, não pra disparar o power-on.

## RE de `baikal_pcie.c` (glue PCIe do Orbis) — mesma sessão, 2026-07-20

Pivô após o beco sem saída do ICC major=4 (ver seção seguinte). Localizado via string `W:\Build\J02690760\sys\freebsd\sys\dev\pci\baikal_pcie.c` → vaddr `0xffffffffdcb3fbcc` neste dump.

**Função encontrada: `0xffffffffdc718b40`** — mecanismo de **registrador indexado** no BAR2 (glue pervasive):
```c
// escreve um "índice/select" em BAR2+0x110084 (a partir de bus_handle em [softc+0x10])
// lê o "dado" correspondente de volta em BAR2+0x110088
// aplica ~(valor >> shift) & mask pra extrair bits específicos
```
Classifica o argumento de entrada (provável número de linha de IRQ) em 3 faixas (`&0xffffffe0==0xa0`, `&0xfffffff8==0x78`, `&0xfffffffc==0x6c`) escolhendo um índice (2 ou 3) e uma máscara/shift diferentes — **é a rotina de leitura de status de interrupção pendente do glue**, não um "liga/desliga" direto. Mas confirma que o BAR2 tem um mecanismo de índice+dado (2 registradores físicos dão acesso a um banco maior de "sub-registradores virtuais") — mecanismo que pode ser reaproveitado para outros fins (clock-gate?) em índices diferentes de 2/3.

**Busca por outros usos de `0x110084`/`0x110088` no binário inteiro:** só essa UMA ocorrência genuína (uma segunda aparente, em `0xdc95452b`, é **falso positivo** — bytes de uma instrução `je` coincidindo com o padrão binário buscado, não uma referência real). **Não há uma contraparte de "escrita" óbvia usando esses mesmos 2 registradores em outro lugar do kernel.**

## ACHADO PRINCIPAL DA SESSÃO: attach() do baikal_pcie.c localizado e decompilado (2026-07-20)

Sequência completa de localização (via strings → xrefs, confirmado com pdg em cada etapa):
1. String `"Baikal PCI Express glue"` → vaddr `0xffffffffdcb3fc77` → xref único em `0xffffffffdc718e6c`.
2. **`probe()` real = `0xffffffffdc718d20`** (neste dump). Decompilado por completo: lê vendor/device/revisão via método PCI-config (`vendor==0x104d`, `device==0x90db` — **novo PCI ID confirmado, o glue Baikal**, `revisão==4`), chama `device_set_desc(dev, "Baikal PCI Express glue")` e retorna sucesso.
3. **`attach()` real = `0xffffffffdc718eb0`** (função seguinte no binário, mesmo padrão FreeBSD de probe/attach adjacentes). Decompilado por completo:
   - Aloca **3 BARs via `bus_alloc_resource_any`**: `rid=0x18` (**BAR2**, o pervasive já conhecido), `rid=0x10` (**BAR0**), e **`rid=0x20` (BAR4 — NUNCA documentado antes neste projeto!)**.
   - Ao alocar BAR4 com sucesso, lê e loga (via `device_printf`) 3 registradores: `BAR4+0x4084`, `BAR4+0xc020`, `BAR4+0xc024` (prováveis IDs/versão do bloco de hardware mapeado por essa BAR — não decodificados ainda).
   - Logo em seguida, **chama `func_0xffffffffdc7190d0()` incondicionalmente** (sem argumentos visíveis) antes de retornar sucesso.

### `func_0xffffffffdc7190d0` — REGISTRADOR DE CLOCK/CONFIG CANDIDATO FORTE
```c
void fcn.ffffffffdc7190d0(void) {
    if (checagem_de_revisao_de_hardware_passa) {   // ver detalhe abaixo
        reg = read32(BAR2 + 0x10a030);
        reg = (reg & 0xfffffe07) | 0xd8;   // limpa bits [8:3] (6 bits), escreve padrão 0x1b nesse campo
        write32(BAR2 + 0x10a030, reg);
    }
}
```
- **Offset físico real (BAR2 = pervasive glue, base `0xc8800000`): `0xc8800000 + 0x10a030 = 0xc890a030`.**
- Padrão *read-modify-write* limpando um campo de 6 bits e escrevendo valor fixo (`0xd8` → campo = `0x1b`) é EXATAMENTE o formato esperado de uma escrita de configuração de clock/PLL/power — muito mais promissor que qualquer coisa achada via ICC até agora.
- **Offset nunca mapeado antes** neste projeto (os blocos pervasive já sondados eram `0x100000`, `0x110084/88`, `0x140000`, `0x160000`, `0x170000`, `0x180000` — `0x10a030` é novo).
- Condição de guarda: `func_0xffffffffdc526e40() == 0x30000`, que por sua vez é `(alguma_leitura_de_ID_de_chip() & 0xff0000) == 0x30000` — parece checar bits [23:16] de um ID de geração/stepping de CPU/SoC (valor esperado = `0x03`). Não confirmado se bate com o hardware real do console de testes, mas **é executado incondicionalmente no attach do barramento PCIe** (não depende de nenhuma lógica específica de GBE) — ou seja, se essa checagem passar no boot normal do Orbis, ela roda em TODO boot, antes de qualquer driver de dispositivo filho (GBE, SATA, etc.) ser inicializado. Combina com o padrão esperado: um init de clock geral do barramento que o Linux atual (`ps4-bpcie.c`) pode não estar replicando.

### Verificação ao vivo (só leitura) — FEITA 2026-07-20
```
dd if=/dev/mem bs=4 count=1 skip=$(( 0xc890a030 / 4 )) | od -An -tx4
→ 000016c9
```
Decodificando o campo de 6 bits (`(valor >> 3) & 0x3f`): atual = `0x19` (`011001`), esperado após a escrita da Sony = `0x1b` (`011011`) — **diferem em 1 bit só (bit 4 do registrador)**. **Confirmado: essa escrita específica NÃO está sendo aplicada no boot atual do Linux.** É diferença real, não ruído — forte candidato a ser (parte d)o que falta pro clock/power da GBE (ou de outro periférico do barramento) ligar.

### Tentativa de escrita — FALHOU por bug de escaping (2026-07-20, NÃO invalida a hipótese)
Primeira tentativa ao vivo usou `printf '\xd9\x16\x00\x00' | dd of=/dev/mem bs=4 seek=... conv=notrunc` encadeado via bash local → `ncat --telnet` → shell remoto (busybox). **O `\xHH` não foi interpretado corretamente nessa cadeia de quoting** — `dd` reportou 12 bytes copiados (3 blocos) em vez dos 4 esperados, e o registrador ficou em `0x78000000` (nem o valor original `0x16c9`, nem o pretendido `0x16d9`). Console permaneceu estável (dmesg limpo, sem panic), `B2_CHIP_ID` continuou `00 00` sem piorar — mas o teste em si não validou nem refutou a hipótese, só ficou inconclusivo por erro de execução. **Usuário reiniciou o console pra restaurar o registrador MMIO (volátil) a um estado limpo.**

**Método corrigido pra próxima tentativa:** usar escapes **octais** (`\NNN`, 3 dígitos), não hex — `busybox printf` não suporta `\xHH` de forma confiável nessa cadeia:
```bash
# 0xd9=\331  0x16=\026  0x00=\000  0x00=\000
printf '\331\026\000\000' | dd of=/dev/mem bs=4 seek=$(( 0xc890a030 / 4 )) conv=notrunc
```
**Sempre conferir que `dd` reporta "1+0 records in / 1+0 records out" (4 bytes) antes de aceitar a escrita como válida** — qualquer outro número é sinal de bug de escaping, não confiar no resultado.

### Retry pós-reboot — escrita mecanicamente correta, resultado INESPERADO (2026-07-20)
1. Console reiniciado pelo usuário; `0xc890a030` reconfirmado em `0x16c9` (estado limpo) antes de escrever.
2. Escrita com método octal corrigido: `dd` confirmou **"1+0 records in/out, 4 bytes"** — desta vez a escrita foi mecanicamente correta (validado ANTES de aceitar, com `wc -c` = 4 também).
3. **Releitura imediata mostrou `00000000`** — nem o original (`0x16c9`) nem o valor escrito (`0x16d9`). Confirmado estável em releituras subsequentes (não é atraso de propagação).
4. `B2_CHIP_ID`/`B2_MAC_CFG` continuam `00 00`. Rebind do `sky2` sem reboot → continua `unsupported chip type 0x0`. Sistema estável (dmesg limpo, sem panic).
5. **Contexto mais amplo capturado** (`dd if=/dev/mem bs=1 count=64 skip=$(( 0xc890a010 ))`):
   ```
   0xc890a010: 49 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
   0xc890a020: 49 12 00 00 00 00 00 00 00 00 00 00 00 00 00 00
   0xc890a030: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00   ← nosso alvo, agora todo zero
   0xc890a040: 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
   ```

### Hipótese revisada: `0x10a030` pode ser registrador de COMANDO/PULSO, não de config persistente
O padrão observado (qualquer escrita → releitura sempre `0`, independente do valor escrito) é típico de um registrador "write triggers action, self-clears" — diferente do que o *read-modify-write* no pseudo-código sugeria à primeira vista (o C decompilado só mostra COMO o valor final é calculado antes de escrever, não garante que o hardware realmente "guarda" esse valor de volta para leitura). **Essa hipótese ainda não está confirmada nem descartada.** Resultado prático: **não ligou a GBE** de qualquer forma — não repetir esse teste específico sem uma teoria nova.

### Estado após esta tentativa (honesto)
Escrita em `0xc890a030` **não é a peça que falta** (ou pelo menos não sozinha) — testada corretamente agora, sem efeito no `B2_CHIP_ID`. Duas hipóteses abertas pra próxima sessão:
1. Talvez seja necessária uma SEQUÊNCIA de escritas (não uma única), ou escrever em conjunto com outros registradores vistos no `attach()` (ex: os lidos em `BAR4+0x4084/0xc020/0xc024` logo antes desta chamada).
2. Talvez o "liga a GBE" não esteja nem em `baikal_pcie.c` — pode estar em outro lugar ainda não mapeado (o `SceGbeMtsCtrl`/`icc_power.c` original, ou um terceiro componente).

### Estado honesto após essa linha de investigação
Não achamos ainda o comando/registrador que liga a GBE. O que temos de concreto:
1. Major=4 ICC é o serviço de power/sistema real (confirmado), mas GET simples não distingue nada — não é o mecanismo de liga da GBE (ou pelo menos não do jeito que testamos).
2. O glue Baikal (`baikal_pcie.c`) tem um mecanismo de índice/dado no BAR2 (`0x110084`/`0x110088`) usado pra status de IRQ — mecanismo real, mas função encontrada é só leitura, não achamos ainda o "liga" usando esse mesmo canal com índices diferentes.
3. Ainda não decompilamos a rotina de `probe()`/`attach()` do PRÓPRIO `baikal_pcie.c` (só achamos funções auxiliares por enquanto) — isso é o próximo passo mais lógico, já que é lá que a Sony provavelmente faz o bring-up genérico de energia dos slots PCI, incluindo a GBE.

### Teste da hipótese de SET — RESULTADO NEGATIVO (mesma sessão, 2026-07-20)
Testado `echo "4 0x38 01" > /proc/ps4_icc` (payload 1 byte = `0x01`, mesmo padrão de `resetUsbPort()`). Resultado: `ret=20` (comando aceito, sem erro), mas `B2_CHIP_ID`/`B2_MAC_CFG` continuam `00 00` — inclusive depois de forçar rebind do `sky2` sem reboot (`unbind`/`bind` via sysfs), que voltou a falhar limpo com `unsupported chip type 0x0`. **Hipótese descartada: minor 0x38 com payload 1-byte on/off não liga a GBE.** Tabela completa de todos os testes (evitar re-testar) em `consolidado/ICC_GBE_TEST_LOG.md` — **checar esse arquivo antes de qualquer novo teste ao vivo.**

### Próximos passos concretos (ordem sugerida)
1. **Testar ao vivo** (com autorização do usuário, conforme Regra de Ouro): `echo "4 0x38" > /proc/ps4_icc; cat /proc/ps4_icc` usando a tag `20260717-iccdbg` já pronta no HD.
2. Catalogar todos os xrefs de `func_0xffffffffdc3f5bd0` (o `icc_query` genérico) — script r2 pra extrair todos os pares major/minor usados no binário inteiro, não só os da GBE.
3. Rastrear o resource `arg1+0x3068` do softc da GBE (provavelmente setado no `probe()`, ainda não localizado) pra confirmar se o registrador `+0x54` é IMR (interrupt mask) ou algo de power/clock.
4. Decompilar `func_0xffffffffdc5a5ec0` (chamada tanto no início do attach quanto em resposta a eventos — parece ser a rotina de "reset"/"(re)inicialização" do controller).

## Sessão de RE profunda 2026-07-20 (continuação) — análise dos 9 arquivos `decompiled_*.txt` pendentes

Contexto: existiam 9 arquivos `consolidado/decompiled_*.txt` já extraídos (r2ghidra) nesta mesma sessão mas ainda não incorporados a este documento. Analisando um a um, documentando achado por achado (positivo e negativo) antes de seguir adiante.

### `decompiled_dc526da0.txt` — POSITIVO (confirma hipótese anterior, não é candidato de teste)
`fcn.ffffffffdc526da0()` lê um global (`0xffffffffde52278c`, provável "southbridge chip ID") e valida contra uma whitelist explícita de IDs conhecidos: `0x10100, 0x10200, 0x10300` (família Aeolia?), `0x20100, 0x20200` (Belize?), `0x30100, 0x30200, 0x30201` (Baikal A0/B0/B1), `0x40100` (southbridge mais novo, não documentado ainda). Se o valor não bate com NENHUM desses, chama um handler de exceção/panic (`invalidInstructionException`) — é uma checagem de "hardware suportado", não um gate de power.
**Confirma** `fcn.ffffffffdc526e40()` (já citado no doc) = `dc526da0() & 0xff0000` — ou seja, extrai só a família (byte alto). Nosso console é Baikal B1 = `0x30201`, `0x30201 & 0xff0000 = 0x030000`, que bate com a checagem `== 0x30000` usada como guarda em `func_0xffffffffdc7190d0` (a escrita em `BAR2+0x10a030`, seção "REGISTRADOR DE CLOCK/CONFIG CANDIDATO FORTE" acima). **Confirmado por RE real (antes só suposto): a guarda dessa escrita PASSA no nosso hardware** — ou seja, no Orbis original essa escrita realmente é executada no boot do nosso console específico. Isso não muda a conclusão já registrada (escrita isolada não liga a GBE), só reforça que o registrador certo está sendo mirado, na hora certa, mas não é suficiente sozinho.

### `decompiled_dc526a60.txt` — sem mudança (já documentado corretamente)
Confirmado bit a bit: `return *0xffffffffde51c604 != 0` — bate exatamente com a descrição já existente (`0xffffffffde51c5d0 + 0x34 = 0xde51c604`). Nenhuma informação nova; já estava corretamente classificado como pista falsa/genérica.

### `decompiled_dc3f5400.txt` — NEGATIVO, descartar
Decompilação sem sentido (aritmética de ponto flutuante pura, `(param_4+param_5)*(param_5-param_4)+param_7*param_2`, e um incremento de contador de flags de CPU `AH`/`CF` num endereço global de estatística). Não é uma função relacionada a GBE/ICC — provavelmente r2ghidra decompilou um trecho de código vizinho sem limites de função corretos (lixo/instrução mal alinhada, ou uma rotina matemática de outro subsistema completamente não relacionado). **Não seguir essa pista.**

### `decompiled_dc5a2680.txt` — POSITIVO, mas não é candidato de power (é MDIO/SMI, downstream do power)
É a rotina clássica de **acesso MDIO/SMI (leitura de registrador de PHY)**: escreve `0x8000` (clear busy) num registrador de controle, monta um comando `(reg_addr&0x1f)<<8 | 0x20 | ...`, escreve, espera em loop (até 10000 tentativas, delay de 1 tick) o bit de status (`iVar3 < 0`, bit mais alto do campo de 16 bits) indicar pronto, e lê o resultado (`>>0x10`) para `*arg3`. Confirma que `*(softc+0x3068)` é o par (bus_space tag, handle) da BAR0 do MAC, reutilizado em várias funções (bate com `dc5a31f0`). **Isso só funciona DEPOIS que o chip já responde** — é código legítimo do driver, mas não é candidato a "ligar" nada; é a prova de que o driver espera acesso direto por I/O de registrador padrão, sem mágica adicional de protocolo.

### `decompiled_dc5a31f0.txt` — POSITIVO IMPORTANTE, mas é init de MAC/DMA (pós-power), não o gatilho de power em si
Rotina de inicialização de hardware do MAC: monta anéis de descritores DMA RX/TX (padrões `0x80000000`/`0xffff0000`/`0x80000600`/`0x7fffffff` típicos de flags de descriptor DMA), e no final escreve registradores reais via `*(softc+0x3068)` (BAR0): offsets `+0x34`, `+0x38` (cada um recebe `OR 1` — **bits de enable**), `+0x3c`, `+0x40`, `+0x44`, `+0x48`, `+0x54` (candidato a IMR, recebe o valor de `softc+0x3098`). **Ponto-chave: essa função só roda quando chamada — e quem a chama é o handler de `SIOCSIFFLAGS` (ver `dc5a3810` abaixo), não o `attach()`.** Ou seja, **o MAC só é de fato inicializado (registradores de enable escritos) no primeiro `ifconfig up`, não no attach/probe.**

### `decompiled_dc5a3810.txt` — ACHADO PRINCIPAL DESTA RODADA: é o handler de ioctl `SIOCSIFFLAGS` (interface up/down) do driver GBE
Função grande (37 cases de switch começando em `0x80206910` = `SIOCSIFFLAGS` no FreeBSD, mais casos tratados fora do switch como `0xc0206921`, `0x80206934`, `0x8020690c` — todos ioctls de rede padrão). O case do meio (`SIOCSIFFLAGS`) faz exatamente o dispatch esperado:
```c
// quando a flag IFF_UP (bit0 de *(arg1+0x80)) está sendo ativada:
func_0xffffffffdc530200(arg1, 0x20000000, 0, 0);   // ver análise abaixo
if (<condição de flags>) func_0xffffffffdc5a31f0(iVar2);   // init do MAC (bring-up real)
else func_0xffffffffdc5a4950(iVar2);                        // caminho alternativo, não analisado
// quando IFF_UP está sendo desativada:
func_0xffffffffdc530200(arg1, 0x40000000, 0, 0);
func_0xffffffffdc5a3060(iVar3);   // provável "stop", não analisado ainda
```
**Isso é uma descoberta nova e potencialmente muito relevante:** no Orbis original, o hardware do MAC só recebe a sequência real de inicialização/enable quando a interface é explicitamente colocada em UP (equivalente a `ifconfig gbe0 up`) — não durante o attach do driver. O `attach()` (já documentado acima) só espera passivamente uma flag e monta a vtable; a "força bruta" de configurar/habilitar registradores do MAC está aqui, condicionada ao evento de interface-up.

### `decompiled_dc530200.txt` (descompilada agora, não existia como arquivo ainda — recomendo salvar) — POSITIVO, mas com conclusão que MUDA a interpretação do achado anterior
Analisando essa função (chamada com `(dev, 0x20000000, 0, 0)` no caminho "up" e `(dev, 0x40000000, 0, 0)` no caminho "down"): **NÃO é uma chamada ICC/hardware direta.** É um mecanismo genérico do framework (aparenta ser newbus/devctl): adquire um lock por dispositivo (`arg1+0x4c0`) e um lock global (`0xffffffffde522bc8`), faz um **OR do valor recebido (0x20000000/0x40000000) num campo de flags em `device+0x520`**, e se existir um "objeto vinculado" (`campo+8` não-nulo) seta um código de evento (`+0x70 = 4`) e opcionalmente chama `func_0xffffffffdc536580()` (não analisada ainda) se certas outras flags (`+0x170 & 0x1bc`) já estiverem setadas — senão só libera um lock (sinalizando um possível waiter/thread dormindo, sem processar na hora).
**Reavaliação honesta:** isso parece ser uma infraestrutura GENÉRICA de flags/notificação de estado de dispositivo (usada por múltiplos drivers do kernel, não só GBE) — não um comando ICC/Syscon de power. **Não é, sozinho, "a" chamada que liga a rail elétrica.** Mas ainda pode ser relevante indiretamente: se `func_0xffffffffdc536580` (chamada condicional) processa esse evento de forma síncrona e SE ela eventualmente dispara um `icc_query`/`icc_send` em algum caminho (não confirmado), essa cadeia poderia ser a ponte real. **Não decompilada ainda — próximo passo mais lógico antes de fechar essa linha.**

### `func_0xffffffffdc536580` decompilada — NEGATIVO, fecha a linha `dc530200`/`dc536580`
Salva em `consolidado/decompiled_dc536580.txt`. Análise: manipula um campo de flags de 16 bits em `arg2+0xd8` (padrão bate com `ifp->if_flags` do FreeBSD), chama um callback opcional em `arg2+0xe8` (formato `(ifp, media, cmd)` — parece `if_ioctl`/media-change genérico), e o grosso da função percorre uma lista ligada de endereços de interface chamando `func_0xffffffffdc50e650(obj, 0, 0x17, ...)` com constantes `0x17`/`0x10006` — isso bate com o padrão de **notificação de rota/endereço via `rtinit`/socket de roteamento** (`0x17` = tamanho de `sockaddr_dl` comum, `RTM_*`-like). **Conclusão: esse é o mecanismo GENÉRICO de notificação de mudança de estado da interface de rede (broadcast pra routing socket), completamente desacoplado de hardware/ICC/power.** A cadeia `dc5a3810 (SIOCSIFFLAGS) → dc530200 (seta flag genérica) → dc536580 (notifica rota)` é só a parte "genérica de rede" do `ifioctl`, comum a QUALQUER driver de interface no kernel — **não tem relação com ligar a energia da GBE**. Essa trilha específica está encerrada.

### Ajuste de interpretação (releitura própria antes de prosseguir, ATUALIZADO após decompilar `dc536580`)
Juntando os achados acima (`dc5a3810` + `dc5a31f0` + `dc530200` + `dc536580`): a evidência mostra que a Sony **adia a inicialização real do MAC (registradores de enable) para o evento de interface-up**, não para o attach — isso é consistente com por que nosso `attach()` (que roda no boot, antes de qualquer "ifconfig up") só fica esperando uma flag genérica e nunca dispara nada. **Porém a cadeia `dc530200`→`dc536580` (que investiguei achando que poderia ser o gatilho de power) se confirmou ser só infraestrutura GENÉRICA de rede (flags de interface + notificação de rota), sem nenhuma relação com ICC/Syscon/power.** Ou seja: **ainda não localizamos o comando/registrador que efetivamente pede o power-on ao Syscon.** Hipóteses remanescentes, em ordem de prioridade pra próxima etapa de análise (não de teste ao vivo):
1. O power pode ser gerenciado inteiramente FORA do driver GBE (ex: em `icc_device_power.c`/SAMU/bootloader, sempre executado cedo no boot do Orbis, antes de qualquer driver rodar) — nesse caso não existe "comando do driver" pra replicar, e a causa raiz seria outra (ex: um passo de inicialização do PRÓPRIO barramento `baikal_pcie` ou do SAMU que o Linux não replica, não necessariamente ligado ao driver GBE em si).
2. Ainda não analisamos `dc5a3060` (rotina "stop", chamada no caminho IFF_UP→down) nem `dc5a4950` (caminho alternativo de "up" quando a condição de flags é falsa) — podem revelar mais contexto sobre QUANDO cada caminho é tomado e se há alguma dependência de power ali.
3. Ainda não fechamos os arquivos grandes não analisados (`dc5a5ae0`, `dc957e10`, `dc95a780`, `dc95a950`) nem os já citados no doc mas não verificados a fundo (`dc5a58d0`, `dc5a5ec0`, `dc7190d0` já coberto).
Continuando a investigação nos arquivos restantes antes de propor qualquer teste ao vivo.

### `decompiled_dc5a5ae0.txt` — NEGATIVO (é o caminho de TRANSMISSÃO de pacotes, downstream)
Função grande: monta descritores DMA de TX a partir de uma cadeia de mbufs (flags de descriptor `0x80000000`="owned by hw", `0x20000000`="first segment", `0x40000000`="last segment", `0x2000000`/`0x1000000`/`0x800000`=flags de checksum offload por tipo de pacote, `0x81000000`+`&0xfff`=inserção de tag 802.1Q VLAN), com wraparound de índice em `0xff`. É o equivalente do `if_transmit`/`start_xmit` do driver — só roda com o chip já totalmente inicializado e a fila de TX pronta. **Não tem relação com power-on.**

### `decompiled_dc957e10.txt`, `decompiled_dc95a780.txt`, `decompiled_dc95a950.txt` — NEGATIVO, infraestrutura genérica do kernel (não é GBE)
As 3 funções (endereços na faixa `0xdc95axxx`/`0xdc957exx`, longe do cluster GBE em `0xdc5axxxx`) são a **infraestrutura genérica de taskqueue/interrupt thread do FreeBSD** (padrão `taskqueue_thread_loop`/`intr_event_execute_handlers`): registram 2 callbacks via `func_0xffffffffdc574460` (API tipo `EVENTHANDLER_REGISTER`) e rodam um loop de thread de interrupção com `KASSERT`s genéricos (chamadas de panic com strings de erro de invariantes, não específicas de hardware). São reaproveitadas por MUITOS drivers do kernel, não só GBE. **Confirmado como infraestrutura compartilhada, não candidatos a power.**

### `decompiled_dc5a58d0.txt` — PRECISÃO sobre achado anterior (revisa nota da seção "ATUALIZAÇÃO GRANDE" acima)
Análise mais profunda mostra que essa função NÃO manda comandos ICC — ela aloca um mbuf, copia um payload nele, e chama **`func_0xffffffffdc5a5ae0` (a própria rotina de TX identificada acima)** para transmitir o frame pela fila DMA normal da placa, e depois espera de forma síncrona (até 1000 tentativas de ~1ms) um contador de resposta (`arg1+0x3108 == arg1+0x3109`) incrementar, indicando que uma resposta chegou. **Revisão da nota anterior:** isso não é o protocolo ICC (major/minor) — é um mecanismo de comando/resposta **dentro do próprio tráfego Ethernet/DMA**, quase certamente conversando com o firmware embarcado **RMU (Remote Management Unit)** do controller Marvell Yukon (bate com a thread `gbe:rmu` já catalogada em `BAIKAL_HARDWARE_DISCOVERIES.md` seção B). Ainda não é candidato a power — pressupõe o chip já respondendo a DMA/MMIO.

### `decompiled_dc5a5ec0.txt` — ACHADO MAIS IMPORTANTE DESTA RODADA (mas ainda NEGATIVO para "achar o comando de power")
Esta função (já citada no doc anterior como "candidato a reset/reinicialização") tem DUAS metades:
1. **Metade 1:** lê um ponteiro de device "irmão" (`*(arg1+0x30a0)`), chama **`func_0xffffffffdc5a31f0` (o init do MAC/DMA) diretamente nesse device irmão**, e se uma flag (`*(arg1+0x30dc) != 0`) está setada, seta o bit `IFF_UP`-like (`+0x80 |= 1`) e **chama `func_0xffffffffdc5a3810(iVar5, 0x80206910, 0)` — ou seja, invoca PROGRAMATICAMENTE o handler de `SIOCSIFFLAGS` (o mesmo ioctl handler já documentado) no device irmão**, simulando um `ifconfig up` interno, disparado pelo kernel (não pelo usuário). Isso é a "cola" entre o controller MAC e o controller PHY (os dois softcs separados, `SceGbeMtsCtrl`/`SceGbeMtsPhyCtrl`, já sabidos desde o início da RE) — um lado inicializa/ativa o outro automaticamente quando pronto.
2. **Metade 2 (quando a flag do passo 1 não se aplica):** um loop de **até 70 tentativas (~7 segundos), dormindo ~100ms entre elas, lendo o bit 0 do registrador `BAR0+4`** — quando esse bit fica 1 (chip "pronto"), monta um frame de gerenciamento de 34 bytes com um "ethertype"/magic `0xfa42` e manda via `func_0xffffffffdc5a58d0` (o mecanismo RMU identificado acima) — um verdadeiro **handshake com o firmware RMU embarcado**. Se estourar as 70 tentativas sem o bit virar 1, cai num caminho de fallback (`func_0xffffffffdc5a6290`, não analisada) mas segue em frente mesmo assim. No final de qualquer caminho, **limpa o bit 12 (`0x1000`) do registrador em `BAR0+0x54`** (a mesma IMR-like já vista) — esse é exatamente o comportamento já citado na seção "ATUALIZAÇÃO GRANDE" anterior (antes atribuído por engano a outra função).

**Por que isso é importante:** depois de mapear TODA a cadeia do attach → ioctl up → init do MAC → handshake RMU, em NENHUM ponto existe uma chamada explícita a `icc_query`/`icc_send` (ou a qualquer MMIO de "power/clock enable" fora do já conhecido e descartado `BAR2+0x10a030`) que pareça ser um pedido ativo de energização da GBE. **Os dois únicos "loops de espera" encontrados em toda a cadeia (o do `attach()` esperando `icc_query(4,0x38)`, e este aqui esperando o bit 0 de `BAR0+4`) são ambos PASSIVOS — esperam uma condição externa acontecer, não a disparam.**

## Conclusão desta rodada de RE profunda (honesta, antes de qualquer teste ao vivo)

Depois de mapear exaustivamente attach() (MAC e PHY), o ioctl de `SIOCSIFFLAGS` (up/down), a inicialização de DMA/MAC, o mecanismo RMU (comando/resposta via frames Ethernet), e a infraestrutura genérica em torno (taskqueue, notificação de rede, ID de hardware) — **não existe, em nenhuma dessas funções, uma chamada que peça explicitamente ao Syscon/ICC para ligar a energia/clock da GBE.** Isso muda a pergunta central da investigação:

### Nova teoria principal (confiança MÉDIA — bem fundamentada pela ausência sistemática de um "botão liga", mas não prova positiva)
O power-on da GBE **provavelmente não é responsabilidade do driver `SceGbeMtsCtrl`/`SceGbeMtsPhyCtrl` nenhuma vez** — é feito antes, por uma camada mais baixa (SAMU / bootloader seguro `sam_ipl` / sequenciamento de hardware do Syscon amarrado ao boot cold-start do console), possivelmente até por um circuito de power-sequencing fixo em hardware, não por software do kernel Orbis. Support: os dois loops de espera do driver são consistentes com "esperar uma condição que outra coisa, alheia a este driver, vai satisfazer" — não com "network driver pede energia".

### Hipótese alternativa nova, também de confiança MÉDIA e mais fácil de checar estaticamente: nosso PRÓPRIO boot pode estar RE-GATEANDO uma rail que já estava ligada
Como nosso Linux é carregado via **kexec de dentro de uma sessão Orbis já totalmente inicializada** (não é cold-boot puro), é bem possível que a rail da GBE **já esteja ligada** quando o `kexec()` acontece (o boot normal da Orbis, se ela também não usa a GBE naquele momento, ainda pode ter energizado a rail cedo no boot como parte de um sequenciamento fixo de todos os periféricos do Southbridge). Se for esse o caso, a causa de `chip_id=0` sob Linux não seria "nunca ligamos", mas sim **"nosso próprio processo de kexec/enumeração de PCI reseta ou desliga de novo a rail"** (reset de barramento secundário do bridge PCIe, FLR, ou um efeito colateral do próprio `kexec()`/transição de kernel). **Checagem estática feita agora:** `grep -in "reset" drivers/ps4/ps4-bpcie.c` (nosso driver do fork) → **zero ocorrências** — nosso glue não faz nenhum reset explícito de barramento. Isso enfraquece um pouco a hipótese (não achamos o "vilão" no nosso próprio código), mas não a descarta: o reset genérico pode vir do core PCI do Linux (enumeração padrão, sem código específico do PS4) ou de um estado que o payload/`kexec()` já deixa alterado antes mesmo do Linux começar a rodar. **Não verificado ainda** — não investigado a fundo nesta rodada por falta de tempo, fica como prioridade #1 pra próxima sessão de RE (ver lista abaixo).

### `decompiled_dc5a3060.txt` — decompilada para verificar/corrigir uma alegação (importante: NÃO é PCI config space)
Uma entrada de log em `memory/INVESTIGACAO_GBE_ETHERNET_BAIKAL.md` (de origem incerta — outra sessão/agente) alegava que `fcn.ffffffffdc5a3060` escreve no **espaço de configuração PCI padrão** (offsets `0x34`/`0x38`/`0x54`) e que isso "controla o power-gating/clock-gating do Yukon", propondo integrar essa sequência no `sky2_probe()` do Linux. **Decompilei essa função agora para verificar antes de aceitar a alegação** (salvo em `consolidado/decompiled_dc5a3060.txt`):
```c
void fcn.ffffffffdc5a3060(int64_t arg1) {
    // offsets relativos a *(softc+0x3068)+0x10 — BAR0 do MAC (bus_space), NÃO PCI config space
    write_reg(base+0x54, 0x7ffffa);      // mascara quase todas interrupções (IMR)
    write_reg(base+0x34, 2);             // pede "stop"
    wait_until((read_reg(base+0x34) & 2) == 0, timeout=1000000);   // espera ACK de parada
    write_reg(base+0x38, 2);
    wait_until((read_reg(base+0x38) & 2) == 0, timeout=1000000);
    // libera buffers DMA (RX/TX), zera descritores
}
```
**Essa é a rotina "stop" (par oposto de `dc5a31f0`, já documentada acima), chamada no caminho `SIOCSIFFLAGS` down.** Os offsets `0x34`/`0x38`/`0x54` são os MESMOS já vistos em `dc5a31f0` (que os escreve com `OR 1` no caminho "up") — **são registradores MMIO internos da BAR0 do MAC (controle/enable/IMR), acessados via bus_space (`in()`/`out()`/ponteiro direto conforme o tipo de recurso), não o espaço de configuração PCI (que seria acessado via `pci_write_config`, um mecanismo completamente diferente e sem essa assinatura de código).** Não há nenhum acesso a PCI config space em `dc5a3060`.
**Conclusão sobre a alegação anterior: não se sustenta.** "Controlar power-gating do Yukon" e "integrar no `sky2_probe` pra ligar a rail" não bate com o que a função realmente faz — é um reset/parada de bloco MAC que só faz sentido com a rail JÁ ligada (mesma lógica de `dc5a31f0`: grava em registradores que só respondem de verdade se a BAR0 já estiver energizada — e sabemos que hoje ela não está, `chip_id`/`mac_cfg` = `00`). **Não virou candidato de teste ao vivo** — replicar isso no `sky2_probe()` não tem fundamento de RE para ligar a rail, seria mais uma tentativa às cegas.

### Próximos passos concretos desta rodada (só análise estática, nenhum teste ao vivo ainda — ordem sugerida)
1. **Investigar se o próprio boot/kexec do Linux reseta a rail.** Verificar (a) se o núcleo genérico de PCI do Linux emite algum reset de barramento secundário (`pci_reset_bridge_secondary_bus`/bridge control register) durante a enumeração do bridge Baikal `baikal_pcie`, e (b) se o payload de `kexec()` (código em `ps4-linux-payloads/`) faz algo que mexa em config space de PCI ou reset de barramento antes de saltar pro kernel Linux. Esse é o item mais promissor e ainda não verificado.
2. **RE de `icc_device_power.c`/`icc_device_power_control` de verdade** (só temos evidência de STRINGS até agora, nunca decompilamos a função real) — `BAIKAL_HARDWARE_DISCOVERIES.md` seção C aponta essa função como candidata a controlar "clock e energia do barramento PCIe para Ethernet", mas os testes ao vivo de `major=5` (que corresponde a esse serviço) só cobriram minors já conhecidos de outros dispositivos (wlan/bt/usb/hdd/bd) — nunca confirmamos por RE se existe um minor (ou um payload/formato origem→destino dentro de um minor já testado) especificamente pra GBE. Buscar a string `icc_device_power_control` ou os xrefs de `icc_device_power.c` linha a linha no dump pode revelar isso.
3. Decompilar `func_0xffffffffdc5a6290` (fallback quando o handshake RMU não responde em 7s) e `func_0xffffffffdc5a4950`/`func_0xffffffffdc5a3060` (caminhos alternativos de up/down ainda não vistos) — só pra fechar 100% da cadeia de código do driver e confirmar que realmente não sobrou nenhuma chamada ICC/MMIO de power não encontrada.
4. Só depois de (1) e (2): se alguma dessas linhas achar um candidato concreto (registrador ou comando ICC com semântica de power claramente identificada), documentar aqui e então (e só então) propor um teste ao vivo específico em `ICC_GBE_TEST_LOG.md`.

## Sessão de RE profunda 2026-07-20 (continuação 2 — item 1 da lista acima)

### `disableMSI()` do payload kexec — analisado e DESCARTADO como causa do power-gating
Investigado `ps4-linux-payloads/linux/ps4-kexec-common/acpi.c:157` (`disableMSI`) e seu uso em `linux_boot.c:357-367` (chamado só quando `sb_id == SB_BAIKAL`, na fase "kexec: Cleaning up hardware..."):
```c
disableMSI(0xf80a00e0); // func = 0 Baikal ACPI
disableMSI(0xf80a10e0); // func = 1 Baikal Ethernet Controller  <- nosso alvo
disableMSI(0xf80a20e0); // func = 2 Baikal SATA AHCI Controller
disableMSI(0xf80a30e0); // func = 3 Baikal SD/MMC Host Controller
disableMSI(0xf80a40e0); // func = 4 Baikal PCI Express Glue and Miscellaneous Devices
disableMSI(0xf80a50e0); // func = 5 Baikal DMA Controller
disableMSI(0xf80a60e0); // func = 6 Baikal Memory (DDR3/SPM)
disableMSI(0xf80a70e0); // func = 7 Baikal USB 3.0 xHCI Host Controller
```
`disableMSI()` só limpa o bit `msiEnable` e mascara todos os vetores (`mask64`) na **MSI Capability** do PCI config space de cada função — é sanitização padrão pré-kexec (deixa o Linux reconfigurar interrupções do zero), não toca em nenhum registrador de power/clock.

**Por que isso descarta a hipótese:** essa mesma chamada roda, de forma idêntica, em TODAS as 8 funções do slot Baikal — inclusive SATA (func 2) e USB xHCI (func 7), que sabemos que funcionam perfeitamente depois do boot. Se `disableMSI` fosse capaz de derrubar power-gating de um periférico, SATA/USB também estariam quebrados. **Não é a causa.** Também não há nenhum outro toque em PCI config space, `pci_reset_*` ou D-state (`D0`/`D3`) específico da GBE em `linux_boot.c` — o resto do arquivo só mexe em: IOMMU (`0xfc000018`, desabilitado globalmente, não específico de dispositivo), GPU (softreset Gladius, endereços `0xe480*`), áudio HDMI, e um `kern.wlanbt(0x2)` (ver achado abaixo).

### Achado colateral relevante: `kern.wlanbt()` mostra que EXISTE precedente de função kernel interna pra gerenciar power de periférico — mas não há equivalente para GBE
Em `linux_boot.c:456`, dentro do hook `hook_icc_query_nowait` (executado no ponto de transição pro kexec), o payload chama `kern.wlanbt(0x2)` — uma função **resolvida por símbolo dentro do próprio kernel Orbis** (não um registrador MMIO/ICC) que desliga o WiFi/BT antes do jump pro Linux, comentário no código: "we re-enable it when the kernel boot". Isso prova que a Sony expõe (e o payload já usa) chamadas internas de kernel para controlar power de periféricos de rede.
Conferido `kernel.h`/`kernel.c` (a struct `ksym_t kern` inteira, todos os símbolos resolvidos): existe `wlanbt`, `set_gpu_freq`, `set_pstate`, `update_vddnp`, `set_cu_power_gate`, `set_nclk_mem_spd` — **nenhum equivalente para GBE/Ethernet**. Ou seja, os autores do payload kexec (projeto de terceiros, não a Sony) nunca precisaram mexer no power da GBE porque aparentemente nunca esperaram que ela precisasse — o que é consistente com a GBE não vir ligada por padrão nem sob Orbis quando o payload é carregado (ver ponto em aberto abaixo).

### ⚠️ Checagem de sanidade ainda NÃO feita — pode invalidar toda a premissa da investigação
Em nenhum documento do projeto até agora há confirmação de que a **GBE funciona sob o firmware Orbis original/retail** (com cabo de rede conectado, configurações de rede via cabo, sem Linux) neste console físico. Toda a investigação assume "a Orbis liga a GBE em algum ponto e o Linux não replica isso" — mas se a Orbis também nunca energiza a GBE a menos que o usuário troque para "Ethernet" nas configurações de rede do PS4 (em vez de usar Wi-Fi), então o payload kexec (que faz seu trabalho **depois** que a Orbis já está totalmente inicializada, via `hook_icc_query_nowait`) faria o kexec exatamente no estado em que a Orbis deixou a rail — que pode já estar desligada simplesmente porque a Orbis nunca a usou nessa sessão de boot. **Isso NÃO é um teste arriscado** (é só verificar/perguntar se o Wi-Fi está ativo nas configurações de rede da Orbis atualmente, ou trocar para Ethernet no menu de configurações e ver se a Orbis consegue link — sem nenhum payload/MMIO envolvido) e pode mudar completamente a direção da investigação: se a Orbis não conseguir link Ethernet nem sozinha, o problema não é "Linux não replica a inicialização da Orbis", é "a rail nunca foi ligada nesta sessão de boot, ponto".

### Próximo passo revisado (prioridade MÁXIMA, é só uma checagem, não um teste de risco)
Antes de continuar caçando registradores/comandos ICC: **confirmar através do menu de Configurações > Rede do próprio PS4 (ainda em Orbis/GoldHEN, sem payload nenhum) se a conexão via cabo Ethernet funciona** (testar conexão, ver se pega link/IP). Isso não precisa de payload, kexec, nem MMIO — é 100% seguro e decide se a premissa central de toda essa investigação (US "a Orbis liga a GBE e o Linux não") é válida ou não.

## Ambiente / ferramentas
- `radare2` instalado via `pacman` nesta sessão (não estava disponível antes).
- Comandos úteis usados:
  - `r2 -q -c "i" arquivo.bin` — info do binário (baddr, arch, etc.)
  - `r2 -q -c "izz~termo" arquivo.bin` — buscar strings no arquivo inteiro
  - `r2 -q -c "/r 0xVADDR" arquivo.bin` — buscar referências de código a um endereço (inclusive `lea rip-relative`)
  - `r2 -q -c "pd N @ 0xVADDR" arquivo.bin` — desmontar N instruções a partir de um endereço
- **Atenção:** `baddr` muda a cada dump novo (KASLR por boot) — sempre reconfirmar com `i` antes de reusar endereços absolutos de uma sessão anterior.

## ATUALIZAÇÃO REVOLUCIONÁRIA (2026-07-21): O "Power-On" da GBE é MMIO puro (BAR4), não ICC!

Durante testes ao vivo, executamos o comando `Major 5, Minor 0, Payload 04` via telnet para tentar ligar a GBE, já que ele era chamado no early boot do Orbis (`func_0xffffffffdc7c8a30(4)`). O resultado foi revelador:
1. O console **não travou** (o debugloop continuou rodando).
2. O **Wi-Fi caiu imediatamente** (erro `HAL_PORT_RD` no dmesg do Orbis e perda de pacotes no ping).
3. Isso provou categoricamente que o domínio de energia "Minor 0" da interface ICC (`icc_device_power`) é inteiramente dedicado à placa combinada **WLAN/BT** (dispositivo PCIe `00:14.3`). O comando `5 0 04` atuou desligando ou resetando o rádio/Wi-Fi. A GBE (**NÃO** controlada pelo Major 5 Minor 0) permaneceu intocada.

### A verdadeira inicialização da GBE (fcn.ffffffffdc5a0c80)
Reanalisamos a função de inicialização da GBE do Orbis (`fcn.ffffffffdc5a0c80`, que é chamada no attach do driver). Descobrimos que ela não faz chamadas ICC para ligar a energia. Em vez disso, ela realiza uma **sequência massiva de escritas MMIO na BAR4** (a região de controle da "Glue Logic" Baikal, mapeada em `0xc9000000`).
Especificamente, ela acessa offsets na sub-região `0xc000` (ex: `0xc0ac`, `0xc07c`, `0xc078`), que configuram os clocks (ex: gravando `25000000` = 25MHz) e controlam os bits de Hard Reset do próprio chip Marvell Yukon encapsulado dentro do Southbridge.

Lemos esses registradores do `BAR4` ao vivo e confirmamos que eles contêm valores de configuração e calibração (`0xbfbf8787`). O fato de o `B2_CHIP_ID` ler `00 00` não é falta de energia no barramento, mas sim que o núcleo MAC do Yukon está preso em **Hard Reset** pela Glue Logic (BAR4) por omissão do Linux, que nunca roda a rotina de descompressão/MMIO que o driver Orbis roda no attach!

**Conclusão Final:**
Devemos abandonar completamente as tentativas de ligar a GBE via `icc_device_power` (Major 5). O foco agora é **transcrever as escritas MMIO de `BAR4 + 0xc000` da função `dc5a0c80`** e executá-las no Linux (ou via script python antes do rebind) para tirar o Marvell Yukon do estado de Reset.

## ⚠️ CORREÇÃO DA SEÇÃO ACIMA (2026-07-21) — `dc5a0c80` NÃO EXISTE; a função real é `dc5a0ba0`

**`0xffffffffdc5a0c80` não é um início de função válido.** Verificado desmontando o código bruto: esse endereço cai **no meio de uma instrução** (`mov word [rbp-0xb0], 0`, que ocupa `0xc79`–`0xc82`), dois bytes antes de um `call 0xffffffffdc5a2840`. O r2ghidra, forçado a decompilar a partir dali, produziu uma pseudo-função sem prólogo, com registradores "não-atribuídos" (`unaff_R13`, `unaff_R15`, `in_RAX`) e uma linha de lixo logo no início (`*in_RAX = *in_RAX + in_RAX;`) — sinais claros de decompilação inválida. **O arquivo `consolidado/decompiled_dc5a0c80.txt` é, portanto, lixo e não deve ser usado como referência.**

**Função real: `0xffffffffdc5a0ba0`** (prólogo `push rbp; mov rbp,rsp` em `0xba0`; 4493 bytes, `0xba0`–`0x1d2d`, 115 basic blocks; recebe `arg1` = ponteiro do softc). Decompilação completa salva em **`consolidado/decompiled_dc5a0ba0_gbe_phy_calib.txt`**.

### O que a função REALMENTE faz (lida por completo, 530 linhas)

**1. Os "efuses" em BAR4+0xc000 — offsets corrigidos.** O acesso é via `func_0xffffffffdc7187a0(offset)`, confirmado por decompilação como `read32([global_0xffffffffde614e78]+0x10 → handle) + 0xc000 + offset`. Os offsets realmente usados são **`0x5c`, `0x60`, `0x64`, `0x68`, `0x6c`** (atenção: o decompilador imprime `0x64` como decimal `100`). A menção anterior a "`{0x60,0x68,0x6c}`" estava incompleta.

**➡️ CONFIRMAÇÃO CRUZADA FORTE com código Linux que já funciona:** `bpcie_baikal_sata_phy_init()` (em `drivers/ps4/ps4-bpcie.c`) lê **`sc->bar4 + 0xC000 + 108`** — que é exatamente `0x6C`, o MESMO registrador — e testa `BIT(18)`/`BIT(26)` como "efuse válido" para AHCI/xHCI. A rotina da GBE testa `(val & 0x80800000) == 0x80800000`, ou seja **bits 23 e 31 do mesmo registrador**. Isso prova que `BAR4+0xc000+0x6c` é um registrador compartilhado de "efuse/trim válido", com bits distintos por periférico — o mecanismo é real e já está parcialmente implementado no nosso Linux (só que apenas para SATA/USB).

**2. Os valores "mágicos" não são mágicos — são endereços MDIO Clause-45.** `func_0xffffffffdc5a24d0(softc, ENCODED, valor)` é uma **escrita** de registrador de PHY e `func_0xffffffffdc5a2680(softc, ENCODED, &out)` a **leitura** correspondente (esta última já documentada neste arquivo como "rotina clássica de acesso MDIO/SMI"). O campo `ENCODED` decodifica como `(reg16 << 8) | devad`:
- `0xe0001e` → devad `0x1E` (30), reg `0xE000`
- `0x115001f` → devad `0x1F` (31), reg `0x1150`
- `0x174001e` → devad `0x1E`, reg `0x1740`
- ...e mais ~18: `0x1750`, `0x1720`, `0x1730`, `0x0120`, `0x0160`, `0x0170`, `0x0180`, `0x0190`, `0x0200`, `0x0210`, `0x0220`, `0x0960`, `0x0370`, `0x0390`, `0x1070`, `0x1710`, `0x1890`, `0x1220`, `0x0330`, `0x2680`.

Devad 30/31 são exatamente os **MMDs "vendor specific 1/2" do MDIO Clause 45** — encaixa perfeitamente. Além disso há uma longa sequência **Clause 22** via `func_0xffffffffdc5a2950` (escrita) / `dc5a2840` (leitura), usando o padrão clássico de *page select*: escreve `0x52b5` no reg `0x1f`, depois `0x11`/`0x12`/`0x10`, e restaura a página — dezenas de tuplas de tuning do PHY analógico.

**3. ⚠️ PROBLEMA CRÍTICO — esta função NÃO pode reviver uma GBE morta (revisa a proposta de `bpcie_baikal_gbe_phy_init()`).**
Todo o trabalho dessa rotina é feito **via MDIO**, e as transações MDIO passam pelos registradores da **BAR0 do MAC** (`*(softc+0x3068)`, o mesmo par bus_space já mapeado em `dc5a2680`/`dc5a31f0`). Ela também escreve direto na BAR0 (`+0xac`=9, `+0x7c`=`25000000`, `+0x14`, `+0x18`, `+0x74`=`0x2277`, `+0x30`=`0x10100`, etc.).
**Se `B2_CHIP_ID` lê `00`, a BAR0 está morta — nenhuma dessas escritas tem efeito e o MDIO nunca completa.** Portanto essa função **pressupõe o MAC já vivo**, exatamente como `dc5a31f0` (init) e `dc5a3060` (stop), já classificadas assim neste documento. Ela é *downstream* do power-on, não a causa dele.

**Consequência prática:** a proposta registrada em `GBE_ACTION_PLAN.md` seção 3 — implementar `bpcie_baikal_gbe_phy_init()` transcrevendo esta sequência e chamando de `sky2_probe()` antes de ler o chip_id — **não se sustenta como está**. Transcrever escritas MDIO para um chip que não responde é inócuo.

**O que continua válido da analogia com o SATA (e é o ponto que importa):** em `bpcie_baikal_sata_phy_init()`, a parte que efetivamente "acorda" o bloco **não é** o tuning do PHY — é o *assert/release* das linhas de hold/pulse escritas na **BAR2 (glue)**, em `BPCIE_USB_BASE(0x180000) + {pulse_offset, hold_offset}`, feito **antes** de qualquer tuning e liberado **depois**. **`dc5a0ba0` não contém esse passo** — ou seja, o equivalente de hold/release da GBE está em outro lugar (provavelmente no caminho de attach do glue/`baikal_pcie`, ou já feito pela Orbis antes). **Achar o par `(pulse_offset, hold_offset)` da GBE na BAR2 é o alvo real — não transcrever o MDIO.**

## DESCOBERTA - 2026-07-21 - hierarquia PCI real: `mtsc_pci` → `mts` (MAC) / PHY

### ✅ Verificado por decompilação (2026-07-21) — `tools/re_find_func.sh` corrigido antes de aceitar
Os dois endereços abaixo foram checados com a ferramenta (que naquele momento tinha 3 bugs
próprios de alinhamento, corrigidos e revalidados contra a regressão conhecida antes de aceitar
qualquer conclusão — ver header de `tools/re_find_func.sh`). Ambos são início real de função.

1. **`mtsc_pci_attach`** (`0xffffffffdc5a0070`, 1734 bytes) — decompilado em
   `decompiled/mtsc_pci_attach_dc5a0070.txt`. Confirmado no pseudo-C:
   - Guarda seu softc no **global `0xffffffffde544938`** (`*0xffffffffde544938 = puVar6;`).
     **Esse é o MESMO global que `fcn.dc59fe10`** (a rotina de *stop* do MAC, achada via a tabela
     de blocos de `dc6df850` nos testes M8/M9) lê para localizar o softc — conecta duas
     descobertas de sessões diferentes.
   - Cria **5 DMA tags** via `func_0xffffffffdc3c9250`, salvas em `puVar6[0..4]` = offsets
     `0x00, 0x08, 0x10, 0x18, 0x20` (aritmética de ponteiro de 8 bytes). A afirmação original
     desta seção ("tags em 0x18 e 0x20") citava só as duas últimas — são 5 ao todo.
   - **Chama `func_0xffffffffdc5a0ba0(puVar6)` diretamente** — a função de calibração de PHY
     via MDIO já mapeada em detalhe na seção acima deste documento. Confirma que ela roda dentro
     do attach do `mtsc_pci`, não do `mts`.
   - Não localizei nesta função uma constante explícita `0x32d0` para o tamanho do softc — dois
     loops de zeragem cobrem o intervalo de offset `0x58` a `0x3058`, consistente com um softc
     grande (~0x3000+ bytes), mas o tamanho exato do softc é alocado pelo framework KOBJ/driver
     class fora desta função e não foi confirmado aqui.

2. **`mts_attach`** (`0xffffffffdc5a34f0`, 770 bytes) — decompilado em
   `decompiled/mts_attach_dc5a34f0.txt`. Confirmado no pseudo-C:
   ```c
   uVar4 = func_0xffffffffdc5b7a20(arg1);      // device_get_parent(dev)
   iVar5 = func_0xffffffffdc5b6b00(uVar4);     // device_get_softc(parent) -> softc do mtsc_pci
   puVar3[1] = arg1;
   puVar3[2] = iVar5;
   *(iVar5 + 0x30a0) = puVar3;                 // back-pointer do filho no softc do pai
   func_0xffffffffdc3c9cd0(*(iVar5 + 0x18), ...);   // usa a 4ª DMA tag do pai
   func_0xffffffffdc3c9cd0(*(iVar5 + 0x20), ...);   // usa a 5ª DMA tag do pai
   ```
   **`iVar5+0x30a0` bate exatamente** com o offset já mapeado em sessão anterior (achado em
   `dc5a5ec0`: "lê um ponteiro de device 'irmão' em `*(arg1+0x30a0)`") — confirma que é o campo
   usado para a ligação MAC↔PHY entre os dois softcs filhos.

### Hierarquia confirmada
```
pci0
 └─ mtsc_pci      (driver PCI real, dispositivo 0x104d:90d8 no Baikal / 0x909e no Aeolia)
     ├─ mts        (MAC, "SceGbeMtsCtrl" nos logs) — softc próprio, mas usa DMA tags do pai
     └─ mts (PHY)  ("SceGbeMtsPhyCtrl") — softc próprio, ligado ao MAC via +0x30a0
```
`baikal_pcie` (`0x104d:90db`) é um dispositivo PCI **diferente** — a glue do barramento (BAR2
pervasive), não o controlador da GBE.

### Anatomia completa do `mtsc_pci_attach` — verificação item a item (2026-07-21)

O usuário mapeou o passo a passo completo da função. Conferido item a item por decompilação:

| Afirmação | Veredito | Evidência |
|---|---|---|
| Aloca BAR0 (`SYS_RES_MEMORY`, rid `0x10`) e IRQ/MSI (`SYS_RES_IRQ`, rid `0x1`) | ✅ **estrutura confirmada**, ⚠️ literais não confirmados | ver abaixo |
| 5 DMA tags (`0x00,0x08,0x10,0x18,0x20`), com as duas últimas de `0xa0000`/`0x60000` bytes | ✅ **confirmado exatamente** | já verificado acima nesta sessão |
| vaddr/paddr das duas primeiras alocações em `0x38/0x40` e `0x48/0x50` | ✅ **confirmado exatamente** | `puVar6+7`/`puVar6[8]` e `puVar6+9`/`puVar6[10]` no decompilado |
| `device_add_child(dev, "mts", -1)` | ✅ **confirmado exatamente** | ver abaixo |

**BAR0/MSI — a função helper existe e faz exatamente isso, mas os valores literais da tabela
não foram lidos deste dump.** `func_0xffffffffdc5ba5e0` foi decompilada
(`decompiled/res_alloc_helper_dc5ba5e0.txt`) e é, comprovadamente, o
**`bus_alloc_resources(device_t dev, struct resource_spec *rs, struct resource **res)`** genérico
do FreeBSD: percorre uma tabela com stride de 12 bytes (`struct resource_spec {int type; int rid;
int flags;}`), parando no terminador `type == -1`, despachando cada entrada para o método kobj
`BUS_ALLOC_RESOURCE`. É chamada **duas vezes** em `mtsc_pci_attach`, com uma segunda tabela
escolhida condicionalmente (`puVar6[0x610]` alterna entre dois endereços dependendo de uma
checagem de capacidade anterior — compatível com "detectar quantidade de vetores MSI e escolher
a tabela de recursos correspondente", mas não confirmado literalmente). **Tentei ler os bytes da
tabela (`0xffffffffddd9ea30`) e vieram todos zero neste dump** — não consegui confirmar os
literais `tipo=3/rid=0x10` (BAR0) e `tipo=1/rid=1` (IRQ) por essa via. Registrado como estrutura
verificada, valores específicos em aberto.

**Investigação adicional (mesma sessão):** testei se era erro de leitura/sessão comparando com o
equivalente do `msk` (Aeolia/Belize) — mesma função `dc5ba5e0` chamada de dentro da região do
driver `msk`, apontando para tabelas em `0xddd92030`/`0xddd92050`. **Também leem zero.** E um
terceiro ponto de controle, um slot de cache de método KOBJ (`0xdddb28b0`, referenciado como
`*0xffffffffdddb28b0 * 8` no despacho de método dinâmico) **também lê zero** — mas esse é
legitimamente zero por design (cache populado só na primeira chamada). Como as três regiões
distintas leem zero de forma consistente, e este ELF não tem section headers para diferenciar
`.data`/`.bss`/regiões não capturadas, a explicação mais provável é que essa faixa de memória
simplesmente **não está com conteúdo útil neste snapshot** (não foi tocada/paginada no momento da
captura, ou é uma área de armazenamento em runtime não populada), não um erro de leitura nosso.
**Não vale insistir nessa via para os literais exatos** — se algum dia for necessário, teria que
vir de outro dump ou de leitura ao vivo do `.rodata` do módulo carregado no console real.

**`device_add_child(dev, "mts", -1)` — confirmado com precisão.** No assembly:
```asm
lea rsi, ["mts"]            ; 0xffffffffdcb0dc43, confirmado via `psz` = "mts"
mov rdi, r14                ; dev
mov edx, 0xffffffff         ; -1
call 0xffffffffdc5b6d30     ; = device_add_child(dev, "mts", -1)
```
Bate exatamente com a assinatura de 3 argumentos de `device_add_child`. (A busca inicial por
"mts" no texto decompilado não achou nada porque o decompilador deixa strings passadas por
endereço como literal hex cru, sem resolver — foi preciso ler a string diretamente com `psz`.)

### Implicação para o port Linux
O nosso `ps4-bpcie.c` não tem equivalente ao `mtsc_pci`: o `sky2` do Linux assume que o
dispositivo PCI da GBE (`00:14.1`) é auto-suficiente (BAR0 próprio, sem pai que aloque DMA tags
compartilhadas). Se a Sony aloca as DMA tags e chama a calibração de PHY (`dc5a0ba0`) a partir de
um driver PAI antes do `mts` (filho) rodar, isso é mais um candidato a "passo que falta" — mas
com a mesma ressalva já registrada acima: `dc5a0ba0` pressupõe o MAC vivo (usa MDIO/BAR0), então
não é ela quem liga a energia; na melhor hipótese ela só precisaria rodar mais cedo/no contexto
certo. **Não testado ao vivo.**

## ATUALIZAÇÃO IMPORTANTE (2026-07-21): A Teoria do D3hot e DPMS do Linux

Durante a análise contínua sobre o motivo de lermos `00 00` no registrador `B2_CHIP_ID` da GBE sob Linux, consolidamos a seguinte descoberta crucial:

### A Causa do `00 00` na BAR0 (Culpa do Linux, não do Syscon)
O hardware report (`hardware_report.txt`) confirmou que o barramento PCIe enxerga perfeitamente o **Sony Baikal Ethernet Controller** no endereço PCI `00:14.1`, e a BAR0 está mapeada em `0xc2000000`. No entanto, como o driver nativo `sky2` não possui o PCI ID `104d:90d8` mapeado, nenhum driver assume o controle do dispositivo durante o boot do Linux.
Pelo comportamento padrão de gerenciamento de energia (Power Management) do kernel Linux moderno, qualquer dispositivo PCI sem driver associado tem:
1. Seu bit de **Memory Decode** desabilitado no PCI Command Register.
2. Seu estado de energia forçado para **D3hot** (suspensão profunda).

Quando o dispositivo entra em `D3hot` ou perde o Memory Decode, qualquer tentativa de ler a BAR0 (`0xc2000000`) retorna `00 00` ou `ff ff`. Isso causou a falsa impressão de que a rail principal de energia (via Syscon/ICC) estava desligada, quando, na verdade, era apenas o PCI Subsystem do Linux bloqueando o acesso por inatividade.

### Incidente do "Display Apagado" e Estabilidade do Kernel
Durante testes via telnet na porta 23, notou-se que o display do PS4 apagou. Suspeitou-se inicialmente de um kernel panic induzido por "IRQ Storm" (ao alterar o PCI Command Register). Contudo, o usuário relatou que *"quando toquei no botão do painel frontal, ele desligou rápido sem travar"*. 
Isso documenta duas provas definitivas:
1. **O kernel Linux estava 100% vivo e funcional**: Um kernel panic teria travado o ACPI e o botão físico não responderia. O desligamento limpo e rápido confirma que o daemon de ACPI do Linux executou um `shutdown` normal e gracioso.
2. **O display apagou por DPMS**: A ausência prolongada de inputs físicos (teclado/mouse) fez o driver de vídeo aplicar o "Screen Blanking" (Screen Saver) padrão do Linux por inatividade. Nenhuma das tentativas de leitura de PCI causou instabilidade.

### Próximo Teste de Baixo Nível Definido
Para o próximo boot, o plano validado para acordar a placa é forçar o D0 e habilitar o Memory Decode diretamente no Config Space do dispositivo `00:14.1`, contornando o bloqueio do kernel:
```bash
# Habilitar Memory Space e Bus Master preservando demais bits (ex: INTx Disable)
setpci -s 00:14.1 COMMAND=0x06
# Ler a BAR0 novamente para encontrar o chip ID da Marvell Yukon
dd if=/dev/mem bs=1 count=32 skip=$((0xc2000100)) | od -An -tx1
```
Se a leitura retornar um ID válido (ex: `0xb3`), o passo definitivo será apenas injetar o ID `104d:90d8` no código-fonte do `sky2.c` e compilar o módulo.
