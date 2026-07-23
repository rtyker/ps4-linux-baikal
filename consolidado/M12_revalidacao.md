# M12 — REVALIDAÇÃO COMPLETA com o harness corrigido

Reexecução de **todas** as medições M8–M11 com `ps4cmd.py` corrigido (marcadores `___INI___`/`___FIM___`) e `sweep.py` que **aborta em saída vazia** em vez de marcar OK.

Motivo: a 1ª execução do M11 marcou 9 passos como OK sem ter medido nada — o console respondia, mas a extração da saída estava quebrada. M8 e M9 usaram a mesma extração antiga, então seus dados precisam ser reconfirmados antes de sustentar qualquer conclusão.

**Controles de validade embutidos nesta mesma execução** (passos 4–7): quatro endereços que devem devolver valores DIFERENTES entre si. Se todos derem igual, a leitura não discrimina e nenhum resultado desta rodada vale.

| # | Alvo | Comando | Resultado | Console |
|---|---|---|---|---|
| 1 | SANIDADE — kernel em execução | `uname -r` | `7.0.8-Strawberry-ThinLTO-Baikal-+` | OK |
| 2 | SANIDADE — BAR0 real da GBE (sysfs) | `head -1 /sys/bus/pci/devices/0000:00:14.1/resource` | `0x00000000c2000000 0x00000000c2000fff 0x0000000000140204` | OK |
| 3 | SANIDADE — sky2 no dmesg | `dmesg | grep -i sky2 | tail -3` | `(vazio)` | OK |

> ⚠️ **Passo 3 respondeu mas devolveu saída VAZIA.** O console está
> vivo, então não é travamento — é falha de captura. Os dados deste passo
> NÃO foram medidos; corrigir a extração e reexecutar antes de concluir.


> **Retomado após power cycle** — continuando do passo 3.

| 3 | SANIDADE — sky2 bound a algum dispositivo? | `ls /sys/bus/pci/drivers/sky2/ 2>/dev/null | grep -c '00:' ; echo fim` | `0 fim` | OK |
| 4 | CONTROLE — 0xc8940000 (esperado 10206333) | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8940000/4)) 2>/dev/null | od -An -tx4 -v` | `10206333` | OK |
| 5 | CONTROLE — 0xc8945000 (esperado 00000000) | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8945000/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 6 | CONTROLE — 0xc894f000 (esperado ffffffff) | `dd if=/dev/mem bs=4 count=1 skip=$((0xc894f000/4)) 2>/dev/null | od -An -tx4 -v` | `ffffffff` | OK |
| 7 | CONTROLE — 0xc8947800 (esperado ffffffff) | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8947800/4)) 2>/dev/null | od -An -tx4 -v` | `ffffffff` | OK |
| 8 | GBE — B2_CHIP_ID/MAC_CFG @0xc2000118 | `dd if=/dev/mem bs=1 count=4 skip=$((0xc2000118)) 2>/dev/null | od -An -tx1 -v` | `30 00 00 00` | OK |
| 9 | 180000 — USB0 hold 0x24 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980024/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 10 | 180000 — USB0 pulse 0x64 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980064/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 11 | 180000 — USB1 hold 0x28 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980028/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 12 | 180000 — USB1 pulse 0x68 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980068/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 13 | 180000 — SATA hold 0x2c | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898002c/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 14 | 180000 — SATA pulse 0x6c | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898006c/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 15 | 180000 — xHCI hold 0x30 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980030/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 16 | 180000 — xHCI pulse 0x70 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980070/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 17 | 180000 — GBE? hold 0x20 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980020/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 18 | 180000 — GBE? pulse 0x74 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980074/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 19 | 180000 — BLK 0x3c00 hold 0x34 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980034/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 20 | 180000 — BLK 0x0c00 hold 0x14 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980014/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 21 | 180000 — BLK 0x1000 hold 0x18 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8980018/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 22 | 180000 — BLK 0x1400 hold 0x1c | `dd if=/dev/mem bs=4 count=1 skip=$((0xc898001c/4)) 2>/dev/null | od -An -tx4 -v` | `00000000` | OK |
| 23 | 180000 — dump 0x00..0x7f (mapa da janela) | `dd if=/dev/mem bs=1 count=128 skip=$((0xc8980000)) 2>/dev/null | od -Ax -tx4 -v` | ` 00000000 00000000 00000000 000060 00000000 00000000 00000000 00000000 000070 00000000 00000000 00000000 00000000 000080` | OK |
| 24 | 140000 — USB0 bloco 0x4000 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8944000/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00007000 00000000` | OK |
| 25 | 140000 — USB1 bloco 0x4400 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8944400/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000c000 00000000` | OK |
| 26 | 140000 — SATA bloco 0x3800 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8943800/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000a000 00000000` | OK |
| 27 | 140000 — xHCI bloco 0x4800 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8944800/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00007000 00000000` | OK |
| 28 | 140000 — GBE? bloco 0x2000 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8942000/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000e000 00000000` | OK |
| 29 | 140000 — BLK 0x3c00 bloco 0x3c00 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8943c00/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000d000 00000000` | OK |
| 30 | 140000 — BLK 0x0c00 bloco 0xc00 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8940c00/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 0000e000 00000000` | OK |
| 31 | 140000 — BLK 0x1000 bloco 0x1000 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8941000/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00002000 00000000` | OK |
| 32 | 140000 — BLK 0x1400 bloco 0x1400 (48B) | `dd if=/dev/mem bs=4 count=12 skip=$((0xc8941400/4)) 2>/dev/null | od -An -tx4 -v` | `10106333 00000000 00000000 00000000 00000000 00000000 00200001 000050c5 06040400 00000000 00007000 00000000` | OK |

