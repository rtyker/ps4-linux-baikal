# Drivers Gráficos (Mesa/Vulkan) para PS4

## Visão Geral

O PS4 usa uma APU AMD personalizada com gráficos baseados na arquitetura GCN (Graphics Core Next). O driver gráfico no Linux é o driver AMD open-source (RADV para Vulkan, Radeon para OpenGL).

## Drivers Mesa Customizados

### ⚠️ Limitação Importante (Kernel 5.4)

Se você estiver usando o **kernel 5.4.247** (Baikal), o Mesa NÃO pode ser atualizado além da versão **25.1**. Versões mais recentes do Mesa exigem libdrm novo, que não é suportado pelo kernel 5.4. Isso resulta em **perda total de aceleração 3D**.

**Solução**: Fixe a versão do Mesa com `fix_versions.sh` ou use o kernel 7.0.8 Strawberry (que não tem essa limitação).

### Mesa Standard (via pacman)

Pacotes oficiais para PS4:
```bash
sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
```

### Mesa Customizado (noob404)

Mesa modificado com correções específicas para PS4:
- https://github.com/noob404yt/ps4-custom-mesa-archlinux
- https://ps4linux.com/ps4-pro-fix-vulkan-fix-crash/

**Download e Instalação**:
```bash
sudo mkdir -p /home/noob404 && sudo chmod -R ugo+rw /home/noob404
wget https://github.com/noob404yt/ps4-custom-mesa-archlinux/releases/download/v1/custom-mesa-arch-v1-ps4linux.tar.xz
tar -xvf custom-mesa-arch-v1-ps4linux.tar.xz -C /home/noob404
source /home/noob404/mesa.sh
vulkaninfo | grep driverInfo
```

### Arquivos de Script

**mesa.sh**: Configura variáveis de ambiente:
```bash
MESA=/home/noob404/mesa
export LD_LIBRARY_PATH=$MESA/lib64:$MESA/lib:$LD_LIBRARY_PATH
export LIBGL_DRIVERS_PATH=$MESA/lib64/dri:$MESA/lib/dri
export VK_ICD_FILENAMES=$MESA/share/vulkan/icd.d/radeon_icd.x86_64.json:$MESA/share/vulkan/icd.d/radeon_icd.x86.json
export D3D_MODULE_PATH=$MESA/lib64/d3d/d3dadapter9.so.1:$MESA/lib/d3d/d3dadapter9.so.1
```

**mesa-steam.sh**: Wrapper para executar jogos Steam com o Mesa customizado:
```bash
MESA=/home/noob404/mesa \
LD_LIBRARY_PATH=$MESA/lib64:$MESA/lib:$LD_LIBRARY_PATH \
LIBGL_DRIVERS_PATH=$MESA/lib64/dri:$MESA/lib/dri \
VK_ICD_FILENAMES=$MESA/share/vulkan/icd.d/radeon_icd.x86_64.json:$MESA/share/vulkan/icd.d/radeon_icd.x86.json \
D3D_MODULE_PATH=$MESA/lib64/d3d/d3dadapter9.so.1:$MESA/lib/d3d/d3dadapter9.so.1 \
    exec "$@"
```

## Verificação do Vulkan

```bash
vulkaninfo | grep driverInfo
```

Saída esperada: driver AMD RADV (Radeon Open-Source Vulkan Driver).

## Problemas Comuns

### Vulkan não funciona
```bash
# Reinstalar drivers
sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon

# Verificar instalação
vulkaninfo | grep driverInfo
```

### Travamentos Gráficos (freeze)

Adicione ao bootargs.txt:
```
radeon.dpm=0 amdgpu.dpm=0
```

Isso desativa o gerenciamento dinâmico de energia, prevenindo flutuações de clock da GPU.

## Drivers na Distro Consolidada

A distro consolidada inclui os pacotes Mesa customizados:
- `mesa-ps4-22.0.3-1-x86_64.pkg.tar.zst`
- `lib32-mesa-ps4-22.0.3-1-x86_64.pkg.tar.zst`

Estes são instalados automaticamente durante o build da distro via `build_latest_distro.sh`.

## Compatibilidade de Jogos

### Jogos testados

| Jogo | Status | Observações |
|------|--------|-------------|
| Overwatch | Funcionou (lento) | Proton 8.0, sem parâmetros especiais |
| Counter-Strike 2 | Testar | - |
| Age of Empires | Proton 8.0 | PROTON_USE_WINED3D=1 |

### Parâmetros recomendados para Steam

```bash
# Performance geral:
RADV_PERFTEST=gpl DXVK_STATE_CACHE=1 DXVK_ASYNC=1 gamemoderun %command%

# Apenas ACO (shader compiler):
RADV_PERFTEST=aco DXVK_ASYNC=1 %command%

# Esconder GPU NVIDIA (se necessário):
PROTON_HIDE_NVIDIA_GPU=0 DXVK_ASYNC=1 RADV_PERFTEST=aco %command%

# Para jogos DirectX 9/10/11 (sem Vulkan):
PROTON_USE_WINED3D=1 %command%
```

### Parâmetros explicados

| Variável | Função |
|----------|--------|
| `RADV_PERFTEST=gpl` | Ativa otimizações extras no driver RADV |
| `RADV_PERFTEST=aco` | Usa compilador de shaders ACO (mais rápido) |
| `DXVK_STATE_CACHE=1` | Acelera recompilação de shaders |
| `DXVK_ASYNC=1` | Compilação assíncrona de shaders (evita stutter) |
| `gamemoderun` | Ativa perfil de desempenho no sistema |
| `PROTON_USE_WINED3D=1` | Usa DirectX via OpenGL (mais compatível, mais lento) |

## Vulkan Fix para PS4 Pro

Para PS4 Pro com problemas de Vulkan:
https://ps4linux.com/ps4-pro-fix-vulkan-fix-crash/
