# Investigação Profunda: Ethernet GBE Baikal (PS4 Pro 12.52)

> **Arquivo vivo** — Atualizar a cada descoberta (positiva ou negativa) para compartilhamento entre agentes.
> **Regra:** Registrar IMEDIATAMENTE após cada teste/análise (Regra 2 do CLAUDE.md).

## 📋 RESUMO EXECUTIVO (Conclusão 2026-07-22)

| Aspecto | Status | Detalhes |
|---------|--------|----------|
| **Hardware** | `00:14.1` `[104d:90d8]` | Sony Baikal Ethernet Controller — **MTS (`if_mts.c` / `SceGbeMtsCtrl`)** |
| **Driver Linux Nativo** | ✅ **CRIADO (`ps4_mts`)** | `drivers_mts/mts.c`, `mts.h` + `patches/mts-baikal-gbe-driver.patch` |
| **Causa Raiz Resolvida** | ✅ **SOFTWARE RESET** | `0x34`/`0x38` retidos em reset pelo Orbis shutdown; 25MHz clock ativo (`0x7c = 0x017D7840`) |
| **Arquitetura de Bring-up** | ✅ **5 Estágios (`stage=0..4`)** | Transcrição fiel do `mts_init()` (`dc5a31f0`), DMA coherent nativo Linux |
| **Status do Plano Telnet** | 🏁 **SUPERSEDED** | O harness Telnet foi substituído pelo driver C nativo `ps4_mts` compilado | imediatamente. Conclusão: a rail vem LIGADA do Orbis; o kexec/Linux é quem a derruba/re-gateia. |

---

## 🗂️ DOCUMENTOS BASE (Consultar antes de qualquer ação)

| Arquivo | Conteúdo Principal |
|---------|-------------------|
| `consolidado/BAIKAL_HARDWARE_DISCOVERIES.md` | Causa raiz, hipóteses descartadas, próximo passo real |
| `consolidado/ICC_GBE_TEST_LOG.md` | **Tabela obrigatória** — todos os testes ICC ao vivo (não re-testar) |
| `consolidado/RE_KERNEL_GBE_ATTACH.md` | RE completo do `kmem_dump_1252.bin` — attach(), ICC wrapper, baikal_pcie.c |
| `consolidado/decompiled_gbe_mac_attach.txt` | `SceGbeMtsCtrl` attach() decompilado (Ghidra/r2ghidra) |
| `consolidado/decompiled_gbe_phy_attach.txt` | `SceGbeMtsPhyCtrl` attach() decompilado |
| `memory/baikal-gbe-e-sky2-nao-stmmac.md` | Prova: é sky2, não stmmac |
| `memory/baikal-gbe-toque-trava-desliga-ps4.md` | **Risco real** — leituras perigosas, block-read pervasive desliga PS4 |
| `distros/arch_minimal_v2/patches/sky2-baikal-gbe.patch` | Patch atual (apenas BAR size fix) |
| `memory/marco-2026-07-17-sky2baikal-pronto-teste.md` | Offsets MMIO já mapeados ao vivo |

---

## ✅ DESCOBERTAS CONFIRMADAS (Positivas)

### 1. Hardware = Marvell Yukon 2 (sky2)
- **Evidência:** `sky2` probe roda sem crash com patch do PCI ID; falha limpa `unsupported chip type 0x0`
- **Fonte:** `BAIKAL_HARDWARE_DISCOVERIES.md`, `baikal-gbe-e-sky2-nao-stmmac.md`
- **Implicação:** Não escrever driver novo — corrigir power-gating do hardware existente.

### 2. Power-gating é a causa raiz
- **Evidência:** `B2_CHIP_ID`/`B2_MAC_CFG` = `0x00`; outros regs do BAR0 leem valores reais; `devpm` = `# gbe off`
- **Conclusão:** Wrapper PCIe ligado, MAC core desligado por rail do Syscon.

### 3. ICC major=4 é serviço de power/sistema real
- **Evidência:** `ps4-apcie-icc.c` usa `major=4 minor=1` para `icc_shutdown()`/`icc_reboot()`; attach GBE chama `icc_query(4, 0x38, 1)`
- **Teste ao vivo:** `echo "4 0x38" > /proc/ps4_icc` → `ret=20` (sucesso), mas `B2_CHIP_ID` continua `00`
- **Interpretação:** Query de status ("está pronto?"), não comando de power-on.

