---
name: dumps-orbis-nao-tem-power-gbe-kernel-cifrado
description: "Dumps Orbis (consolidado/dumps_orbis) analisados: userland (mini-syscore/libSceNet/libkernel_sys) NÃO tem sequência de power da GBE; icc_device_power só tem wlan/usb/hdd/bd (sem 9c09+ p/ gbe); CoreOS sflash0s1 está cifrada. Power do barramento GBE está no driver do kernel FreeBSD cifrado — próximo alvo = dump do kernel Orbis DESCRIPTOGRAFADO Baikal"
metadata: 
  node_type: memory
  type: project
  originSessionId: dfd95c6f-d4a4-4437-929d-a734e0aa051c
  modified: 2026-07-18T21:41:38.655Z
---

Em 2026-07-18 o usuário coletou 43 arquivos do PS4 Pro (FTP/GoldHEN) em `consolidado/dumps_orbis/` (ELF/SPRX FreeBSD x86_64 **descriptografados** + partições NOR). Inventário: `consolidado/RELATORIO_COLETA_DUMPS.md`. Payload dumper movido p/ `ps4-linux-payloads/ps4-sflash0-dumper.bin`.

**Analisei (objdump, offline, sem tocar no console) buscando como o Orbis liga o barramento da GBE Baikal. Resultado: não está no userland.**
- CoreOS `sflash0s1.bin` (30MB, kernel+drivers) está **CIFRADA** (header "SONY COMPUTER ENTERTAINMENT INC.") — não temos o kernel em claro.
- `mini-syscore.elf`/`libSceNet.sprx`: `gbe0` é só nome de INTERFACE de rede (mapeador lo0/eth0/eth1/dbg0/wlan0/wlan1/gbe0=idx6/bt0/phone0/pppoe0). Userland assume o barramento pronto.
- Nenhum dos 15 ELF/SPRX liga `gbe` a power/clock/pcie (grep = 0 hits).
- `libkernel_sys.sprx`: wrapper `icc_device_power` = `open(/dev/icc_device_power)` → `ioctl(0x____9c__)` → `close`; IOCTLs só 9c03/9c04/9c07/9c08 (usb+bd), tudo dentro de wlan/usb/hdd/bd (9c01–9c08). **NÃO existe 9c09+ p/ GBE** → confirma 100% o teste ao vivo (minor 0x41 = NAK). Ver [[baikal-gbe-e-sky2-nao-stmmac]].

**Conclusão:** o power/clock do barramento GBE Baikal é feito pelo **driver GBE do kernel FreeBSD (CoreOS cifrada)** — não replicável por comando ICC do userland. Precedente forte: `bpcie_baikal_sata_phy_init()` do fork foi RE'ado de um kernel Orbis **5.4 Baikal descriptografado** (comentário cita "The 5.4 Baikal sequence"); a fail0verflow tinha esse kernel mas nunca implementou a GBE.

**PRÓXIMO ALVO (o que realmente resolve):** dump do **kernel Orbis DESCRIPTOGRAFADO** p/ Baikal (payload kernel-dumper no Orbis, ou o mesmo kernel 5.4 que a f0f usou). Lá está a sequência de registradores do glue/pervasive que liga o clock da GBE. **NÃO** adianta re-rodar o sflash0-dumper (só pega NOR cifrada/config). E **NÃO** sondar o pervasive às cegas no hardware — isso desliga o console ([[baikal-gbe-toque-trava-desliga-ps4]]).

**Descriptografia OFFLINE do kernel do CoreOS = IMPOSSÍVEL sem chaves (comprovado 2026-07-18).** O usuário extraiu o container SLB2 de `sflash0s1_crypt.bin` (que expõe a estrutura, mas os SELF internos seguem cifrados) → `coreos_extracted/slot_0x1C0000/kernel.elf` (entry 80010002). Teste empírico: **entropia do segmento = 7.999 bits/byte** (máx 8.0 = aleatório/cifrado) e `zlib`/gzip FALHAM em todos os offsets → é SELF cifrado, NÃO só comprimido (a hipótese IELF/ZLIB do RELATORIO_COLETA_DUMPS.md está errada). Header ELF diz filesz 21.6MB num arquivo de 10.8MB = layout decifrado descrito, corpo cifrado. Ferramentas de descompressão (ps4-pup-unpacker/PFU) NÃO resolvem — elas descomprimem o que já foi decifrado. **Única via p/ kernel em claro: dumpar da RAM do Orbis rodando** (o processador seguro já decifrou na memória) via payload kernel-dumper, OU keydump p/ decifrar os SELF offline. Os módulos menores (80010006/8/9/A/B = SAMU arch 0x667, sam_ipl) não servem p/ GBE.
