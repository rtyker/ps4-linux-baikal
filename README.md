# PS4 Linux — Baikal (CUH-2xxx)

Linux rodando nativamente no hardware da PlayStation 4 Slim (SoC **Baikal**, CUH-2xxx),
carregado por `kexec` a partir de payload de jailbreak (PSFree/GoldHEN) — sem depender de
software da Sony depois do handoff.

> ⚠️ **Requer um PS4 já destravado (jailbreak) com firmware compatível.** O projeto não ensina
> nem fornece jailbreak. Uso educacional / de pesquisa em engenharia reversa e sistemas embarcados.

## Duas frentes

O repositório é dividido em duas frentes independentes, com uma única dependência explícita:
a distro consome os artefatos de boot que o kernel produz.

| Frente | Pasta | O que faz | README |
|---|---|---|---|
| **1 — Kernel 7.0 Baikal** | [`kernel/`](kernel/) | Compila o kernel `7.0.8-Strawberry-ThinLTO-Baikal-+`, mantém os patches, o driver `mts.ko`, a árvore fonte, os diagnósticos (UART/netconsole) e **toda a engenharia reversa** (SQLite, decompilado, memórias, planos) | [`kernel/README.md`](kernel/README.md) |
| **2 — Distro Linux Baikal** | [`distro/`](distro/) | Gera o rootfs Arch mínimo + initramfs, grava no HD, faz deploy do boot, firmware/Mesa patchado, montagem das partições PFS e releases | [`distro/README.md`](distro/README.md) |

```
kernel/00-build-kernel-7.0.sh  ──(bzImage, config por tag)──►  distro/boot_referencia/  ──►  distro/deploy-boot-7.0.sh
```

Nenhuma outra dependência cruza as frentes: a distro nunca compila kernel e o kernel não
conhece rootfs. `PS4_BOOT_REF` permite apontar a distro para outro conjunto de artefatos.

## Status atual — o que funciona

| Subsistema | Status | Detalhes |
|---|---|---|
| **Boot** | ✅ | `kexec` → kernel 7.0 → initramfs → rootfs Arch |
| **Vídeo (HDMI)** | ✅ | 1080p@60, GPU Gladius via `amdgpu` (Mesa patchado para reconhecer o chip) |
| **Áudio (HDMI)** | ✅ | `snd_hda_intel` |
| **GPU 3D** | ✅ | OpenGL 4.5, Vulkan 1.3 (RADV) |
| **SSH (WiFi admin)** | ✅ | `root@192.168.6.128`, sobe automático |
| **SATA interno (HD real)** | ✅ | `ata1` estável via polling timer de 1 ms na function PCI `.7` (`xhci_aeolia`) — validado ao vivo na tag `20260730-sata-polling-fase-ab`; a build do `v1.0.0` contém o mecanismo mas não tem boot de validação registrado |
| **USB 3.0 / SD-MMC** | ✅ | `xhci_aeolia` / `sdhci` |
| **KVM-AMD** | ✅ | `/dev/kvm` responde a ioctls reais, QEMU no rootfs |
| **Baikal Memory / SPM (`00:14.6`)** | ✅ | Driver próprio `baikal-memory.ko` v0.2 in-tree: expõe `/dev/baikal-memory` (0600) e sysfs, lê MAC real de fábrica (`2c:cc:44:3f:69:5f`), região de mailbox ICC, e escrita controlada com proteção por parâmetro (`allow_write=0`) na janela DDR3 (BAR2) |
| **RTC via ICC** | ✅ | `/dev/rtc0` operacional via `rtc-ps4-icc`, sincronização em tempo real e NTP ativo (`timedatectl` synchronized: yes), sem reset para 1970 no boot |
| **Bluetooth** | ✅ | `btmtksdio` (MediaTek MT7668, SDIO): funcionando perfeitamente. Teste do usuário em 2026-11-13 |
| **Áudio via Bluetooth** | ✅ | Reprodução em caixa de som Bluetooth funcionando perfeitamente. Teste do usuário em 2026-11-13 |
| **Joystick** | ✅ | Funcionando perfeitamente. Teste do usuário em 2026-11-13 (modelo e forma de conexão não registrados) |
| **Ethernet cabeada (`eth0`)** | ⚠️ parcial | Driver próprio `mts.ko` liga MAC e DMA, mas o PHY nunca sai de power-down (bloqueador de firmware, investigação encerrada) |
| **Desligamento total (S5)** | ⚠️ parcial | `poweroff` encerra o SO; a luz azul não apaga sozinha |

### 🌟 Destaque de Engenharia Reversa: Driver Baikal Memory (SPM/DDR3)
O Southbridge Baikal (PS4 Slim) possui um chip de memória DDR3 auxiliar dedicado de 256 MB (Scratch Pad Memory - SPM, PCI `00:14.6`), anteriormente sem suporte algum no Linux. O projeto desenvolveu do zero o driver `baikal-memory`:
* **Mapeamento de Hardware:** BAR0 (4 KiB MMIO), BAR2 (256 MB DDR3), BAR4 (1 MiB), BAR5 (256 KiB Mailbox/ICC/Bootparams).
* **Identidade do Hardware:** Extração do endereço MAC de fábrica em tempo de execução (`BAR5+0x2f000`).
* **Ponte Syscon/ICC:** Mapeamento seguro da área compartilhada de mensagens com o Syscon (`BAR5+0x2c000`).
* **Segurança e Idempotência:** Módulo com escrita protegida (`allow_write=0`), whitelist estrita para a janela BAR2 e integração idempotente via patch no kernel 7.0.

Detalhamento, causa raiz e o que já foi descartado: [`outros/docs/BACKLOG.md`](outros/docs/BACKLOG.md).

## Release

[`distro/RELEASE/`](distro/RELEASE/) traz a versão de distribuição **v1.0.0** (`bzImage`,
`bootargs`, `initramfs`, `config` + README de deploy e MD5) e o histórico de tags promovidas.

## Começando

```bash
# 1) Kernel (frente 1)
cd kernel && sudo ./00-build-kernel-7.0.sh <TAG>

# 2) Distro (frente 2)
cd ../distro
sudo ./01-build-image-7.0.sh          # rootfs Arch + initramfs
sudo ./02-burn-image-7.0.sh /dev/sdX  # particiona e grava (label psxitarch!)
sudo ./deploy-boot-7.0.sh <TAG>       # ou só troca o boot, mantendo o rootfs
./scripts/promote-release.sh <TAG>    # promove tag testada ao vivo
```

Regras completas (idempotência de patches, snapshot obrigatório, convenções de `bootargs`,
procedimento de deploy, SSH, UART, banco de RE): [`AGENTS.md`](AGENTS.md) — fonte única, e o
`CLAUDE.md` apenas importa esse arquivo.

## Aviso legal

Pesquisa/engenharia reversa em hardware próprio. O repositório não inclui nem distribui firmware,
chaves ou binários proprietários da Sony — apenas artefatos originados aqui (kernel Linux, drivers
próprios, scripts e documentação).