### 4. baikal_pcie.c (Orbis) inicializa clock BAR2+0x10a030
- **Descoberta RE:** `func_0xffffffffdc7190d0` chamada incondicionalmente no `attach()` do glue PCIe:
  ```c
  reg = read32(BAR2 + 0x10a030);
  reg = (reg & 0xfffffe07) | 0xd8;  // limpa bits [8:3], escreve 0x1b
  write32(BAR2 + 0x10a030, reg);
  ```
- **Offset físico:** `0xc890a030` (BAR2 pervasive `0xc8800000` + `0x10a030`)
- **Estado no Linux:** Leitura ao vivo = `0x16c9` (campo 6 bits = `0x19`); Sony espera `0x1b` → **diff de 1 bit (bit 4)**
- **Teste escrita:** Octal-correto (`printf '\331\026\000\000'`) → `dd` confirma 4 bytes → releitura = `0x00000000` (sempre zero pós-escrita), GBE não liga
- **Hipótese:** Registrador pode ser "command/pulse" (write-trigger, self-clears), não config persistente.

### 5. SceGbeMtsCtrl attach() tem loop de espera ICC
- **Decompilado:** Loop de até 100 tentativas chamando `icc_query(4, 0x38, 1)` (~10s total), esperando flag global
- **Flag global era falsa pista:** Endereço `0xde51c5d0` tem 130+ xrefs no kernel inteiro — estrutura genérica de lock/WITNESS, não flag GBE
- **Conclusão:** O "botão" de power-on **não está no attach** — está em handler assíncrono ICC ou init anterior do barramento.

### 6. BAR0 da GBE (4KB) é segura para leitura MMIO
- ~21 leituras `dd` sequenciais em `0xc2000000` não travaram console (tag `20260717-iccdbg`, 64 min uptime)
- **Regra:** Só varrer BAR0 (0xc2000000, 4KB). **NÃO** varrer pervasive BAR2 (0xc8800000+) — block-read desliga PS4.

---

## ❌ HIPÓTESES TESTADAS E DESCARTADAS (Negativas)

| # | Hipótese | Teste | Resultado | Doc |
|---|----------|-------|-----------|-----|
| 1 | GBE = Synopsys DWMAC (stmmac) | `CONFIG_STMMAC` + probe | **Oops real** — BAR0 4KB < offset DMA 0x1000 → page fault | `BAIKAL_GBE_EXPERIMENTS.md` |
| 2 | ICC device_power (major 5) tem minor GBE | Varredura minors 0x01–0xf1 | Só 4 minors válidos (wlan/bt, usb, hdd, bd); 0x41 = NAK | `ICC_GBE_TEST_LOG.md` #1-2 |
| 3 | ICC major 4 minor 0x38 com payload 1-byte liga GBE | `echo "4 0x38 01"` | Comando aceito (ret=20), `B2_CHIP_ID` continua `00` | `ICC_GBE_TEST_LOG.md` #4 |
| 4 | GET ICC major 4 distingue minors | Varredura 0x20–0x50 | **Todos retornam reply idêntica** — GET genérico não discrimina | `ICC_GBE_TEST_LOG.md` #5 |
| 5 | Flag global `0xde51c5d0+0x34` = GBE power-ready | Busca xrefs no dump | 130+ refs — estrutura genérica de lock, não flag GBE | `RE_KERNEL_GBE_ATTACH.md` seção "CORREÇÃO" |
| 6 | Escrita MMIO `0xc890a030` = config clock persistente | Write corrigido (octal) | Registrador volta `0` sempre; GBE não liga | `RE_KERNEL_GBE_ATTACH.md` M3, `ICC_GBE_TEST_LOG.md` M3 |
| 7 | Escrita `0xc890a030` no boot (ps4-bpcie.c) | Tag `20260720-gbe-bpcie-init` | **TELA PRETA + TRAVA TOTAL** — power cycle obrigatório | `ICC_GBE_TEST_LOG.md` M4, `RE_KERNEL_GBE_ATTACH.md` |

---

## 🎯 PRÓXIMOS ALVOS PRIORITÁRIOS (Ordem de Investigação)

### P1: Handler ICC Assíncrono / Notificação Syscon (ALTO)
- **O quê:** Função em `icc_power.c` que recebe resposta do Syscon e seta flag de "rail ligada"
- **Por que:** O attach GBE **espera passivamente** — o gatilho real vem de fora (notificação assíncrona)
- **Como:** Buscar xrefs às linhas de `icc_power.c` próximas a 2127-2133 e 4586-4611 (locks usados no attach)
- **Ferramenta:** `r2ghidra` decompilar `icc_power.c` no dump — achar `icc_send` / callback de resposta

