---
name: feedback-dados-live-harness-sobrepoe-docs-antigos
description: "Quando dados coletados ao vivo via harness_gbe.py (ou testes ao vivo equivalentes) conflitarem com o que está documentado em consolidado/*.md de sessões anteriores, o dado ao vivo mais recente prevalece."
metadata:
  node_type: memory
  type: feedback
  originSessionId: f3c36916-3701-4d7d-932c-68a4af43a5c3
---

O usuário afirmou explicitamente (2026-07-22): "lembre-se que a nossa verdade que encontramos via harness sobrepuja os documentos antigos."

**Regra:** ao encontrar um documento estático (`consolidado/*.md`, memórias antigas) que contradiz ou parece refutar uma linha de investigação, não tratar isso como veto automático — cruzar com os dados mais recentes coletados ao vivo (SQLite `test_history`/`hardware_registers`, `dmesg.log`) primeiro. Se o dado ao vivo é mais novo e foi coletado de forma sistemática (varredura ampla, sondagem ICC completa), ele tem precedência sobre a conclusão estática do documento antigo — os docs podem estar desatualizados, incompletos, ou basear conclusões em testes menos completos do que os que fazemos hoje.

**Como aplicar:** ainda vale mencionar o que os documentos antigos dizem (dá contexto e evita retrabalho cego), mas ao decidir o próximo passo, priorizar o que os dados ao vivo mais recentes mostram. Não descartar uma linha de investigação só porque um doc antigo (ex: `GBE_ACTION_PLAN.md`, testes M8-M13) a marcou como "refutada" — revalidar com os dados atuais antes de abandonar.

## Reforço 2026-07-22 (ampliado): vale também para RE/decompilação, e para os MEUS próprios argumentos

O usuário reafirmou: *"entre o que está escrito e o que foi medido ao vivo, prefiro o que foi lido ao vivo"*. Isso estende a regra além dos `consolidado/*.md` antigos — **inclui decompilação, planos e a própria argumentação do assistente**. Toda vez que uma alegação for verificável por medição, medir em vez de argumentar.

Exemplos concretos do dia em que a regra decidiu a questão nos dois sentidos:

- **Contra o documento:** o `GBE_PLANO_SOFTWARE_RESET.md` definia sucesso como "chip ID válido do Yukon 2 (`0x0a`/`0x0b`)" e `sky2: Yukon-2 EC Ultra`. A medição ao vivo (strings do dump + BAR0 viva) mostrou que o hardware é **MTS, não Yukon** — critério inalcançável por construção, descartado.
- **A favor de um argumento, mas só depois de medido:** a objeção a habilitar Bus Master vinha da decompilação (`0x40`/`0x44`/`0x48` seriam ponteiros de anel de DMA). Em vez de sustentar isso pela RE, foi medido: `/proc/iomem` ao vivo mostra `00700000-7efe7fff : System RAM`, e os ponteiros medidos na BAR0 (`0x100042a0`, `0x10000000`, `0x10004000`) caem **dentro** dessa faixa. A objeção passou de inferência a fato medido.
- **Contra a premissa central do projeto:** ver [GBE-VIVA-driver-errado-mts-nao-sky2](GBE-VIVA-driver-errado-mts-nao-sky2.md) — a teoria "GBE desalimentada" sobreviveu sessões inteiras enquanto os 36 registradores vivos que a refutavam já estavam gravados no SQLite.

**Regra prática que emerge:** antes de defender uma conclusão por raciocínio, perguntar "isso é mensurável no console?". Se for, medir primeiro.
