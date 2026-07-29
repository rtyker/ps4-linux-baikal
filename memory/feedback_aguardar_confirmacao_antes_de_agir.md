---
name: feedback_aguardar_confirmacao_antes_de_agir
description: Nunca diagnosticar, tentar remediar ou propor ação corretiva sem antes confirmar com o usuário o que está de fato acontecendo
metadata:
  type: feedback
---

Quando algo parece errado durante um teste ao vivo no PS4 (captura vazia, PS4 não
responde a ping/SSH, boot demorando), **perguntar o que está na tela e esperar a
resposta antes de qualquer diagnóstico ou ação** — não presumir falha, não cogitar
rollback, não descrever cenários de "isso pode significar X ou Y" como se fossem
igualmente prováveis sem ter perguntado primeiro.

**Why:** em 2026-07-28, a captura UART ficou 15 minutos gravando só a censura
pré-kexec (bytes `0x20`) e o PS4 parou de responder a ping/SSH. Isso levou a um
diagnóstico ansioso (";pode estar travado, pode ser preocupante, ligado às minhas
mudanças") quando a causa real era trivial: **o usuário ainda nem tinha iniciado o
boot** — não tinha carregado o payload. Nada de errado havia acontecido; eu deveria
ter perguntado "o que está na tela?" e parado aí, sem elaborar hipóteses de falha.

Isso é uma extensão prática da "Regra de Ouro da Injeção" já registrada em
`AGENTS.md`: a regra cobre não disparar o payload sem esperar o "pronto"; esta
lição cobre o lado simétrico — não *reagir* a uma ausência de sinal como se fosse
um problema, sem antes confirmar o estado real com quem está olhando a tela.

**How to apply:** ao armar uma captura/monitor para um boot ao vivo, depois de
"ligar" a instrumentação, o próximo passo do assistente é **esperar** — não
verificar o resultado, não montar teorias, não gerar diagnóstico — até o usuário
dizer que o boot foi iniciado (ou que algo aconteceu). Se um monitor expira sem
dado nenhum, a primeira pergunta é "você chegou a iniciar/carregar o payload?",
não uma lista de hipóteses técnicas.
