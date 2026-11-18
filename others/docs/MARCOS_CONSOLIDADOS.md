# Marcos Consolidados — Kernel 7.0 Baikal

> **Única fonte de marcos validados ao vivo no PS4 real.** Todo o projeto foca exclusivamente
> no **kernel 7.0 Strawberry Baikal**. Não há mais suporte ao kernel 5.4 (neocine).
>
> Este documento substitui todos os planos individuais em `others/docs/planos/` (que foram
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
| **Bluetooth, áudio Bluetooth e joystick** | 2026-11-13 | ✅ | Teste do usuário: Bluetooth, reprodução de áudio em caixa de som Bluetooth e joystick funcionando perfeitamente. Driver `btmtksdio` (MT7668). Modelo do joystick e forma de conexão não registrados. |
| **KVM-AMD viável** | 2026-07-24 | ✅ | CPU Jaguar expõe SVM/NPT completo; build estático com `kvm.ko` + `kvm-amd.ko` OK (não testado no PS4). |
| **SATA interno UDMA/100 confirmado em build limpo** | 2026-11-15 | ✅ | Tag `20261113-full-rebuild`: `ata1.00: configured for UDMA/100`, 931.51 GiB, `dd` 27 MB/s, zero `disable device` — SATA interno funcional em build reprodutível. |
| **RTC via ICC (timekeeping)** | 2026-11-15 | ✅ | Tag `20261113-full-rebuild`: `/dev/rtc0` operacional, system clock semeado no boot, `/proc/driver/rtc` hora correta, `pacman -Sy` sem erro SSL/clock. `hwclock -r` timeout (falta UIE emulation). |
| **Áudio HDMI** | 2026-11-15 | ✅ | Tag `20261113-full-rebuild`: `plughw:0,3` (HDMI 0) e `plughw:0,7` (HDMI 1) funcionam, `speaker-test` confirmado. |
| **Baikal Memory v0.2 (device)** | 2026-11-15 | ✅ | Tag `20261113-full-rebuild`: módulo carrega, MAC `2c:cc:44:3f:69:5f` em offset 0x52f000, ICC em 0x52c000. Sysfs offsets desalinhados. |
| **eth0 cabeada funcional (driver `mtsx`)** | 2026-11-17 | ✅ | Tag `20261117-mtsx`: limpar o resíduo `0x0147.1e` (`0x0010`) subiu o link (`BAR0+0x04 0xb18 → 0xb19`, BMSR `7969 → 796d`); **100 MB em cada sentido com SHA-256 idêntico**, 0 erros, MAC `2c:cc:44:3f:69:5f`. `CONFIG_MTSX=m` no build oficial, autoload pelo rootfs (`/etc/modules-load.d/mtsx.conf`) e `blacklist mts` no legado. Depois passou a pegar IP por **DHCP** (`.131`), com rota padrão pela cabeada. O antigo "PHY mudo/bloqueador de firmware" está refutado. |
| **Video Bridge Panasonic MN864729 funcional** | 2026-11-16 | ✅ | Tag `20261116-keep-mode-aplicado`: 2 patches no `ps4_bridge.c` — `dp-init` habilita init lado DP (antes comentado *"No idea... Meh"*), `keep-mode` preserva `mode` no `post_disable` via flag `idle` evitando tela preta no unblank. Console puro (sem Xorg) estável 1h45m+ idle. Driver built-in (símbolos em `/proc/kallsyms`), DP link training ativo. |

---

## 🔴 Bloqueadores Confirmados (não solucionáveis via driver Linux atualmente)

| Bloqueador | Data | Status | Detalhe |
|------------|------|--------|---------|
| **PHY GBE nunca acorda** | 2026-07-30 | 🔒 | MAC liga via ICC (`0x004=0xb19`), TX por software funciona (~95%), mas PHY não responde a MDIO (Clause 22 e 45 sempre timeout/zero). RX morto. Bloqueador é firmware/bootloader Sony (power do PHY feito antes do kernel assumir). Investigação de RE encerrada. |
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
| `20261113-full-rebuild` | 2026-11-15 | ✅ **Full build testado ao vivo** — SATA ✅, RTC timekeeping ✅, Áudio HDMI ✅, Baikal Memory device ✅, eth0 NO-CARRIER (causa: resíduo `0x0147.1e`, resolvido em 2026-11-17), CIFS BTF mismatch, S5 não testado |
| `20261116-keep-mode-aplicado` | 2026-11-16 | ✅ **Video bridge fix** — console puro estável 1h45m+, DP init + keep-mode patches aplicados |
| `20261116-s5-dma` | 2026-11-16 | ✅ **S5 completo:** `poweroff -f` desliga o console; DMA→SPM validado (547–624 MB/s) |
| `20261117-mtsx` | 2026-11-17 | ✅ **eth0 funcional** (`mtsx`: link up, 100 MB cada sentido com SHA-256) + `eth0` por DHCP; rootfs no disco interno (`ps4root=internal`). Promovida em `distro/RELEASE/20261117-mtsx/` |

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

others/                 # Fora do build (RE, docs, harnesses, ferramentas)
  docs/                 # Doc técnica: BACKLOG, LICOES_APRENDIDAS, ESTADO_E_HISTORICO, este documento
  rea/                  # Acervo RE: dumps, decompiled, scans, ps4_hardware_memory.db
  scripts/              # Harnesses ao vivo: uart_*, ps4_send_payload, fetch-internal-boot
  tools/                # Diagnóstico: mts_peek, mtsx (build/teste rápido), harness/, ps4_hdd_tools/

distro/RELEASE/v1.0.0/  # Únicos artefatos de release versionados (tag 20260801-*)
```

---

## Regras de Ouro (ver AGENTS.md)

- Todo build/pass deploy passa pelos scripts oficiais (`00-build-kernel-7.0.sh`, `01/02-build-image`, `deploy-boot`).
- Toda mudança de kernel/módulo vai via `.patch` com `git apply --check` + `exit 1` se falhar.
- Nunca montar diretamente em `/mnt`.
- Label do rootfs é obrigatória: `psxitarch`.
- Bootargs: UART `uart8250,mmio32,0xC890E000` + `rootwait` (nunca `console=ttyS0` nem `rootdelay=N`).
- `eth0` (driver `mtsx`) pega IP por **DHCP**, como um PC comum (2026-11-17) — `systemd-networkd` com `DHCP=ipv4`; o `dhcpcd` só cuida do `wlan0`.
- `eth0` e `wlan0` estão na **mesma** LAN (`192.168.6.0/24`) desde 2026-11-17: ping **não** prova por qual interface o tráfego passou. Prove pelos contadores (`ip -s link show eth0`) ou `tcpdump -i eth0`.
