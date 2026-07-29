# Plano — Teste de Instrumentação ACK Debug (2026-07-28)

## Objetivo
Confirmar **exatamente quando e por que o glue para de sinalizar a subfunção 1 (SATA)** após 6.219s.

## Hipótese sob teste
O registrador `BPCIE_ACK_READ` (BAR2 glue `0x110088`) **trava em estado fixo** (`0x001e0103` = "só sub0 pendente") após 6.219s, e o glue nunca mais reconhece a subfunção 1 como tendo dados a entregar.

## Build
- **Tag:** `20260728-sata-glue-ack-debug`
- **Mudanças:** dump do `BPCIE_ACK_WRITE` cru (antes da limpeza) na primeira invocação de func7
- **Bootargs:** `sata-noncq-hdmi-force-20260728.txt` (console UART + HDMI otimizado)
- **Initramfs:** `sata-noncq-fix-20260728.cpio.gz` (compatível)

## O que procurar no log UART

### Fase 1: Boot até 6.219s
Esperado:
```
[    2.XXX] bpcie_dbg: func7 — ACK_WRITE (antes)=0x????????  ← novo (nosso debug)
[    3.XXX] bpcie_dbg: f7 -> despacho subfuncao 1 (#1)
[    3.XXX] bpcie_dbg: f7 -> despacho subfuncao 1 (#2)
...
[    6.219] bpcie_dbg: f7 -> despacho subfuncao 1 (#6)
```

### Fase 2: Silêncio (6.219s até 97s)
Esperado:
```
[    6.220] ← NENHUMA chamada de sub1
[    7.000] ...
[   36.000] ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6 frozen
...
[   97.XXX] bpcie_dbg: f7 sub0 call#4096 — sub1 continua ausente
```

## Pergunta crítica que será respondida
**O `vec_read` (ACK state) nunca muda, ou muda e depois trava?**

Se no log de debug aparecer um `ACK_WRITE` diferente **depois** do silêncio começar, isso sugere:
- A subfunção 1 **foi limpa permanentemente** do ACK
- O glue pode estar hard-resetando o SATA internamente

Se o `ACK_WRITE` **nunca mudar**, então:
- O registrador está congelado
- Há um erro no hardware ou no firmware do glue

## Próximos passos após coleta
1. Comparar `vec_read` nos primeiros 30s vs. após 97s
2. Se mudou: investigar **quem** modificou o ACK (não foi o demux)
3. Se não mudou: investigar por que o MAC SATA parou de marcar pendência

## Contingência
Se a compilação falhar ou o boot travar, reverter para:
```bash
sudo ./deploy-boot-7.0.sh sata-noncq-hdmi-force-20260728
```
(versão estável anterior)