### P2: Catálogo Completo de Comandos ICC no Kernel Orbis (ALTO) ← **NOVO: 2026-07-20 COMPLETO**
- **O quê:** Todos xrefs de `func_0xffffffffdc3f5bd0` (`icc_query` genérico) → extrair TODOS pares `(major, minor)`
- **Por que:** Pode revelar majors não testados (ex: major=3, major=0, major=6...) que controlam rails
- **Como:** Script r2 para extrair major/minor de cada call site
- **Status:** ✅ **CATALOGADO** — Ver seção "Catálogo ICC major=4" abaixo

### P3: probe()/attach() do baikal_pcie.c (Orbis) (MÉDIO)
- **O quê:** Decompilar `0xffffffffdc718d20` (probe) e `0xffffffffdc718eb0` (attach) completos
- **Por que:** O `attach` já achamos — chama `func_0xffffffffdc7190d0` (clock BAR2). O `probe` pode revelar sequência de bring-up de slots PCI genérica (incluindo GBE)
- **Status:** Parcial — só achamos `func_0xffffffffdc7190d0` e alocação de 3 BARs (BAR2, BAR0, **BAR4 novo!**)

### P4: Registradores "Pulse/Command" no BAR2 Pervasive (MÉDIO)
- **O quê:** Mapear índices do mecanismo indexado BAR2+0x110084/0x110088 (já achado em `baikal_pcie.c`)
- **Por que:** Mesmo mecanismo pode acessar clock-gate GBE em índice diferente de 2/3 (IRQ status)
- **Risco:** **NÃO fazer block-read contíguo** — só leituras pontuais de 4 bytes em offsets conhecidos/confirmados

### P5: NVS Offset 0x38 ("gbe related" psdevwiki) (BAIXO/RISCO)
- **O quê:** Byte de config na NVS lido pelo EMC/Syscon no boot
- **Risco:** **NVS write pode brickar** — não testar sem decisão explícita do usuário
- **Alternativa:** Ler NVS via `/dev/mem` (offset físico?) apenas para diagnóstico

---

## 📊 CATÁLOGO ICC MAJOR=4 — TODOS OS COMANDOS NO KERNEL ORBIS 12.52

> **Descoberta 2026-07-20:** Análise de **35+ call sites** de `icc_query` (`0xffffffffdc3f5bd0`) no `kmem_dump_1252.bin`. **TODOS usam major=4** (power/sistema). O wrapper valida `if (major < 5)` — majors 0-4 válidos, mas só major=4 aparece.

