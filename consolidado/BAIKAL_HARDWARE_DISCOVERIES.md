# Descobertas de Hardware: PS4 Pro Baikal (Southbridge)

Este documento registra as descobertas técnicas avançadas feitas durante a engenharia reversa do suporte de hardware do PS4 Pro (chipset Baikal) no Linux, especificamente relacionadas à interface Ethernet e aos reinícios espontâneos.

## 1. O Problema da Ethernet Baikal (GBE) — CAUSA RAIZ CONFIRMADA (atualizado 2026-07-20)

> ⚠️ **Esta seção foi reescrita.** A versão anterior deste documento defendia a hipótese de que o chip era um Synopsys DWMAC (stmmac). Essa hipótese foi **testada ao vivo e refutada**: o driver `stmmac` causa um Oops real no kernel (BAR0 tem só 4KB, `dwmac4_dma_reset()` lê o offset `0x1000` → page fault). O relato completo da tentativa descartada está arquivado em `consolidado/obsoleto/BAIKAL_GBE_EXPERIMENTS.md` e `memory/obsoleto/sessao-2026-07-17-resumo-ethernet-stmmac.md`.

A interface de rede cabeada do PS4 Pro Baikal é apresentada no barramento PCI como `00:14.1 [104d:90d8]`.

```text
sky2 0000:00:14.1: unsupported chip type 0x0
sky2: probe of 0000:00:14.1 failed with error -95
```

### A Verdadeira Causa Raiz: Power-Gating, não Driver Errado
O chip **É de fato um Marvell Yukon 2**, atendido pelo driver `sky2` — mesma família das gerações anteriores do PS4 (Aeolia `0x909e`, Belize `0x90c9`). Confirmado por comentário no `Makefile` do fork fail0verflow ("sky2 implements ps4-gbe") e por teste ao vivo: com o PCI ID do Baikal adicionado à tabela do `sky2` (patch `distros/arch_minimal_v2/patches/sky2-baikal-gbe.patch`, tag `20260717-sky2baikal`), o probe roda **sem crash** — boot completo, estável por 30+ iterações.

O motivo do `unsupported chip type 0x0` é que o **MAC core do Yukon está com clock/power desligado** (power-gated) por uma rail administrada pelo **Syscon** do Southbridge — o comando `devpm` do Syscon lista explicitamente `# gbe off`. Leituras MMIO diretas confirmam: `B2_CHIP_ID` (0x11b) e `B2_MAC_CFG` (0x11a) leem `0x00`, mas outros registradores do mesmo BAR0 (`0x000`, `0x008`) leem valores reais e estáveis — ou seja, o wrapper PCIe está ligado, só o núcleo MAC em si está sem energia.

**Hipóteses já testadas e descartadas:**
- ICC `device_power` (major 5) — o serviço só expõe 4 dispositivos (wlan/bt, usb, hdd, bd); a GBE não está entre eles (varredura completa dos minors 0x01–0xf1, confirmada também no userland do dump Orbis: `libkernel_sys.sprx` só implementa ioctls `9c01`–`9c08`).
- Varredura cega da região "pervasive" do bpcie glue (BAR2, `0xc8800000`+) — **PERIGOSA**: um `dd` em bloco num offset ativo já desligou o console fisicamente. Técnica abandonada; ver `memory/baikal-gbe-toque-trava-desliga-ps4.md`.

### Próximo Passo Real: Reverse-engineering do dump do kernel Orbis
Diferente da situação até 2026-07-19 (kernel CoreOS cifrado, sem acesso ao driver real), agora temos o **dump completo e descriptografado do kernel Orbis 12.52** (`kmem_dump_1252.bin`, 32.2 MB — ver seção 5 abaixo), que contém o driver GBE real da Sony para Baikal (`SceGbeMtsCtrl`/`SceGbeMtsPhyCtrl`, arquivo fonte `icc_device_power.c`/`icc_power.c`). O caminho correto agora é localizar e desmontar (disassembly) a rotina de `attach`/`power-on` desse driver dentro do dump para achar o registrador/comando real que liga a rail da GBE — substituindo definitivamente a tentativa e erro no hardware.

