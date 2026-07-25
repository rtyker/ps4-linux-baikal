# Backlog do Projeto — Fonte Única de Pendências

**Última atualização:** 2026-07-25 (item RTC adicionado)

Este é o **único documento** onde a lista de tarefas pendentes do projeto deve ser mantida. Nenhum outro arquivo (`STATUS_ATUAL.md`, `MASTER_CONSOLIDADO.md`, `O_QUE_FALTA.md`, etc.) deve manter sua própria lista de "próximos passos" — todos apontam para cá, para evitar itens duplicados ou desatualizados espalhados pelo projeto.

Convenção: `[ ]` pendente · `[~]` em andamento · `[x]` concluído (mover para "Concluídos recentemente" ao fechar).

O trabalho **ativo no momento** (investigação detalhada, passo a passo) fica nos documentos próprios linkados em cada item — aqui fica só o resumo do estado e o próximo passo objetivo.

---

## Prioridade alta

### [~] GBE Ethernet — PHY nunca sai de power-down (RX morto)

**Contexto:** MAC ligado com sucesso via ICC (`0x004=0xb19`), TX por software funcional (~95%, doorbell corrigido em 2026-07-25). Mas o PHY nunca responde a MDIO — Clause 45 (MMD1/MMD7) e Clause 22 (BMCR, scan completo endereços 0-31) sempre retornam zero/timeout. RX permanece morto (`MTS_CNT_PKTS=0`, ping 100% perda).

**Já descartado:** `MTS_MAC_EN2` como causa; hipótese de IRQ real (`IMR=0x7d`) reproduzindo full-duplex; correção do efuse (BAR4 em vez de BAR2) foi necessária mas insuficiente sozinha.

**Próximo passo exato:** validar pós-power-cycle os fixes de `mts_mac_stop()`/doorbell TX, depois varredura read-only da janela Glue BAR2 `0x140000`-`0x180000+` e reordenar o diagnóstico MDIO para rodar após o release do hold.

**Documentos:** plano ativo em [`../PLANO_FASES_GBE_2026-07-25.md`](../PLANO_FASES_GBE_2026-07-25.md); histórico de RE em [`RE_KERNEL_GBE_ATTACH.md`](RE_KERNEL_GBE_ATTACH.md) e [`ICC_GBE_TEST_LOG.md`](ICC_GBE_TEST_LOG.md).

---

### [~] S5 incompleto no `poweroff -f` (luz azul não apaga)

**Contexto:** `sync && poweroff -f` encerra o SO e derruba a rede, mas o console fica com a luz azul acesa/pulsando — desligamento total da fonte (S5) não ocorre.

**Já feito:**
1. [x] RE no dump Orbis 12.52 (disassembly de `icc_power_shutdown`, offset `0x1d8a3c`): estrutura real do payload ICC S5 tem **32 bytes** (`cause` em `+0x0E`, `depth` em `+0x0F`, `hand` em `+0x10`) — o driver Linux enviava só 6 bytes truncados.
2. [x] Patch aplicado em `ps4-bpcie-icc.c` e `ps4-apcie-icc.c`: monta o payload de 32 bytes e loga o hex dump da resposta do MCU.

**Pendente:** [ ] compilar o bzImage com o patch e testar ao vivo no console — aguardando autorização explícita do usuário (Regra de Ouro da Injeção).

---

## Prioridade média

### [~] SATA interno (HD Toshiba MQ04ABF100) cai após ~31s — **pendente teste no próximo build**

**Contexto:** drive interno cai por HIPM/DIPM (power management) matando o disco. `libata.force=1.00:3.0Gbps,noncq` já testado e não resolveu sozinho.

**Alterações aplicadas (2026-07-25) — pendentes de teste ao vivo:**
- `[bootargs]` `ahci.mobile_lpm_policy=1` em `bootargs-7.0.txt` e `01-build-image-7.0.sh` — testar primeiro (sem rebuild)
- `[quirk]` `ATA_QUIRK_NOLPM` para `"TOSHIBA MQ04ABF100"` em `libata-core.c:4194` — requer rebuild
- `[ICC]` Power-on SATA (major 5 minor 0x20) em `ps4-bpcie.c` — requer rebuild

**Próximo passo:** rebuild de kernel com o quirk + ICC, ou testar bootargs primeiro sem rebuild. **NÃO TESTADO AINDA.**
**Impacto:** baixo no dia a dia (rootfs já roda no USB), mas bloqueia uso do HD interno como storage.

### [x] Testar renderização 3D ao vivo (glxgears/vulkaninfo) — **VALIDADO ao vivo 2026-07-25**

