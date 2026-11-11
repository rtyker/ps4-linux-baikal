---
name: build-sh-reforca-btf-apos-nosso-disable
description: build.sh do upstream reativava CONFIG_DEBUG_INFO_BTF mesmo com --disable no 00-build-kernel-7.0.sh; resolvido eliminando a dependência do build.sh por completo.
metadata:
  type: project
---

**ATUALIZAÇÃO 2026-07-22 (mesma sessão, resolução final):** em vez de manter um patch (`build-sh-disable-btf.patch`) só pra corrigir duas linhas do `build.sh` upstream, o `00-build-kernel-7.0.sh` foi reestruturado pra ser o **único e oficial script de build**, incorporando diretamente todas as configs relevantes do perfil "General/ThinLTO/Baikal" do `build.sh` (cgroups, namespaces, BPF, scheduler, hardening trims, IO schedulers, etc) e chamando `make bzImage`/`make modules` direto — sem invocar `./build.sh` nunca mais. O script agora faz `rm -f build.sh` logo após o checkout/patches, pra deixar claro que ele não é usado (reaparece a cada `git reset --hard` por ser parte do repo upstream, por isso a remoção é repetida a cada build em vez de virar um patch de exclusão). O patch `build-sh-disable-btf.patch` foi removido de `patches/` por ficar órfão. Pedido explícito do usuário: "para melhor organização vamos deixar o 00-build-kernel-7.0.sh o único e oficial script de build [...] se o outro build.sh fazia a mesma coisa, exclua".

---

Relato original do incidente (histórico, causa raiz — o mecanismo abaixo não se aplica mais, já que `build.sh` não é mais chamado):

O `00-build-kernel-7.0.sh` já tinha `scripts/config --disable CONFIG_DEBUG_INFO_BTF` (adicionado em 2026-07-21 depois de um OOM real — pahole chegou a 10.9GB de RSS). Mas isso sozinho não bastava: o `build.sh` do próprio repositório do kernel (não é nosso, vem do clone `rmuxnet/linux`), na função do perfil `use=General` (linhas ~552-553), faz `scripts/config --enable CONFIG_DEBUG_INFO_BTF` / `CONFIG_DEBUG_INFO_BTF_MODULES` e depois roda seu **próprio** `make olddefconfig` (linha ~712) — isso acontece DEPOIS do nosso disable, então sobrescreve de volta pra `y` toda vez.

Confirmado ao vivo em 2026-07-22 (build tag `20260722-gbe-revertido`): o `.config` final tinha `CONFIG_DEBUG_INFO_BTF=y`, e o pahole (`BTF .tmp_vmlinux1`) chegou a **9.4GB de RSS com a máquina de build em só 469Mi de RAM livre e 8.1Gi de swap em uso** — repetindo exatamente o incidente de 2026-07-21. O build foi morto manualmente (`sudo pkill -9 -f pahole`) antes de travar a máquina/OOM-killer derrubar outros processos (havia uma VM libvirt e outros apps abertos).

**Correção aplicada:** criado `distros/arch_minimal_v2/patches/build-sh-disable-btf.patch`, que troca as duas linhas `--enable` por `--disable` dentro do `build.sh` do repo do kernel. Adicionado ao loop de aplicação de patches em `00-build-kernel-7.0.sh` (junto com `sky2-baikal-gbe.patch` e `ps4-icc-proc-debug.patch`).

**Por que:** `build.sh` é parte do código versionado no repo `rmuxnet/linux` (clonado em `/mnt/hdauxiliar/temp/kernel_build_7.0`), então qualquer edição direta nele seria descartada no próximo `git reset --hard origin/$BRANCH` que o `00-build-kernel-7.0.sh` faz sempre que HEAD diverge do remoto — por isso a correção precisa ser um patch versionado (mesmo padrão dos outros dois), não uma edição solta no working tree.

**Como aplicar:** antes de assumir que um `scripts/config --disable` em `00-build-kernel-7.0.sh` realmente "gruda" no `.config` final, checar se algum outro passo do fluxo (`build.sh`, `olddefconfig` adicional, patch de terceiros) roda depois e pode reverter. Sintoma característico: RAM caindo rápido demais e/ou pahole/BTF aparecendo no log quando não deveria — checar `grep CONFIG_DEBUG_INFO_BTF .config` no meio do build antes de deixar rodar até o fim.
