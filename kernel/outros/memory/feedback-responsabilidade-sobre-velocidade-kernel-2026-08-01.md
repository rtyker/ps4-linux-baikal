---
name: feedback-responsabilidade-sobre-velocidade-kernel-2026-08-01
description: Usuário pede responsabilidade e cautela acima de velocidade em mudanças de kernel/módulos — não fazer ciclos de build/teste/desfazer sem disciplina.
metadata:
  type: feedback
---

## Regra

Para mudanças de kernel/módulos (e por extensão, qualquer mudança técnica de risco/irreversibilidade não-trivial neste projeto): priorizar responsabilidade sobre velocidade. Analisar patches com cuidado antes de aplicar, evitar ciclos de build/teste/desfazer repetidos sem plano claro, validar cada mudança isoladamente (compilação isolada do(s) arquivo(s) tocado(s), `git apply --check` a partir de árvore pristina) antes de escalar para o build completo. Não iniciar uma nova tentativa até entender completamente por que a anterior falhou.

**Why:** Na sessão de 2026-08-01 (ver [[regressao-sata-2026-08-01-diagnostico-solucao]]), o assistente reconstruiu às pressas um patch de SATA perdido, escrevendo-o à mão (contexto não batia contra o kernel real) e cometendo bugs reais de compilação (`ap->lock` tratado como struct quando é ponteiro; função usada antes de declarada). Builds foram iniciados e cancelados repetidamente sem plano — inclusive uma ação indevida (`git stash -u`) rodada durante o próprio modo de planejamento, quando só o arquivo de plano deveria ser tocado. O usuário reagiu: "você está fazendo e desfazendo coisas sem muita responsabilidade... reduza sua velocidade, pense mais" e depois "altere seu settings para MAIS RESPONSABILIDADE e MENOS VELOCIDADE".

**How to apply:** Antes de rodar qualquer build oficial ou aplicar um patch numa árvore de kernel (neste projeto: `/mnt/hdauxiliar/temp/kernel_build_7.0`, sempre efêmera por design — o `git reset --hard` dela é correto e não deve ser enfraquecido), validar isoladamente primeiro: editar → compilar isolado (`make CC="ccache clang" LLVM=1 ARCH=x86_64 <arquivo>.o`) → gerar o patch via `git diff HEAD` real (nunca escrever `.patch` à mão) → `git apply --check` a partir de pristino → só então integrar ao script e commitar. Regra irmã registrada em `AGENTS.md` do projeto (seção "Idempotência de Alterações no Kernel"), que qualquer sessão futura já carrega automaticamente — esta memória reforça o padrão de comportamento em paralelo.
