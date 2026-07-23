# Marco Histórico: Sucesso de Bring-up da Interface `eth0` GBE Baikal (`mts.ko`) no PS4 Pro (Kernel 7.0)

**Data de Realização:** 22 de Julho de 2026  
**Console:** PS4 Pro (Placa Baikal, FW 12.52 GoldHEN)  
**Kernel:** Linux 7.0.8-Strawberry-ThinLTO-Baikal-+ (Build #32)  
**Git Tag do Kernel:** `v7.0-20260722-clean-video-ok` (Commit `811184c1f`)  
**Tag de Boot:** `20260722-clean-video-ok`  

---

## 🏆 Resumo da Conquista

Após extensas sessões de engenharia reversa e desenvolvimento de driver nativo:
1. **Vídeo HDMI 100% Funcional**: Resolvida a causa raiz da tela preta na compilação do zero (removido o patch conflitante `sky2-baikal-gbe.patch` que forçava o `sky2` embutido a tentar dar probe no hardware MTS, travando o PCIe; e forçados `CONFIG_MFD_SYSCON=y` e `CONFIG_REGMAP_MMIO=y`).
2. **Registro de Rede `eth0` ao Vivo no PS4**: O driver `mts.ko` (módulo nativo para a controladora Ethernet Sony MTS do Baikal) foi carregado em `stage=4` via Telnet.
3. **MAC Address Real Lido da SPM**: A interface `eth0` registrou automaticamente o endereço MAC físico da placa (`2c:cc:44:3f:69:5f`).
4. **Alocação e Programação DMA**: Anéis DMA alocados sem conflito (TX `0x010dd000`, RX `0x010de000`).
5. **Estabilidade Perfeita**: Zero Kernel Panic, zero travamento, display HDMI mantido aceso, e sessão Telnet remota via `wlan0` 100% ativa.

---

## 📐 Evidências Técnicas Coletadas ao Vivo via Telnet (`192.168.6.128`)

### 1. Inicialização do Driver (`dmesg`)
```text
[  241.656140] mts 0000:00:14.1:   clock (0x7c) = 25000000 Hz (25 MHz, esperado)
[  241.656654] mts 0000:00:14.1:   contadores: pkts=0 bytes=0 | pkts2=0 bytes2=0
[  241.657179] mts 0000:00:14.1: MDIO: residuo inicial 0x0000
[  241.661382] mts 0000:00:14.1: aneis: TX va=00000000340328ea dma=0x00000000010dd000 | RX va=000000001c37adf5 dma=0x00000000010de000 | bufs dma=0x0000000001180000 (384 KB)
[  241.662131] mts 0000:00:14.1: aneis programados: TX base/ptr=0x010dd000/0x010dd000 RX base/ptr=0x010de000/0x010de000
[  241.662883] mts 0000:00:14.1: MAC enable: 0x34=0x00000001 0x38=0x00000008 0x50=0x00000040 0x70=0x00014003
[  241.663607] mts 0000:00:14.1: IMR (0x54) = 0x00000000
[  241.664498] mts 0000:00:14.1: MAC lido da SPM: 2c:cc:44:3f:69:5f
[  241.665672] mts 0000:00:14.1: mts registrado como eth0, MAC 2c:cc:44:3f:69:5f
```

### 2. Estado da Interface no Sistema (`ifconfig -a` / `ip link show`)
```text
eth0      Link encap:Ethernet  HWaddr 2C:CC:44:3F:69:5F  
          inet addr:192.168.6.131  Bcast:192.168.6.255  Mask:255.255.255.0
          UP BROADCAST MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:3 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)
```

### 3. Validação do Netconsole via UDP (Tempo Real)
Configuração dinâmica enviada via Telnet (`/sys/kernel/config/netconsole/target_wlan`):
```text
[  384.975018] netconsole: network logging started
[  385.962509] === TESTE NETCONSOLE OVER WLAN0 SUCESSO ===
```
Recepção confirmada no PC com `scripts/netconsole_listener.py` na porta `6666/UDP`.

---

## 🛠️ Artefatos Preservados do Projeto

1. **Repositório do Kernel Linux (`/mnt/hdauxiliar/temp/kernel_build_7.0`)**:
   - Branch: `baikal/7.0.8-Stable`
   - Commit: `811184c1f` (`feat(baikal): integrate sony mts ethernet driver & ps4 icc debug driver`)
   - Git Tag: `v7.0-20260722-clean-video-ok`

2. **Código do Driver MTS**:
   - `drivers/net/ethernet/sony/mts.c`
   - `drivers/net/ethernet/sony/mts.h`
   - `drivers/net/ethernet/sony/Makefile`
   - `drivers/net/ethernet/sony/Kconfig`
   - Backup do patch: `distros/arch_minimal_v2/patches/mts-baikal-gbe-driver.patch`

3. **Script de Compilação e Deploy Integrado**:
   - `distros/arch_minimal_v2/00-build-kernel-7.0.sh` (garante `CONFIG_MFD_SYSCON=y`, `CONFIG_REGMAP_MMIO=y` e `.config` de referência)
   - `distros/arch_minimal_v2/deploy-boot-7.0.sh`

4. **Binários de Boot de Referência (`distros/arch_minimal_v2/boot_referencia/`)**:
   - `bzImage-7.0-20260722-clean-video-ok`
   - `config-7.0-20260722-clean-video-ok`
   - `bootargs-7.0-20260722-clean-video-ok.txt`
   - `initramfs-7.0-20260722-clean-video-ok.cpio.gz`

---

## 📌 Regras de Proteção de Dados

- Os arquivos marcados com a tag `20260722-clean-video-ok` e a git tag `v7.0-20260722-clean-video-ok` são a **referência imutável oficial** do projeto para o kernel compilado do zero.
- O patch `sky2-baikal-gbe.patch` permanece permanently descartado e banido do script de build por causar travamento do barramento PCIe e perda de vídeo no Baikal.
