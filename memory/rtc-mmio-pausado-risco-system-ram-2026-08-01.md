---
name: rtc-mmio-pausado-risco-system-ram-2026-08-01
description: RTC via MMIO real pausado — endereços 0x05180000/0x05140000 caem dentro de System RAM ativa no mapa do Linux, risco não aceito pelo usuário.
metadata:
  type: project
---

## Decisão

Seguindo `PLANO_RTC_FINALIZACAO_2026-08-01.md` (Passo 1, bloqueador), foi checado `/proc/iomem` ao
vivo no PS4 (2026-08-01). Resultado:

```
00700000-7efe7fff : System RAM
  06000000-0763a09f : Kernel code
  07800000-08b25fff : Kernel rodata
  08c00000-08d155ff : Kernel data
  08e8b000-08f25fff : Kernel bss
```

Os endereços do RTC via ICC (`0x05180000` ≈ 81,5 MB read, `0x05140000` ≈ 81,3 MB write —
confirmados por RE do `rtc.c` do Orbis 12.52, ver `memory/rtc-via-icc-re-validada-2026-07-25.md`)
caem **dentro** desse bloco `System RAM`, o mesmo range genérico onde o próprio kernel Linux tem
código/dados carregados. Não é uma região reservada/dedicada — é RAM ativamente gerenciada pelo
alocador de páginas.

Apresentadas ao usuário 4 opções (reservar a região via `memmap=`/`memblock_reserve`; testar
`ioremap` direto mesmo assim; investigar se o Orbis/FreeBSD e o Linux enxergam o mesmo endereço
físico neste hardware; ou pausar). **Usuário escolheu pausar — risco não vale a pena.**

## Estado resultante

- O driver `drivers/rtc/rtc-ps4-icc.c` permanece na versão atual (contador de software via
  `jiffies`, funcional mas não persiste hora entre boots — ver
  `memory/rtc-patch-idempotencia-quebrada-e-corrigida-2026-08-01.md`). Essa versão é segura (não
  toca em MMIO nenhum) e continua sendo a idempotente/commitada no patch.
- `PLANO_RTC_FINALIZACAO_2026-08-01.md` (raiz do projeto) fica pausado nos Passos 2-5 (lógica MMIO,
  build, deploy, teste de reboot). Não retomar sem novo direcionamento do usuário ou uma via segura
  para os endereços MMIO (ex: confirmação de que Orbis/Linux não compartilham o mesmo mapa físico
  nesses endereços, ou uma estratégia de reserva de memória validada).
- Nenhuma mudança de código foi feita nesta sessão para o RTC — só o registro desta decisão.
