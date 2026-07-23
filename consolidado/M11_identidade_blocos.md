# M11 — Identidade dos blocos: primeiros 48 bytes de cada BLOCO (BAR2+0x140000)

O M10 mostrou que `BLOCO+0x20` vale `06040400` em **todos** os 9 blocos — provável registrador de ID/versão do wrapper (mesmo IP instanciado por bloco), não estado. Confirmado que a região decodifica endereços: dentro de um bloco os valores variam.

Aqui lemos os **primeiros 48 bytes** de cada bloco, onde o offset `+0x00` mostrou valor específico (`10106333` no bloco `0x2000`). Objetivo: identificar cada bloco pela sua assinatura e ver se a GBE difere dos periféricos que funcionam.

Somente leituras, um passo por vez.

| # | Alvo | Comando | Resultado | Console |
|---|---|---|---|---|
| 1 | USB0 (controle) — 0x4000+0x00 = 0xc8944000 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8944000)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000f000 00000000` | OK |
| 2 | USB1 (controle) — 0x4400+0x00 = 0xc8944400 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8944400)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000a000 00000000` | OK |
| 3 | SATA (controle) — 0x3800+0x00 = 0xc8943800 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8943800)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00001000 00000000` | OK |
| 4 | xHCI (controle) — 0x4800+0x00 = 0xc8944800 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8944800)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00006000 00000000` | OK |
| 5 | GBE? (bloco 0x2000) — 0x2000+0x00 = 0xc8942000 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8942000)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00002000 00000000` | OK |
| 6 | BLOCO 0x3c00 ??? — 0x3c00+0x00 = 0xc8943c00 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8943c00)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00001000 00000000` | OK |
| 7 | BLOCO 0x0c00 ??? — 0xc00+0x00 = 0xc8940c00 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8940c00)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00003000 00000000` | OK |
| 8 | BLOCO 0x1000 ??? — 0x1000+0x00 = 0xc8941000 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8941000)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000c000 00000000` | OK |
| 9 | BLOCO 0x1400 ??? — 0x1400+0x00 = 0xc8941400 | `dd if=/dev/mem bs=1 count=48 skip=$((0xc8941400)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00009000 00000000` | OK |

**Varredura concluída — 9 passos, console vivo ao final.**


## Resultado: os 9 blocos têm conteúdo BYTE A BYTE IDÊNTICO

```
10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 ...
```
Igual em USB0, USB1, SATA, xHCI, no bloco `0x2000` e nos quatro nunca identificados.

### Controle: não é espelhamento — a região decodifica endereços de verdade
| Endereço | Valor | Leitura |
|---|---|---|
| `0xc8940000` (bloco 0) | `10206333 …` | **conteúdo diferente** dos blocos |
| blocos `0x0c00`–`0x4800` | `10106333 …` | idênticos entre si |
| `0xc8945000` | `00000000` | região existente porém vazia |
| `0xc894f000`, `0xc8947800` | `ffffffff` | nada mapeado |

Quatro respostas distintas para quatro endereços distintos: a janela decodifica. Portanto os
nove blocos **de fato** contêm o mesmo valor — são a mesma IP de wrapper instanciada N vezes,
todas em estado de reset padrão.

## Conclusão consolidada dos testes M8–M11

Em **três janelas distintas** da glue, o bloco da GBE é **indistinguível** dos periféricos que
estão funcionando naquele exato momento:

| Janela | Registrador | GBE | USB/SATA/xHCI |
|---|---|---|---|
| `0x180000` | hold / pulse | `00000000` | `00000000` |
| `0x140000` | `BLOCO+0x20` | `06040400` | `06040400` |
| `0x140000` | `BLOCO+0x00..0x2f` | idêntico | idêntico |

**O estado de reset/hold do bloco na glue não é o que diferencia a GBE.** Isso encerra a linha
aberta na seção 4 do `GBE_ACTION_PLAN.md` — não há o que "soltar": o bloco já está no mesmo
estado dos que funcionam.

Reforça também a segunda explicação que ficou em aberto no M8: **o bloco `0x2000` provavelmente
não é a GBE.** A associação veio da vizinhança da chamada a `dc59fe10` na rotina de *quiesce* —
evidência circunstancial. Como os nove blocos são idênticos, essa varredura não consegue nem
confirmar nem negar qual bloco é qual: **a identidade dos blocos não é observável por leitura**
neste estado.

## Lição de método (o M11 quase virou um falso negativo)

A primeira execução do M11 marcou os 9 passos como `OK` — mas a coluna de resultado continha
apenas o eco do comando, sem dado nenhum: o helper de telnet quebrava com comandos contendo
múltiplos pipes e aspas. **O harness reportou sucesso porque o console respondeu; ele não tinha
como saber que a saída estava vazia.**

Corrigido em dois pontos:
1. `ps4cmd.py` passou a delimitar a saída com marcadores `___INI___`/`___FIM___` e extrair
   estritamente o que está entre eles — imune ao conteúdo do comando;
2. `sweep.py` passou a **abortar** quando um passo responde mas devolve saída vazia, em vez de
   contá-lo como OK. Console vivo + saída vazia = falha de captura, não medição.
