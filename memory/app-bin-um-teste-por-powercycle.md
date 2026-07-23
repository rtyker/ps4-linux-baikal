---
name: app-bin-um-teste-por-powercycle
description: "O app.bin do scene-kmem-dumper (kern_dumper_main.c/kern_base_finder.c) só permite UM teste bem-sucedido por power cycle do PS4 — depois disso, precisa desligar da tomada e religar antes de tentar de novo"
metadata:
  node_type: memory
  type: project
  originSessionId: 2026-07-20-session
  modified: 2026-07-20T00:00:00.000Z
---

**O `app.bin` (dumper atual em `scene-kmem-dumper/`, compilado de `kern_dumper_main.c` + `kern_base_finder.c`) só aceita UMA injeção/teste por power cycle do console.** Depois de um teste (sucesso ou falha), reinjetar sem reiniciar o PS4 não funciona — é preciso um power cycle completo (tirar da tomada 15–30s) antes da próxima tentativa.

**Why:** observado na sessão 2026-07-20 — depois do Teste 2 (LSTAR=0, mas fluxo completo até abrir porta 9020), a tentativa seguinte de reinjetar sem reboot não progrediu; só voltou a funcionar depois de um power cycle completo. Causa raiz ainda não confirmada (suspeita: o `kexec()`/hook do payload deixa algum estado do kernel — página mapeada, GDT/IDT alterada, ou o próprio listener na porta 9020 — "sujo" depois da primeira execução, e uma segunda injeção sem reboot esbarra nesse estado residual). Isso é diferente da regra [[nunca-probar-porta-9090-9020-manualmente]] (que é sobre não fazer probe manual) — aqui o problema é needing reboot mesmo fazendo tudo certo (`send_payload_loop.py` limpo).

**How to apply:**
- Todo ciclo de teste do `app.bin` (ou variantes como `diag.bin`) no PS4 real deve ser tratado como **um power cycle completo = um teste**. Não tentar reinjetar em sequência sem reiniciar o console.
- Ao planejar uma sessão de testes ao vivo, contar o tempo de power cycle (15–30s de tomada + boot do PS4 + reabrir GoldHEN/Payload Server) como parte do custo de CADA iteração — não assumir que dá pra iterar rápido testando várias versões seguidas.
- Se um teste falhar ou não progredir como esperado, a próxima ação correta é sempre "avisar o usuário para fazer power cycle" antes de sugerir reinjetar — não insistir em reinjetar sem isso.
- Vale investigar futuramente (não bloqueador agora): o que exatamente fica "sujo" entre execuções — se for algo específico e corrigível no payload (ex.: fechar o socket TCP corretamente, restaurar algum estado do `kexec`), pode ser possível eliminar essa limitação.
