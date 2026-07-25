# Correção do Mesa para os chips PS4 (Liverpool) / PS4 Pro (Gladius) — 2026-07-24

> **✅ STATUS: VALIDADO AO VIVO 2026-07-24.** Patch aplicado ao Mesa 26.1.5, build nativo concluído, deployado no PS4 via `LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH` e testado: `glxinfo` confirma `OpenGL renderer: ... (radeonsi, **gladius**, ACO, ...)` (antes: `kaveri`). Corrupção visual (Nemo, janelas com ícones) **desapareceu completamente**, mesmo SEM a mitigação `AMD_DEBUG=notiling` — ou seja, a causa raiz real foi corrigida, não só mascarada. Confirmado visualmente pelo usuário direto na TV do console.

## Como reproduzir o teste que validou (2026-07-24)

```bash
# no PS4, como usuário ps4, sessão X ja aberta:
export LD_LIBRARY_PATH=/opt/mesa-ps4-patched/lib
export LIBGL_DRIVERS_PATH=/opt/mesa-ps4-patched/lib/dri
glxinfo | grep renderer   # deve mostrar "gladius"
```
Artefatos usados no teste: `/opt/mesa-ps4-patched/` no PS4 (extraído de `meson install --destdir` do build local, não commitado — refazer via `01-build-mesa.sh` + deploy).

**Achado importante durante o teste:** `LIBGL_DRIVERS_PATH` sozinho NÃO foi suficiente — o loader continuou abrindo o `libgallium` do sistema (`/usr/lib/libgallium-26.1.5-arch1.1.so`). Só funcionou setando **também** `LD_LIBRARY_PATH` apontando pro diretório do Mesa patchado (garante que `libGLX_mesa.so`/`libgallium` inteiros sejam os nossos, não uma mistura com o do sistema).

## ✅ Persistência e integração no pipeline (2026-07-24, feito)

O Mesa patchado agora é parte do pipeline de build da imagem, não mais um deploy manual:

- **`mesa/01-build-mesa.sh`** — além do tarball versionado (`mesa/mesa-$VERSION-ps4-gladius-liverpool.tar.xz`), agora também produz uma cópia estável `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz` (cópia, não symlink — sobrevive a mover a pasta `mesa/`), consumida automaticamente pelo passo abaixo.
- **`distros/arch_minimal_v2/01-build-image-7.0.sh`** — novo passo (logo após copiar `mts.ko`, antes de gerar o initramfs): se `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz` existir, extrai pra `$ROOTFS_DIR/opt/mesa-ps4-patched/` e adiciona `LD_LIBRARY_PATH=/opt/mesa-ps4-patched/lib` + `LIBGL_DRIVERS_PATH=/opt/mesa-ps4-patched/lib/dri` em `/etc/environment` do rootfs (mesmo mecanismo — `pam_env` — validado ao vivo). Se o tarball não existir, o build da imagem **não falha**, só avisa e segue sem o patch (igual ao tratamento já existente pro `mts.ko` opcional).
- O pacote `mesa`/`vulkan-radeon` oficial do Arch continua sendo instalado normalmente via pacman (já estava em `IgnorePkg` do `pacman.conf` do rootfs, decisão tomada antes mesmo deste fix) — não tocamos nos arquivos do pacote, só adicionamos o prefixo `/opt/mesa-ps4-patched` por cima via variável de ambiente. Isso evita qualquer conflito com `pacman -Syu` e não depende de nomes de arquivo com sufixo de versão do Arch (`-archX.Y`), que mudam a cada rebuild do pacote oficial.
- **Resultado prático:** rodar `mesa/01-build-mesa.sh` (uma vez, ou sempre que quiser atualizar o Mesa) e depois `distros/arch_minimal_v2/01-build-image-7.0.sh` já entrega uma imagem com a correção **persistente por padrão**, sem passo manual nenhum no console.
- `AMD_DEBUG=notiling` (mitigação antiga, testada num console já rodando) **não faz parte do pipeline de imagem** — nunca foi adicionado lá, só setado ao vivo via SSH numa sessão já booteada. Não precisa de ação pra "remover do pipeline" porque nunca entrou nele. Se algum console antigo (já gravado antes deste fix) ainda tiver essa variável em `/etc/environment` por ter sido setada manualmente, pode remover à vontade — não conflita com o Mesa patchado, só fica redundante.

