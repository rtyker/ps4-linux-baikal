# Status: Kernel 5.15 PS4 Baikal — 15/Jul/2026 23:20

## Objetivo
Fazer o kernel 5.15 (codedwrench/ps4-linux) funcionar no PS4 RTYKER com southbridge Baikal B1.

## O que foi feito

### Patches aplicados ao kernel 5.15

**Patch 1: TSC Calibration (calibrate.c)**
- Pula EMC timer em Baikal (endereço Aeolia 0xd0281000 inválido no Baikal)
- Usa PS4_DEFAULT_TSC_FREQ (1.594 GHz) direto
- Detecta Baikal via scan de PCI IDs (0x90d7-0x90de)

**Patch 2: PCIe Glue Skip (ps4-apcie.c)**
- Pula apcie_glue_init() em Baikal (BAR4 incompatível)
- Pula apcie_icc_init() em Baikal
- Seta apcie_initialized = true para permitir probe de drivers PCI básicos
- Dispositivos SATA/GPU/USB devem funcionar em modo fallback (sem MSIs customizadas)

### Arquivos modificados
- `arch/x86/platform/ps4/ps4.c` — is_ps4_baikal() via PCI scan
- `arch/x86/platform/ps4/calibrate.c` — skip EMC timer se is_baikal
- `arch/x86/include/asm/ps4.h` — extern bool is_baikal
- `drivers/ps4/ps4-apcie.c` — skip glue_init se is_baikal

### Configuração do sda1
- bzImage: kernel 5.15 + patches Baikal
- initramfs.cpio.gz: sem clear, sem printk suppression
- bootargs.txt: earlyprintk=efi loglevel=8 drm.debug=0x06 rootdelay=10 root=/dev/sda2 rw
- bootargs-sos.txt: config emergencial (nomodeset, 800x600, break=premount)

### sda2 (rootfs)
- Arch Linux + systemd 258.1-1
- Label: psxitarch
- Módulos 5.15 instalados

## Testes realizados (15/Jul)
1. ✅ Kernel 5.15 original → tela preta + luz branca
2. ✅ Patch TSC skip → tela preta + luz branca (mesmo resultado)
3. ❌ Patch glue skip → **PS4 DESLIGOU** (shutdown, não responde)

### Análise do teste 3 (glue skip)
O PS4 **desligou** ao invés de continuar com tela preta. Isso indica:
- O kernel está passando mais longe que antes (antes ficava travado na luz branca)
- Pode estar crashando em outro componente que depende da glue logic
- Possível causa: ICC (Inter-Chip Communication) init falha e causa shutdown
- Outra possibilidade: GPU/SATA driver tenta acessar registradores que precisam da glue
- **Não é progresso direto** — mas mostra que o patch está tendo efeito diferente

### Hipóteses para o desligamento
1. `apcie_icc_init` pode ser necessário para comunicação interna — sem ele o chip reinicia
2. GPU driver pode precisar de glue para acessar display engine
3. Pode ser timeout de watchdog — sem glue, IRQ não funciona, watchdog reinicia
4. Pode ser thermal shutdown — sem glue, controle de energia falha

## O que testar amanhã

### Estratégia: Aprofundar debug do glue skip
1. **NÃO** pular `apcie_icc_init` — tentar fazer ICC funcionar isoladamente
2. Verificar se Baikal tem ICC em endereço diferente (não Aeolia)
3. Testar `init=/bin.sh` com glue skip para ver se shell aparece
4. Testar `netconsole` com driver sky2 (Ethernet) — pode ser a única saída viável

### Se desligamento persistir:
1. Reverter para kernel 5.4 neocine (que funciona) — confirmar hardware OK
2. Testar sem patches Baikal — voltar ao estado original (tela preta, luz branca)
3. Investigar repositório feeRnt/ps4-linux-12xx — pode ter Baikal ICC patch

### Outra abordagem: netconsole
- Se Ethernet funciona (sky2.c com Baikal PCI ID 0x90d8)
- Configurar netconsole remotamente para capturar panic
- Mais viável que UART (não precisa de hardware extra)

## O que testar amanhã

### Se tela preta persistir:
1. Usar bootargs-sos.txt (renomear para bootargs.txt)
2. Testar com TV real (não monitor LG com HDMI-VGA)
3. USB de energia no adaptador HDMI-VGA
4. Testar init=/bin/sh nos bootargs

### Se HDMI funcionar:
1. Verificar SATA detecta /dev/sda2
2. Verificar initramfs monta rootfs
3. Configurar netconsole para debug remoto

## Referências rápidas
- Kernel build: /mnt/hdauxiliar/temp/kernel_build_515/
- Config neocine 5.4: /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/neocine.config
- Config 5.15: /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/boot_referencia/config-5.15
- Patch salvo: /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/baikal-safe-pcie.patch
- Código referência: https://github.com/feeRnt/ps4-linux-12xx (ps4-apcie.c com irq_map)
- Licoes aprendidas: /mnt/t/downloads/PS4/linux_in_ps4/consolidado/LICOES_APRENDIDAS.md (itens 15-26)