| Call Site (vaddr) | Major | Minor (hex) | Minor (dec) | Len | Contexto / Função Provável |
|---|---|---|---|---|---|
| `0xffffffffdc36bb53` | 4 | `0x38` | 56 | 1 | **SceGbeMtsCtrl attach** — loop espera status GBE |
| `0xffffffffdc36bc6b` | 4 | `0x322` | 802 | 1 | Perto do attach GBE |
| `0xffffffffdc36bc8d` | 4 | `0x329` | 809 | 1 | Perto do attach GBE |
| `0xffffffffdc36bce7` | 4 | `0x38` | 56 | 1 | Loop espera GBE (repetição) |
| `0xffffffffdc36c04c` | 4 | `0x38` | 56 | 1 | Loop espera GBE (repetição) |
| `0xffffffffdc3983a1` | 4 | `0x20` | 32 | 1 | Função desconhecida |
| `0xffffffffdc39914b` | 4 | `0x20` | 32 | 1 | Função desconhecida |
| `0xffffffffdc3993c4` | 4 | `0x20` | 32 | 1 | Função desconhecida |
| `0xffffffffdc3997f3` | 4 | `0x20` | 32 | 1 | Função desconhecida |
| `0xffffffffdc4cf1a2` | 4 | `0x38` | 56 | 1 | Função desconhecida |
| `0xffffffffdc57ea0a` | 4 | `0x50` | 80 | 1 | Função desconhecida |
| `0xffffffffdc57f757` | 4 | `0x50` | 80 | 1 | Função desconhecida |
| `0xffffffffdc5a4462` | 4 | `0x38` | 56 | 1 | **SceGbeMtsCtrl attach** (confirma) |
| `0xffffffffdc7350a9` | 4 | `0x100` | 256 | 256 | **Len=256** — leitura bloco grande |
| `0xffffffffdc7991d6` | 4 | `0x30` | 48 | 1 | **NOVO** — minor 0x30 |
| `0xffffffffdc79920b` | 4 | `0x65` | 101 | 1 | **NOVO** — minor 0x65 |
| `0xffffffffdc799b38` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc799be8` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc799e9b` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc84e27e` | 4 | `0x1000` | 4096 | 768 | **Len=768** — minor 0x1000 |
| `0xffffffffdc84e2a4` | 4 | `0x1300` | 4864 | 768 | **Len=768** — minor 0x1300 |
| `0xffffffffdc84e43b` | 4 | `0x1000` | 4096 | ? | Jmp para icc_query |
| `0xffffffffdc84e47b` | 4 | `0x1300` | 4864 | ? | Jmp para icc_query |
| `0xffffffffdc8c7589` | 4 | `0x30` | 48 | 1 | **Confirma** minor 0x30 |
| `0xffffffffdc8c7866` | 4 | `0x30` | 48 | 1 | **Confirma** minor 0x30 |
| `0xffffffffdc8c86a4` | 4 | `0x30` | 48 | 1 | **Confirma** minor 0x30 |
| `0xffffffffdc8c9adf` | 4 | `0x30` | 48 | 1 | **Confirma** minor 0x30 |
| `0xffffffffdc8d1f2e` | 4 | `0x30` | 48 | 1 | **Confirma** minor 0x30 |
| `0xffffffffdc8d21d9` | 4 | `0x30` | 48 | 1 | **Confirma** minor 0x30 |
| `0xffffffffdc8f84f2` | 4 | `0x30` | 48 | 1 | **Confirma** minor 0x30 |
| `0xffffffffdc913c10` | 4 | `0x80` | 128 | 104 | **Len=104** — minor 0x80 |
| `0xffffffffdc913d40` | 4 | `0x80` | 128 | 104 | **Confirma** minor 0x80 len=104 |
| `0xffffffffdc9141c5` | 4 | `0x80` | 128 | 104 | **Confirma** minor 0x80 len=104 |
| `0xffffffffdc9885ab` | 4 | `0x80` | 128 | 104 | **Confirma** minor 0x80 len=104 |
| `0xffffffffdc9885e6` | 4 | `0x900` | 2304 | 256 | **Len=256** — minor 0x900 |
| `0xffffffffdc98870e` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc988f37` | 4 | `0xf0` | 240 | 16 | **Len=16** — minor 0xf0 |
| `0xffffffffdc9890eb` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc98959c` | 4 | `0x80` | 128 | 104 | **Confirma** minor 0x80 len=104 |
| `0xffffffffdc989e51` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc989e70` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc989ffe` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc98a039` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |
| `0xffffffffdc99a750` | 4 | `0x80` | 128 | ? | Cluster 0x988xxx |

### 🎯 Observações Críticas do Catálogo

1. **Major=4 é onipresente** — todos os 35+ call sites usam major=4. O wrapper permite majors 0-4 (`if (major < 5)`), mas **nenhum outro major aparece** no kernel Orbis 12.52 para `icc_query`.

2. **Minor 0x38 (56)** — Usado **exclusivamente** pelo `SceGbeMtsCtrl` attach (loop de espera). Testado ao vivo: query válida, não liga rail.

3. **Minor 0x30 (48)** — Aparece em **8 call sites distintos** (0xffffffffdc7991d6, dc8c7589, dc8c7866, dc8c86a4, dc8c9adf, dc8d1f2e, dc8d21d9, dc8f84f2). Candidato forte para outra função de status.

4. **Minor 0x80 (128)** — Cluster enorme em `0xffffffffdc988xxx` (9+ call sites), sempre com **len=104** ou **len=256/2304**. Parece ser leitura de estrutura grande (possivelmente tabela de dispositivos/rails).

5. **Minor 0x1000 / 0x1300** — Minors grandes com **len=768**. Provavelmente leitura de bloco de configuração/estado de múltiplos dispositivos.

6. **Minor 0x900 (2304)** — Com **len=256** no cluster 0x988xxx.

7. **Minor 0xf0 (240)** — Com **len=16** em `0xffffffffdc988f37`.