**Notas técnicas da integração:**
1. Um build corrompeu no meio do caminho por um bug real (não deste patch, mas de um arquivo separado, `radeon_surface.c`, que tem um enum `radeon_family` privado só para o driver clássico `radeon.ko` — nunca usado no PS4, mas precisa compilar). Corrigido e já incorporado no patch salvo (`mesa/ps4-gladius-liverpool-patch/mesa-26.1.5-ps4-gladius-liverpool.patch`).
2. **Ainda não testado**: rodar o `01-build-image-7.0.sh` completo (que exige sudo e reconstrói o rootfs inteiro) com o novo passo de Mesa incluído, e gravar essa imagem nova no PS4 do zero (power cycle completo). O que foi validado ao vivo foi o deploy manual equivalente (mesmos arquivos, mesmo mecanismo de env vars) num sistema já rodando — o próximo teste real de ponta a ponta é gerar e gravar a imagem completa.

## Resumo executivo

O ambiente desktop (Xorg + Cinnamon) instalado no PS4 apresentava **corrupção visual real** (padrão xadrez azul/branco em janelas compostas via OpenGL — não um flicker sutil, blocos grandes de "confete" cobrindo parte da tela). A mitigação imediata (`AMD_DEBUG=notiling` em `/etc/environment`, já aplicada e funcionando) força o Mesa a nunca usar superfícies tiled, o que elimina o sintoma mas custa performance.

A causa raiz real: o kernel já tem suporte dedicado aos chips do PS4 (`CHIP_LIVERPOOL`/`CHIP_GLADIUS` em `drivers/gpu/drm/amd/amdgpu/`), mas o **Mesa instalado (pacote oficial Arch, binário, sem patch)** não sabe o que são esses chips — ele recebe do kernel a família genérica `AMDGPU_FAMILY_KV` (mesma "família" da Kaveri real) e, sem um patch específico, usa a tabela de distribuição de tiles entre backends de renderização (`raster_config`) da **Kaveri** (1 Shader Engine / 2 RBs) num hardware que na verdade tem 4 Shader Engines (PS4 Pro). Esse descasamento entre o que o Mesa assume e o layout físico real do silício é o que gera a corrupção.

A boa notícia: esse é um problema **já resolvido pela comunidade PS4-Linux** desde ~2017 (fail0verflow) e mantido por forks mais recentes. Os patches existem publicamente, foram baixados, comparados e adaptados para a versão atual do Mesa (26.1.5) usada neste projeto. O patch resultante está neste repositório, pronto para build.

## O sintoma (como identificar se isso volta a acontecer)

- Corrupção em blocos/xadrez azul-e-branco, aparecendo em janelas específicas compostas via OpenGL (ex: Nemo, qualquer app com muitos ícones/texturas).
- Terminal com só texto pode renderizar limpo enquanto uma janela ao lado (com mais conteúdo texturizado) mostra o padrão — não é uniforme na tela toda.
- `glxinfo` mostra `OpenGL renderer: AMD ... (radeonsi, **kaveri**, ...)` — o Mesa está identificando o GPU real do PS4/PS4 Pro como se fosse uma Kaveri comum.
- Print de tela estático (`import -window root`) pode não capturar o artefato se ele for transitório — funcionou para nós na segunda tentativa, durante uso ativo da janela.

## Investigação — como chegamos na causa raiz

