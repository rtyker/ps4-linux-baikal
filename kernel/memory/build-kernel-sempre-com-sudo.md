---
name: build-kernel-sempre-com-sudo
description: "Todo script de build de kernel (00-build-kernel*.sh) deve rodar com sudo/root, nunca como usuário comum"
metadata:
  node_type: memory
  type: feedback
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

Todo script de build de kernel neste projeto (`00-build-kernel.sh`, `00-build-kernel-7.0.sh`, `00-build-kernel-5.15.sh`) deve ser executado com `sudo` (ou como root), nunca como usuário comum.

**Por quê:** builds anteriores sempre rodaram como root, então arquivos do diretório de build incremental (`/mnt/hdauxiliar/temp/kernel_build_7.0/`, incluindo `.config`) ficam com dono `root:root`. Se um build incremental subsequente rodar sem `sudo`, comandos como `scripts/config` falham com `Permissão negada` ao tentar escrever no `.config` existente — foi exatamente o que aconteceu em 2026-07-16 ao tentar rodar `00-build-kernel-7.0.sh` sem `sudo` pela primeira vez nesta sessão.

**Como aplicar:** sempre prefixar `sudo` ao chamar qualquer `00-build-kernel*.sh`, mesmo em builds incrementais que pareçam não precisar de privilégio elevado. Isso é consistente com o `README.md` do projeto, que já documenta `sudo ./00-build-kernel.sh` no fluxo de build completo. Ver também [[ler-licoes-aprendidas-primeiro]].
