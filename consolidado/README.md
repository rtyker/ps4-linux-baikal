# consolidado/ — documentação técnica consolidada

Fonte única da documentação técnica do projeto PS4 Linux Baikal (kernel 7.0.8-Strawberry-ThinLTO).

> **Revisão de 2026-11-11:** este README era, até hoje, o README do antigo **Arch Base v2 /
> kernel 5.4.247-neocine** (`systemd 258.1-1`, `video=HDMI-A-1:1280x720@60e`, "NÃO usar kernel
> Strawberry 7.0"). Todo esse conteúdo é da era 5.4 e **contradiz o estado atual** — foi preservado
> como registro em [`obsoleto/README_arch_base_v2_kernel54_historico.md`](obsoleto/README_arch_base_v2_kernel54_historico.md).
> O projeto roda hoje em kernel 7.0 com vídeo 1080p60, Mesa patchado e GPU Gladius acelerada.

## Por onde começar

| Você quer | Vá para |
|-----------|---------|
| Visão geral e status por subsistema | [`../README.md`](../README.md) |
| Regras, procedimentos, build/deploy, SSH, UART | [`../AGENTS.md`](../AGENTS.md) (auto-carregado via `../CLAUDE.md`) |
| **Índice de toda a documentação** | [`INDEX_DOCUMENTACAO.md`](INDEX_DOCUMENTACAO.md) |
| O que está pendente / próximos passos | [`BACKLOG.md`](BACKLOG.md) |
| O que funciona e o que não funciona agora | [`STATUS_ATUAL.md`](STATUS_ATUAL.md) |
| Armadilhas que já custaram sessões | [`LICOES_APRENDIDAS.md`](LICOES_APRENDIDAS.md) |
| Histórico narrativo das sagas técnicas | [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) |
| Registradores/varreduras/funções decompiladas | [`ps4_hardware_memory.db`](ps4_hardware_memory.db) + [`decompiled/INDEX.md`](decompiled/INDEX.md) |
| Cronologia por sessão de trabalho | [`../memory/MEMORY.md`](../memory/MEMORY.md) |

## Convenções destas pastas

- **`consolidado/`** — documentação técnica consolidada, banco de RE (SQLite), saídas do Ghidra.
  Algo aqui deve continuar verdadeiro por semanas; detalhes datados de uma sessão vão para `memory/`.
- **`memory/`** — registro cronológico por sessão (uma descoberta por arquivo, com data no nome).
- **`docs/planos/`** e **`docs/relatorios/`** — frentes ativas e resultados de testes pontuais.
- **`obsoleto/`** — documentos superados ou refutados. **Nunca apagar** (o histórico de hipóteses
  descartadas evita repetir testes que custam power cycle); apenas mover para cá e ajustar o índice.

## Regras de manutenção

1. Regra ou procedimento novo → `AGENTS.md` (nunca no `CLAUDE.md`, que é só um stub `@AGENTS.md`).
2. Pendência nova → `BACKLOG.md`.
3. Descoberta datada → `memory/` no mesmo dia, com `MEMORY.md` atualizado.
4. Arquivo criado/movido/removido aqui → atualizar `INDEX_DOCUMENTACAO.md` na mesma alteração.
5. Nada de links absolutos de máquina (`/mnt/t/downloads/...`, `file:///...`): usar caminho relativo.
