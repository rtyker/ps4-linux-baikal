# Marcos Consolidados — Kernel 7.0 Baikal

> **Única fonte de marcos validados ao vivo no PS4 real.** Todo o projeto foca exclusivamente
> no **kernel 7.0 Strawberry Baikal**. Não há mais suporte ao kernel 5.4 (neocine).
>
> Este documento substitui todos os planos individuais em `outros/docs/planos/` (que foram
> removidos). Os marcos abaixo são o que foi efetivamente confirmado em hardware real.

---

## 🏆 Marcos de Sucesso (validados ao vivo)

| Marco | Data | Status | Detalhe |
|-------|------|--------|---------|
| **Kernel 7.0 boot completo** | 2026-07-22 | ✅ | Vídeo HDMI OK, boot completo, telnet OK. Tag `v7.0-20260722-clean-video-ok`. |
| **eth0 com MAC real (driver mts.ko)** | 2026-07-22 | ✅ | `mts.ko stage=4` via Telnet registrou `eth0` com MAC `2c:cc:44:3f:69:5f` da SPM, anéis DMA OK, 0 erros. |
| **SSH via WiFi** | 2026-07-30 | ✅ | IP `192.168.6.128`, porta 22, root/ps4. |
| **SATA interno funcional** | 2026-07-30 | ✅ | `ata1.00: configured for UDMA/100`, `dd`/`fdisk` leem HD interno (931.51 GiB), zero `disable device`. Tag `20260730-sata-polling-fase-ab`. |
| **WiFi conecta + telnet** | 2026-07-29 | ✅ | `wlan0` associou, telnet porta 23 funcionou, IP `192.168.6.128`. |
| **Netconsole pronto** | 2026-07-23 | ✅ | `netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff` nos bootargs. |
| **Desligamento remoto** | 2026-07-22 | ⚠️ | `sync && poweroff -f` encerra SO + rede, mas luz azul permanece (S5 exige ICC dedicado). |
| **Auto-eth0 no boot** | 2026-07-23 | ✅ | `mts.ko stage=4` carrega automaticamente, `eth0` sobe sem Telnet. |
| **KVM-AMD viável** | 2026-07-24 | ✅ | CPU Jaguar expõe SVM/NPT completo; build estático com `kvm.ko` + `kvm-amd.ko` OK (não testado no PS4). |

---

## 🔴 Bloqueadores Confirmados (não solucionáveis via driver Linux atualmente)

| Bloqueador | Data | Status | Detalhe |
|------------|------|--------|---------|
| **PHY GBE nunca acorda** | 2026-07-30 | 🔒 | MAC liga via ICC (`0x004=0xb19`), TX por software funciona (~95%), mas PHY não responde a MDIO (Clause 22 e 45 sempre timeout/zero). RX morto. Bloqueador é firmware/bootloader Sony (power do PHY feito antes do kernel assumir). Investigação de RE encerrada. |
| **RTC persistente** | 2026-08-01 | ⏸️ | `0x05180000`/`0x05140000` caem em `System RAM` ativa (`/proc/iomem`). Usuário decidiu não arriscar `ioremap` sobre RAM em uso. Pausado sem novo direcionamento. |
| **S5 (desligamento total)** | 2026-07-30 | ⚠️ | `poweroff -f` encerra SO/rede, mas fonte não desliga (luz azul acesa/pulsando). Exige comando ICC dedicado. |
| **WiFi calibração EEPROM** | 2026-07-29 | ⚠️ | Cartão SDIO detectado, driver init, mas `load manufacture data fail` — dados de calibração não aplicados. WiFi não associa sozinho (funciona apenas com telnetd debug). |

---

## 📋 Histórico de Tags de Build (para referência)

| Tag | Data | Resultado |
|-----|------|-----------|
| `20260722-clean-video-ok` | 2026-07-22 | ✅ Baseline oficial — vídeo OK, boot completo, telnet OK |
| `20260730-sata-polling-fase-ab` | 2026-07-30 | ✅ Baseline mais recente — GBE + SATA interno funcional juntos |
| `20260801-kvm-rtc-sata-final` | 2026-08-01 | ⚠️ Única cópia íntegra em `distro/RELEASE/v1.0.0/` (4 artefatos, MD5 conferido) |
| `20261111-preflight-test` | 2026-11-11 | ✅ Build de teste validado — bzImage 16.1 MB, versão `7.0.8-Strawberry-ThinLTO-Baikal-+` |

---

## 🗂️ Onde fica cada coisa

```
kernel/                 # Frente 1: build do kernel 7.0 (só build + patches)
  00-build-kernel-7.0.sh
  patches/              # Fonte única dos patches (git apply --check)
  drivers_mts/          # Driver mts.ko (código + documentação)
  kernel_build_7.0/     # Árvore fonte (gitignored)
  .ccache/              # Cache (gitignored)
  snapshots/            # Snapshots pós-build (gitignored)

distro/                 # Frente 2: Arch Linux mínima (não compila kernel)
  01-build-image-7.0.sh
  02-burn-image-7.0.sh
  deploy-boot-7.0.sh
  rebuild-initramfs-7.0.sh
  boot_referencia/      # Artefatos por tag (bzImage, config, bootargs, initramfs)

outros/                 # Fora do build (RE, docs, harnesses, ferramentas)
  consolidado/          # Doc técnica: LICOES_APRENDIDAS, BACKLOG, ESTADO_E_HISTORICO
  rea/                  # Acervo RE: dumps, decompiled, scans, ps4_hardware_memory.db
  scripts/              # Harnesses ao vivo: build_mts_module, deploy_mts, uart_*, etc.
  tools/                # Diagnóstico: harness/, ps4_hdd_tools/
  docs/                 # Este documento (MARCOS_CONSOLIDADOS) + MIGRACAO_7.0.md

distro/RELEASE/v1.0.0/  # Únicos artefatos de release versionados (tag 20260801-*)
```

---

## Regras de Ouro (ver AGENTS.md)

- Todo build/pass deploy passa pelos scripts oficiais (`00-build-kernel-7.0.sh`, `01/02-build-image`, `deploy-boot`).
- Toda mudança de kernel/módulo vai via `.patch` com `git apply --check` + `exit 1` se falhar.
- Nunca montar diretamente em `/mnt`; builds em ext4 (nunca NTFS).
- Label do rootfs é obrigatória: `psxitarch`.
- Bootargs: UART `uart8250,mmio32,0xC890E000` + `rootwait` (nunca `console=ttyS0` nem `rootdelay=N`).
- `eth0` testado em `192.168.0.0/24` (WiFi `192.168.6.0/24` só para SSH).
- Não testar `eth0` na subnet do WiFi.
