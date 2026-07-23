# Roteiro de Compilação do Kernel Neocine (PS4 Pro Baikal)

Este documento descreve o processo de compilação do kernel **Neocine 5.4.247-neocine-1.1**, os arquivos envolvidos e como resolver dependências de firmware de forma limpa e independente de máquina host.

---

## 1. Visão Geral do Processo

A compilação do kernel envolve:
1. **Clonar o Repositório**: Obter o código-fonte do kernel PS4 de `feeRnt`.
2. **Checkout do Código**: Apontar para a tag de release estável `v5.4.247__neocine-1.1`.
3. **Extração da Configuração**: Usar a configuração exata (`neocine.config`) extraída do kernel em funcionamento.
4. **Resolução de Firmwares Embutidos (Built-in)**: Baixar os binários dos controladores Wi-Fi/Bluetooth do repositório oficial da Linux Foundation para evitar erros de compilação.
5. **Configuração de Diretório de Firmware**: Modificar o `.config` para usar a pasta de firmwares local do repositório.
6. **Compilação**: Executar o compilador.
7. **Instalação**: Copiar a `bzImage` resultante para a pasta de boot de referência.

---

## 2. Arquivos Envolvidos e Estrutura

### No Repositório do Projeto (Este Diretório)
*   **[00-build-kernel.sh](file:///mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/00-build-kernel.sh)**: Script automatizado para configurar o ambiente e executar os downloads.
*   **[neocine.config](file:///mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/neocine.config)**: Arquivo contendo a configuração original (extraída via `extract-ikconfig` do `bzImage` funcional).
*   **[boot_referencia/bzImage](file:///mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/boot_referencia/bzImage)**: Local final para onde o kernel compilado (`bzImage`) é copiado.

### No Diretório de Compilação (`/mnt/hdauxiliar/temp/kernel_build`)
*   **`.config`**: Arquivo de configuração ativo do kernel.
*   **`extra_firmware/`**: Diretório local onde os firmwares embutidos são armazenados:
    *   **Wi-Fi Realtek/MediaTek** (já inclusos no repositório):
        *   `EEPROM_MT7668.bin`, `EEPROM_MT7668_e1.bin`, `mt7668_patch_e1_hdr.bin`, `mt7668_patch_e2_hdr.bin`, `TxPwrLimit_MT76x8.dat`, `wifi.cfg`, `WIFI_RAM_CODE2_SDIO_MT7668.bin`, `WIFI_RAM_CODE2_USB_MT7668.bin`, `WIFI_RAM_CODE_MT7668.bin`.
    *   **Bluetooth/Wi-Fi adicionais** (baixados dinamicamente das fontes oficiais):
        *   `mediatek/mt7668pr2h.bin` (Bluetooth MediaTek)
        *   `mrvl/sd8897_uapsta.bin` (Wi-Fi/Bluetooth Marvell)
        *   `mrvl/sd8797_uapsta.bin` (Wi-Fi/Bluetooth Marvell)

---

## 3. Resolução de Firmwares (Sem dependência de Host)

### A. Firmwares de Wi-Fi e Bluetooth Embutidos (Built-in)
O arquivo `.config` original aponta `CONFIG_EXTRA_FIRMWARE_DIR` para `"/lib/firmware"`, o que gera falhas caso o sistema host de compilação não possua as chaves dos drivers do PS4. 

Para resolver isso de forma portátil, as dependências são baixadas das URLs públicas do repositório oficial da Linux Foundation:
*   [mediatek/mt7668pr2h.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7668pr2h.bin)
*   [mrvl/sd8897_uapsta.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mrvl/sd8897_uapsta.bin)
*   [mrvl/sd8797_uapsta.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mrvl/sd8797_uapsta.bin)

E a variável no `.config` é alterada:
```ini
CONFIG_EXTRA_FIRMWARE_DIR="extra_firmware"
```

### B. Firmware de Rede Ethernet Realtek (Diferença Crucial)
Para a interface de rede cabeada (`eth0`), o driver Realtek RTL8111 foi habilitado como um **módulo do kernel** (`CONFIG_R8169=m` e `CONFIG_REALTEK_PHY=m`). 

*   **Como funciona a carga de firmware:** Sendo um módulo (`.ko`), ele não exige embutir os firmwares da Realtek dentro do arquivo binário `bzImage`. Em vez disso, o driver é carregado pelo kernel após a montagem do sistema de arquivos raiz (`rootfs`) e busca o firmware correspondente à sua revisão específica (ex: `rtl8168g-2.fw`, `rtl8168h-2.fw`) dinamicamente em `/lib/firmware/rtl_nic/`.
*   **Vantagens:** Isso evita inchar a imagem do kernel (`bzImage`), garante compatibilidade automática com diferentes revisões da placa Realtek e previne erros de compilação por falta de firmwares proprietários no host.
*   **Onde colocar o firmware:** A pasta `/usr/lib/firmware/rtl_nic/` deve conter esses arquivos de firmware no seu HD (`/dev/sdb2`). Isso já é garantido nativamente ao instalar o pacote `linux-firmware` na criação da sua imagem de sistema via [01-build-debug-image.sh](file:///mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/01-build-debug-image.sh).

---

## 4. Passo a Passo Manual de Compilação

Se você preferir executar as etapas manualmente linha por linha no terminal, siga estas instruções:

### Passo 1: Preparar o ambiente e clonar o repositório
```bash
# Crie e acesse a pasta de trabalho (deve ser em sistema de arquivos Linux, ex: ext4)
mkdir -p /mnt/hdauxiliar/temp/kernel_build
cd /mnt/hdauxiliar/temp/kernel_build

# Clone o repositório oficial diretamente na tag neocine
git clone https://github.com/feeRnt/ps4-linux-12xx.git . --depth 1 -b v5.4.247__neocine-1.1
```

### Passo 2: Copiar e preparar a configuração base
```bash
# Copie o arquivo neocine.config do diretório da distro para a pasta raiz da compilação
cp /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/neocine.config .config

# Atualize a configuração base
make olddefconfig
```

### Passo 3: Baixar e organizar os firmwares obrigatórios
```bash
# Crie a estrutura de diretórios para os firmwares adicionais
mkdir -p extra_firmware/mrvl extra_firmware/mediatek

# Baixe os firmwares ausentes das fontes oficiais do kernel Linux
curl -L -o extra_firmware/mrvl/sd8897_uapsta.bin "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mrvl/sd8897_uapsta.bin"
curl -L -o extra_firmware/mrvl/sd8797_uapsta.bin "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mrvl/sd8797_uapsta.bin"
curl -L -o extra_firmware/mediatek/mt7668pr2h.bin "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7668pr2h.bin"

# Ajuste a diretiva de diretório de firmware no .config
sed -i 's|CONFIG_EXTRA_FIRMWARE_DIR="/lib/firmware"|CONFIG_EXTRA_FIRMWARE_DIR="extra_firmware"|' .config
```

### Passo 3.5: Corrigir compatibilidade do GCC 16 (Erros de __bad_copy_to)
Compiladores modernos (como o GCC 16 presente no host) possuem verificações de segurança de limites de buffer (`FORTIFY_SOURCE`) estritas que falham ao analisar o código antigo de controle do driver de Wi-Fi MediaTek (`gl_proc.c`), gerando o erro de compilação `__bad_copy_to`.

Para resolver isso, aplique a seguinte correção no arquivo `drivers/net/wireless/mediatek/mt76x8/drv_wlan/MT6632/wlan/os/linux/gl_proc.c` utilizando Python 3 (executando o comando de dentro do repositório clonado):

```bash
python3 -c "
path = 'drivers/net/wireless/mediatek/mt76x8/drv_wlan/MT6632/wlan/os/linux/gl_proc.c'
with open(path, 'r') as f:
    c = f.read()

pat1 = '''\tUINT_32 u4CopySize = sizeof(g_aucProcBuf);
\tP_GLUE_INFO_T prGlueInfo;
/*\tPARAM_CUSTOM_P2P_SET_STRUCT_T rSetP2P; */


\tkalMemSet(g_aucProcBuf, 0, u4CopySize);
\tif (u4CopySize >= (count+1))
\t\tu4CopySize = count;
\telse
\t\tu4CopySize -= 1;'''

rep1 = '''\tUINT_32 u4CopySize = (count < sizeof(g_aucProcBuf)) ? count : (sizeof(g_aucProcBuf) - 1);
\tP_GLUE_INFO_T prGlueInfo;
/*\tPARAM_CUSTOM_P2P_SET_STRUCT_T rSetP2P; */


\tkalMemSet(g_aucProcBuf, 0, sizeof(g_aucProcBuf));'''

pat2 = '''\tUINT_32 u4CopySize = sizeof(g_aucProcBuf);

\tkalMemSet(g_aucProcBuf, 0, u4CopySize);
\tif (u4CopySize >= count+1)
\t\tu4CopySize = count;
\telse
\t\tu4CopySize -= 1;'''

rep2 = '''\tUINT_32 u4CopySize = (count < sizeof(g_aucProcBuf)) ? count : (sizeof(g_aucProcBuf) - 1);

\tkalMemSet(g_aucProcBuf, 0, sizeof(g_aucProcBuf));'''

new_c = c.replace(pat1, rep1).replace(pat2, rep2)
if new_c != c:
    with open(path, 'w') as f:
        f.write(new_c)
    print('gl_proc.c corrigido com sucesso')
"
```

### Passo 3.6: Corrigir conflitos de palavras-chave C23 no GCC 16 (bool, true, false)
Como o GCC 16 compila por padrão no padrão C23 (onde `bool`, `true` e `false` são palavras-chave reservadas), as compilações do realmode (`arch/x86/boot/`) e do boot descompactador (`arch/x86/boot/compressed/`) falharão.

Você deve forçar o padrão `-std=gnu11` nesses dois Makefiles rodando este comando em Python 3 de dentro da raiz de compilação:

```bash
python3 -c "
# Corrigir realmode CFLAGS
path1 = 'arch/x86/Makefile'
with open(path1, 'r') as f:
    c1 = f.read()
pat1 = 'REALMODE_CFLAGS\t:= $(M16_CFLAGS) -g -Os -DDISABLE_BRANCH_PROFILING \\\\'
rep1 = 'REALMODE_CFLAGS\t:= $(M16_CFLAGS) -g -Os -std=gnu11 -DDISABLE_BRANCH_PROFILING \\\\'
if pat1 in c1:
    with open(path1, 'w') as f:
        f.write(c1.replace(pat1, rep1))
    print('arch/x86/Makefile corrigido (-std=gnu11)')

# Corrigir compressed boot CFLAGS
path2 = 'arch/x86/boot/compressed/Makefile'
with open(path2, 'r') as f:
    c2 = f.read()
pat2 = 'KBUILD_CFLAGS := -m$(BITS) -O2'
rep2 = 'KBUILD_CFLAGS := -m$(BITS) -O2 -std=gnu11'
if pat2 in c2:
    with open(path2, 'w') as f:
        f.write(c2.replace(pat2, rep2))
    print('arch/x86/boot/compressed/Makefile corrigido (-std=gnu11)')
"
```

### Passo 3.7: Habilitar o Driver de Ethernet Baikal (Rede Cabeada)
No chip Baikal (PS4 Pro Baikal), a interface Ethernet física (`104d:90d8`) é baseada no driver `sky2` (Marvell Yukon 2). Além do suporte vir comentado por padrão, os registradores físicos de identificação da placa (`B2_CHIP_ID` e `B2_MAC_CFG`) retornam `0x00` fisicamente neste silício customizado, fazendo com que a verificação de tipo de chip lance o erro `"unsupported chip type 0x0"` no probe.

Para contornar este problema, descomente o ID do dispositivo e force o tipo do chip para `CHIP_ID_YUKON_EX` (Yukon-2 Extreme) rodando o seguinte script em Python 3 a partir da raiz de compilação:

```bash
python3 -c "
path_sky2 = 'drivers/net/ethernet/marvell/sky2.c'
with open(path_sky2, 'r') as f:
    c = f.read()

# 1. Descomenta ID do dispositivo
c = c.replace('//{ PCI_DEVICE(PCI_VENDOR_ID_SONY, PCI_DEVICE_ID_SONY_BAIKAL_GBE) },', '\t{ PCI_DEVICE(PCI_VENDOR_ID_SONY, PCI_DEVICE_ID_SONY_BAIKAL_GBE) },')

# 2. Injeta o override de chip_id e chip_rev
pat = '\thw->chip_id = sky2_read8(hw, B2_CHIP_ID);\n\thw->chip_rev = (sky2_read8(hw, B2_MAC_CFG) & CFG_CHIP_R_MSK) >> 4;'
rep = '\thw->chip_id = sky2_read8(hw, B2_CHIP_ID);\n\thw->chip_rev = (sky2_read8(hw, B2_MAC_CFG) & CFG_CHIP_R_MSK) >> 4;\n#ifdef CONFIG_X86_PS4\n\tif (hw->pdev->vendor == PCI_VENDOR_ID_SONY && hw->pdev->device == PCI_DEVICE_ID_SONY_BAIKAL_GBE) {\n\t\thw->chip_id = CHIP_ID_YUKON_EX;\n\t\thw->chip_rev = CHIP_REV_YU_EX_B0;\n\t}\n#endif'

with open(path_sky2, 'w') as f:
    f.write(c.replace(pat, rep))
print('sky2.c remendado com sucesso para a Ethernet Baikal!')
"
```


### Passo 4: Compilar o Kernel
```bash
# Inicie a compilação utilizando todos os núcleos do processador disponíveis
make -j$(nproc)
```

### Passo 5: Copiar o resultado
Se a compilação finalizar com sucesso, o kernel estará em `arch/x86/boot/bzImage`. Mova-o para a pasta de boot de referência:
```bash
cp arch/x86/boot/bzImage /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/boot_referencia/bzImage
```
