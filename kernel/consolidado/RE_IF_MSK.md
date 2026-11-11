# RE do `if_msk.c` (driver GBE Aeolia/Belize) e comparação com o `if_mts.c` (Baikal)

Análise estática do dump `kmem_dump_1252.bin`. Motivação: o `msk` é o driver FreeBSD do
Marvell Yukon-2 — **ancestral direto do `sky2` do Linux** — e o `sky2` **funciona** em
Aeolia/Belize. Como o Baikal usa o `mts`, a pergunta útil não é "como o `msk` funciona", e sim
**o que o `mts` faz que o `msk` não faz**.

> `baddr` deste dump = `0xffffffffdc350000`. Muda a cada boot (KASLR) — reconfirmar com
> `r2 -q -c i` antes de reusar qualquer endereço absoluto daqui.

## 1. Confirmado: `msk` = Aeolia/Belize, `mts` = Baikal

`fcn.ffffffffdc4cdfc0` é a **probe** do `msk` (retorna `0xffffffec` = `-20` =
`BUS_PROBE_DEFAULT`). Desmontada:

```asm
call dc5b6b00                   ; device_get_softc  -> rbx
call dc526e40                   ; identidade do SoC (& 0xff0000)
movzx r8d, byte [rbx + 0x30]    ; "GBE Id"  <- softc+0x30
movzx r9d, byte [rbx + 0x31]    ; "Rev"     <- softc+0x31
cmp   eax, 0x10000              ; família == Aeolia?
lea   rax, ["Aeolia"]           ; 0xdcaf51be
lea   rcx, ["Belize"]           ; 0xdcaf51c5
cmove rcx, rax                  ; escolhe o nome
call  dc630720                  ; snprintf(buf, 100, "%s GBE Id:0x%02x Rev:0x%02x", ...)
call  dc5b7c80                  ; device_set_desc
```

Só existem dois nomes possíveis: **Aeolia** (família `0x10000`) e **Belize** (qualquer outra).
O Baikal é `0x30000` e não é atendido por este driver — bate com `SceGbeMskCtrl` (Aeolia/Belize)
vs `SceGbeMtsCtrl` (Baikal).

### ⚠️ A probe do `msk` NÃO lê `B2_CHIP_ID`
O "GBE Id" e o "Rev" impressos vêm de **`softc+0x30`/`softc+0x31`**, preenchidos antes, e não de
uma leitura do registrador `B2_CHIP_ID` (`BAR0+0x11a`) — que é justamente o que o `sky2` do Linux
lê e onde ele falha com `unsupported chip type 0x0`.

Isso **não** explica sozinho o nosso problema (o `sky2` funciona em Aeolia/Belize lendo esse
registrador, então lá ele responde), mas registra que o driver da Sony não depende dessa leitura
para identificar o hardware.

## 2. ACHADO ESTRUTURAL: a GBE do PS4 tem um **L2 switch**, não só MAC+PHY

As tabelas de strings dos **dois** drivers contêm o mesmo conjunto:

| String | `msk` (Aeolia/Belize) | `mts` (Baikal) |
|---|---|---|
| `gbe0.1` → `eth0` | ✅ | ✅ |
| `gbe0.2` → `dbg0` | ✅ | ✅ |
| `L2 switch has been reset.` | ✅ | ✅ |
| `gbe:rmu` (kthread) | ✅ | ✅ |
| `switch_rmu_reg_read` / `_write` / `_exec` / `_get_id` | ✅ | — (não localizadas) |
| `Switch ID = 0x%04x` | ✅ | — |
| `VTU Busy` (VLAN Table Unit) | ✅ | — |
| `Skip VLAN config OUI: 0x%04x, Model: 0x%04x` | ✅ | — |

**Conclusão:** o subsistema de rede do PS4 é **MAC Yukon → L2 switch Marvell → PHY**, e o switch
expõe **duas portas**: `gbe0.1` (= `eth0`, a porta LAN física) e `gbe0.2` (= `dbg0`, uma porta de
depuração). O switch é gerenciado **in-band via RMU** (Remote Management Unit) — comandos
enviados como quadros Ethernet pelo próprio caminho de DMA, não por MMIO.

Isso explica retroativamente o mecanismo já mapeado em `RE_KERNEL_GBE_ATTACH.md`
(`fcn.dc5a58d0`): montar um mbuf, transmitir pela fila de TX normal e esperar um contador de
resposta incrementar, com "ethertype"/magic `0xfa42`. **Aquilo é conversa com o L2 switch**, não
com o MAC.

### Por que isso importa para o nosso problema
O `sky2` do Linux trata o dispositivo como um Yukon simples. Não há, no `sky2`, nenhuma noção de
switch L2, RMU, VTU ou porta `dbg0`. Em Aeolia/Belize isso não impede o MAC de funcionar (e de
fato funciona). **Não está estabelecido** que a ausência disso seja a causa da falha no Baikal —
o `B2_CHIP_ID` lendo `00` é anterior a qualquer questão de switch. Fica registrado como contexto
arquitetural que faltava, não como causa.

## 3. Inventário de diagnóstico do `msk` (referência)

Strings de erro úteis para reconhecer sintomas caso algum dia se porte esse caminho:

```
phy read timeout. (phy=%d, reg=%d)          waiting for read completion, i=%d, val=0x%08x
phy write timeout. (phy=%d, reg=%d, ...)    waiting for write completion, i=%d
Retry L2 Switch Init OK. (%d)               Retry L2 Switch Init NG.
%s: no response from L2 Switch              L2 switch has been reset.
Rx/Tx descriptor error                      Hw error status=0x%08x
PHY FIFO underrun/overflow.                 Tx FIFO underrun!
prefetch unit stuck?                        watchdog timeout (missed link)
initialization failed: no memory for Rx buffers
kthread_suspend_async failed (gbe:ctrl)     Tx BMU stop failed
```

Região de código do driver: **`0xdc4c5000`–`0xdc4d1000`** neste dump (71 xrefs à string do
caminho `if_msk.c`, em `0xffffffffdcaf4afd`).

## 4. `attach` do `msk` — localizado e VERIFICADO por decompilação (2026-07-21)

Existem duas camadas: o controller (`mskc`) e a porta (`msk`).

- **`mskc_probe`** (`0xffffffffdc4c4ff0`): Compara o Vendor ID com `0x104d` (Sony) e o Device ID
  com `0x909e` (Aeolia) ou `0x90c9` (Belize). Usa uma tabela de IDs PCI em `0xffffffffdd450df0`.
- **`mskc_attach`** (`0xffffffffdc4c5140`): Aloca a BAR0 e lê `B2_MAC_CFG` (offset `0x11b`) e
  **`B2_CHIP_ID` (offset `0x11a`)** — confirmado no pseudo-C decompilado
  (`consolidado/decompiled/mskc_attach_dc4c5140.txt`):
  ```c
  pcVar14 = *(iVar12 + 0x10) + 0x11b;
  cVar2 = *(*piVar7 + 8) == 0 ? in(pcVar14) : *pcVar14;   // B2_MAC_CFG
  *(piVar7 + 6) = cVar2;
  puVar15 = *(iVar12 + 0x10) + 0x11a;
  uVar3 = *(*piVar7 + 8) == 0 ? in(puVar15) : *puVar15;   // B2_CHIP_ID
  *(piVar7 + 0x31) = uVar3 >> 4;
  if (cVar2 == -0x43) { ... }                              // 0xbd — valor esperado
  ```
  **Prova, por RE direta e não por inferência, que o driver original da Sony para Aeolia/Belize
  espera que `B2_CHIP_ID`/`0x11a` responda normalmente** — são os mesmos offsets que o `sky2` do
  Linux lê e onde ele falha no Baikal com `unsupported chip type 0x0`. Isso reforça (não prova
  sozinho, mas é evidência a favor) que os três chips da família usam a mesma convenção de
  detecção via BAR0, e que o `chip_id=0` do Baikal é genuinamente um problema de power/reset —
  não um offset errado nem uma suposição arquitetural equivocada da nossa parte.
- **`msk_attach`** (`0xffffffffdc4ce060`): attach da porta LAN em si — anéis de DMA, thread
  `gbe:ctrl`, setup da interface.

**Pendências que continuam abertas:**
- Não confirmei se o `mts` (Baikal) tem as rotinas `switch_rmu_*` com outros nomes, ou se a
  gestão do switch no Baikal é feita de forma diferente. As strings `switch_rmu_*` só apareceram
  na região do `msk`.
- Ainda não há evidência de que a diferença msk/mts explique o `chip_id = 0` — as duas linhas
  seguem independentes até que algo as conecte.

### ⚠️ Nota de método: os 3 endereços acima quase foram descartados por bug na ferramenta
Ao conferir esta descoberta, `tools/re_find_func.sh` inicialmente **contradisse** os três
endereços (relatou que `0xdc4c4ff0` e `0xdc4c5140` resolviam para fora dos limites da função mais
próxima). Investigação do assembly bruto mostrou que os três **são mesmo** início real de função
— a ferramenta tinha três bugs próprios (janela de bytes desalinhada, entre outros; detalhes no
cabeçalho do script). Corrigidos e revalidados contra a regressão conhecida (`0xdc5a0c80`) antes
de aceitar esta descoberta. Ver header de `tools/re_find_func.sh` para o histórico completo.

## 5. Método

```bash
# 1) achar a região do driver pelas xrefs da string do caminho do arquivo
r2 -q -c "izz~if_msk.c" kmem_dump_1252.bin          # -> offset da string
r2 -q -c "/r <vaddr>" kmem_dump_1252.bin            # -> xrefs = região do driver

# 2) listar as strings vizinhas (ficam agrupadas por driver na seção de dados)
r2 -q -c "izz" kmem_dump_1252.bin | awk '{off=strtonum("0x"substr($2,3));
  if (off>=INICIO && off<=FIM) print}'

# 3) resolver a função de um xref ANTES de decompilar
consolidado/tools/re_find_func.sh kmem_dump_1252.bin <vaddr> saida.txt
```

O passo 2 foi o mais produtivo aqui: a tabela de strings de um driver fica contígua na seção de
dados, então listar a vizinhança da string do caminho do arquivo entrega de uma vez o vocabulário
inteiro do driver (nomes de função, mensagens de erro, nomes de interface) — foi assim que o L2
switch apareceu, sem precisar decompilar nada.