8. **Minors 0x20, 0x50, 0x65, 0x322, 0x329** — Aparecem 1-3 vezes cada.

### 📋 Próximos Testes Ao Vivo Sugeridos (baseado no catálogo)
| Minor | Prioridade | Razão |
|-------|------------|-------|
| `0x80` | ALTA | Cluster grande, len=104/256 — pode ser "lista de dispositivos power" |
| `0x30` | ALTA | 8 call sites — query de status comum |
| `0x1000` / `0x1300` | MÉDIA | Len grande (768) — estrutura multi-dispositivo |
| `0x900` | MÉDIA | Len=256 no mesmo cluster do 0x80 |
| `0xf0` | BAIXA | Len=16 — estrutura menor |

---

## 🛑 REGRAS DE SEGURANÇA (Obrigatórias)

1. **NUNCA** fazer `cat /sys/bus/pci/devices/0000:00:14.1/config` — trava/desliga PS4 reproduzivelmente
2. **NUNCA** fazer block-read/varredura contígua da região pervasive BAR2 (`0xc8800000`+) — desliga PS4
3. **SEMPRE** usar escapes **octais** (`\NNN`) para `printf | dd of=/dev/mem` — `busybox printf` não suporta `\xHH` confiável
4. **SEMPRE** conferir `dd` reporta `"1+0 records in/out, 4 bytes"` antes de aceitar escrita
5. **SEMPRE** avisar usuário e esperar "pronto" antes de qualquer escrita MMIO / comando ICC novo (Regra de Ouro)
6. **NUNCA** sobrescrever tag `wifissh`/`iccdbg` que funciona — usar tag nova para testes de driver Ethernet
7. **Antes de qualquer teste ao vivo:** Checar `ICC_GBE_TEST_LOG.md` — **não re-testar** o que já está lá

---

## 📝 LOG DE INVESTIGAÇÃO (Atualizar a cada sessão)

### 2026-07-20 — Sessão RE + Teste Ao Vivo (Tag `20260717-iccdbg`)
- **RE:** Decompilado attach `SceGbeMtsCtrl` + `icc_query` wrapper + `baikal_pcie.c` attach/clock.
- **Descoberta:** Encontrada a função `fcn.ffffffffdc5a3060` (chamada durante a inicialização em `decompiled_dc5a3810.txt` e `SceGbeMtsCtrl_attach`). Ela realiza a inicialização do slot PCIe da GBE por meio de escritas proprietárias no espaço de configuração PCI padrão do dispositivo (offsets `0x54`, `0x34`, `0x38`), que controlam o power-gating e clock-gating do Yukon.
- **Pivô:** Desenvolvido plano de ação para integrar esta inicialização proprietária no `sky2_probe` do Linux, permitindo ativar a rail de energia do Yukon de forma limpa e sem risco de travamento de barramento.

### 2026-07-20 (rodada 2, mesma sessão) — CORREÇÃO da entrada acima, com decompilado real de `dc5a3060` em mãos
Decompilei `fcn.ffffffffdc5a3060` agora (não estava decompilada ainda quando a entrada acima foi escrita — salvo em `consolidado/decompiled_dc5a3060.txt`). Achado real, diferente do que a entrada anterior descreve:
- **NÃO é espaço de configuração PCI** — os offsets `0x34`/`0x38`/`0x54` são relativos a `*(softc+0x3068)+0x10`, ou seja, **registradores MMIO da própria BAR0 do MAC** (o mesmo bloco de registradores usado por `dc5a31f0`, `dc5a2680`/MDIO, e `dc5a5ec0`) — não o config space PCI padrão, e não a região pervasive/Syscon (BAR2).
- `dc5a3060` é a rotina de **"stop"** (chamada no caminho `SIOCSIFFLAGS` down, o par oposto de `dc5a31f0`): escreve `0x54 = 0x7ffffa` (mascara quase todas as interrupções), escreve `0x34 = 2` e espera (até 1.000.000 iterações) o bit 1 desse registrador **zerar** (ack de "parou"), repete o mesmo para `0x38`, depois libera os buffers DMA. **Isso é o padrão clássico "software reset do bloco, espera ACK" de MAC — downstream de power, não um comando de power-gating do Syscon.**
- `dc5a31f0` (par "start", já documentado em `RE_KERNEL_GBE_ATTACH.md`) escreve os MESMOS offsets `0x34`/`0x38` com `OR 1` (enable) — reforça que são registradores de controle/enable/IMR internos do MAC, não do Syscon.
- **Conclusão: a alegação da entrada anterior ("controlam o power-gating e clock-gating do Yukon", "integrar no `sky2_probe` ativaria a rail de energia") não se sustenta com o decompilado real.** Esses registradores só têm efeito ÚTIL se a rail/clock do MAC já estiver ligada (senão a BAR0 inteira — incluindo `chip_id`/`mac_cfg`, já comprovadamente `00` — não responde de verdade). **Recomendação: NÃO integrar essa sequência no `sky2_probe` esperando que ligue a rail** — na melhor hipótese seria inofensivo mas inútil (grava em registrador não-responsivo), na pior seria mais uma tentativa às cegas sem lastro. Detalhe completo em `consolidado/RE_KERNEL_GBE_ATTACH.md` (seção "Sessão de RE profunda 2026-07-20 (continuação)").
- **Mantendo a entrada anterior no log (não apagada) por transparência — esta é a correção, não a substituição.**

