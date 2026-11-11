# Status Atual — PS4 Linux Baikal

**Última atualização:** 2026-11-11 (revisão de documentação: caminhos, bootargs e estrutura
corrigidos para o estado real do repositório; **status técnico inalterado desde 2026-08-01**)

**Kernel:** `7.0.8-Strawberry-ThinLTO-Baikal-+` (branch `baikal/7.0.8-Stable`, ThinLTO, profile General)
**Build de distribuição:** `distro/RELEASE/v1.0.0` (origem: tag `20260801-kvm-rtc-sata-final`)
**Baseline com validação ao vivo conhecida:** tag `20260730-sata-polling-fase-ab`
(⚠️ artefatos **perdidos** — não existem em disco nenhum; ver `../../AGENTS.md`, seção "ESTADO DOS
ARTEFATOS", e "Pendências de infraestrutura" no fim deste arquivo.)

> Para pendências e próximos passos, a fonte única é [`BACKLOG.md`](BACKLOG.md).
> Para regras e procedimentos, [`../../AGENTS.md`](../../AGENTS.md).

---

## ✅ FUNCIONANDO

| Subsistema | Detalhes |
|------------|----------|
| **Boot** | `kexec` via payload (PSFree/GoldHEN) → kernel 7.0 → initramfs → rootfs Arch |
| **Vídeo HDMI** | 1920x1080@60, GPU Gladius via `amdgpu` + `ps4_bridge` (VIC 16) |
| **Áudio HDMI** | `snd_hda_intel` (1002:9921) — confirmado em uso real |
| **GPU 3D** | OpenGL 4.5 (`glxinfo` → `gladius`), Vulkan 1.3 (RADV), Mesa patchado |
| **SSH (WiFi admin)** | `root@192.168.6.128` / senha `ps4`; sobe automático por systemd |
| **EDID persistente** | `drm.edid_firmware=edid/ps4_tv_edid.bin` no initramfs |
| **RTC** | `/dev/rtc0` funciona **manualmente** (`date`/`hwclock`) — não persiste sozinho entre boots |
| **USB 3.0** | `xhci_aeolia` |
| **SD/MMC** | `sdhci` |
| **KVM-AMD** | `/dev/kvm` responde a ioctls reais (API 12), nested paging OK, QEMU no rootfs |
| **SATA interno (`ata1`)** | ✅ no baseline `20260730-sata-polling-fase-ab` (polling timer 1ms na function `.7`). ⚠️ a build `v1.0.0` já contém o mecanismo, mas **não tem boot de validação registrado** — ver ressalva no `BACKLOG.md` |
| **VRAM** | `vram.txt` (FAT32) lido pelo payload, default 1024 MB |
| **Banco de RE** | `ps4_hardware_memory.db`: integridade `ok` — 1338 registradores, 866 leituras verificadas, 87 funções decompiladas, 79 testes |
| **Dump do kernel Orbis 12.52** | `consolidado/dumps_orbis/kmem_dump_1252.bin` (gitignored, 32 MB) |

---

## ⚠️ PARCIAL / NÃO FUNCIONA

| Subsistema | Estado |
|------------|--------|
| **Ethernet cabeada (`eth0`, driver próprio `mts.ko`)** | MAC liga via ICC (`BAR0+0x004=0xb19`), tem MAC real `2c:cc:44:3f:69:5f`, DMA TX funciona (RMU/DMA completam, OWN devolvido). **PHY nunca sai de power-down**: MDIO Clause 45 devolve zeros, Clause 22 dá timeout, RX morto, link DOWN. **Investigação encerrada em 2026-07-30** — o power-on físico do PHY é feito pelo firmware Sony antes do kernel; não há sequência replicável. Não reabrir sem fonte de dados nova |
| **Desligamento total (S5)** | `poweroff -f` encerra SO e rede, mas a luz azul não apaga (falta comando ICC correto). Fix de framing do payload ICC construído (`20260730-s5-poweroff-fix`), **aguardando teste ao vivo** |
| **WiFi/BT MT7668** | Driver `mt76x8` funciona para `wlan0`; dados de manufatura/regdomain ainda ausentes (baixa prioridade) |
| **Decriptação das partições do HD interno (PFS/EAP)** | Chave EAP obtida e estável; premissa de tweak XTS = LBA absoluto **refutada** (pares A/B). Bloqueador migrou para derivação de chave/tweak. Ver [`../docs/planos/PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md`](../docs/planos/PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md) |
| **`kexec` a partir do Linux nativo** | Mecanismo funciona, mas trava após o `mts_driver_init` (~127s) no kernel-alvo. Ver [`../docs/planos/PLANO_KEXEC_WARM_REBOOT_2026-07-27.md`](../docs/planos/PLANO_KEXEC_WARM_REBOOT_2026-07-27.md) |

---

## ⚙️ CONFIGURAÇÕES CRÍTICAS

### bootargs (kernel cmdline) — modelo validado

Ver o arquivo real do build em [`../../distro/RELEASE/v1.0.0/bootargs-7.0-v1.0.0.txt`](../../distro/RELEASE/v1.0.0/bootargs-7.0-v1.0.0.txt).
Pontos que **não** podem ser "otimizados" sem medir:

| Regra | Detalhe |
|-------|---------|
| `rootwait`, **nunca** `rootdelay=N` | `rootdelay` dorme os N segundos mesmo com o disco pronto: 10,5 s perdidos (medido em 2026-07-28) |
| `earlycon=uart8250,mmio32,0xC890E000` + `console=uart8250,mmio32,0xC890E000` + `console=tty0` | **`console=ttyS0,115200n8` NÃO funciona** — é a 8250 legada x86, sem hardware no PS4; dá tela preta |
| `root=LABEL=psxitarch` | Label hardcoded no `init` do initramfs; outra label cai em rescue shell |
| `netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff` | Logs UDP para o PC (`scripts/netconsole_listener.py`) |
| Console serial **custa tempo de boot** | Com UART o `ata1` proba em 2,4–7 s; sem ela, em 0,68 s. Só comparar tempos entre boots com a mesma config de console |

### Initramfs

- `mkinitcpio.conf`: `COMPRESSION="gzip"` **obrigatório** — o kernel 7.0 Baikal não tem `CONFIG_RD_ZSTD`.
  Conferir: `xxd boot_referencia/initramfs-7.0-<TAG>.cpio.gz | head -1` deve começar com `1f8b 0800`.
- Hooks: `/hooks/early/set-time-from-cmdline` (lê `time=` injetado pelo payload) e
  `/hooks/init/00-settime`.

### Arquivos na partição BOOT (FAT32, `/dev/sdX1`)

```
bzImage              # kernel da tag ativa
initramfs.cpio.gz    # initramfs da MESMA tag (nunca o genérico)
bootargs.txt         # cmdline
vram.txt             # "1024" (MB)
bootlog.txt          # escrito pelo payload
```

---

## 📁 ESTRUTURA DO REPOSITÓRIO

```
AGENTS.md   · CLAUDE.md    # regras (fonte única + stub de import)
README.md                  # visão geral e status
kernel/                    # FRENTE 1: 00-build-kernel, patches/, drivers_mts/, consolidado/,
                           #   memory/, docs/, tools/, tests/, scripts/ (mts, UART, netconsole)
distro/                    # FRENTE 2: 01/02-build, deploy-boot, mesa/, firmware_*/, RELEASE/,
                           #   monitor_edid/, scripts/ (promote-release, crypt_mount)
```

**Não versionados neste clone (build output / binários grandes):** `kernel/boot_referencia/`,
`kernel/kernels/` (symlink para `/mnt/hdauxiliar/temp/kernel_build_7.0`),
`kernel/consolidado/dumps_orbis/`, `keys/`, `kernel/tests/uart_logs/`, `old_project/`,
`ps4-linux-payloads/`. Ver `.gitignore`.
O source do kernel **não vive no repositório**: fica na árvore ext4 `/mnt/hdauxiliar/temp/kernel_build_7.0`
(reconstruída pelos patches a cada build).

---

## ⚠️ PROBLEMAS CONHECIDOS

| Problema | Causa | Workaround |
|----------|-------|------------|
| Sem vídeo em 1080p em monitores lentos | Bridge PS4 (MN86471A/29) não vê HPD a tempo | `drm.edid_firmware` + adaptador HDMI energizado |
| `DP link training error` no log | Caminho custom da bridge | Normal, a bridge força enable |
| DPM causa instabilidade | Clocks dinâmicos bugados | `radeon.dpm=0 amdgpu.dpm=0` |
| systemd > 258 quebra boot | Incompatibilidade de cgroup | Fixar 258.1-1 (`IgnorePkg`) |
| `rmmod mts` gera `WARNING ... msi.c:294` | Bug de cleanup de MSI no driver | Não bloqueia reload; sistema só fica tainted |
| HD interno desabilita após ~84 s (kernels antigos) | Glue PCIe para de entregar IRQ do AHCI | Polling timer de 1 ms (patch) — ver ressalva de validação |
| `__readmsr()` em userland | Instrução privilegiada | Nunca; usar `kexec()` para código de kernel |
| Luz azul não apaga no `poweroff` | Falta comando ICC de S5 | Desligar no botão (ou aguardar fix de S5) |

---

## 🔧 PENDÊNCIAS DE INFRAESTRUTURA (achadas na revisão de 2026-11-11)

Nenhuma delas é regressão de código — são artefatos ausentes/desatualizados neste clone:

1. `kernel/boot_referencia/` **não existe** neste checkout (é gitignored). Ou seja:
   `distro/deploy-boot-7.0.sh <TAG>` e o rollback documentado **não funcionam aqui** até a pasta ser
   repopulada (novo build com `kernel/00-build-kernel-7.0.sh`, cópia dos artefatos de
   `distro/RELEASE/v1.0.0/`, ou extração dos snapshots de 2026-08-01).
2. `kernel/kernels/ps4-baikal-7.0.8-kernel` (symlink para o source do kernel) **não existe**, e o destino
   `/mnt/hdauxiliar/temp/kernel_build_7.0` também não — qualquer build exigirá clonar a árvore de novo.
3. `keys/` (chave EAP + testes do EAPDumper) é gitignored e não existe aqui.
4. Documentos citados em `BACKLOG.md`/memórias que vivem fora do repositório (`~/.claude/plans/*`)
   não são recuperáveis por este clone.

---

## 📚 REFERÊNCIAS

- Índice completo da documentação: [`INDEX_DOCUMENTACAO.md`](INDEX_DOCUMENTACAO.md)
- Pendências: [`BACKLOG.md`](BACKLOG.md) · Lições: [`LICOES_APRENDIDAS.md`](LICOES_APRENDIDAS.md)
- Kernel base: https://github.com/rmuxnet/linux (branch `baikal/7.0.8-Stable`)
- Payloads: https://github.com/ArabPixel/ps4-linux-payloads · Guia: https://dionkill.github.io/ps4-linux-tutorial/