---

## 2. Reinícios Espontâneos (Watchdog Timer)
Durante os testes, o PS4 Pro sofreu um reinício espontâneo ("reboot") após alguns minutos operando no Linux.

### Causa
O Southbridge do PS4 possui um Watchdog Timer (WDT) em hardware. Antes de carregar o Linux, o sistema operacional original (Orbis OS) ou o processo de *jailbreak* ativa este timer. 
Se o sistema operacional ativo (Linux) não enviar um sinal de "vida" (alimentar o watchdog) periodicamente ou não o desativar, o hardware pressupõe que o sistema travou e força um reinício elétrico.

### Diagnóstico
Verificamos via SSH que o arquivo de dispositivo `/dev/watchdog` não existe no rootfs do Arch Linux rodando no PS4. Isso confirma que **não há nenhum driver de watchdog ativo no kernel Linux** gerenciando o timer do Baikal.

### Solução
A mitigação deste problema no ecossistema PS4 Linux depende exclusivamente do **Payload Loader** (ex: o payload enviado via webkit/PPPwn). 
É responsabilidade do *Linux Loader payload* (como o do GoldHEN ou Payload Guest) desativar fisicamente o watchdog do Southbridge antes de passar a execução para o `bzImage` do kernel Linux. Se reinícios persistirem, a versão do payload injetado deve ser atualizada para uma que trate corretamente o watchdog do modelo Baikal/12xx.

---

## 3. Código C de Diagnóstico (Leitura de BAR PCI em User Space)
Para referência futura, este é o código utilizado para ler os registradores do controlador de rede driblando as restrições de `read()` do sysfs do Linux (usando `mmap`):

```c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

const char *gbe_res_path = "/sys/bus/pci/devices/0000:00:14.1/resource0";

int main() {
    int fd = open(gbe_res_path, O_RDONLY);
    if (fd < 0) {
        perror("Erro abrindo resource0");
        return 1;
    }
    
    // O BAR0 da Ethernet Baikal tem 4K (0x1000)
    uint8_t *map = mmap(NULL, 0x1000, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        perror("Erro de mmap");
        close(fd);
        return 1;
    }
    
    printf("B2_CHIP_ID (0x11b) = 0x%02x\n", map[0x11b]);
    printf("B2_MAC_CFG (0x11c) = 0x%02x\n", map[0x11c]);
    
    printf("Registradores B2 (0x100-0x110): ");
    for (int i = 0; i < 16; i++) {
        printf("%02x ", map[0x100 + i]);
    }
    printf("\n");
    
    munmap(map, 0x1000);
    close(fd);
    return 0;
}
```
*Compilado no host com:* `gcc -O2 -static -o diagnostic diagnostic.c`

---

## 4. Perfil de Hardware Validado (Relatório Completo)
Um relatório completo de hardware do PS4 Pro Baikal (`hardware_report.txt`) foi extraído do console e analisado. Seguem os dados críticos validados no sistema operacional:

### CPU & Memória
- **Arquitetura:** AMD DG1501SML87LB (Jaguar), x86_64, 8 núcleos (sem SMT).
- **Frequência:** Base ~1594 MHz.
- **RAM Utilizável:** ~6.83 GiB alocados pelo kernel.
- **Bugs Mitigados:** `spectre_v1`, `spectre_v2`, `retbleed` etc.

### GPU & Display
- **Dispositivo (00:01.0):** AMD/ATI Gladius (RDNA custom PS4). ID `1002:9924`.
- **Driver Gráfico:** `amdgpu` rodando framebuffer com DRM debug ativo.
- **Observações:** O Gerenciamento Dinâmico de Energia (DPM) está forçado como desabilitado via kernel (`amdgpu.dpm=0`).