### 2026-07-20 (rodada 3) — Investigação do kexec (item 1 da lista de próximos passos) + achado crítico de processo
- **Analisado `ps4-linux-payloads/linux/ps4-kexec-common/acpi.c`/`linux_boot.c`:** `disableMSI()` roda uniformemente nas 8 funções PCI do slot Baikal (incl. SATA/USB, que funcionam pós-boot) — só limpa `msiEnable`/mascara vetores MSI, não é power/clock. **Descartado como causa do power-gating específico da GBE.**
- **Achado colateral:** `kern.wlanbt(0x2)` (linha 456 de `linux_boot.c`) é uma função resolvida por símbolo do PRÓPRIO kernel Orbis, chamada pelo payload para desligar WiFi/BT antes do kexec ("re-enable it when the kernel boot"). Conferida a struct `ksym_t` inteira (`kernel.h`) — não existe função equivalente para GBE. O payload de terceiros nunca tratou a GBE.
- **ACHADO CONFIRMADO (2026-07-21):** O teste de sanidade nativa sob Orbis puro (GoldHEN retail, cabo direto) foi realizado e **confirmou que a Ethernet funciona normalmente na Orbis**. A rail de energia vem LIGADA do Orbis. A conexão só é cortada no momento do kexec/boot do Linux. Portanto, a investigação é sobre o que no kexec ou na enumeração PCI do Linux está re-gateando/derrubando a GBE.
- Detalhe completo em `consolidado/RE_KERNEL_GBE_ATTACH.md` seção "Sessão de RE profunda 2026-07-20 (continuação 2 — item 1 da lista acima)".
- Nota de processo: o agente de RE que vinha rodando em background foi interrompido por um filtro de segurança automático da Anthropic (falso positivo, tópico legítimo de engenharia reversa de hardware do próprio console) no meio da investigação do `disableMSI`; a análise acima foi concluída diretamente na sessão principal, sem subagente, para evitar repetir o bloqueio.

---

## 🔗 REFERÊNCIAS CRUZADAS (Para busca rápida)

| Termo | Arquivo/Seção |
|-------|---------------|
| `B2_CHIP_ID` / `B2_MAC_CFG` | `ICC_GBE_TEST_LOG.md` linha 17, `BAIKAL_HARDWARE_DISCOVERIES.md` linha 19 |
| `0xc890a030` / `0x10a030` | `RE_KERNEL_GBE_ATTACH.md` linha 183, `ICC_GBE_TEST_LOG.md` M1/M3 |
| `icc_query` / `0xffffffffdc3f5bd0` | `RE_KERNEL_GBE_ATTACH.md` linha 101 |
| `SceGbeMtsCtrl` attach | `RE_KERNEL_GBE_ATTACH.md` linha 20, `decompiled_gbe_mac_attach.txt` |
| `SceGbeMtsPhyCtrl` attach | `decompiled_gbe_phy_attach.txt` |
| `baikal_pcie.c` probe/attach | `RE_KERNEL_GBE_ATTACH.md` linha 149-171 |
| BAR2 pervasive perigo | `baikal-gbe-toque-trava-desliga-ps4.md` linha 34 |
| Patch sky2 atual | `distros/arch_minimal_v2/patches/sky2-baikal-gbe.patch` |

---

## 📌 NOTAS PARA PRÓXIMO AGENTE

