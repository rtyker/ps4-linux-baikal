---
name: devmem-nao-existe-usar-dd-octal
description: O comando devmem NÃO existe no initramfs do PS4 — toda escrita MMIO tem que ser via printf octal + dd. Harnesses que usam devmem com 2>/dev/null falham silenciosamente.
metadata:
  type: feedback
---

# ⛔ `devmem` NÃO EXISTE neste sistema — e o `2>/dev/null` esconde isso

Medido ao vivo em 2026-07-22:

```
~ # which devmem
/bin/sh: devmem: not found
~ # devmem 0xc2000034 32 0x00000001; echo exit=$?
/bin/sh: devmem: not found
exit=127
~ # busybox devmem 0xc200007c 32
devmem: applet not found
~ # busybox --list | grep -i mem
smemcap
```

Não existe nem como binário próprio, nem como applet do busybox. O único applet com "mem" no nome é `smemcap`.

## O estrago

Toda a sessão de 2026-07-22 usou `devmem <addr> 32 <valor> 2>/dev/null` nos harnesses de escrita. O `2>/dev/null` engoliu o `not found`, o comando "rodou" sem erro aparente, e **nenhuma escrita jamais chegou ao hardware**. Os testes seguintes foram todos reportados como "sem efeito" — quando na verdade nada tinha sido escrito:

| fase | teste | status real |
|---|---|---|
| 8 | pulso isolado bit 10 (`0x10a030`/`34`) | nenhuma escrita ocorreu |
| 9 | sweep hold/pulse GBE (`0xc8980020`/`0x74`) | nenhuma escrita ocorreu |
| 10 | sequência correta AHCI/xHCI nos 2 offsets | nenhuma escrita ocorreu |
| 14 | enable do MAC (`BAR0+0x34`/`0x38`) | nenhuma escrita ocorreu |

Também os testes intermediários `CHIPID_STEP_BY_STEP` e `REPEAT_SEQUENCE` (8 ciclos). Todos marcados `INVALIDO_DEVMEM_NAO_EXISTE` em `test_history` e `write_sweep_results`.

**Atenção:** o `harness_gbe.py` (harness oficial do projeto) usa `devmem` no Bloco 9 (pulso de 4 passos do bit 10) com o mesmo `2>/dev/null`. Ou seja, **esse bloco nunca escreveu nada em nenhuma execução histórica** — todas as conclusões de "pulso sem efeito" tiradas dele precisam ser revistas.

## O método que funciona: `printf` octal + `dd`

Já estava documentado no projeto em [escrita-mmio-telnet-printf-octal-nao-hex](escrita-mmio-telnet-printf-octal-nao-hex.md) (escaping `\xHH` não é confiável via telnet — usar `\NNN` octal). Medido funcionando:

```sh
printf '\001\000\000\000' | dd of=/dev/mem bs=4 count=1 seek=$((0xc2000034/4))
# 1+0 records in / 1+0 records out / 4 bytes (4B) copied  -> exit=0
```

Ordem dos bytes é **little-endian**: para escrever `0xAABBCCDD`, os bytes vão `\DDD \CCC \BBB \AAA` em octal (byte menos significativo primeiro).

## Regras que ficam

1. **Nunca usar `devmem`** neste projeto. Toda escrita MMIO via `printf` octal + `dd of=/dev/mem`.
2. **Nunca suprimir stderr de um comando cujo sucesso importa.** O `2>/dev/null` existia para calar ruído do `dd`, mas calou o erro que invalidava a sessão inteira.
3. **Sempre conferir o exit code e a saída do `dd`** (`records in/out`, `bytes copied`) — é a prova de que a escrita ocorreu.
4. **Verificar o instrumento antes de concluir sobre o alvo.** Um resultado "sem efeito" só tem valor se a ação foi comprovadamente executada. Antes de reportar não-efeito, provar que o comando rodou.

## Primeira escrita REAL medida (via `dd`)

Escrevendo `0x00000001` em `0xc2000034` com o método correto (exit 0, 4 bytes copiados), a releitura ainda devolve `0x00000000`. Esse é o **primeiro dado válido** sobre esse registrador — ao contrário de tudo que foi reportado antes. Ainda não permite concluir se é write-only, self-clearing ou write-ignored. Ver [GBE-VIVA-driver-errado-mts-nao-sky2](GBE-VIVA-driver-errado-mts-nao-sky2.md) para o contexto do bring-up do MAC.

## Segundo caso no mesmo dia: falso positivo na sonda MDIO (Fase 15)

Poucas horas depois de corrigir o `devmem`, o **mesmo tipo de falha** apareceu de novo — agora não no instrumento, mas no **critério de sucesso**.

A sonda MDIO (`harness_gbe_mdio_probe.py`) leu 8 registradores diferentes do PHY e declarou *"MDIO RESPONDEU com dados plausíveis em 8 de 8 alvos — bring-up VALIDADO"*. Mas os 8 alvos devolveram **exatamente o mesmo valor `0x7949`**, que já estava no registrador **antes** de qualquer transação. PHY ID1, PHY ID2, Control 1 e Status 1 não podem ter conteúdo idêntico — a transação simplesmente não completou.

A lógica só verificava `res != 0x0000 and res != 0xFFFF`. Passou.

**Correção aplicada** — duas exigências, ambas necessárias para aceitar uma leitura como real:
1. o dado tem que **diferir do valor pré-existente** no registrador (resíduo);
2. alvos diferentes têm que devolver **valores diferentes entre si**.

Ambas validadas contra o próprio caso que gerou o falso positivo (rejeitado) e contra um caso sintético de leitura real (aceito).

**Padrão comum aos dois erros do dia:** aceitar um resultado sem verificar que o mecanismo que o produziria realmente funcionou. No primeiro caso, o comando não existia; no segundo, o valor era resíduo. **Regra:** todo critério de sucesso precisa incluir um controle negativo — algo que falharia se o mecanismo não estivesse operando. "Valor não é zero" não é controle; "valores diferem entre alvos diferentes" é.
