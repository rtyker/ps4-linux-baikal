---
name: feedback-scripts-simples-sem-parametro
description: "Usuário prefere que scripts de build/deploy do projeto PS4 Linux rodem simples, sem exigir parâmetros na chamada."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: be8808ab-6ec2-4311-82dd-0c7a95fcd198
  modified: 2026-07-22T17:25:37.141Z
---

O usuário prefere que os scripts wrapper do projeto (ex: `00-build-kernel-7.0.sh` em `distros/arch_minimal_v2/`) sejam simples de rodar, sem precisar passar parâmetros toda vez.

**Por que:** comentário direto do usuário (2026-07-22) enquanto o assistente rodava `sudo ./00-build-kernel-7.0.sh 20260722-gbe-revertido` com uma TAG explícita — "a ideia do build.sh é ser um script que rodo sem parametros, coisa simples".

**Como aplicar:** ao criar ou tocar em scripts de build/deploy desse projeto, preferir que funcionem bem com defaults sensatos (sem exigir args) em vez de forçar o usuário a lembrar/passar valores manualmente a cada execução. `00-build-kernel-7.0.sh` já tem fallback de TAG via `$(date +%Y%m%d)-sky2builtin`; ao editar scripts como `deploy-boot-7.0.sh` (que hoje exige `<TAG>` obrigatório), considerar se dá pra automatizar a escolha da tag mais recente por padrão, mantendo a possibilidade de override explícito quando necessário.
