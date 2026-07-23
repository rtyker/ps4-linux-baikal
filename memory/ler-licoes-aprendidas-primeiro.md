---
name: ler-licoes-aprendidas-primeiro
description: "REGRA #0 do projeto: ANTES de qualquer build/deploy/teste, ler consolidado/LICOES_APRENDIDAS.md por inteiro — é o arquivo mais importante do projeto"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
  modified: 2026-07-19T20:06:51.260Z
---

**REGRA #0 — antes de qualquer ação no projeto PS4 Linux (build, deploy, gravação, teste, edição de bootargs/scripts), LER POR INTEIRO `consolidado/LICOES_APRENDIDAS.md`.**

É o arquivo mais importante do projeto: consolida todas as regras imperativas e erros já cometidos (label `psxitarch`, `root=LABEL`, ordem de enumeração de disco no PS4, etc.). Não é referência opcional — é pré-requisito.

**Why:** em 2026-07-16 gastei horas "descobrindo" do zero que o rootfs monta por `root=LABEL=psxitarch` (não `/dev/sda2`) e diagnosticando um falso problema de "SATA morrendo", quando a lição #7 desse arquivo já ditava a regra do LABEL. O usuário ficou (com razão) frustrado: a informação estava documentada no arquivo central e eu não a consultei antes de agir. Ver [[root-sempre-label-psxitarch]].

**How to apply:** no início de toda sessão que envolva este projeto, o PRIMEIRO tool call é `Read` em `consolidado/LICOES_APRENDIDAS.md`. Só depois planejar/agir. Se o arquivo crescer, reler as seções relevantes à tarefa. Tratar cada lição numerada como restrição rígida, não sugestão.

**ATUALIZAÇÃO 2026-07-19 (decisão explícita do usuário):** `consolidado/` é agora a ÚNICA fonte de documentação do projeto. `old_project/` (incluindo `old_project/distros/arch_minimal_v2/LICOES_APRENDIDAS.md`, que tinha lições extras #24-27 sobre kernel 7.0/root=LABEL/sdb SSD/eFuse WiFi) deve ser IGNORADO para fins de documentação — não consultar, não usar como referência, mesmo que pareça mais completo. O caminho canônico da Regra #0 passou a ser `consolidado/LICOES_APRENDIDAS.md` de fato (não mais `distros/arch_minimal_v2/...`).

**ATUALIZAÇÃO 2026-07-19 (parte 2):** o projeto tinha um `MEMORY.md` duplicando o `CLAUDE.md` na raiz — o usuário decidiu EXCLUIR o `MEMORY.md` e manter só o `CLAUDE.md` (que já é carregado automaticamente pelo Claude Code no início de toda sessão; um `MEMORY.md` separado não tem esse auto-load e exigiria leitura manual). `CLAUDE.md` agora é o único arquivo de memória/regras na raiz do projeto.
