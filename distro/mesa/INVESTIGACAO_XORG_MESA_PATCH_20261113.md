# Investigação — Xorg com o Mesa patcheado (2026-11-13, revisada)

> **Revisão:** a primeira versão deste documento tinha erros. Foram corrigidos após reauditoria. A seção "Correções" lista o que mudou.

## O que está comprovado (medido ao vivo)

1. O `libgbm` do patch procura o backend em `/usr/local/lib/gbm/dri_gbm.so`, que não existe. O `dri_gbm.so` está em `/opt/mesa-ps4-patched/lib/gbm/`. Mensagem do Mesa: `MESA-LOADER: failed to open dri: /usr/local/lib/gbm/dri_gbm.so … (search paths /usr/local/lib/gbm, suffix _gbm)`.
2. Nos logs do X de `anderson` (`Xorg.3.log`, `Xorg.4.log`): `AMDGPU(0): gbm_create_device returned NULL, using ShadowFB`, depois `DRI3 disabled`, `AIGLX: Screen 0 is not DRI2 capable` e `GLX: Initialized DRISWRAST`.
3. `glxinfo` como `anderson` no `:4`: `glx: failed to create drisw screen` e `BadValue` em `X_GLXCreateNewContext`.
4. **A variável `GBM_BACKENDS_PATH=/opt/mesa-ps4-patched/lib/gbm` resolve o GBM.** Teste via `ctypes` no PS4, sem link simbólico: `gbm_create_device` retornou um dispositivo válido. `GBM_DRIVERS_PATH` não tem efeito (nome errado, é o que eu havia testado antes).

## Validação com o X reiniciado (2026-11-13, 11:5x)

Com `GBM_BACKENDS_PATH=/opt/mesa-ps4-patched/lib/gbm` no ambiente do servidor X (um `Xorg :4 vt2` de teste, iniciado como root), o log mostrou:
- `AMDGPU(0): glamor X acceleration enabled on AMD DG1501SML87LB (radeonsi, gladius, ACO, DRM 3.64, …)` e `glamor: Using OpenGL 4.5 context`
- `[DRI2] DRI driver: radeonsi`, `DRI3 enabled`, `AIGLX: Loaded and initialized radeonsi`

`glxinfo -B` como `anderson`: `direct rendering: Yes`, `OpenGL renderer: AMD DG1501SML87LB (radeonsi, gladius, ACO …) (0x9924)`, `OpenGL version: 4.5 (Compatibility Profile) Mesa 26.2.7`. **O Mesa patcheado funciona e reconhece o Gladius.**

## O que NÃO foi comprovado

- **O desktop Cinnamon subindo.** Tentei iniciar `cinnamon-session` por `su` nesse X de teste e falhou (`Unable to start session: Lost name on bus: org.gnome.SessionManager`; `dconf` tentando `/run/user/0`). Esse teste usou `su` fora de uma sessão de login (sem `XDG_RUNTIME_DIR`), então **não reproduz o `startx` real do usuário** e não dá para concluir nada sobre o Cinnamon. Há ainda processos `cinnamon-session-binary` antigos de tentativas anteriores (PIDs 2881 e 3482) que podem interferir, não investigado.
- Que esta seja a causa do sintoma exato do usuário ("o Xorg não sobe"). A causa do **X em software** está comprovada. A falha do Cinnamon na sessão real ainda precisa ser reproduzida com `startx` na `tty2`.
- Que a mistura entre `libGL`/`libGLX` do sistema e `libgbm`/`libEGL` do patch cause problema.

## Correções à primeira versão

| Afirmação anterior | Estado |
|---|---|
| "O `libgbm` não reconhece nenhuma variável de ambiente" | **Errada.** Reconhece `GBM_BACKENDS_PATH`. Eu testei só `GBM_DRIVERS_PATH`. |
| "A correção definitiva exige rebuild do Mesa" | **Errada.** Basta definir `GBM_BACKENDS_PATH`. Rebuild com o prefixo certo continua sendo uma opção melhor a longo prazo, mas não é obrigatório. |
| "`IgnorePkg = mesa …` é um fator" | **Errada.** É intencional: impede o `pacman` de atualizar o Mesa. Não é causa. |
| Link `/usr/local/lib/gbm` | Foi criado para teste e **já foi removido**. O PS4 está como antes da investigação. |

## Resultado final e persistência no build (2026-11-13)

O usuário rodou `startx` na `tty2` com a variável no ambiente e **o Cinnamon subiu corretamente**. O log do X dessa sessão (`Xorg.4.log`) mostra `glamor X acceleration enabled … (radeonsi, gladius, ACO …)` e `DRI3 enabled`.

**Persistido nos scripts (não testado com um build completo, só a sintaxe e a lógica idempotente):**
- `distro/01-build-image-7.0.sh`, bloco do Mesa patchado: grava `GBM_BACKENDS_PATH=/opt/mesa-ps4-patched/lib/gbm` em `/etc/environment` com `grep -q … ||` (mesmo padrão das outras variáveis). Rodar o script várias vezes não duplica a linha (testado).
- `distro/01-build-image-7.0.sh`, heredoc do `.xinitrc` (`--desktop`): `export GBM_BACKENDS_PATH=…`.
- **Não** foi acrescentado `.bash_profile`: o build não cria esse arquivo, e o login por TTY passa pelo `pam_env` (`/etc/pam.d/system-login`, linha 21), que lê `/etc/environment`. No PS4 atual o `.bash_profile` também tem a variável, mas foi uma edição manual minha.
- O `.xinitrc` exporta depois que o servidor X já subiu, então é o `/etc/environment` que vale para o servidor.

**Pendente:** validar em um build novo da imagem (`01-build-image-7.0.sh --desktop`) que `/etc/environment` sai com a linha e o X sobe com glamor.

## Estado do PS4 (alterações feitas, todas reversíveis)

- `GBM_BACKENDS_PATH=/opt/mesa-ps4-patched/lib/gbm` acrescentado em `/etc/environment`, em `/home/anderson/.bash_profile` e em `/home/anderson/.xinitrc` (antes do `exec cinnamon-session`). Backup de cada um com sufixo `.bak-gbm`. Para desfazer: restaurar os `.bak-gbm`.
- A sessão `startx` antiga na `tty2` foi **encerrada** e o X de teste também. O console está no prompt da `tty2`. **O desktop não está de pé**: para subir, fazer login em `anderson` na `tty2` (para ler o `.bash_profile` novo) e rodar `startx`.
- O link `/usr/local/lib/gbm` usado nos testes foi removido.

## Opções de correção (nenhuma aplicada)

1. **Barata, sem build:** acrescentar `GBM_BACKENDS_PATH=/opt/mesa-ps4-patched/lib/gbm` em `/etc/environment` (e no `.xinitrc`). Precisa reiniciar o X para validar. Já existe no rootfs a linha equivalente para `LIBGL_DRIVERS_PATH`, por isso é o lugar natural.
2. **Pelo build da imagem:** gravar a mesma variável no `/etc/environment` que `01-build-image-7.0.sh` gera (linhas ~599–601). Mexe no script de build.
3. **Rebuild do Mesa** com `-Dgbm-backends-path`. Opcional.

## Próximos passos (precisam de autorização, pois reinicia o X do usuário)

1. Definir a variável e reiniciar a sessão.
2. Conferir `glamor` ativo, DRI3 e `glxinfo -B` mostrando `radeonsi`.
3. Se o Cinnamon ainda falhar, coletar `~/.xsession-errors` e o log do `cinnamon-session`.