**Resultados:**
- **OpenGL:** 4.5 Core Profile, Mesa 26.1.5, renderizador `AMD DG1501SML87LB (radeonsi, kaveri, ACO)`, 1024MB VRAM dedicada
- **glxgears:** ~54 FPS (1920x1080@60 via HDMI, sincronizado com refresh)
- **Vulkan:** 1.3.354, driver RADV KAVERI 26.1.5, device `AMD DG1501SML87LB`, `INTEGRATED_GPU`, todas features 1.3 habilitadas
- **Direct rendering:** sim, acelerado por hardware
- **Comprovado:** GPU Gladius 100% funcional — OpenGL 4.5 + Vulkan 1.3 + aceleração 3D real

### [~] RTC via ICC no PS4 Linux — implementar driver `rtc-ps4-icc`

**Contexto:** `CONFIG_RTC_CLASS=n` no kernel do PS4 → sem `/dev/rtc`, sem `/sys/class/rtc`. Clock travado na build epoch (2026-06-26), o que bloqueia `pacman` por validação SSL. Orbis FreeBSD tem RTC real via ICC + MMIO; o driver Linux precisa replicar.

**RE 2026-07-25 (100% validada no dump Orbis 12.52):**
- Descobertos **dois drivers RTC em camadas** no kernel: `rtc_mvl.c` (baixo nível, MMIO direto, read-only) e `rtc.c` (alto nível via ICC, **recomendado para o Linux** — tem settime)
- Protocolo ICC confirmado:
  - `icc_query(major=2, minor=0x0c, sub=0x81/1, 1B)` = load context (recupera flag "contexto salvo")
  - `icc_query(major=2, minor=0x0b, sub=0x81/1, 1B)` = save context
  - `icc_query(major=4, minor=0x50, 1B)` = ler bitmask de alarmes (`0xff` = sem alarmes; bits 0/1/2 = alarm0/alarm1/alarm2 que estão nos offsets `softc+0xc0/+0xc4/+0xc8`)
- MMIO confirmado: read 8B em `0x5180000` (gettime), write 8B em `0x5140000` (settime)
- Constante Sony `0x4effa200` = offset de epoch Sony — **NÃO usar no Linux** (escrever epoch unix puro)
- 8 funções RE registradas no `ps4_hardware_memory.db` (`decompiled_functions`, categorias "RTC (rtc_mvl.c)" e "RTC (rtc.c)")
- Lacunas para decompilar se necessário: `dc839e40`/`dc839d90` (MMIO read/write wrappers), `dc6b1a20`/`dc6b1b80` (dispatchers save/load), `dc797090` (transport ICC subjacente)

**Próximos passos (plano em [`plans/rtc_via_icc_plan.md`](plans/rtc_via_icc_plan.md)):**
1. [x] Fase 1 — Habilitar `CONFIG_RTC_CLASS=y` + `CONFIG_RTC_INTF_DEV=y` + `CONFIG_RTC_DRV_CMOS=y` + `CONFIG_RTC_HCTOSYS=y` no `00-build-kernel-7.0.sh` (linhas 513-528). ⚠️ Não habilitar `CONFIG_RTC_DRV_PS4_ICC` ainda (driver não existe).
2. [x] Fase 2 — Wrapper `ps4_icc_rtc_cmd()` com retry loop (100× 50ms) criado em `drivers/ps4/ps4-bpcie-icc.c` + declarado em `baikal.h`/`aeolia.h`. **Patch versionado** em `distros/arch_minimal_v2/patches/ps4-icc-rtc-wrapper.patch` + aplicação idempotente no `00-build-kernel-7.0.sh`. Validado com compile isolado (`make drivers/ps4/ps4-bpcie-icc.o` OK, símbolo `__export_symbol_ps4_icc_rtc_cmd` presente). Nada novo em `EXPORT_SYMBOL_GPL(bpcie_icc_cmd)` — já existia.
3. [ ] Fase 3 — Criar `drivers/rtc/rtc-ps4-icc.c` (esboço pronto no plano, seção "Fase 3").还需 criar `drivers/rtc/Kconfig` e `drivers/rtc/Makefile` entries.
4. [ ] Fase 4 — Rebuild kernel + módulos (combinando Fases 1+2+3 num único build); deploy; validar `hwclock -r`, `date`, `pacman -Sy`
5. [ ] (opcional) Fase 5 — NTP no boot (`systemd-timesyncd` ou `ntpd -q -g`) + `fake-hwclock` como safety net

**Critérios de sucesso:** `/dev/rtc0` aparece após `modprobe rtc-ps4-icc`; `hwclock -r` retorna tempo válido; `date` estável entre boots (com NTP sync); `pacman -Sy` não falha por clock.

