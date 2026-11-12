# consolidado/ — documentação técnica consolidada

Fonte única da documentação técnica do projeto PS4 Linux Baikal (kernel 7.0.8-Strawberry-ThinLTO).

> **Revisão de 2026-11-11:** este README era, até hoje, o README do antigo **Arch Base v2 /
> kernel 5.4.247-neocine** (`systemd 258.1-1`, `video=HDMI-A-1:1280x720@60e`, "NÃO usar kernel
> Strawberry 7.0"). Todo esse conteúdo é da era 5.4 e **contradiz o estado atual** — ficava
> preservado em `obsoleto/README_arch_base_v2_kernel54_historico.md`, pasta apagada em 2026-11-11.
> O projeto roda hoje em kernel 7.0 com vídeo 1080p60, Mesa patchado e GPU Gladius acelerada.

## Por onde começar

| Você quer | Vá para |
|-----------|---------|
| Visão geral e status por subsistema | [`../../README.md`](../../README.md) |
| Regras, procedimentos, build/deploy, SSH, UART | [`../../AGENTS.md`](../../../AGENTS.md) (auto-carregado via `../../CLAUDE.md`) |
| **Índice de toda a documentação** | [`INDEX_DOCUMENTACAO.md`](INDEX_DOCUMENTACAO.md) |
| O que está pendente / próximos passos | [`BACKLOG.md`](BACKLOG.md) |
| O que funciona e o que não funciona agora | [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) |
| Armadilhas que já custaram sessões | [`LICOES_APRENDIDAS.md`](LICOES_APRENDIDAS.md) |
| Histórico narrativo das sagas técnicas | [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) |
| Registradores/varreduras/funções decompiladas | [`../rea/ps4_hardware_memory.db`](../rea/ps4_hardware_memory.db) + [`../rea/decompiled/INDEX.md`](../rea/decompiled/INDEX.md) |

## Convenções destas pastas

- **`consolidado/`** — documentação técnica consolidada.
  Algo aqui deve continuar verdadeiro por semanas.
- **`../rea/`** — acervo de engenharia reversa: dumps do Orbis, saídas do Ghidra,
  scripts de RE, varreduras de registradores e o banco SQLite `ps4_hardware_memory.db`.
- ~~`memory/`~~ — **pasta apagada em 2026-11-11** por decisão do usuário (descobertas datadas iam
  para lá). O que continua valendo vive em `ESTADO_E_HISTORICO.md`/`BACKLOG.md`; o resto é
  recuperável pelo histórico do git.
- **`docs/planos/`** — frentes ativas. Documentação do MTS (motor GBE, testes, RE) fica em
  [`../../drivers_mts/`](../../drivers_mts/); a antiga `docs/relatorios/` foi consolidada lá.
- ~~`obsoleto/`~~ — **pasta apagada em 2026-11-11** por decisão do usuário. Documentos superados
  ou refutados que continuem relevantes devem ser resumidos no documento vivo correspondente.

## Regras de manutenção

1. Regra ou procedimento novo → `AGENTS.md` (nunca no `CLAUDE.md`, que é só um stub `@AGENTS.md`).
2. Pendência nova → `BACKLOG.md`.
3. Descoberta datada → resumir em `ESTADO_E_HISTORICO.md` (a pasta `memory/` foi apagada em 2026-11-11).
4. Arquivo criado/movido/removido aqui → atualizar `INDEX_DOCUMENTACAO.md` na mesma alteração.
5. Nada de links absolutos de máquina (`/mnt/t/downloads/...`, `file:///...`): usar caminho relativo.
