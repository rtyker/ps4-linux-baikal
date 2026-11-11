---
name: sessao-2026-07-20-debug-incremental
description: "2026-07-20: re-instrumentação do app.bin com contador incremental [step++] em cada notificação para rastrear exatamente até onde a execução chegou"
metadata:
  node_type: memory
  type: project
  originSessionId: 2026-07-20-session
  modified: 2026-07-20T00:00:00.000Z
---

## Mudanças aplicadas

`kern_dumper_main.c` e `kern_base_finder.c` foram completamente re-instrumentados:

1. **`kern_dumper_main.c`:**
   - Adicionado `int step = 0;` no início de `_main()`
   - Cada `printf_notification()` agora leva um `[%d]` seguido de `step++` — ex: `printf_notification("[%d] iniciando initKernel", step++)`
   - Notificações também adicionadas para cada passo crítico: entrada/saída de funções init, alocação de memória, socket setup, conexão TCP, início de dump, limpeza de recursos
   - Sequência esperada: [0] até [35+] dependendo do caminho (LSTAR vs SCAN, sucesso vs falha)

2. **`kern_base_finder.c`:**
   - Adicionados campos `int pages_scanned` e `int copyout_errors` à struct `kern_base_result_t` (já existiam, agora usados)
   - `try_lstar_method()`: sem prints novos (LSTAR é rápido), mas comentários adicionados explicando cada validação
   - `try_scan_method()`: comentários adicionados em pontos-chave (magic encontrada, header lido, PT_LOAD iterado)
   - `kern_base_finder()`: comentários para deixar claro que é LSTAR-primeiro, depois SCAN-fallback

## Valores esperados de `[step]` na TV (cenário sucesso)

```
(initKernel, initLibc, initNetwork sem notificações — essas libs precisam estar carregadas)

[0] inicializacoes OK
[1] alocando result struct
[2] OK mmap result
[3] chamando kern_base_finder via kexec
[4] OK kexec retornou
[5] LSTAR/SCAN: LSTAR=0x... base=0x... size=0x...
[6] criando socket TCP
[7] OK socket criado (fd=...)
[8] configurando sockaddr_in
[9] OK sockaddr_in pronto
[10] bind + listen na porta 9020
[11] OK bind+listen porta 9020
[12] aguardando conexao (accept)
[13] OK conexao aceita (fd=...)
[14] recebendo pedido (start,size)
[15] OK pedido: start=0x... size=0x...
[16] alocando buf (...)
[17] OK buf alocado
[18] iniciando dump de kernel
[...] (nenhuma notificação durante loop de envio de chunks)
[19] DUMP CONCLUIDO: 0x... bytes enviados, N chunks com erro
[20] limpando: munmap buf
[21] limpando: munmap result
[22] limpando: close conn
[23] limpando: close srv
[24] programa finalizado com sucesso
```

Total esperado: ~25 notificações até [24] se tudo der certo.

## Cenários de falha (o que procurar)

### Para em [8] "chamando kern_base_finder via kexec"
- O `kexec()` não retorna — hang silencioso.
- Nenhuma notificação [9] aparece; console continua respondendo (não é kernel panic).
- **Suspeita:** `kexec()` ou o `copyout_kernel()` macro dentro de `kern_base_finder` têm problema neste console.

### Para em [9] retornou, mas [10] mostra LSTAR=0x0 base=0x0
- O `kexec()` retornou corretamente.
- Ambos os métodos (LSTAR + scan fallback) falharam.
- **Suspeita:** LSTAR lê como 0 neste contexto, scan ELF não encontrou magic `\x7fELF` em nenhuma das 256 páginas 2MB (ou `copyout_kernel()` não funciona bem).

### Para entre [11-22] (stack TCP)
- Socket criado, mas bind/listen/accept falha.
- **Suspeita:** Problema de permissão de rede ou port 9020 em uso.

### Chega até [24], mas enviou 0 bytes
- Dump "completo" mas nenhum byte transferido.
- **Causa:** kernel_base retornou como 0 (deve ter aparecido em [10]).

## Rebuild e teste

Build já foi feito: `./rebuild.sh` executado em 2026-07-20 14:10, gerou `app.bin` (27628 bytes, maior que antes por causa das notificações).

**Próximo passo:** Injetar este novo `app.bin` via `./inject.sh`, observar a TV, anotar a sequência de `[N]` até aonde chega, e usar isso para definir o próximo passo de investigação.

Lembrar: Todo teste precisa de um power cycle do PS4 entre tentativas ([[app-bin-um-teste-por-powercycle]]).
