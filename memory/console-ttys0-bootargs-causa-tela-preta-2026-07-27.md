---
name: console-ttys0-bootargs-causa-tela-preta
description: Adicionar console=ttyS0,115200n8 ao bootargs.txt causou tela preta/boot travado (rede e UART mudas) — revertido, causa raiz não confirmada
metadata:
  type: project
---

# `console=ttyS0,115200n8` no bootargs.txt causou tela preta (2026-07-27)

## Contexto

Sessão de teste da solda de UART TTL feita pelo usuário no southbridge Baikal. Objetivo: confirmar a solda vendo o log de boot do kernel Linux sair pela porta serial física (`/dev/ttyUSB0` no PC, via adaptador 3.3V).

## O que foi feito

1. Confirmado que o `cmdline` ativo padrão usa só `console=tty0` — o log de boot nunca foi direcionado à UART física.
2. `/dev/ttyS0-3` do kernel são portas 8250 legadas (`port:0x3F8` etc.) reportadas como `uart:unknown` — não são a UART física do Baikal (que fica em MMIO `0xC890E000`, dentro do BAR `bpcie.glue` 00:14.4, região já documentada como perigosa para pokes cegos).
3. Editado `bootargs.txt` (partição `/dev/sdb1`, montada em `/mnt/bootpart` via SSH) adicionando `console=ttyS0,115200n8` antes do `console=tty0` existente (backup salvo em `bootargs.txt.bak`).
4. `reboot` via SSH → boot via disco `HEN.AIO` (não payload de rede) deu **erro de R/W no disco** na primeira tentativa (ver pendência separada no `BACKLOG.md`, "Boot via disco AIO — erros de R/W constantes").
5. Segunda tentativa de boot (mesmo bootargs com `ttyS0` incluído) → **tela preta**, sem ping, sem dados na UART em nenhum baud rate testado (115200/9600/57600/38400/19200/230400).
6. Restaurado `bootargs.txt.bak` (HD conectado direto no PC via leitor, sem precisar de SSH). Boot seguinte com bootargs original → **subiu normal** (ping OK, SSH OK, `uptime` confirmado).

## Conclusão

- A adição de `console=ttyS0,115200n8` é suspeita de causar falha de boot (tela preta) neste kernel/build (`bzImage` de 2026-07-26 no `/dev/sdb1`), mas **não está 100% isolada** do erro de R/W do disco que o usuário já relata como recorrente/constante (ver `BACKLOG.md`) — a tela preta pode ter sido causada por qualquer um dos dois problemas, ou pela combinação.
- **Não repetir esse teste exatamente do mesmo jeito** (adicionar `console=ttyS0,115200n8` cru e reiniciar) sem antes isolar a variável do erro de R/W do disco (ex: confirmar 2-3 boots limpos consecutivos com o bootargs ORIGINAL antes de reintroduzir a mudança).
- Hipótese técnica ainda não verificada: como `/dev/ttyS0` no `/proc/tty/driver/serial` aparecia como `uart:unknown` (porta legada 0x3F8 sem hardware real detectado), é possível que o driver 8250 trave/demore tentando inicializar uma porta que não existe fisicamente nesse endereço, atrasando ou travando o boot antes do vídeo subir. Se for isso, a UART física do Baikal precisaria de outro caminho (earlycon MMIO customizado ou driver dedicado), não o `console=ttyS0` genérico x86.

## Próximo passo (quando retomado)

1. Primeiro resolver/entender o erro de R/W do disco (`BACKLOG.md`) isoladamente, com bootargs original, para ter um baseline limpo de boots repetidos com sucesso.
2. Só depois testar `console=ttyS0,115200n8` de novo, e se travar de novo, testar `earlycon=uart8250,mmio32,0xC890E000` (caminho MMIO direto, conforme `consolidado/obsoleto/CABO_UART.md`) em vez do `ttyS0` legado — mais provável de ser o caminho correto para a UART física soldada, já que ela está em MMIO Baikal, não em I/O port x86 legado.
3. Testar sempre com o HD acessível fisicamente pro PC como plano B de revert rápido (como fizemos aqui), não só via SSH — SSH fica inacessível se o boot travar antes da rede subir.
