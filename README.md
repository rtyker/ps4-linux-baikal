# PS4 Linux — Baikal (CUH-2xxx)

Kernel Linux rodando nativamente no hardware da PlayStation 4 Slim (SoC **Baikal**, CUH-2xxx),
carregado via `kexec` a partir de um payload de jailbreak (PSFree/GoldHEN) — sem depender de
qualquer software da Sony após o handoff. Este repositório reúne o kernel, os drivers escritos do
zero para o silício do Baikal (não documentado publicamente), as ferramentas de engenharia reversa
usadas para descobri-los, e os scripts de build/deploy de uma distribuição Arch Linux mínima.

> ⚠️ **Requer um PS4 já destravado (jailbreak) com firmware compatível.** Este projeto não ensina
> nem fornece jailbreak — assume-se que o console já roda payloads homebrew. Uso educacional / de
> pesquisa em engenharia reversa e sistemas embarcados.

## Por que isso é difícil

O Baikal é um SoC customizado da Sony (AMD Jaguar + GPU Gladius + periféricos proprietários) sem
datasheet público. Praticamente todo driver de hardware específico da PS4 neste projeto — GBE
Ethernet, controle de energia via ICC, RTC, o próprio bring-up do SATA — foi escrito a partir de
**engenharia reversa ao vivo**: dump de memória do kernel original (Orbis/FreeBSD) via payload TCP,
descompilação com Ghidra, e validação em hardware real via UART/SSH, um power-cycle por vez.

## Status atual — o que funciona

| Subsistema | Status | Detalhes |
|---|---|---|
| **Boot** | ✅ | `kexec` a partir de payload → kernel → initramfs → rootfs Arch |
| **Vídeo (HDMI)** | ✅ | 1080p@60Hz, GPU Gladius via `amdgpu` (Mesa patchado para reconhecer o chip) |
| **Áudio (HDMI)** | ✅ | `snd_hda_intel` |
| **SSH (WiFi admin)** | ✅ | Acesso root via WiFi, independente da rede sob teste |
| **SATA interno (HD real)** | ✅ | `ata1` 100% estável via polling timer de 1ms na função PCI correta (`.7`, composta com o xHCI) — corrigido depois de descobrir que o driver genérico `ahci.c` nunca era o dono real do disco |
| **USB 3.0** | ✅ | `xhci_aeolia` |
| **SD/MMC** | ✅ | `sdhci` |
| **KVM (virtualização)** | ✅ | KVM-AMD funcional — nested paging/virtualização confirmados, `/dev/kvm` responde a ioctls reais, QEMU instalado no rootfs |
| **RTC (relógio de tempo real)** | ⚠️ parcial | `/dev/rtc0` funciona **manualmente** (`date`/`hwclock`) mas não persiste a hora sozinho entre boots — a implementação via MMIO real ficou pausada porque os endereços físicos do RTC caem dentro de uma região que o Linux já usa como RAM geral, risco não assumido ainda |
| **Ethernet cabeada (`eth0`)** | ⚠️ parcial | Driver próprio `mts.ko` liga o MAC e o DMA por software, mas o **PHY nunca sai de poder-desligado** — investigação de engenharia reversa esgotada (o power-on físico do PHY parece ser feito pelo firmware da Sony antes do kernel assumir, sem sequência replicável via software) |
| **Desligamento total (S5)** | ⚠️ parcial | `poweroff` encerra o SO e a rede, mas a luz azul do console não apaga sozinha — falta o comando ICC dedicado correto |

Para o detalhamento completo de cada item (causa raiz, testes já feitos, o que já foi descartado),
ver [`consolidado/BACKLOG.md`](consolidado/BACKLOG.md).

## Primeira release: v1.0.0

A pasta [`RELEASE/`](RELEASE/) contém a primeira versão consolidada para distribuição — o kernel
`bzImage`, `bootargs` e `initramfs` prontos para gravar no boot, combinando os três avanços acima
(SATA interno funcional + KVM + RTC manual) num único build validado ao vivo. Ver
[`RELEASE/README.md`](RELEASE/README.md) para instruções de deploy e os MD5 de cada arquivo.

## Estrutura do repositório

```
distros/arch_minimal_v2/   # scripts oficiais de build/deploy do kernel + rootfs Arch
drivers_mts/                # driver Ethernet (GBE) do Baikal, escrito do zero
docs/                       # planos de ação, relatórios de testes e investigações (planos e relatórios)
memory/                     # registro cronológico de descobertas e decisões de cada sessão
consolidado/                # documentação técnica consolidada, banco de RE (SQLite), scripts Ghidra
tools/                      # ferramentas de diagnósticos, harnesses de teste e ps4_hdd_tools
RELEASE/                    # releases prontas para deploy
AGENTS.md                   # regras e procedimentos do projeto (fonte única — ler antes de contribuir)
```

## Build a partir do zero

Toda compilação e deploy passam pelos scripts oficiais em `distros/arch_minimal_v2/` — nunca rodar
`make` diretamente (o kernel usa uma árvore de build efêmera que é resetada a cada execução por
design; toda mudança persistente precisa estar em um `.patch` versionado, não editada à mão na
árvore). Resumo:

```bash
cd distros/arch_minimal_v2
sudo ./00-build-kernel-7.0.sh <TAG>   # compila o kernel (ThinLTO, Baikal)
sudo ./01-build-image-7.0.sh          # gera rootfs Arch + initramfs
sudo ./02-burn-image-7.0.sh /dev/sdX  # particiona e grava tudo num HD/pendrive USB
```

Para gravar só uma atualização de boot (mantendo o rootfs intacto), usar
`sudo ./deploy-boot-7.0.sh <TAG>`. Detalhes completos, convenções de `bootargs` e o procedimento de
idempotência obrigatório para qualquer mudança de kernel estão em [`AGENTS.md`](AGENTS.md).

## Engenharia reversa

As descobertas de hardware (registradores, endereços MMIO, protocolo ICC, funções do kernel
original decompiladas) ficam catalogadas e consultáveis em
[`consolidado/ps4_hardware_memory.db`](consolidado/ps4_hardware_memory.db) (SQLite) e
[`consolidado/decompiled/INDEX.md`](consolidado/decompiled/INDEX.md) — a ideia é que nenhuma
varredura ao vivo (cada uma custa um power-cycle real do console) precise ser repetida.

## Aviso legal

Projeto de pesquisa/engenharia reversa em hardware próprio. Não inclui, distribui nem depende de
firmware, chaves ou binários proprietários da Sony — apenas os artefatos originados neste
repositório (kernel Linux, drivers próprios, scripts). O usuário é responsável por possuir
legalmente o hardware e por cumprir a legislação aplicável em sua jurisdição.