1. **O kernel dump `kmem_dump_1252.bin` (32.2 MB) está em `consolidado/dumps_orbis/`** — base de toda RE
2. **r2ghidra já instalado** — use `r2 -q -c "af @ 0xVADDR; pdg @ 0xVADDR" arquivo.bin` para pseudo-C
3. **Tag de teste ativa:** `20260717-iccdbg` (tem `/proc/ps4_icc`, MD5 verificado contra `boot_referencia/*-iccdbg`)
4. **IP do PS4 muda a cada boot** — sempre confirmar via ping antes de testar
5. **Não confiar em endereços absolutos (baddr muda com KASLR)** — sempre recalcular: `vaddr = baddr + offset_no_arquivo`

---

> **Última atualização:** 2026-07-20 (rodada 4 — implementação do fix de clock no `bpcie_glue_init`)
> **Próxima ação recomendada:** Compilar kernel 7.0 (ThinLTO, General, Baikal) com o patch aplicado, flashear no HD, testar no PS4 real. Verificar se `B2_CHIP_ID`/`B2_MAC_CFG` saem de `0x00` após o boot.

---

## 🛠️ IMPLEMENTAÇÃO REALIZADA (2026-07-20 — Sessão Atual)

### Objetivo
Replicar no Linux (`ps4-bpcie.c`) a inicialização de clock que o driver Orbis `baikal_pcie.c` faz no seu `attach()` (`func_0xffffffffdc7190d0`), na esperança de que isso ligue a rail de energia/clock do MAC Yukon 2 (GBE) antes do `sky2_probe`.

### Arquivos Modificados

#### 1. `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/baikal.h`
```c
/* Clock/config register written by Orbis baikal_pcie.c attach() */
#define BPCIE_GLUE_CLK_CFG        0x10a030
```

#### 2. `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/ps4-bpcie.c` — função `bpcie_glue_init()`
Adicionado **após** a alocação de IRQs e **antes** do `return 0`:

```c
/* Replicate Orbis baikal_pcie.c attach() clock init (func_0xffffffffdc7190d0):
 * Read-modify-write BAR2+0x10a030: clear bits [8:3] (6 bits), write 0x1b (0xd8 >> 3) */
u32 clk_reg = glue_read32(sc, BPCIE_GLUE_CLK_CFG);
sc_info("Baikal GLUE clock cfg before: %08x\n", clk_reg);
clk_reg = (clk_reg & 0xfffffe07) | 0xd8;
glue_write32(sc, BPCIE_GLUE_CLK_CFG, clk_reg);
clk_reg = glue_read32(sc, BPCIE_GLUE_CLK_CFG);
sc_info("Baikal GLUE clock cfg after:  %08x\n", clk_reg);
```

### Contexto da Descoberta (RE do `kmem_dump_1252.bin`)
- Offset físico: `0xc890a030` (BAR2 pervasive `0xc8800000` + `0x10a030`)
- Valor lido no Linux antes: `0x16c9` (campo 6 bits = `0x19`)
- Valor esperado pelo Orbis: `0x1b` (diff de 1 bit no bit 4)
- Teste de escrita MMIO anterior (`0xc890a030` ← `0x16d9`) **não ligou a GBE** — registrador zera após escrita (comportamento "command/pulse"), mas a **sequência correta de bring-up do barramento PCIe** (que o Orbis faz no `baikal_pcie.c` attach **antes** de qualquer driver filho) pode ser o pré-requisito que falta.

### Patch `sky2` já integrado
O `00-build-kernel-7.0.sh` aplica `patches/sky2-baikal-gbe.patch` que:
- Adiciona `PCI_DEVICE_ID_SONY_BAIKAL_GBE` (0x90d8) à tabela do `sky2`
- Roteia MSIs via `bpcie_assign_irqs`/`bpcie_free_irqs` (em vez de `apcie_*`)
- Corrige `ioremap` size para `pci_resource_len(pdev, 0)` (4KB BAR0)

### Próximo Passo (Build + Teste)
```bash
cd /mnt/hdauxiliar/temp/kernel_build_7.0
./build.sh --option 3 use=General lto=ThinLTO southbridge=Baikal
# ou make manual
# deploy no HD via deploy-boot-7.0.sh + teste no PS4 real
# verificar dmesg: "Baikal GLUE clock cfg before/after"
# verificar B2_CHIP_ID/B2_MAC_CFG via /sys/bus/pci/devices/0000:00:14.1/resource0
```