1. **Descartado:** driver de vídeo/KMS em si (sem erros novos no `dmesg` durante o período de corrupção; os erros de `amdgpu_atombios_dp_link_train`/`EDID changed` encontrados eram de janelas de restart do Xorg durante o setup, não correlacionados no tempo com o artefato).
2. **Teste que confirmou ser Mesa/tiling:** relançar o Cinnamon com `AMD_DEBUG=notiling` (força alocação linear, sem tiling) eliminou 100% da corrupção nas mesmas janelas. Prova que o bug está na camada de tiling do Mesa, não no kernel/Xorg/compositor em si.
3. **Leitura do código-fonte do kernel** (`/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/gpu/drm/amd/amdgpu/`):
   - `amdgpu_drv.c`: PCI ID `0x9924` (`PCI_DEVICE_ID_CUH_7XXX`, ou seja, **PS4 Pro**) mapeado para `CHIP_GLADIUS|AMD_IS_APU`. Existe também `CHIP_LIVERPOOL` para o PS4 base.
   - `gfx_v7_0.c`: `CHIP_GLADIUS` tem seu próprio bloco em `gfx_v7_0_gpu_early_init()` com os valores reais de hardware (4 Shader Engines, 8 canais TCC — bate com a spec pública do PS4 Pro, comentado como "Verified" no código).
   - `amdgpu_device.c:2666-2677`: **aqui está o bug de origem** — `CHIP_GLADIUS`/`CHIP_LIVERPOOL` caem no mesmo `case` de `CHIP_KAVERI`/`CHIP_BONAIRE`/etc., e como são `AMD_IS_APU`, o kernel reporta `adev->family = AMDGPU_FAMILY_KV` — o enum genérico "família Kaveri" que qualquer Mesa (patched ou não) recebe via ioctl `AMDGPU_INFO`.
   - `cik.c:2509-2563`: **descoberta importante** — o kernel **já** foi preparado para uma integração específica com Mesa: `CHIP_LIVERPOOL` recebe `external_rev_id = rev_id + 0x61` e `CHIP_GLADIUS` recebe `external_rev_id = rev_id + 0x71`. Os comentários no código já mencionam "PS4" explicitamente. Ou seja, **o lado do kernel deste projeto já está pronto e correto** — só faltava a metade do Mesa.
4. **Mesa 26.1.5 instalado (binário oficial Arch) não tem nenhum patch para isso** — por isso caía no fallback genérico Kaveri.

## Descoberta dos patches da comunidade

Busca na web revelou que este exato problema (chips `LIVERPOOL`/`GLADIUS` no Mesa) já foi resolvido publicamente por múltiplos projetos da cena PS4-Linux:

