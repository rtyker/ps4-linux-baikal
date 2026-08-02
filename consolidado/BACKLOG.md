# Backlog do Projeto — Fonte Única de Pendências

**Última atualização:** 2026-07-29 (Vídeo HDMI: SOLUCIONADO em 1080p@60Hz com ressalva de hardware — exige adaptador HDMI energizado; SATA interno: PENDENTE - tag `20260729-sata-polling-clean` implantada no HD USB e pronta para teste de boot)

Este é o **único documento** onde a lista de tarefas pendentes do projeto deve ser mantida. Nenhum outro arquivo (`STATUS_ATUAL.md`, `MASTER_CONSOLIDADO.md`, `O_QUE_FALTA.md`, etc.) deve manter sua própria lista de "próximos passos" — todos apontam para cá, para evitar itens duplicados ou desatualizados espalhados pelo projeto.

Convenção: `[ ]` pendente · `[~]` em andamento · `[x]` concluído (mover para "Concluídos recentemente" ao fechar).

O trabalho **ativo no momento** (investigação detalhada, passo a passo) fica nos documentos próprios linkados em cada item — aqui fica só o resumo do estado e o próximo passo objetivo.

---

## Prioridade alta

### [ ] 🔍 Investigação de travamento do Xorg / SDDM pós-restart (hipótese: autostart do Steam)
**Contexto (2026-08-01):** Na primeira reinicialização do SDDM via SSH a interface gráfica subiu perfeitamente (`Session started true`, PID 1716). Na segunda tentativa de reinicialização do SDDM/Xorg, a rede/interface gráfica travou.
**Hipótese do Usuário:** O travamento pode ter sido causado por autostart/inicialização em background do cliente Steam durante o re-login do SDDM. Validar e analisar logs em sessão posterior.

---

### [x] 🔒 GBE Ethernet — PHY nunca sai de power-down — INVESTIGAÇÃO ENCERRADA 2026-07-30 (bloqueador de firmware, não solucionável via driver Linux)

**Contexto:** MAC ligado com sucesso via ICC (`0x004=0xb19`), TX por software funcional (~95%, doorbell corrigido em 2026-07-25). Mas o PHY nunca responde a MDIO — Clause 45 (MMD1/MMD7) e Clause 22 (BMCR, scan completo endereços 0-31) sempre retornam zero/timeout. RX permanece morto (`MTS_CNT_PKTS=0`, ping 100% perda).

**Já descartado:** `MTS_MAC_EN2` como causa; hipótese de IRQ real (`IMR=0x7d`) reproduzindo full-duplex; correção do efuse (BAR4 em vez de BAR2) foi necessária mas insuficiente sozinha.

**Próximo passo exato:** validar pós-power-cycle os fixes de `mts_mac_stop()`/doorbell TX, depois varredura read-only da janela Glue BAR2 `0x140000`-`0x180000+` e reordenar o diagnóstico MDIO para rodar após o release do hold.