**Documentos:** [`plans/rtc_via_icc_plan.md`](plans/rtc_via_icc_plan.md) (com seção "Validação da RE (2026-07-25)"); [`../memory/rtc-via-icc-re-validada-2026-07-25.md`](../memory/rtc-via-icc-re-validada-2026-07-25.md); [`decompiled/baikal_rtc_mvl.txt`](decompiled/baikal_rtc_mvl.txt); [`decompiled/INDEX.md`](decompiled/INDEX.md) §6.B.

---

## Prioridade baixa

### [ ] Enxugar o kernel: remover tudo que não é específico do PS4 nem tem uso prático

**Objetivo:** reduzir o `.config` ao que o console realmente usa. Ganhos esperados: builds mais rápidos, menor pico de memória (hoje um build chega a exigir mais RAM do que a máquina tem), `bzImage` menor e menos superfície para bug/regressão.

**Caso exemplar já identificado — `CONFIG_DEBUG_INFO_BTF`:**
- Gera metadados de tipos para **BPF CO-RE** (bpftrace, BCC, libbpf). Nada disso é usado aqui: o debug do projeto é `dmesg` + telnet + leitura de MMIO.
- Custo medido em 2026-07-21: o passo `pahole` consome **10,9 GB de RSS** e roda depois do link, sobre o `vmlinux` pronto. Foi o maior consumidor de memória do build inteiro — maior que o próprio link ThinLTO.
- Desabilitar **não desabilita BPF** (`CONFIG_BPF_SYSCALL` continua funcionando); só remove os metadados.
- O projeto já roda cgroup v1 (`systemd.unified_cgroup_hierarchy=0`), então nem os usos de BPF do systemd pesam.
- Implementação: `scripts/config --disable CONFIG_DEBUG_INFO_BTF` (e provavelmente `CONFIG_DEBUG_INFO_BTF_MODULES`) no `00-build-kernel-7.0.sh`, junto dos outros `scripts/config` que já estão lá.

**Outros candidatos a avaliar** (não verificados ainda — levantar antes de desabilitar):
- Drivers de hardware que o console não tem (o `.config` vem de um defconfig genérico).
- Sistemas de arquivos não usados — hoje só precisamos de ext4 (rootfs), vfat (partição BOOT) e o necessário ao initramfs.
- Subsistemas de virtualização já parcialmente desligados no script (`KVM`, `PARAVIRT`, `HYPERVISOR_GUEST`) — conferir se sobrou algo.
- `CONFIG_DEBUG_INFO` em si: se ninguém for abrir o `vmlinux` em debugger/Ghidra, é muito peso morto. **Cuidado:** hoje ele é útil para inspecionar o binário compilado, então avaliar caso a caso.

**Cuidado ao executar esta tarefa:** mudar o `.config` dispara recompilação ampla (~40 min nesta máquina). Vale agrupar todas as remoções em **uma única** rodada e testar o boot depois, em vez de ir removendo aos poucos. E manter a tag anterior em `boot_referencia/` para rollback — cada teste ao vivo custa um power cycle completo.

### [ ] WiFi/BT — manufacture data ausente

`wlanAdapterStart: load manufacture data fail` — NVRAM `/data/nvram/APCFG/APRDEB/WIFI` ausente. WiFi conecta mesmo assim usando defaults do eFUSE, mas pode ter potência/canal subótimo. Baixa prioridade, não bloqueador.

### [ ] Power Management — reativar DPM

`radeon.dpm=0 amdgpu.dpm=0` está fixo hoje por instabilidade de clocks dinâmicos. Reativar com testes de estresse quando houver tempo, não é bloqueador.

---

## Concluídos recentemente (referência — não repetir)

- [x] **GPU amdgpu/Gladius (GFX/CP)** — `ring gfx test failed (-110)` resolvido em 2026-07-23 com firmware genuíno extraído via `kexec`; 32 CUs ativos, OpenGL 55 FPS, Vulkan 1.3 disponível. Ver `MARCO_HISTORICO_GPU_GLADIUS_REAL.md`.
- [x] **Migração para kernel 7.0 Baikal** — concluída em 2026-07-22 (baseline `v7.0-20260722-clean-video-ok`), superou de vez a necessidade de "migrar para 6.x" (item removido do roadmap).
- [x] **Rootfs completo via systemd (RELEASE, sem debug loop)** — validado ao vivo 2026-07-23 com `bzImage-7.0-20260723-RELEASE`.
- [x] **Ethernet GBE — MAC core e TX por software** — interface `eth0` sobe, MAC ligado via ICC, TX ~95% funcional (RX ainda pendente, ver item ativo acima).
- [x] **Kernel Dump 12.52 via TCP** — concluído em 2026-07-20 (32.2 MB em 3s, zero corrupção).
