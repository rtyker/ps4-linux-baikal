---
name: scripts-build-inject-riscos-app-bin-desatualizado
description: "Auditoria 2026-07-20 de rebuild.sh/build_diag.sh/inject.sh/listen.sh + Makefile do scene-kmem-dumper: nenhum bug ativo confirmado agora, mas 5 riscos de design que podem causar 'edição não chegou no teste' — pendente de correção, usuário pediu para não mexer ainda"
metadata:
  node_type: memory
  type: project
  originSessionId: 2026-07-20-session
  modified: 2026-07-20T00:00:00.000Z
---

Auditoria pedida pelo usuário em 2026-07-20 ("investigue se rebuild.sh/listen.sh/inject.sh estão corretamente apontados e construindo o app.bin, pois algumas alterações não estão indo para os testes"). Verificação por timestamp confirmou que, NO MOMENTO da auditoria, o `app.bin` estava sim atualizado em relação à última edição de `kern_base_finder.c` (source 14:01:14, `.o`/`app.bin` gerados 14:01:25) — ou seja, não havia um bug ativo pegando no flagra. Mas a auditoria achou 5 riscos estruturais reais que explicam por que isso pode falhar silenciosamente:

1. **`inject.sh` nunca builda nem checa staleness.** Só envia o `app.bin` que já está no disco — não roda `make`, não compara mtime do binário com os `.c`. Editar source e rodar `inject.sh` direto (sem `rebuild.sh` antes) injeta o binário velho, sem aviso nenhum.
2. **`make clean` apaga `app.bin` mesmo ao buildar só o `diag.bin`.** O alvo `clean` do `Makefile` (`scene-kmem-dumper/Makefile`) remove `$(TARGET)` incondicionalmente. `build_diag.sh` roda `make clean` antes de `make diag.bin` — toda vez que se builda o diag, o `app.bin` some até alguém rodar `rebuild.sh` de novo.
3. **`TARGET = $(shell basename "$(CURDIR)").bin` é frágil.** Só vira `app.bin` porque `rebuild.sh`/`build_diag.sh` montam o volume Docker em `-w /app`. Se `make` rodar fora desse container exato, o binário sai com outro nome e nem `rebuild.sh` nem `inject.sh` detectam — `inject.sh` continuaria enviando um `app.bin` antigo.
4. **Lista de objetos do link é hardcoded** (`$(ODIR)/kern_dumper_main.o $(ODIR)/kern_base_finder.o` na recipe de `$(TARGET)`), não usa a variável `$(OBJS)` calculada a partir de `$(CFILES)`. Hoje bate porque só há esses 2 arquivos fonte relevantes, mas um novo `.c` adicionado em `source/` seria compilado (é dependência) e NÃO linkado (recipe não muda) — falha silenciosa futura.
5. **`listen.sh` (raiz do projeto, não em `scene-kmem-dumper/`) tem parâmetros mortos.** Aceita `PS4_IP`/`PORT` como `$1 $2`, mas `ps4-linux-payloads/receive_kmem_dump.py` ignora esses args — IP (`192.168.6.130`) e porta (`9020`) estão hardcoded dentro do próprio `.py`, que só lê `argv` pra START/SIZE/OUT. Passar IP diferente pro `listen.sh` não faz nada, silenciosamente.

**Achado à parte (não é bug de script):** o `inject_diag.sh` criado nesta mesma sessão (ver [[sessao-2026-07-20-kern-base-finder]]) sumiu do disco entre um turno e outro — nenhum script do repo o apaga (nem `rebuild.sh` nem `build_diag.sh` tocam em `.sh`), causa desconhecida, provavelmente remoção manual. Precisa ser recriado antes do próximo uso do `diag.bin`.

**Status:** usuário optou por NÃO aplicar nenhuma correção agora ("não faça nada") — só documentar. Antes de propor de novo, perguntar; não aplicar essas correções por iniciativa própria.

**Correções propostas (não aplicadas):**
- Fazer `inject.sh`/`inject_diag.sh` chamarem `rebuild.sh`/`build_diag.sh` automaticamente antes de injetar (ou pelo menos abortar se `app.bin` for mais velho que qualquer `.c` em `source/`).
- Trocar a lista hardcoded de objetos na recipe de `$(TARGET)` por `$(OBJS)`.
- Recriar `inject_diag.sh`.
