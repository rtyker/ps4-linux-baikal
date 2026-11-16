# M9 — Varredura de leitura: tabela de blocos de fcn.dc6df850

Objetivo: descobrir se algum dos **4 blocos não identificados** da tabela de reset do Baikal se comporta diferente dos que sabemos funcionar. Se o bloco `0x2000` não é a GBE (uma das duas explicações abertas após o M8 refutar a hipótese), ela deve ser um destes.

Apenas **leituras** — provadas seguras no M8. Os 4 primeiros blocos (USB0/USB1/SATA/xHCI) entram como **grupo de controle**: sabemos que funcionam, então servem de baseline.

Base: BAR2 `0xc8800000` + `0x180000` (a mesma janela que `fcn.dc718710` usa e que o `resetUsbPort()` do nosso driver já acessa em produção).

Um passo por vez, com ping após cada um; o arquivo é atualizado a cada passo, então um travamento não perde os dados anteriores.

| # | Alvo | Comando | Resultado | Console |
|---|---|---|---|---|
| 1 | USB0  (controle) — hold 0x24 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980024/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980024/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 2 | USB0  (controle) — pulse 0x64 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980064/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980064/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 3 | USB1  (controle) — hold 0x28 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980028/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980028/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 4 | USB1  (controle) — pulse 0x68 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980068/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980068/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 5 | SATA  (controle) — hold 0x2c | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898002c/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898002c/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 6 | SATA  (controle) — pulse 0x6c | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898006c/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898006c/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 7 | xHCI  (controle) — hold 0x30 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980030/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980030/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 8 | xHCI  (controle) — pulse 0x70 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980070/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980070/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 9 | GBE?  (refutado) — hold 0x20 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980020/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980020/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 10 | GBE?  (refutado) — pulse 0x74 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980074/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980074/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 11 | BLOCO 0x3c00 ??? — hold 0x34 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980034/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980034/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 12 | BLOCO 0x0c00 ??? — hold 0x14 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980014/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980014/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 13 | BLOCO 0x1000 ??? — hold 0x18 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980018/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980018/4)) 2>/dev/null | od -An -tx4 00000000` | OK |
| 14 | BLOCO 0x1400 ??? — hold 0x1c | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898001c/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898001c/4)) 2>/dev/null | od -An -tx4 00000000` | OK |

**Varredura concluída — 14 passos, console vivo ao final.**


## Resultado: todos os 14 registradores leem `00000000` — inclusive os 4 blocos desconhecidos

Nenhum dos blocos `0x3c00`, `0x0c00`, `0x1000`, `0x1400` se distingue. Console vivo nos 14 passos.

## Verificação crítica: a janela É legível (o zero é dado real, não artefato)

Como até os periféricos **ativos** (USB0/USB1/SATA/xHCI) liam zero, surgiu a dúvida de se
esses registradores retornam informação alguma — o mesmo padrão do M3, onde `0x10a030`
sempre lia `0` após qualquer escrita (registrador de comando/pulso, não de estado).

Dump de 128 bytes da janela (`0xc8980000`, `od -Ax -tx4 -v`):
```
000000 00000001 00000000 00000000 00000000
000010 00000000 00000000 00000000 00000000
000020 00000000 00000000 00000000 00000000
000030 00000000 00000000 00000000 00000001
000040 00000000 00000001 00000000 00000001
000050 00000000 00000000 00000000 00000000
000060 00000000 00000000 00000000 00000000
000070 00000000 00000000 00000000 00000000
```
**Quatro offsets retornam `1`: `0x00`, `0x3c`, `0x44`, `0x4c`.** Ou seja, a janela é legível e
alguns registradores dela realmente retêm estado. Nenhum desses quatro aparece na tabela de
blocos de `fcn.dc6df850` — são registradores ainda não identificados dessa mesma região.

## Conclusão (com a incerteza que de fato resta)

**A refutação do M8 se sustenta, mas não é hermética.** A favor dela: a janela é legível e há
registradores nela que retêm valor, então o `00000000` dos hold/pulse é leitura real e
uniforme entre GBE e periféricos funcionando. Contra: não está provado que *esses* offsets
específicos retêm estado — podem ser strobes de escrita que sempre leem `0`, caso em que a
leitura não diz nada sobre hold estar ativo ou não.

**O que NÃO se pode mais afirmar:** que soltar o hold da GBE resolveria — se o registrador
lê igual ao dos periféricos que funcionam, escrever ali não muda o estado observável.

**Alvo novo que apareceu:** os offsets `0x3c`, `0x44` e `0x4c`, que valem `1` e não estão
mapeados na RE. Vale procurar no dump do kernel quem os escreve (`fcn.dc718710` com esses
imediatos) antes de qualquer teste ao vivo.

## Ferramenta produzida

`sweep.py` + `plano_*.json` (no scratchpad da sessão): executa um acesso por vez, grava a
tentativa no arquivo de controle **antes** de executar (com `fsync`), verifica vida por ping
após cada passo, e guarda o índice do último passo OK para retomar com `--resume` após um
power cycle. Foi desenhado exatamente para o caso em que um passo trava o console: nada do
que já foi medido se perde, e o passo culpado fica identificado.