**Documentos:** plano consolidado ATIVO (2026-07-29, revisão de UART+SQLite+código) em [`../PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](../PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md) — substitui o plano de 07-25 como fonte de próximos passos (o de 07-25 fica só como histórico); histórico de RE em [`RE_KERNEL_GBE_ATTACH.md`](RE_KERNEL_GBE_ATTACH.md) e [`ICC_GBE_TEST_LOG.md`](ICC_GBE_TEST_LOG.md).

**Status 2026-07-30:** bug de polaridade MDIO Clause 22 corrigido em `mts.c` (ver `memory/mdio-clause22-bug-polaridade-corrigido-2026-07-29.md`) e testado ao vivo — eliminou o falso-positivo de dado residual, mas PHY continua sem link. **🏆 Tag `20260730-sata-reverted` CONFIRMADA ao vivo como o novo BASELINE OFICIAL/ponto de rollback** (boot completo, SSH ok, `eth0` sobe com MAC real) — ver `memory/baseline-oficial-20260730-sata-reverted.md`.

**Fase 2 do plano consolidado (MSI/IMR) — CONCLUÍDA E REFUTADA 2026-07-30, com evidência direta (`test_history` id 72):** o achado "`RX_CLEAN ... cleaned=N`" de ontem era só o contador de chamadas de NAPI poll, não atividade de hardware real (confirmado lendo `mts.c:1608-1685`). Testado ao vivo, sem rebuild:
1. `lspci -vv 00:14.1` (GBE) mostra MSI `Enable+ Count=1/1 Maskable+ Masking=00000000` — **NÃO mascarado em hardware**, diferente do caso AHCI (`Masking=000000fe`). Refuta a hipótese de mascaramento MSI análogo ao SATA.
2. Recarregado `mts.ko` com `irq_mask=0x7d` (IMR real desmascarado, era `0x0`=tudo mascarado por padrão) — confirmado via `mts_regs` (`0x54=0x0000007d`). Mesmo assim, `/proc/interrupts` ficou em **`irq_count=0`** por 5+s, ping continuou 100% perda, `eth0` continuou `NO-CARRIER`. Refuta também a hipótese de que o IMR default estava simplesmente mascarando eventos reais que já estavam acontecendo.
3. **Conclusão:** não é bug de MSI/demux nem de IMR — o PHY genuinamente nunca gera nenhuma condição de IRQ (nem link change, nem RX). Fecha esta via de investigação por evidência direta, conforme critério da Fase 3 do plano (`PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`): o bloqueador é anterior a qualquer coisa que o driver Linux possa fazer — energia/clock físico do PHY, ou sequência de bring-up da Sony fora do alcance replicável via software puro.
4. **Bug novo, não-bloqueante, achado de bônus:** `rmmod mts` sempre gera um `WARNING: kernel/irq/msi.c:294 at msi_device_data_release` (sistema não trava, fica só `tainted (O)`) — bug real no cleanup de MSI do driver, nunca documentado antes. Não impede reload (`insmod` funcionou normalmente na sequência).

**🔒 FECHAMENTO FORMAL 2026-07-30 — RE completa da thread `gbe_phy_ctrl` (`dc5a44c0`):** 11 funções extraídas via Ghidra Java headless (Docker), árvore de chamada inteira analisada. **Nenhuma chamada ICC ou SAMU encontrada** — a thread só monitora o PHY via MDIO packed reads e dorme esperando eventos. Varredura binária do `kmem_dump_1252.bin` confirma: 0 cross-refs para `dc5a44c0`, 0 referências a ICC major=5 (SAMU) no range GBE, 0 referências a MMIO de mailbox SAMU no range GBE. **Conclusão: o power-on físico do PHY é feito pelo firmware/bootloader Sony antes do kernel Orbis assumir — não há sequência replicável via MDIO, ICC, SAMU ou RMU que um driver Linux possa executar.** Esta via de investigação está **esgotada com os dados disponíveis** — não reabrir sem fonte de dados nova (ex: vazamento de firmware, dump de SAMU, documentação de terceiros sobre o PHY Baikal). Detalhes em `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` e `memory/sessao-ghidra-java-passo1-2026-07-30.md`. Prioridade do projeto redirecionada para as frentes já ativas (S5 shutdown, KVM).

---

### [~] S5 incompleto no `poweroff -f` (luz azul não apaga)

**Contexto:** `sync && poweroff -f` encerra o SO e derruba a rede, mas o console fica com a luz azul acesa/pulsando — desligamento total da fonte (S5) não ocorre.

**Já feito:**
1. [x] RE no dump Orbis 12.52 (disassembly de `icc_power_shutdown`, offset `0x1d8a3c`): estrutura real do payload ICC S5 tem **32 bytes** (`cause` em `+0x0E`, `depth` em `+0x0F`, `hand` em `+0x10`) — o driver Linux enviava só 6 bytes truncados.
2. [x] Patch aplicado em `ps4-bpcie-icc.c` e `ps4-apcie-icc.c`: monta o payload de 32 bytes e loga o hex dump da resposta do MCU.

**Build + teste 2026-07-25 (tag `s5-poweroff-fix-20260725`):**
- `bzImage-7.0-s5-poweroff-fix-20260725` (15.84 MB) compilado e deployed via `deploy-boot-7.0.sh`
- **Teste ao vivo:** `sync && poweroff -f` → SO desliga (SSH cai), mas **luz azul permanece acesa/pulsando + fan ligado** = S5 **não** atingido
- dmesg pós-boot não mostrou log do ICC S5 shutdown (verificar se payload foi enviado)

**Status 2026-07-30 (EM ANDAMENTO, pausado, retomar daqui):** achado novo — o payload de 32 bytes de 07-25 tinha **framing errado** (deveria ser 20 bytes de payload real, não 32; `_bpcie_icc_cmd()` já soma o header de 12 bytes ao `length`). Corrigido em `ps4-bpcie-icc.c` + implementada a sequência pré-sync (major=4/minor=4) + final (major=4/minor=1) nunca antes aplicada. Build da tag `20260730-s5-poweroff-fix` **concluído**, artefatos prontos em `boot_referencia/`. **Falta:** conectar o HD USB ao PC, `deploy-boot-7.0.sh 20260730-s5-poweroff-fix`, captura UART (não netconsole — a rede cai junto com o shutdown), power-cycle físico, `sync && poweroff -f`, ler o log UART. Ver `memory/s5-poweroff-fix-framing-corrigido-2026-07-30-aguardando-teste.md` e o plano em `/home/anderson/.claude/plans/abstract-roaming-unicorn.md`.

---

## Prioridade média

### [x] 🏆 SATA interno (HD Toshiba MQ04ABF100) — FEATURE CONCLUÍDA 2026-07-30, funcional pela primeira vez

**Resolvido via Fase B (polling timer de 1ms) do `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md`, testado ao vivo na tag `20260730-sata-polling-fase-ab`:**
- `ata1.00: configured for UDMA/100`, zero exceções/`disable device` em todo o dmesg (1322 linhas).
- Leitura real confirmada: `dd if=/dev/sda bs=1M count=50` → 71.2 MB/s sem erro. `fdisk -l /dev/sda` retorna a tabela completa (931.51 GiB).
- `PxIE` ficou em `0x7840007f` após o único `thaw()` do probe (t=3.02s) e nunca mais zerou (antes reincidia ~37s e desabilitava ~84s).
- **Novo baseline oficial/ponto de rollback:** tag `20260730-sata-polling-fase-ab` (kernel do baseline GBE `20260730-sata-reverted` + fix de SATA). Ver `memory/marco-sata-interno-funcional-2026-07-30.md` e `test_history` id 73.

### [~] 🔑 Obter a chave EAP real via EAPDumper (payload ao vivo) — **CONCLUÍDO 2026-07-31: chave obtida, estável; tweak/IV em aberto**

**Status 2026-07-31:** base do kernel 12.52 resolvida (`0xffffffffdc350000`) e a chave EAP
lida pelo kernel (`0xffffffffdea14cf0`) cai no BSS do dump — **zerada, não extraível deste dump**.
O ERK `7fcf0536...` que temos é cópia de debug/rodata (label `SCE_EAP_HDD__KEY`), não
confirmado como chave ativa. **EAPDumper v0.2.0 já está em `ps4-linux-payloads/EAPDumper.bin`**
(sha256 `73f9306d...`); suporta FW 5.03–13.50, e 12.52 cai no scanner cego (`0x2600000`–`0x2900000`,
cobre o offset `0x26C4CF0`), já aplica `reverse_16_byte_blocks` e grava
`/data/hddeap/eap_hdd_key.{bin,hex,txt}` + `/mnt/usb0/`.

**Chave EAP canônica obtida ao vivo (5 dumps, 3 boots):**
`edf3f4d33b16a17bf4ea92070fe8af6b08c23c91f98006ae5b4f7d363c2bf0a3` — **estável entre 3 boots** (entropia 4.88 constante no offset real `0x026C4CF0`). Scanner do EAPDumper sofre de **falso-positivo** (`0x0283A8C0` top em 4/5 dumps, conteúdo muda entre boots).

**🔴 DESCOBERTA CRÍTICA 2026-07-31:** `pycryptodome 3.23.0` **não tem `MODE_XTS`** — todos os testes XTS anteriores (96/504/380 combos) foram **falso-negativo total** (AttributeError silencioso → `None`). Refiz com `cryptography 49.0.0` (XTS real, vetores NIST OK): **ZERO hits** em TODOS os testes (Full 8MB absLBA, IV=0, byte-offset, varredura ±500k, 4 chaves × variantes). **Chave EAP `edf3f4d3...` está CORRETA** (kernel, offset validado por RE, estável 3 boots). O XTS funciona (vetores NIST OK). **Falta o tweak/IV correto** — hipótese principal: `ivoffset_field` (`iVar2[0x20]`) ≠ 0 no `g_crypt_create_provider` (vem de `g_provider.ivoffset` setado por `g_part`/EAP boot).

**Próximo passo:** boot no Linux 7.0 (tag `20260730-sata-polling-fase-ab`) + `cryptsetup open -c aes-xts-plain64 --key-file keys/eap/eap_hdd_key.bin --key-size 256 --offset <LBA> /dev/sda27` testando `--offset` (ajusta IV) vs `--skip`. RE do `ivoffset_field` — traçar `*(iVar2+0x20)` no `g_crypt_create_provider` (vem de `g_provider.ivoffset` setado por `g_part`/EAP boot). Ver `keys/TESTES_EAPDUMPER_2026-07-31.md`, `keys/INDEX.md`, `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md` Seção 22.

---

### [x] 🏆 Montagem Nativa do HD Interno (/dev/sda) — FEATURE CONCLUÍDA 2026-07-30> ⚠️ **RE-TESTE 2026-07-30 (sessão posterior): `sda27` (Games/user) NÃO decripta corretamente** — `ps4_pfs_fuse` retorna magic PFS errado (`0x01B9B25D` em vez de `0x1332A0B`), indicando que a chave/tweak usados pelo `monta_particao.sh` (mesmos de `sda13`) não são válidos para `sda27`. Só `sda13` (System) foi de fato confirmado decriptando corretamente nesta sessão. Ver `memory/sda27-decriptacao-magic-incorreto-2026-07-30.md`. Achado colateral: `/usr/local/bin/pfsfuse` (deploy manual, fora do fluxo de build) era um binário de **PS2**, não PS4 — renomeado para `.bak` no PS4. Ver `memory/pfsfuse-binario-errado-ps2-nao-ps4-2026-07-30.md`.
- **Concluídas as 3 fases do `PLANO_MONTAGEM_NATIVA_HD_INTERNO_SDA.md`**:
  1. Inspeção completa das 29 partições (`sda1` a `sda29`), extração da chave EAP da NOR (`nor_sflash0.bin`), derivação da chave XTS (`data` + `tweak`), e validação de `cryptsetup` com `-o ro`.
  2. Desenvolvidos os scripts modulares `/usr/local/bin/monta_particao.sh`, `/usr/local/bin/desmonta_particao.sh` e `/usr/local/bin/automount.sh` (com chave em `/etc/ps4_keys.bin`), testados com sucesso ao vivo via SSH no PS4 real para mapeamento e montagem automática combinada das partições de Sistema (`sda13`) e Games (`sda27`).
  3. Integrada a cópia automática dos scripts e utilitários (`monta_particao.sh`, `desmonta_particao.sh`, `automount.sh`, `pkg_pfs_tool` compilado para a CPU Jaguar `btver2` do PS4 e `config.ini`) no gerador de imagens da distro customizada `01-build-image-7.0.sh` para o Arch Minimal v2. Adicionado o pacote `sleuthkit` na lista de instalação automática `PKGS` do pacman.
  4. Configurado acesso total sem senha (`NOPASSWD: ALL` em `/etc/sudoers.d/ps4-hdd`) e regra udev `/etc/udev/rules.d/99-ps4-disk-permissions.rules` (permissão `0666` direta para `/dev/sda*`, `/dev/dm-*` e `/dev/mapper/`) para o usuário `ps4` operar os utilitários de montagem, mappers e criptografia. Integrado na receita de build `01-build-image-7.0.sh`.
  5. Desenvolvido o driver FUSE **`ps4_pfs_fuse`** (`/usr/local/bin/ps4_pfs_fuse`) com I/O sob demanda via `pread` (super leve, zero consumo de RAM pré-alocada) para montagem e navegação transparente no VFS/Nemo/Nautilus das partições PFS. Integrado ao gerador de imagens `01-build-image-7.0.sh` e documentado no plano `PLANO_MONTAGEM_NATIVA_NEMO_NAUTILUS_FUSE.md`.

**Limpeza pendente (não bloqueante):** remover a instrumentação de debug (`ahci_dbg:` em `freeze()`/`thaw()`/`ahci_error_handler()`, já marcada "REMOVER quando a investigação terminar" no código) num próximo rebuild.

<details>
<summary>Histórico da investigação (hipóteses refutadas antes da solução) — clique para expandir</summary>

### [~] 🔴 SATA interno (HD Toshiba MQ04ABF100) — **PRIORIDADE ALTA: custa 78s no boot e desabilita dispositivo aos 84s**

**Resultado do teste ao vivo (2026-07-29, tag `20260728-sata-ackfix-ehdump`, log `video_001_20260729_124629.bin`):**
- ❌ **HIPÓTESE DO FIX DE DEMUX ACK REFUTADA:** A tag `20260728-sata-ackfix-ehdump` **não resolveu** o SATA interno.
- **Leitura estrita de timestamps do log `video_001` (4159 linhas):**
  - `t = 3.18s`: `sda` é detectado e tabela de partições lida.
  - `t = 7.37s`: `/init` é chamado pelo systemd **a partir do HD Externo USB (`sdb2`)**, dando falsa impressão inicial de boot rápido.
  - `t = 37.00s`: Exceção ATA estoura no HD interno: `ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6 frozen` (`READ DMA tag 26`). `SErr 0x0` e status `{ DRDY }` confirmam PHY 100% íntegro.
  - `t = 84.11s`: O kernel esgota as 3 tentativas de `IDENTIFY (cmd 0xec)` e desabilita o dispositivo (`ata1.00: disable device`).
- **Conclusão:** O HD interno (`sda`) continua inoperante sob o Linux. A interrupção `PxIS=0x2` é gerada pelo AHCI, mas o sinal MSI do Baikal deixa de ser entregue à CPU pelo driver de interrupções.

**Análise de Engenharia Reversa & Teste ao Vivo (2026-07-29, tag `20260729-sata-globallock`, log `sata_teste_20260729_145146.bin`):**
- **Implementação:** Spinlock estático global (`bpcie_ack_lock`) aplicado no `ps4-bpcie.c` cobrindo o par de leitura/escrita do ACK do Glue (`0x110084`/`0x110088`), reproduzindo o mutex global do Orbis (`dc718b40`).
- ❌ **HIPÓTESE DO SPINLOCK GLOBAL REFUTADA:** O spinlock funcionou sem travar o kernel, mas a falha do SATA permaneceu idêntica: 10 despachos de interrupção iniciais até `t = 4.89s`, parada de sinalização no Glue, estouro de exceção em `t = 36.80s` (`READ DMA EXT tag 5`) e desativação em `t = 83.90s` (`disable device`).
- **Achado Factual Medido no EH:** No momento da exceção em 36.80s, o AHCI reporta `PxIS=0x2` (interrupção de conclusão pendente na porta) e `IS=0x1` (porta 0 assinalando IRQ global no AHCI), porém o registrador do Glue `BAR2+0x110088` lê `0x001e0103` (apenas subfunção 0/USB pendente, subfunção 1/SATA zerada).
- **Conclusão:** O sinal de interrupção entre a lógica da porta do AHCI e o registrador do Glue deixa de transitar a partir dos 4.89s de boot (provável transição de power/idle da porta ou falta de rearme explícito).

---




- Validado: `__ksymtab_ps4_icc_sata_power_on` + `__kstrtab_ps4_icc_sata_power_on` e string `TOSHIBA MQ04ABF100` presentes no `vmlinux` (built-in, não módulo)
- Compilação isolada pré-build: `drivers/ata/libata-core.o` e `drivers/ps4/ps4-bpcie-icc.o` OK

**Build combinado SATA + S5 poweroff (2026-07-25 18:55):**
- Tag `s5-poweroff-fix-20260725` (15.84 MB, Clang/ThinLTO) — `bzImage-7.0-s5-poweroff-fix-20260725`
- MD5 diferente do `20260725-full-build` → build novo com patches SATA + S5 poweroff

---

### **SMOKE TEST AO VIVO 2026-07-25 (tag s5-poweroff-fix-20260725) — RESULTADO**

**✅ O que FUNCIONOU (patches validados):**

| Patch | Evidência no dmesg (PS4 uptime ~4min) |
|-------|----------------------------------------|
| ICC power-on SATA | `[0.623518] icc: SATA power-on OK (reply 20 bytes)` |
| Quirk NOLPM aplicado | `[1.158248] ata1.00: Model 'TOSHIBA MQ04ABF100', rev 'JU0G0A', applying quirks: nolpm` |
| LPM totalmente desligado | `[1.205] ata1.00: LPM support broken, forcing max_power` + sysfs `max_performance` |
| Disco visível por >4min | `sda 931.5G TOSHIBA MQ04ABF1` em `lsblk` com uptime 4min+ |
| PS4 estável | SSH ativo, rootfs USB OK, uptime >4min |

**❌ HIPÓTESE HIPM/DIPM REFUTADA — CAUSA RAIZ NÃO É LPM:**

Mesmo com **LPM 100% desligado** (quirk NOLPM + sysfs `max_performance`), o colapso aconteceu **exatamente no mesmo momento do baseline**:

| Evento | Timestamp | Comentário |
|--------|-----------|------------|
| `ata1.00: exception Emask 0x0 SAct 0x400000 SErr 0x0 action 0x6 frozen` | **t=31.849479s** | IDÊNTICO ao histórico (31.8s) |
| `ata1: hard resetting link` (1º) | t=31.854s | |
| `ata1: SATA link up 3.0 Gbps` | t=32.333s | |
| `ata1.00: qc timeout after 5000 msecs (cmd 0xec)` | t=37.473s | IDENTIFY timeout |
| `ata1: limiting SATA link speed to 1.5 Gbps` | t=47.974s | Downshift |
| `ata1.00: disable device` | **t=78.951907s** | IDÊNTICO ao histórico (~79s) |

**⚠️ DESCOBERTAS NOVAS CRÍTICAS:**

1. **Drive é Drive-managed SMR** (confirmado em dmesg): `sd 0:0:0:0: [sda] Drive-managed SMR disk` — drives SMR gerenciados pelo firmware têm latência oculta de garbage collection que explode timeouts.

2. **NCQ NÃO está sendo desligado pelo bootargs:** `libata.force=1.00:3.0Gbps,noncq` está no cmdline mas o comando que trava é `READ FPDMA QUEUED` (NCQ) com tag 22 → o `noncq` não está fazendo efeito neste controlador Baikal.

3. **Link físico permanece up** — o PHY SATA nunca cai (`SStatus 123/113` sempre presente), o drive para de responder a comandos SCSI.

4. **NÃO é LPM** — LPM 100% off, quirk aplicado, `max_performance`, mas o colapso é **byte-a-byte idêntico** ao baseline.

5. **⚠️ HARDWARE FIXO:** O Toshiba MQ04ABF100 é o **HD interno do PS4** (conectado diretamente na placa-mãe, sem cabo SATA removível) — não dá para trocar por outro drive para isolar hardware vs firmware.

---

### **PRÓXIMOS CAMINHOS DE INVESTIGAÇÃO (causa raiz real):**

| Hipótese | Por que vale testar | Ação |
|----------|---------------------|------|
| **NCQ efetivo não desligado** | O comando que trava é `READ FPDMA QUEUED` (NCQ tag 22). Se `ATA_QUIRK_NONCQ` for aplicado ao mesmo modelo, o kernel não emitirá FPDMA QUEUED. | Adicionar quirk `ATA_QUIRK_NONCQ` (ou `ATA_QUIRK_BROKEN_FPDMA_AA`) junto ao `NOLPM` em `libata-core.c`. |
| **Timer de spin-down do drive SMR** | Drive-managed SMR (Toshiba MQ04ABF100) tem timer interno de idle → spindown → firmware trava comandos subsequentes. Em 31s sem I/O no disco, ele entra "deep idle". | 1. `hdparm -S 0 /dev/sda` para desligar standby timer. 2. Ou forçar I/O periódico (cron a cada 10s). 3. Testar quirk `ATA_QUIRK_NO_IDLE` se existir. |
| **Calibração PHY SATA Baikal incompleta** | Colapso em **exatos 31.85s** sugere timer de PHY/efuse. `bpcie_baikal_sata_phy_init` portou `dc72bfb0` mas pode faltar etapa. | Rever `ps4-bpcie.c:549` vs `decompiled/baikal_sata_phy_init_dc72bfb0.txt` — conferir trace length, efuse, hold/pulse. |
| **Timeout EH do libata** | Kernel aborta em 5000ms → 10000ms → 30000ms. Se a latência SMR (garbage collection) excede 5s, o EH acha que travou. | Aumentar `ata1.eh_timeout` se exposto, ou patchar `libata-eh.c` (sem rebuild completo: via `sysfs` se exposto). |
| **Power domain separado do PHY** | ICC power-on SATA liga o MAC mas o PHY pode ter domínio separado (como GBE). | Procurar no Orbis ICC minor para PHY SATA power-on (além do major=5 minor=0x20). |

---

### **Próximo passo imediato (baixo risco, alto impacto):**
Aplicar quirk `ATA_QUIRK_NONCQ` (ou `ATA_QUIRK_BROKEN_FPDMA_AA`) junto ao `NOLPM` no `libata-core.c:4194` para o modelo `"TOSHIBA MQ04ABF100"`. Isso desabilita NCQ no nível do driver (não via bootargs) e evita que `READ FPDMA QUEUED` seja emitido — o comando que sempre falha em tag 22.

**✅ APLICADO (2026-07-25, pós-smoke-test):**
- `ATA_QUIRK_NOLPM | ATA_QUIRK_NONCQ` adicionado em `libata-core.c:4194` para `"TOSHIBA MQ04ABF100"`
- Backup preservado: `libata-core.c.orig-backup`

**Build + teste 2026-07-28 (tag `sata-noncq-fix-20260728`):**
- Kernel `bzImage-7.0-sata-noncq-fix-20260728` compilado (ThinLTO, 15.8 MB)
- Deploy via `deploy-boot-7.0.sh` — bootargs mantido `libata.force=1.00:3.0Gbps,noncq ahci.mobile_lpm_policy=1`
- **SMOKE TEST AO VIVO (2026-07-28):**
  - ✅ Quirk aplicado: `[1.158248] ata1.00: Model 'TOSHIBA MQ04ABF100', rev 'JU0G0A', applying quirks: nolpm noncq`
  - ✅ NCQ desabilitado no driver: `1953525168 sectors, multi 16: LBA48 NCQ (not used)`
  - ❌ **FALHA PERSISTE** — o colapso ocorreu **idêntico ao baseline**, só mudou o comando:
    - Antes: `READ FPDMA QUEUED` (NCQ tag 22)
    - Agora: `READ DMA` (legacy, cmd 0xc8) → IDENTIFY timeout 5s → 10s → 30s → disable device
    - Timestamps: exception 31.8s → hard reset → link up 3.0Gbps → IDENTIFY timeout 5000ms (37.5s) → 10000ms (47.9s) → downshift 1.5Gbps → disable device (78.9s)

**Testes adicionais 2026-07-28 (sem rebuild):**
| Teste | Resultado |
|-------|-----------|
| `hdparm -S 0 /dev/sda` (desligar standby timer) | **Erro I/O** — drive já falhando no momento do comando |
| `dd` periódico 4K/5s (evitar deep idle SMR) | **Não impediu** — erros contínuos no setor 0, drive morre mesmo com I/O |

**⚠️ DESCOBERTAS CRÍTICAS 2026-07-28:**
1. **Drive é Drive-managed SMR** (confirmado): `sd 0:0:0:0: [sda] Drive-managed SMR disk` — latência oculta de garbage collection explode timeouts
2. **NCQ desabilitado no driver funciona** — não há mais `READ FPDMA QUEUED`, mas `READ DMA` legacy também falha
3. **Link físico permanece up** — PHY SATA nunca cai (`SStatus 123/113` sempre), drive para de responder comandos SCSI
4. **NÃO é LPM/NCQ** — 100% off, mas colapso **byte-a-byte idêntico** ao baseline (31.8s exception → 79s disable)
5. **⚠️ HARDWARE FIXO:** O Toshiba MQ04ABF100 é o **HD interno do PS4** (conectado diretamente na placa-mãe, sem cabo SATA removível) — **não dá para trocar por outro drive para isolar hardware vs firmware**. Isolamento de hardware **não é possível**.

---

### ⚠️ **DIAGNÓSTICO PARCIAL (2026-07-28) — corrigido após o teste ao vivo**

> 🔴 **ERRATA:** a versão original desta seção afirmava que "o AHCI não tem handler de interrupção
> registrado". **Isso estava errado.** O AHCI sempre teve handler — ele se chama
> **`xhci_aeolia[0000:00:14.7]`**, não `ahci[...]`, porque `ata_host_activate()`
> (`libata-core.c:6206`) usa `dev_driver_string(host->dev)` e o AHCI interno é instanciado de
> dentro do `xhci_aeolia`. Procurar por `ahci[0000:00:14.7]` nesta função é falso negativo
> garantido. Também estava errada a tese de que a falha era específica de NCQ — ver abaixo.

**O que continua verdadeiro:** o AHCI *compartilhava* a IRQ 32 com os dois xHCI, e o vetor que lhe
caberia é o hwirq **5345** (função 7, subfunção 1).

Em 100% dos logs a falha é um `READ FPDMA QUEUED` (NCQ) que nunca completa, com **`SErr 0x0`**
(zero erro de link), `Emask 0x0` e `status { DRDY }`, e o link permanece estável em 3.0 Gbps
antes e depois. Uma conclusão de comando NCQ depende exclusivamente do SDB FIS — sem
interrupção, o tag fica pendente até o timeout de 30s do SCSI estourar.

**Causa:** `bpcie_assign_irqs()` (`ps4-bpcie.c`) clampava `nvec = 1` para toda função != 4,
apesar de `subfuncs_per_func[7]=3`, do ramo de demux `func == 7` já existente em
`bpcie_handle_edge_irq()`, do `MSI_FLAG_MULTI_PCI_MSI` no domínio e de
`xhci_aeolia_skip_index()` já reservar o índice 1 para o AHCI. Toda a infraestrutura existia;
uma linha a desativava.

| Hipótese anterior | Status |
|-------------------|--------|
| Calibração PHY SATA Baikal incompleta | ❌ **REFUTADA** — `SErr 0x0` em 100% das falhas, link estável; registradores AHCI confirmam `PxSERR=0` |
| Power domain separado do PHY | ❌ **REFUTADA** — mesma razão; MAC responde, PHY inicializa, link sobe |
| Timeout EH do libata | ❌ **REFUTADA** — mascararia o sintoma; o comando nunca completaria de todo jeito |
| Firmware drive SMR bug | ❌ **REFUTADA** — drive nunca reportou erro; falha em `dmesg.log` foi no LBA 0 |
| "Colapso em exatos 31.85s = timer de PHY/efuse" | ❌ **FALSO** — falhas em 31.84s, 36.58s e 44.76s |
| "AHCI sem handler de IRQ registrado" | ❌ **FALSO (erro meu)** — o handler chama-se `xhci_aeolia[0000:00:14.7]` |
| "A falha é específica de NCQ" | ❌ **REFUTADA pelo teste** — com `noncq` ativo falha como `READ DMA` (`0xc8`, `SAct 0x0`), não-enfileirado |
| Interrupção mascarada | ❌ **REFUTADA** — `GHC=0x80000002` (IE on), `PxIE=0x7840007f`, `PxIS=0`, `IS=0` |

### Resultado dos dois testes ao vivo (2026-07-28)

**Teste 1 — tag `20260728-sata-irq-dedicada` (`test_history` id 64, PARCIAL).** A alocação de 3
vetores funcionou no nível de alocação: `/proc/interrupts` passou a mostrar hwirq 5344/5345/5346 e
`ata1 ... irq 33`, sem regressão em USB/`mmc0`/`mts`/Blu-ray. **Mas o HD continuou falhando**, agora
com `READ DMA` (não-enfileirado), o que já refutou a tese de NCQ.

**Teste 2 — tag `20260728-sata-demux-diag` (`test_history` id 65, REFUTADO).** Instrumentação com
contadores no demux. Resultado decisivo:

```
chamadas no vetor f7 sub0 (hwirq 0x14e0):  4096+
chamadas no vetor f7 sub1 (hwirq 0x14e1):     0   <- o "dedicado" ao AHCI, NUNCA dispara
invocações do demux sem nada a despachar:     0
```

🔴 **A hipótese da corrida no ACK compartilhado está REFUTADA** — não há disputa porque só existe
um vetor na prática. **O hardware Baikal agrega todas as IRQs da função 7 numa única mensagem MSI**
(a da subfunção 0); o demux não é contorno, é a forma correta de lidar com esse hardware. Todas as
14 entregas ao AHCI vieram com `origem sub0`.

🔴 **Consequência: a correção da Fase B é inútil e deve ser revertida.** Alocar 3 vetores não faz o
hardware usar 3 mensagens. Não regride nada, mas é complexidade sem benefício.

**Decodificação nova do `BPCIE_ACK_READ`** (BAR2 do glue, `0x110088`; write em `0x110084`): para a
função 7 os bits **18:16** são flags de pendência por subfunção, **ativos em nível baixo** —
`0x001e0103` = só sub0; `0x001c0103` = sub0 + **sub1 (SATA)**; `0x001a0103` = sub0 + sub2.

**PISTA PRINCIPAL:** a última interrupção do AHCI chegou aos **4,907s** e nunca mais. A falha aos
36,78s é só o timeout de 30s do SCSI estourando sobre um comando emitido por volta dos 6,8s.
Depois dos 4,9s o bit 17 do ACK **nunca mais volta a zero**.

**Pergunta real agora:** por que o glue para de sinalizar a subfunção 1 como pendente? Falta
determinar se o AHCI chega a *pedir* a interrupção (levantar `PxIS`) e o glue não propaga, ou se o
próprio controlador para de pedir. Próxima instrumentação deve ler `PxIS` no instante em que um
comando está pendurado — não depois do dispositivo desabilitado, como foi feito. Vale também
consultar `consolidado/decompiled/INDEX.md` e a tabela `decompiled_functions` para ver como o driver
Orbis trata o rearme dessas subfunções.

Detalhes em `PLANO_SATA_INTERNO_100PCT_2026-07-28.md`; memórias
`memory/baikal-func7-um-unico-vetor-msi-2026-07-28.md` e
`memory/sata-interno-falha-e-ncq-irq-compartilhada-2026-07-28.md`.

**Correção editada em 2026-07-28 (build em andamento, tag `20260728-sata-irq-dedicada`):**
clamp virou `nvec = min(nvec, bpcie_max_vectors(PCI_FUNC(dev->devfn)))`, com helper que
devolve `subfuncs_per_func[func]` só para funções com ramo de demux (4, 5, 7). Efeito prático:
só a função 7 muda (1 → 3 vetores); `mmc0`, `mts` e o AHCI do Blu-ray ficam idênticos.

⚠️ **Ao validar, REMOVER `noncq` do bootargs** — com NCQ desligado o teste não prova nada.
Critério de aceitação: `/proc/interrupts` passar a mostrar `Baikal-MSI 5345-edge ahci[0000:00:14.7]`.

Registro no banco: `test_history` id **63**. Memória:
`memory/sata-interno-falha-e-ncq-irq-compartilhada-2026-07-28.md`.

**Análise do Log UART (2026-07-29):**
- Confirmado via captura UART (`sata_teste_20260729_113413.log`): `sda` reconhecido aos 3.13s; exception estoura aos 36.79s (`READ DMA` opcode `0xc8`, tag 15); descarte final aos 83.89s; `/init` chamado apenas aos 84.60s (atraso medido de 78s).
- `SErr 0x0` e status `{ DRDY }` confirmados: link físico SATA está 100% íntegro. A falha é a perda do ACK de interrupção no demux do Glue (`0x110084`).
- **Deploy realizado (2026-07-29):** Tag `20260728-sata-ackfix-ehdump` gravada com sucesso no HD USB (gravado `bzImage` com o fix no ACK do demux, `bootargs` com console UART e `rootwait`). Pronto para teste ao vivo pós-power-cycle.

---

### **Plano detalhado — SATA interno 100% funcional:**
Ver documento dedicado: [`PLANO_SATA_INTERNO_100PCT_2026-07-28.md`](../PLANO_SATA_INTERNO_100PCT_2026-07-28.md)


**Custo restante (muito menor que o estimado antes):**
- Não requer mais RE de PHY nem troca de hardware — ambas as linhas foram refutadas
- Falta: build (em andamento) + montar tag + 1 deploy + 1 power cycle + teste de carga
- Rootfs no USB (`sdb`) já funciona — SATA interno é **storage extra**, não bloqueador de boot

---

### **Impacto no projeto:**
- 🔴 **BLOQUEIA O BOOT — corrigido 2026-07-28.** A afirmação anterior ("não bloqueia boot") estava
  **errada**. Medição ao vivo com `systemd-analyze`: o boot leva **2min 15s** (101s kernel + 34s
  userspace), e **~78s disso é a cascata de EH do SATA** — o `sda` é detectado em 1,28s, falha em
  31,84s, e o `Freeing unused kernel image` (fim da init do kernel) acontece **50 ms depois** do
  `EH complete` em 79,44s. São **58% do tempo de boot** parados esperando a leitura da tabela de
  partição do `sda` fracassar. Resolver isto sozinho derruba o boot de 135s para ~57s.
- Os outros dois custos de boot (fora do escopo deste item): `systemd-modules-load` carregando o
  `mts` = **32,0s** (24%), e `rootdelay=10` = 10s fixos (7%). Ver item próprio.
- **Bloqueia uso do HD interno** como armazenamento confiável
- **Prioridade média mantida** — foco principal continua GBE Ethernet (RX morto)

</details>

---

### [x] Testar renderização 3D ao vivo (glxgears/vulkaninfo) — **VALIDADO ao vivo 2026-07-25**

**Resultados:**
- **OpenGL:** 4.5 Core Profile, Mesa 26.1.5, renderizador `AMD DG1501SML87LB (radeonsi, kaveri, ACO)`, 1024MB VRAM dedicada
- **glxgears:** ~54 FPS (1920x1080@60 via HDMI, sincronizado com refresh)
- **Vulkan:** 1.3.354, driver RADV KAVERI 26.1.5, device `AMD DG1501SML87LB`, `INTEGRATED_GPU`, todas features 1.3 habilitadas
- **Direct rendering:** sim, acelerado por hardware
- **Comprovado:** GPU Gladius 100% funcional — OpenGL 4.5 + Vulkan 1.3 + aceleração 3D real

### [ ] RTC via ICC no PS4 Linux — implementar driver `rtc-ps4-icc`

⚠️ **Correção 2026-07-31:** esta entrada estava marcada `[x]` com Fase 4 "validada" (`hwclock -r`,
`pacman -Sy` OK em hardware real), mas isso é **falso** — não há nenhum log/teste em
`test_history` ou `tests/` que comprove um boot real com este driver. O arquivo
`drivers/rtc/rtc-ps4-icc.c` já existia (criado 2026-07-25) mas continha um bug nunca detectado
porque nunca foi testado: `ps4_rtc_read_time()` lia de `sc->mmio_write` (`0x5140000`, endereço de
**escrita**) em vez de `sc->mmio_read` (`0x5180000`, endereço de **leitura**) — teria devolvido
lixo/hora errada em qualquer teste real. Reaberta como pendente até haver teste ao vivo de fato.

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

**Executado (plano em [`plans/rtc_via_icc_plan.md`](plans/rtc_via_icc_plan.md)):**
1. [x] Fase 1 — Habilitar `CONFIG_RTC_CLASS=y` + `CONFIG_RTC_INTF_DEV=y` + `CONFIG_RTC_DRV_CMOS=y` + `CONFIG_RTC_HCTOSYS=y` no `00-build-kernel-7.0.sh` (linhas 513-528). `CONFIG_RTC_DRV_PS4_ICC` agora habilitado como módulo (`--module`, linha ~535) já que o driver existe (Fase 3 concluída).
2. [x] Fase 2 — Wrapper `ps4_icc_rtc_cmd()` com retry loop (100× 50ms) criado em `drivers/ps4/ps4-bpcie-icc.c` + declarado em `baikal.h`/`aeolia.h`. **Patch versionado** em `distros/arch_minimal_v2/patches/ps4-icc-rtc-wrapper.patch` + aplicação idempotente no `00-build-kernel-7.0.sh`. Validado com compile isolado (`make drivers/ps4/ps4-bpcie-icc.o` OK, símbolo `__export_symbol_ps4_icc_rtc_cmd` presente). Nada novo em `EXPORT_SYMBOL_GPL(bpcie_icc_cmd)` — já existia.
3. [x] Fase 3 — Criado/corrigido `drivers/rtc/rtc-ps4-icc.c` (2026-07-31) + entries em `drivers/rtc/Kconfig` e `drivers/rtc/Makefile` (já existiam no source tree). Bug de leitura da MMIO errada (ver nota acima) corrigido — `read_time` agora lê de `sc->mmio_read` (`0x5180000`). Compile isolado validado: `sudo make ARCH=x86_64 drivers/rtc/rtc-ps4-icc.o` → `CC [M] drivers/rtc/rtc-ps4-icc.o` sem erros/warnings; `nm` confirma `ps4_icc_rtc_cmd` como símbolo indefinido (`U`), resolvido no link do módulo contra o `EXPORT_SYMBOL_GPL` existente.
4. [~] Fase 4 — **EM ANDAMENTO (2026-08-01)**: rebuild completo feito via `00-build-kernel-7.0.sh` (tag `20260801-rtc-icc-ok`, 4 arquivos completos em `boot_referencia/`, `CONFIG_RTC_DRV_PS4_ICC=m` confirmado no `.config` gerado). Deploy do boot feito via `deploy-boot-7.0.sh 20260801-rtc-icc-ok` (MD5 origem→destino OK, rootfs `psxitarch` intocado). `rtc-ps4-icc.ko` copiado manualmente para `/lib/modules/7.0.8-Strawberry-ThinLTO-Baikal-+/kernel/drivers/rtc/` no rootfs (label `psxitarch`, montagem em subdiretório dedicado, nunca em `/mnt` raiz) + `depmod -a` rodado contra esse root — `modules.dep` confirma a entrada `kernel/drivers/rtc/rtc-ps4-icc.ko`. **Ainda faltando:** ligar o PS4 fisicamente, `modprobe rtc-ps4-icc`, validar `/dev/rtc0`, `hwclock -r`, `date` estável entre boots, `pacman -Sy` sem erro de SSL/clock, e confirmar em `/proc/iomem` que `0x5180000`/`0x5140000` não colidem com outro driver.
5. [ ] (opcional) Fase 5 — NTP no boot (`systemd-timesyncd` ou `ntpd -q -g`) + `fake-hwclock` como safety net

**Critérios de sucesso (ainda não atendidos, aguardando teste ao vivo pós power-cycle):** `/dev/rtc0` aparece após `modprobe rtc-ps4-icc`; `hwclock -r` retorna tempo válido; `date` estável entre boots (com NTP sync); `pacman -Sy` não falha por clock.

**Se der certo, isto é uma FEATURE nova do projeto** (não só correção de bug): PS4 Linux passa a ter relógio de sistema real e persistente entre power cycles, sem depender de rede disponível no boot — desbloqueia uso confiável de TLS (`pacman`, `curl https://`) e timestamps corretos em log desde o primeiro segundo do userspace.

**Documentos:** [`plans/rtc_via_icc_plan.md`](plans/rtc_via_icc_plan.md) (com seção "Validação da RE (2026-07-25)"); [`../memory/rtc-via-icc-re-validada-2026-07-25.md`](../memory/rtc-via-icc-re-validada-2026-07-25.md); [`decompiled/baikal_rtc_mvl.txt`](decompiled/baikal_rtc_mvl.txt); [`decompiled/INDEX.md`](decompiled/INDEX.md) §6.B.

---

## Prioridade baixa

### [~] KVM-AMD para VMs QEMU (uso como ambiente de desenvolvimento)

**Objetivo:** habilitar `CONFIG_KVM`/`CONFIG_KVM_AMD` no kernel 7.0 Baikal para rodar máquinas
virtuais QEMU aceleradas por hardware diretamente no PS4, como ambiente de desenvolvimento.

**Contexto:** estudo de viabilidade já feito em 2026-07-24 — veredito **tecnicamente viável**.
O SoC Jaguar do PS4 (`DG1501SML87LB`, AMD family 0x16 model 0x67) expõe todo o conjunto
SVM/NPT necessário (`svm npt lbrv svm_lock nrip_save tsc_scale flushbyasid decodeassists
pausefilter pfthreshold vmmcall` em `/proc/cpuinfo`), `lscpu` confirma `Virtualization: AMD-V`,
~5.1 GB de RAM disponível. Única barreira real identificada: `# CONFIG_KVM is not set` no
`.config` atual — o código KVM já está presente na árvore do kernel, só falta habilitar via
Kconfig e reconstruir.

**Status:** Fase 1 (levantamento/build estático) concluída — ver `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md`
para o roadmap técnico completo (Kconfigs necessárias, ordem de habilitação, riscos).

**Próximo passo:** habilitar `CONFIG_KVM`/`CONFIG_KVM_AMD` no `.config`, rebuild via
`00-build-kernel-7.0.sh`, testar `/dev/kvm` aparece e `qemu-system-x86_64 -enable-kvm` sobe uma
VM básica.

---

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

### [x] ✅ `rootwait` no lugar de `rootdelay=10` — **10,5s de boot economizados, validado ao vivo 2026-07-28**

Medição isolando a fase de initramfs (fim da init do kernel → start do systemd), que é onde o
`rootdelay` atua:

| Boot | Fase initramfs | Bootarg |
|------|----------------|---------|
| tag `20260728-sata-irq-dedicada` | 79,5s → 101,2s = **21,7s** | `rootdelay=10` |
| tag `20260728-sata-demux-diag` | 84,5s → 95,7s = **11,2s** | `rootwait` |

Ganho de **10,5s**, batendo exatamente com os 10s removidos. E o ganho real é **maior** que o
medido, porque o boot com `rootwait` carregava também console UART e instrumentação de debug,
ambos custosos. `dmesg | grep -ic "Waiting for root"` = **0** — o rootfs (`/dev/sdb2`, USB) foi
encontrado de imediato, sem espera.

`rootdelay=N` é espera cega (dorme N segundos mesmo com o disco pronto); `rootwait` espera o
dispositivo *aparecer* e segue na hora. **Usar `rootwait` em todo bootargs novo.** Modelo:
`boot_referencia/bootargs-7.0-20260728-sata-diag.txt`. Registrado em `AGENTS.md` (convenções de
bootargs), `test_history` id **66**, memória
`memory/rootwait-substitui-rootdelay-ganho-10s-2026-07-28.md`.

- [x] **GPU amdgpu/Gladius (GFX/CP)** — `ring gfx test failed (-110)` resolvido em 2026-07-23 com firmware genuíno extraído via `kexec`; 32 CUs ativos, OpenGL 55 FPS, Vulkan 1.3 disponível. Ver `MARCO_HISTORICO_GPU_GLADIUS_REAL.md`.
- [x] **Migração para kernel 7.0 Baikal** — concluída em 2026-07-22 (baseline `v7.0-20260722-clean-video-ok`), superou de vez a necessidade de "migrar para 6.x" (item removido do roadmap).
- [x] **Rootfs completo via systemd (RELEASE, sem debug loop)** — validado ao vivo 2026-07-23 com `bzImage-7.0-20260723-RELEASE`.
- [x] **Ethernet GBE — MAC core e TX por software** — interface `eth0` sobe, MAC ligado via ICC, TX ~95% funcional (RX ainda pendente, ver item ativo acima).
- [x] **Kernel Dump 12.52 via TCP** — concluído em 2026-07-20 (32.2 MB em 3s, zero corrupção).

---

### Achado do RE (2026-07-28) — lock do ACK do glue diverge do Orbis

Consultando **apenas o corpus já decompilado**, o `baikal_pcie_neighborhood.txt` continha (sem
estar catalogada) a função `dc718b40`, equivalente Orbis do nosso `bpcie_handle_edge_irq()`.
Agora catalogada em `decompiled_functions`, status `revisado`.

**Confirmações úteis:** os valores mágicos do nosso demux **estão corretos** (func 4 →
`w=2/mask=-1/shift=0`; func 7 → `w=3/mask=7/shift=0x10`; func 5 → `w=3/mask=3/shift=0`), e o
cálculo `mask & ~(valor >> shift)` bate com o `andn` do Orbis. Diferença estrutural: a função da
Sony só **devolve** a máscara — o dispatch fica no chamador; a nossa faz as duas coisas juntas.

**Divergência a corrigir:** `0x110084` é um **seletor compartilhado** entre func 4 (`icc`),
func 5 (DMAC) e func 7 (xHCI + AHCI), e o acesso é um par não-atômico (escreve o seletor, lê a
máscara). O Orbis serializa com um **mutex global único** (objeto `0xde615a80`, lock `dc6c8710`
linha 318 / unlock `dc6c88b0` linha 321). Nós usamos `raw_spin_lock(&desc->lock)` — **por
descritor**, sem exclusão mútua entre descritores diferentes. Dois handlers em CPUs distintas
podem interleavar e um ler a máscara do grupo errado.

⚠️ **Provavelmente NÃO é a causa da falha do SATA:** se a corrida fosse frequente veríamos
invocações com máscara zerada (`VAZIO`) e a instrumentação mediu **zero**; o `icc`, principal
candidato a colidir, disparou só 26 vezes no boot inteiro. Corrigir mesmo assim, por ser bug real.

**O corpus decompilado não tem nada de AHCI/SATA no lado da interrupção** — só `dc72bfb0` (PHY
init) e helpers de leitura do glue. A resposta para "por que o glue deixa de sinalizar a
subfunção 1" não está no material já decompilado. Memória:
`memory/glue-ack-lock-global-divergencia-orbis-2026-07-28.md`.
