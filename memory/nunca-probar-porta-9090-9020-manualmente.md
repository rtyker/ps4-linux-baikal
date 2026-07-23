---
name: nunca-probar-porta-9090-9020-manualmente
description: "REGRA DURA: nunca fazer probe/teste de conectividade manual (ping é OK, mas TCP connect NÃO) nas portas 9090 (BinLoader/Payload Server do GoldHEN) e 9020 (dump TCP) do PS4 — consome o accept() único do servidor e trava a injeção"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: fc4fadeb-3722-411d-a2a9-87e84f1aeebc
  modified: 2026-07-19T20:55:19.080Z
---

**Nunca abrir uma conexão TCP manual (nem só pra testar se a porta está aberta) contra a porta 9090 ou 9020 do PS4** — nem com `/dev/tcp/IP/porta` do bash, nem `nc`, nem `python socket.connect()` solto, nem nenhuma outra ferramenta.

**Why:** o servidor BinLoader do GoldHEN (porta 9090) e o próprio payload de dump (porta 9020) fazem `accept()` de UMA ÚNICA conexão e travam/saem depois. Uma conexão TCP completa é feita no handshake (SYN/SYN-ACK/ACK) assim que o `connect()` do lado cliente sucede — isso sozinho já consome o `accept()` do servidor, mesmo que a conexão seja fechada imediatamente sem enviar nada. Cometi esse erro DUAS VEZES na mesma sessão (2026-07-19): uma vez com `/dev/tcp/.../9090` só pra "verificar se a porta está aberta" antes de injetar, e me esqueci da própria regra e repeti minutos depois. Cada vez que isso aconteceu, a porta 9090 passou a recusar conexões (`Conexão recusada`) e o usuário teve que sair e reentrar na tela do Payload Server no PS4 pra reabrir o listener.

**How to apply:**
- Pra checar se o PS4 está na rede, usar só `ping` (não consome nenhum socket TCP do payload server).
- Pra injetar de fato, usar SEMPRE `send_payload_loop.py` (ele faz `connect_ex` e, se conectar, já manda o payload imediatamente — não deixa a conexão "pendurada" sem uso).
- Pra capturar o dump, usar SEMPRE `receive_kmem_dump.py` (mesma lógica: só conecta quando já vai mandar o pedido de verdade).
- NUNCA rodar um `cat < /dev/null > /dev/tcp/IP/9090`, `nc -zv IP 9090`, ou qualquer probe "inofensivo" nessas duas portas específicas do PS4. Isso é diferente de portas normais de servidor multi-conexão, onde probing seria inofensivo.
