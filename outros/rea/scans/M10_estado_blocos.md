# M10 — Registradores de estado dos blocos (BAR2+0x140000+BLOCO+0x20)

Alvo melhor que o M9: na rotina de quiesce `fcn.dc6df850`, cada bloco tem um registrador em **outra janela** (`0x140000`, acessada por `dc7187d0`/`dc718800`) do qual o código **limpa os bits 0 e 4**. Diferente dos hold/pulse — que leem `0` em todos os blocos, inclusive nos que funcionam — esses retêm estado real.

Se a GBE estiver com bits diferentes dos periféricos funcionando, temos o alvo com lastro que faltava. Grupo de controle (USB0/USB1/SATA/xHCI) primeiro, como no M9.

Somente leituras, um passo por vez, arquivo atualizado a cada passo.

| # | Alvo | Comando | Resultado | Console |
|---|---|---|---|---|
| 1 | USB0 (controle) — 0x4000+0x20 = 0xc8944020 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8944020/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8944020/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 2 | USB1 (controle) — 0x4400+0x20 = 0xc8944420 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8944420/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8944420/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 3 | SATA (controle) — 0x3800+0x20 = 0xc8943820 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8943820/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8943820/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 4 | xHCI (controle) — 0x4800+0x20 = 0xc8944820 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8944820/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8944820/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 5 | GBE? (bloco 0x2000) — 0x2000+0x20 = 0xc8942020 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8942020/4)) 2>/dev/null | od -An -tx4` | ⏳ em execução | — |

> **Retomado após power cycle** — continuando do passo 5.

| 5 | GBE? (bloco 0x2000) — 0x2000+0x20 = 0xc8942020 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8942020/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8942020/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 6 | BLOCO 0x3c00 ??? — 0x3c00+0x20 = 0xc8943c20 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8943c20/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8943c20/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 7 | BLOCO 0x0c00 ??? — 0xc00+0x20 = 0xc8940c20 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8940c20/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8940c20/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 8 | BLOCO 0x1000 ??? — 0x1000+0x20 = 0xc8941020 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8941020/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8941020/4)) 2>/dev/null | od -An -tx4 06040400` | OK |
| 9 | BLOCO 0x1400 ??? — 0x1400+0x20 = 0xc8941420 | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8941420/4)) 2>/dev/null | od -An -tx4` | `dd if=/dev/mem bs=4 count=1 skip=$((0xc8941420/4)) 2>/dev/null | od -An -tx4 06040400` | OK |

**Varredura concluída — 9 passos, console vivo ao final.**

