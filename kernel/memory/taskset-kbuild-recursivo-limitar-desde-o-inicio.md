---
name: taskset-kbuild-recursivo-limitar-desde-o-inicio
description: "taskset/renice pós-hoc num build de kernel (make -j) em andamento não propaga pros sub-makes recursivos do kbuild já em execução — só funciona se aplicado ANTES do build começar"
metadata:
  node_type: memory
  type: feedback
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

Tentar limitar CPU/prioridade de um build de kernel (`00-build-kernel-7.0.sh`, que roda `make -j$(nproc)` via `build.sh`) DEPOIS que ele já começou, usando `taskset -pc`/`renice -p` no processo raiz, **não funciona de forma confiável**.

**Por quê:** o kbuild é fortemente recursivo — o `make -j8` do topo dispara dezenas de sub-`make` recursivos (um por subdiretório do kernel) via jobserver compartilhado (pipe/FD), não só por hierarquia de processos simples. `taskset -pc`/`renice -p` só afeta o PID exato que você aponta; processos-filho JÁ EM EXECUÇÃO (sub-makes recursivos que já tinham nascido antes do comando) mantêm sua afinidade/prioridade original e continuam gerando `clang` sem restrição. Em 2026-07-17, tentei restringir um build já rodando (`taskset -pc 0-3` + `renice -n 15` no processo `bash` raiz e num `make` filho) e a carga da máquina não caiu — os `clang` continuavam usando todos os 8 núcleos, porque o `make -j8` real (uma camada abaixo do que eu tinha restringido) nunca foi tocado.

**Como aplicar:** se o usuário pedir pra limitar recursos de um build de kernel, aplicar `taskset -c 0-3` (e/ou `nice -n 15`) **envolvendo o comando inteiro desde o `nohup`/lançamento** (ex: `sudo bash -c 'nohup nice -n 15 taskset -c 0-3 ./00-build-kernel-7.0.sh <tag> > log 2>&1 & disown'`), nunca como correção pós-hoc num build já em andamento — nesse caso a única forma confiável é matar e reiniciar o build (ok fazer isso, é incremental, a perda de progresso é pequena). Ver [[build-kernel-sempre-com-sudo]].