### Topologia do Barramento Baikal
O Southbridge expõe um barramento principal contendo todos os periféricos customizados, todos isolados no **IOMMU Group 0**:
- **00:14.0 (ACPI):** Sony Baikal ACPI.
- **00:14.1 (GBE):** Sony Baikal Ethernet. Inicialmente reportado sem driver antes da injeção do patch Yukon-2 Extreme.
- **00:14.2 (SATA):** AHCI da Sony. Reportado desconectado no barramento durante o boot sem payload específico de disco, mas presente fisicamente.
- **00:14.3 (SD/MMC):** Host Controller (ativado pelo `sdhci-pci`).
- **00:14.4 (PCIe Glue):** Ativado pelo driver `baikal_pcie`. Exibe as regiões de memória Base (BAR2 - `c8800000`) utilizadas pela nossa prova de conceito (PoC) em C.
- **00:14.7 (USB 3.0):** xHCI Host Controller (ativado pelo `xhci_aeolia`).

### Armazenamento
- O sistema monta múltiplas partições formatadas como GPT customizado do PS4 no disco interno SATA (`sda` - HDD TOSHIBA 465 GiB). O mapeamento detectou até a partição 27 (`sda27`), indicando que o esquema de tabelas do Orbis OS está acessível para o kernel Linux.

---

## 5. Revelações do Dump do Kernel Orbis FW 12.52 (Engenharia Reversa)
Em 2026-07-20, a análise das strings extraídas do dump descriptografado completo `kmem_dump_1252.bin` (32.2 MB) revelou a estrutura interna dos drivers de hardware originais da Sony no FreeBSD 9 (Orbis OS):

### A. Estrutura do Tree de Código Fonte da Sony
Os logs e assertivas de pânico revelam a localização física dos drivers no servidor de compilação da Sony (unidade `W:`):
`W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\`
Isso indica que:
- `scesb` refere-se a **Sony Computer Entertainment South Bridge**.
- Todos os periféricos são integrados no subsistema **ICC** (*Inter-Chip Communication*).

### B. Especificações da Ethernet (GBE)
O kernel do Orbis possui drivers dedicados para cada geração de Southbridge:
- **Aeolia/Belize (GBE original):** Gerenciado pela classe `SceGbeMskCtrl`.
- **Baikal (PS4 Pro / Slim):** Gerenciado pelas classes `SceGbeMtsCtrl` (controller) e `SceGbeMtsPhyCtrl` (PHY controller).
- **Threads dedicadas do driver:**
  - `gbe:ctrl`
  - `gbe:phy_ctrl`
  - `gbe:rmu`

### C. Gerenciamento de Energia e Syscon (ICC)
O gerenciamento de energia de hardware no PS4 é realizado através de subcomponentes do driver ICC:
- **Controle de Energia de Dispositivos:** Gerenciado pelo driver `sys/dev/scesb/icc/icc_device_power.c`.
  - Função crítica identificada: `icc_device_power_control(origem -> destino)` (responsável por desligar/ligar o clock e energia do barramento PCIe para Ethernet).
- **Outros Submódulos ICC:**
  - `icc_thermal.c` / `SceIccThermal`: Rastreamento de temperatura e notificações térmicas.
  - `icc_buttons.c`: Tratamento dos botões físicos de Power, Reset e Eject.
  - `icc_fan.c` / `icc_fan_get_fan_manual_duty`: Controle manual de velocidade da ventoinha via Syscon.
  - `icc_indicator.c` / `icc_indicator_set_buzzer`: Sinalizador sonoro (bip) e estados do LED dinâmico.

### D. Controle de Vídeo/Áudio HDMI via ICC
Ao contrário dos PCs que usam canais I2C puros de display (DDC) diretos na GPU, o PS4 encapsula a configuração de vídeo e EDID em comandos ICC enviados pelo kernel para a controladora HDMI (no chip do Southbridge):
- `Set EDID Read Request` / `Read EDID Data`
- `Hdmi OutputMode` / `Video Mute Control`
- `Control Video Resolution` / `Init Video`
- `Stop HDCP HW` / `CEC Message`

Essas assinaturas ajudam a mapear por que o driver de vídeo (`ps4_bridge_get_modes()`) do Linux precisa simular ou interceptar comandos ICC no Baikal para conseguir ler o EDID dinamicamente de monitores convencionais.
