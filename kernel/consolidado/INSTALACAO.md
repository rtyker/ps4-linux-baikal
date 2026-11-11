# Guia de Instalação do Linux no PS4

## Pré-requisitos

- PS4 com firmware compatível (5.05 a 13.50)
- GoldHEN v2.4b18.5+ instalado
- Payload Guest app (ou outro carregador de payload)
- HDD externo (ou USB) para instalação
- Acesso a um computador Linux para preparar o disco

## PS4-RTYKER (Este projeto)
- Firmware: 12.52
- Southbridge: Baikal B1 0x30201
- GoldHEN: v2.4b18.9
- IP: 192.168.6.130

## Método de Instalação

### 1. Particionamento do Disco (HDD Externo)

Duas partições são necessárias:
- **sda1**: 50MB, formato FAT32 (partição de boot)
- **sda2**: Restante do disco, formato ext4 (partição root)

```bash
sudo fdisk /dev/sda

# Comandos no fdisk:
# o   - criar nova tabela de partição (DOS)
# n   - nova partição
# p   - primária
# 1   - número da partição
# Enter - primeiro setor (padrão)
# +50M - tamanho (50MB para boot)
# t   - alterar tipo
# b   - tipo W95 FAT32
# a   - bootável
# 1   - partição 1
# n   - nova partição
# p   - primária
# 2   - número da partição
# Enter - primeiro setor (padrão)
# Enter - último setor (padrão = resto do disco)
# w   - escrever e sair
```

### 2. Formatação

```bash
sudo mkfs.vfat -F 32 /dev/sda1
sudo mkfs.ext4 -L psxitarch /dev/sda2
```

### 3. Montagem e Cópia dos Arquivos de Boot

```bash
sudo mkdir -p /mnt/boot /mnt/root
sudo mount /dev/sda1 /mnt/boot
sudo mount /dev/sda2 /mnt/root

cd /mnt/t/downloads/PS4/linux_in_ps4/distros/
sudo cp bootargs.txt bzImage initramfs.cpio.gz /mnt/boot/
sync
```

### 4. Extração da Distro

```bash
# Para tar.xz:
sudo tar -xvJpf psxitarch_v3.1-ITm.tar.xz -C /mnt/root --numeric-owner

# Para tar simples:
sudo tar -xvpf arch_minimal.tar -C /mnt/root --numeric-owner

# Para outras distros:
sudo tar -xvJpf batocera_ps4linux_40.tar.xz -C /mnt/root --numeric-owner
sudo tar -xvf "cachyos final fantasy v2.tar" -C /mnt/root --numeric-owner
sudo tar -xvJpf Steam4PS.tar.xz -C /mnt/root --numeric-owner
sudo tar -xvJpf winesapos_ps4linux.tar.xz -C /mnt/root --numeric-owner
sudo tar -xvJpf "garuda rc1.tar.xz" -C /mnt/root --numeric-owner
```

### 5. Desmontagem

```bash
sync
sudo umount /mnt/boot
sudo umount /mnt/root
```

### 6. Boot no PS4

1. Conecte o HDD ao PS4
2. Ajustes de vídeo recomendados (se tiver problemas):
   - Resolução: 1080p
   - Gama RGB: Completa
   - HDR: Desligado
   - HDCP: Desabilitado
   - HDMI device link: Desabilitado
3. Abra o Payload Guest app (ou outro carregador)
4. Carregue o payload (v24+ é firmware agnóstico, qualquer um funciona):
   - Exemplo: `linux-3072mb.bin` ou `linux-3072mb.elf`
   - O payload detecta automaticamente seu firmware (12.52), southbridge (Baikal) e modelo
5. O Linux deve iniciar

## Método Alternativo (mais rápido)

Copie os arquivos via FTP para o HDD interno do PS4:
1. `/data/linux/boot/` (caminho padrão)
2. `/user/system/boot/` (fallback - novo em payloads v23+)

## Uso do Script Automatizado

```bash
# Verificação (modo simulação):
sudo ./test_automatiza.sh distros/psxitarch3.1-unoficial/psxitarch_v3.1-ITm.tar.xz

# Instalação real:
sudo ./automatiza.sh distros/psxitarch3.1-unoficial/psxitarch_v3.1-ITm.tar.xz

# Ou use o script simplificado:
sudo ./distros/formata_e_grava.sh distros/psxitarch3.1-unoficial/psxitarch_v3.1-ITm.tar.xz
```

## Notas Importantes

- Várias distros só funcionam em TV (não em monitor)
- Sempre verifique se a gravação não teve erros
- Muitos problemas são causados por cabo HDMI ou HDD defeituoso
- Use payload de preferência 3GB (3072MB) para uso geral, 1GB (1024MB) para instalação inicial
- VRAM pode ser ajustada via `vram.txt` (ex: `echo "3072" > vram.txt`)
- Para uso como servidor headless: use 32MB a 512MB (libera RAM para o sistema)
- Distros baseadas em Arch geralmente precisam de `DisableSandbox` no pacman.conf
