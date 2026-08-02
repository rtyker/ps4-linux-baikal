---
name: mesa-patchado-nao-exportar-para-xorg-server-2026-07-30
description: LD_LIBRARY_PATH/LIBGL_DRIVERS_PATH do Mesa patchado (Gladius/Liverpool) quebram o próprio Xorg se exportadas para o processo do servidor — devem valer só para os clientes, via pam_env.
metadata:
  type: project
---

Ao reativar o fix [mesa-gladius-liverpool-patch-2026-07-24](mesa-gladius-liverpool-patch-2026-07-24.md) ao vivo (2026-07-30), descobri que `/etc/environment` no rootfs rodando no PS4 **não tinha** `LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH` do Mesa patchado (só `LIBGL_DRIVERS_PATH=/usr/lib/dri` do sistema) — o rootfs atual no HD é anterior à integração do fix no pipeline (`01-build-image-7.0.sh`), ou nunca foi regravado via `02-burn-image-7.0.sh` desde 07-25. `/opt/mesa-ps4-patched/` existe no disco (artefato do teste manual de 07-24) mas não estava sendo usado.

Reescrevi `/etc/environment` com as duas variáveis (backup salvo em `/etc/environment.bak-20260730`). Confirmado via `pam_env`: só funciona em sessão de **login real** (`ssh ps4@...`), não em `su -l` (o pam stack de `su-l` não inclui `pam_env`, só `system-login`/`system-remote-login` incluem).

**Erro cometido e corrigido:** ao reiniciar o Xorg (`kill` + novo processo) para validar, tentei `source /etc/environment; export ...` antes de lançar o `/usr/lib/Xorg`, herdando essas variáveis para o **processo do servidor X**. Resultado: Xorg subiu mas GLX quebrou — `glxinfo` retornava `Error: couldn't find RGB GLX visual or fbconfig`, e o log do Xorg mostrava `MESA-LOADER: failed to open dri: /usr/local/lib/gbm/dri_gbm.so` (procurando no lugar errado). Causa: o servidor Xorg usa `libEGL`/`gbm` internamente para GLAMOR/DRI2, e essas variáveis apontando pro prefixo `/opt/mesa-ps4-patched` confundem essa resolução — o servidor precisa do Mesa **do sistema**, não do patchado.

**Correção:** subir o Xorg com `env -i` (ambiente limpo, sem essas vars) e deixar que só o cliente (`glxinfo`, apps do usuário `ps4`) herde `LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH` via `pam_env` no login. Depois disso, `glxinfo` confirmou `direct rendering: Yes` e `OpenGL renderer: ... (radeonsi, gladius, ACO, ...)`.

**Por quê isso importa:** é exatamente como o pipeline oficial já faz (`/etc/environment` + `pam_env`, nunca tocando no processo do Xorg) — reforça que a integração original em `01-build-image-7.0.sh` está correta; o erro foi só meu ao testar manualmente ao vivo. **Regra prática:** nunca exportar essas duas variáveis no ambiente que vai lançar o `Xorg` (script de start do display manager, `.xinitrc` antes do `exec X`, etc.) — só no ambiente do usuário/sessão que roda os clientes gráficos por cima.

**Pendência:** nenhum Cinnamon/WM estava rodando sobre o Xorg testado (só o servidor bruto na tela) — teste visual completo na TV ainda não foi refeito com o Mesa patchado ativo desta vez.