| Projeto | Arquivo | Observação |
|---|---|---|
| [fail0verflow/ps4-radeon-patches](https://github.com/fail0verflow/ps4-radeon-patches) | `mesa-13.0.2-liverpool.patch` | Patch original (2017), só Liverpool (PS4 base) |
| [Ps3itaTeam/ps4linux-video-drivers](https://github.com/Ps3itaTeam/ps4linux-video-drivers) | `mesa-git/mesa.patch` | Já inclui Gladius (PS4 Pro), Mesa-git ~2021 |
| [paranoidnela/mesagit-ps4patches](https://github.com/paranoidnela/mesagit-ps4patches) | `patchwip.patch` | Variante quase idêntica ao Ps3itaTeam |

Cópias desses três patches (para não depender do GitHub estar no ar numa sessão futura) estão salvas em `mesa/ps4-gladius-liverpool-patch/referencias-comunidade/`.

Também existe, no mesmo diretório `mesa/` deste projeto, um **Mesa customizado pré-compilado de terceiros** (`custom-mesa-arch-v1-ps4linux.tar.xz`, por "noob404"/ps4linux.com) — **testado e descartado**: é um binário de ~2020-2022 (LLVM 9, glibc/libxml2 antigos) incompatível com o Arch atual (2026) do PS4 (`libLLVM-9.so` exige `libxml2.so.2`, só existe `libxml2.so.16` no sistema). Confirmamos via `strings` que ele tem os mesmos nomes `LIVERPOOL`/`GLADIUS` internamente (Mesa 20.0.8), então é da mesma linhagem, mas não vale a pena tentar rodá-lo — mais barato recompilar do zero.

## O patch aplicado (Mesa 26.1.5)

Arquivo: `mesa/ps4-gladius-liverpool-patch/mesa-26.1.5-ps4-gladius-liverpool.patch` (formato diff -u, aplicável com `patch -p1` dentro do source do Mesa 26.1.5).

Adaptação necessária em relação aos patches de referência (que visavam Mesa ~13.0.2/git-2021): o Mesa moderno **já lê `max_se`, `max_tcc_blocks` etc. diretamente do kernel** (via `device_info->num_shader_engines` etc.) — não precisou mais hardcoded por chip como nos patches antigos (`radv_null_winsys.c`, `radeon_drm_winsys.c` — ambos removidos/obsoletos no Mesa atual, não portados). Os únicos pontos que realmente precisam de dado hardcoded por chip (porque são resultado de engenharia reversa do silício real, não algo que o kernel reporta) são a identificação do chip e o `raster_config`.

Arquivos modificados:

1. **`include/pci_ids/radeonsi_pci_ids.h`** — adiciona `CHIPSET(0x9920/0x9922/0x9923, LIVERPOOL)` e `CHIPSET(0x9924, GLADIUS)`.
2. **`src/amd/addrlib/src/amdgpu_asic_addr.h`** — reduz `AMDGPU_SPOOKY_RANGE` de `0x41-0x81` para `0x41-0x61` e cria `AMDGPU_STARSHA_RANGE` (`0x61-0x71`, Liverpool) e `AMDGPU_STARSHP_RANGE` (`0x71-0x81`, Gladius) — **essas faixas batem exatamente com o `external_rev_id` que o nosso kernel já calcula** (`rev_id + 0x61` / `rev_id + 0x71`).
3. **`src/amd/common/amd_family.h`** — novos valores `CHIP_LIVERPOOL`/`CHIP_GLADIUS` no enum `radeon_family`, inseridos dentro do grupo "GFX7 (Sea Islands)" (entre `CHIP_KAVERI` e `CHIP_KABINI`) para que `ac_get_gfx_level()` (que compara `family >= CHIP_BONAIRE` / `family >= CHIP_TONGA`) resolva automaticamente para `GFX7` sem precisar de código extra.
4. **`src/amd/common/amd_family.c`** — nomes (`ac_get_family_name`) e nome de processador LLVM de fallback (`ac_get_llvm_processor_name` → `"bonaire"`, já que LLVM não conhece "Liverpool"/"Gladius"; só relevante se o ACO não estiver disponível, o que não é o caso normal aqui).
5. **`src/amd/common/ac_gpu_info.c`** — o arquivo central:
   - `ac_identify_chip()`: adiciona `identify_chip2(STARSHA, LIVERPOOL)` e `identify_chip2(STARSHP, GLADIUS)` dentro do `case FAMILY_KV:`.
   - `max_render_backends`: replica o workaround do Kaveri (`info->max_render_backends = 2`) também para `CHIP_LIVERPOOL`, fiel ao patch de referência (não afeta Gladius/PS4 Pro).
   - `ac_get_gs_table_depth()`: adiciona os dois chips ao grupo de profundidade 32 (chips com 2+ SEs).
   - **`ac_get_raster_config()` — o fix mais provavelmente responsável pela corrupção:** antes, nosso hardware caía no `case CHIP_KAVERI` (`raster_config=0x00000002`, layout de 1 SE/2 RBs). Adicionado `case CHIP_LIVERPOOL` (`0x2a00161a`/`0x00000000`) e `case CHIP_GLADIUS` (`0x2a00161a`/`0x0000002e`) com os valores reais de RE da comunidade (4 SEs para o Pro).

Não portado (arquivos/padrões não existem mais no Mesa 26.1.5, removidos upstream): `src/amd/vulkan/winsys/null/radv_null_winsys.c` (RADV null winsys) e `src/gallium/targets/d3dadapter9/description.c` (Gallium Nine — Direct3D9 legado). Nenhum dos dois afeta o bug de corrupção em OpenGL/desktop.

Não portado por decisão de escopo (baixo risco de afetar o bug atual, específico de tessellation+geometry shader em Vulkan): o workaround `partial_vs_wave` para chips de 2 SEs em `radv_pipeline_graphics.c`/`radv_cmd_buffer.c` (RADV) e `si_state_draw.cpp` (radeonsi/GL) — só relevante para `CHIP_LIVERPOOL` (PS4 base), não para `CHIP_GLADIUS` (nosso hardware, PS4 Pro).

## Build

Compilado nativamente no host (não no PS4 — o Jaguar do console é lento demais para isso e nem tem `llvm` instalado). Confirmado que host e PS4 rodam **exatamente as mesmas versões** de `glibc` (2.43+r37), `libdrm` (2.4.134) e `mesa` (1:26.1.5), então os `.so` resultantes são compatíveis por ABI sem cross-compile.

Fonte oficial baixado de `https://archive.mesa3d.org/mesa-26.1.5.tar.xz`.

Comando de configuração usado:
```bash
meson setup build \
  -Dbuildtype=release \
  -Dgallium-drivers=radeonsi \
  -Dvulkan-drivers=amd \
  -Dplatforms=x11 \
  -Dgles1=disabled -Dgles2=enabled \
  -Dglx=dri -Degl=enabled -Dgbm=enabled \
  -Dllvm=enabled -Dvalgrind=disabled -Db_ndebug=true
ninja -C build -j8
```

## Próximos Passos (retomar daqui)

1. **Confirmar que o build terminou sem erro** (rodava em background no host ao final desta sessão; log em `/tmp/.../scratchpad/mesa_build.log` — esse caminho é efêmero/por sessão, se já não existir mais, refazer o build com o patch salvo em `mesa/ps4-gladius-liverpool-patch/`).
2. **Deploy não-destrutivo no PS4:** copiar os `.so` resultantes (`build/src/gallium/targets/dri/libgallium_dri.so` → renomear/linkar como `radeonsi_dri.so`, `build/src/mapi/es*/`, `libGL`, `libEGL`, etc. — checar exatamente quais libs o `ninja install --destdir` gera) para um prefixo separado tipo `/opt/mesa-ps4-patched/`, testar via `LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH` **sem sobrescrever o Mesa do sistema**, do mesmo jeito que fizemos com o blob de terceiros (que falhou por outro motivo, mas o método de teste isolado via env vars funcionou bem).
3. **Teste de validação:** `glxinfo | grep renderer` deve mostrar `gladius` (ou o nome que `ac_get_family_name` retornar) em vez de `kaveri`. Depois, reabrir as mesmas janelas que corrompiam (Nemo com ícones) e tirar print para comparar.
4. **Se funcionar:** remover a mitigação `AMD_DEBUG=notiling` de `/etc/environment` (não vai mais ser necessária) e promover o Mesa patched para substituir o do sistema (ou manter via `LD_LIBRARY_PATH` no `.xinitrc`/sessão do Cinnamon — a decidir).
5. **Se não funcionar / corrupção parcial:** próximo candidato a investigar é `ac_get_gs_table_depth`/outras tabelas de tile mode ainda não cobertas, ou revisitar se `rev_id` (usado para calcular `external_rev_id` no kernel) está de fato caindo dentro da faixa `STARSHP` esperada (0x71-0x80) — não confirmamos o valor exato de `rev_id` ao vivo, só a fórmula no código-fonte.

## Onde encontrar tudo

- Patch pronto para aplicar: `mesa/ps4-gladius-liverpool-patch/mesa-26.1.5-ps4-gladius-liverpool.patch`
- Patches de referência da comunidade (cópia local): `mesa/ps4-gladius-liverpool-patch/referencias-comunidade/`
- Este documento: `consolidado/MESA_GLADIUS_LIVERPOOL_FIX.md`
- Memória do projeto: ver entrada correspondente em `memory/MEMORY.md` e `memory/mesa-gladius-liverpool-patch-2026-07-24.md`