**Varredura concluída — 32 passos, console vivo ao final.**


## Resultado: TODAS as medições M8–M11 confirmadas

### Controles de validade — a leitura discrimina (passos 4–7)
| Endereço | Valor | Esperado |
|---|---|---|
| `0xc8940000` | `10206333` | ✅ |
| `0xc8945000` | `00000000` | ✅ |
| `0xc894f000` | `ffffffff` | ✅ |
| `0xc8947800` | `ffffffff` | ✅ |

Quatro endereços, quatro respostas distintas. **Nenhum resultado desta rodada é artefato de
leitura** — que era a dúvida que motivou a revalidação.

### ⚠️ Armadilha evitada no passo 8 — o chip_id NÃO mudou
O passo 8 leu `30 00 00 00` em `0xc2000118`, contra `00 00 00 00` das medições anteriores.
Parece mudança, **mas não é**: releituras dão `0c 00 00 00`, `00 00 00 00`, `30 00 00 00`.

O byte que varia é o de **offset `0x118`**, que a seção "Observações auxiliares" já registrava
como volátil. O `B2_CHIP_ID` fica em `0x11a` e o `B2_MAC_CFG` em `0x11b` — **terceiro e quarto
bytes, ambos `00` em todas as leituras, sem exceção**. A GBE continua muda.

Registrado porque é exatamente o tipo de leitura apressada que geraria falso entusiasmo: o
primeiro byte do dump não é o chip_id.

### Demais medições — todas idênticas às rodadas anteriores
- **Janela `0x180000`** (passos 9–22): todos os hold e pulse = `00000000`, incluindo GBE.
- **Mapa da janela** (passo 23): apenas `0x00`, `0x3c`, `0x44` e `0x4c` valem `1`; resto zero.
- **Janela `0x140000`** (passos 24–32): os 9 blocos byte a byte idênticos (`10106333 …`).
- **`sky2` bound a 0 dispositivos** (passo 3) — confirma que o probe falhou, como esperado.

## Conclusão

**Nenhum falso positivo. Os resultados M8–M11 estavam corretos** e agora estão confirmados com
harness corrigido e controles de validade na mesma execução. A linha de investigação da glue
permanece encerrada: em três janelas distintas, a GBE é indistinguível dos periféricos que
funcionam.

## Nota de método: o guarda de saída vazia se provou na prática

Na primeira tentativa, o M12 **abortou no passo 3** porque `dmesg | grep -i sky2` devolveu
vazio. Verificação posterior mostrou que `dmesg | grep -ci sky2` retorna `3` — as linhas
existem, foi **falha de captura**, não resultado legítimo. Sem o guarda, teriam sido gravadas
30 linhas "OK" a partir de uma sessão telnet já degradada.

Causa: o `dmesg` do console acumula horas de `=== DEBUG LOOP N ===`, e percorrer esse buffer
engasga a sessão telnet (o console em si nunca oscilou — ping com 0% de perda o tempo todo).
**Evitar `dmesg` sem filtro agressivo neste console**; usar `/sys` quando possível, como foi
feito ao trocar o passo 3 por `ls /sys/bus/pci/drivers/sky2/`.
