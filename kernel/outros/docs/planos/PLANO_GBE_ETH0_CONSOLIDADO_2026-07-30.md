# Plano Consolidado — GBE Ethernet (`mts.ko` / `eth0`) — PS4 Baikal

> **Substitui todos os planos de GBE anteriores** (arquivados em `consolidado/obsoleto/` em
> 2026-07-30): `PLANO_BAR4_EFUSE_CALIBRACAO_2026-07-23.md`, `PLANO_DUPLEX_PHY_MDIO_2026-07-23.md`,
> `PLANO_FASES_GBE_2026-07-24.md`, `PLANO_FASES_GBE_2026-07-25.md`,
> `PLANO_INVESTIGACAO_RX_TX_2026-07-23.md`, `PLANO_IRQ_REAL_FULLDUPLEX_2026-07-23.md`,
> `PLANO_MAC_EN2_INVESTIGACAO_2026-07-23.md`, `PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md`,
> `PLANO_RX_MTS_2026-07-23.md`. Este arquivo é a **única fonte de próximos passos para o GBE**
> a partir de 2026-07-30. Histórico bruto de RE continua em `consolidado/RE_KERNEL_GBE_ATTACH.md`
> e `consolidado/ICC_GBE_TEST_LOG.md` — não arquivados, ainda usados como referência de dados brutos.

## Estado Atual (2026-07-30) — o que funciona, o que não funciona

| Camada | Estado | Evidência |
|---|---|---|
| Enumeração PCI (`0000:00:14.1`) | ✅ OK | `lspci`, driver `mts` carrega |
| MAC core power-on (ICC `major=4 minor=0x38`) | ✅ OK | `BAR0+0x004` muda de `0` para `0xb19` |
| MAC enable (`0x34`/`0x38`) | ✅ OK | one-shot por power cycle, sequência stop/start validada |
| DMA TX (anel, doorbell) | ✅ ~95% funcional | frames RMU in-band completam, bit `OWN` devolvido |
| DMA RX | ❌ nunca completa | anel sempre `OWN=1`, `MTS_CNT_PKTS=0` |
| MDIO Clause 22 (protocolo) | ✅ corrigido 2026-07-29/30 | bug de polaridade em `mts_mdio_wait_write()` (esperava bit 15 zerar, deveria esperar setar) — fix testado ao vivo, eco limpo agora (`0x1000`) em vez de dado residual |
| MDIO Clause 45 | ⚠️ "sucede" mas retorna zero | `ret=0 val=0x0000` sempre — sem timeout, mas sem dado real |
| PHY (link físico) | ❌ nunca liga | `AN_complete=0`, `link=0`, ping 100% perda, `eth0` sempre `NO-CARRIER` |
| MSI (hardware) | ✅ correto | `lspci -vv`: `Enable+ Count=1/1 Maskable+ Masking=00000000` — não mascarado |
| IMR (software, `BAR0+0x54`) | ✅ testado desmascarado | `irq_mask=0x7d` aplicado ao vivo, `mts_regs` confirma `0x54=0x7d` |
| IRQ real entregue | ❌ nunca | `/proc/interrupts`: `irq_count=0` mesmo com MSI e IMR ambos desmascarados |
| Código de demux do glue (`ps4-bpcie.c`) | ✅ correto para a GBE | `bpcie_assign_irqs(pdev, 1)` — vetor único, não passa por nenhum caso especial de `bpcie_handle_edge_irq` (só func 4/glue e func 7/xHCI têm demux) |

**Conclusão objetiva, com evidência direta (testada ao vivo 2026-07-30, `test_history` id 72):**
o bloqueador **não é software** — não é bug de protocolo MDIO (corrigido, insuficiente sozinho),
não é mascaramento de MSI em hardware, não é IMR mascarando eventos reais, não é bug de demux de
IRQ no glue. **O PHY genuinamente nunca gera nenhuma condição de evento** (nem link change, nem
conclusão de RX) — o MAC/DMA está 100% operacional, mas fala sozinho porque não há PHY do outro
lado respondendo.

## Hipótese Investigada e Fechada — RE completa concluída 2026-07-30

O PHY tem um **domínio de energia separado do MAC** (`SceGbeMtsPhyCtrl` no Orbis, já identificado
por engenharia reversa). O comando ICC que liga o MAC (`major=4, minor=0x38`, confirmado
funcional) **não** liga o PHY. A thread do Orbis que controla o PHY (`gbe_phy_ctrl`, endereço
`dc5a44c0`) foi **completamente decompilada** (11 funções via Ghidra headless, ver Passo 1/2
abaixo): ela só monitora o PHY via MDIO packed reads e dorme esperando eventos — **não há
nenhuma chamada ICC ou SAMU em toda a árvore**. Ou seja, o power-on físico do PHY acontece
**antes** do kernel Orbis assumir, via firmware/bootloader Sony, e não é replicável por nenhum
mecanismo (MDIO, ICC, SAMU, RMU) acessível a um driver Linux. Ver conclusão final no Passo 4.

## Próximos Passos (em ordem de custo/risco crescente)

### Passo 1 — RE completa de `gbe_phy_ctrl` (`dc5a44c0`) e vizinhança (sem hardware, sem risco)

Terminar a decompilação desta função e tudo que ela chama/espera. Objetivo: identificar
exatamente qual bit/evento ela aguarda, e de onde esse bit poderia vir (registrador MMIO, RMU,
ICC, SAMU). Consultar `consolidado/decompiled/INDEX.md` e a tabela `decompiled_functions` do
SQLite antes de pedir nova extração:
```bash
sqlite3 consolidado/ps4_hardware_memory.db \
  "SELECT addr_hex, role, status FROM decompiled_functions WHERE addr_hex='dc5a44c0' OR role LIKE '%phy_ctrl%';"
```

> ✅ **CONCLUÍDO 2026-07-30.** 11 funções extraídas via Ghidra Java headless (Docker). Árvore completa analisada. **Nenhuma chamada ICC ou SAMU encontrada** — o controle do PHY é puramente via MDIO + registradores MMIO. A thread espera eventos externos (bit `0x100` no flag word) e lê o PHY via packed MDIO reads (`0xa2001e`). PHY power-on é feito pelo firmware/bootloader Sony, não replicável via driver Linux puro.

### Passo 2 — Procurar chamadas SAMU relacionadas a GBE/PHY no dump Orbis (sem hardware, sem risco)

Buscar no dump `kmem_dump_1252.bin` por referências cruzadas a `gbe_phy_ctrl` que apontem para
comandos de coprocessador de segurança (padrão já usado em outras análises deste projeto para
RTC/ICC). Se existir uma chamada SAMU dedicada ao power-up do PHY da GBE, ela provavelmente é
**irreplicável em Linux puro** sem a chave/firmware da Sony — isso decidiria a questão de forma
definitiva (fechamento formal, não mais tentativa).

> ✅ **CONCLUÍDO 2026-07-30.** Varredura binária do `kmem_dump_1252.bin`:
> - Cross-refs para `dc5a44c0`: **0** (thread criada via `kthread_create`, não chamada direta)
> - ICC major=5 (SAMU) no range GBE (`dc5aXXXX`): **0 referências**
> - MMIO SAMU mailbox (`0x80000000/0xE0000000`) no range GBE: **0 referências**
> **Conclusão:** GBE/PHY não usa SAMU nem ICC para controle de PHY. PHY power-on é anterior ao kernel (firmware/bootloader Sony).

### Passo 3 — Testar se o RMU consegue "acordar" o PHY via comando dedicado (1 power cycle, baixo risco)

> ⚠️ **PULA:** RE concluída (Passo 1+2) não encontrou sub-comando RMU de PHY power-up.
> Thread `gbe_phy_ctrl` não comanda RMU — só lê MDIO e dorme. Power-up do PHY é pré-kernel.
> RMU já testado com `cmd=0x0000`/`0x800b` — completam DMA mas não ativam PHY.

### Passo 4 — Decisão de continuidade

- ~~**Se o Passo 1/2 revelar uma sequência de bring-up replicável**~~ (refutado: PHY power-on é pré-kernel)
- ~~**Se depender de SAMU/chave proprietária**~~ (refutado: não há chamadas SAMU na árvore)
- **Conclusão final:** O PHY da GBE Baikal é ligado pelo firmware/bootloader Sony ANTES do kernel Orbis assumir. Não há sequência replicável via MDIO, ICC, SAMU ou RMU que o driver Linux possa executar para ligá-lo. **Esta via de investigação está esgotada com os dados disponíveis.** Fechar formalmente em `consolidado/BACKLOG.md`.

## Referências e Dados Brutos (não arquivados, continuam válidos)

- `consolidado/RE_KERNEL_GBE_ATTACH.md` — histórico de RE do attach/probe.
- `consolidado/ICC_GBE_TEST_LOG.md` — log de testes de comandos ICC.
- `consolidado/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md` — marco histórico do bring-up de `eth0`.
- `consolidado/decompiled/INDEX.md` + tabela `decompiled_functions` (SQLite) — catálogo de RE.
- `memory/mdio-clause22-bug-polaridade-corrigido-2026-07-29.md` — fix de polaridade MDIO.
- `memory/gbe-fase2-msi-imr-refutada-2026-07-30.md` — refutação de MSI/IMR (2026-07-30).
- `consolidado/ps4_hardware_memory.db` → `test_history` (ids relevantes: buscar `target_component LIKE '%mts%' OR target_component LIKE '%GBE%' OR target_component LIKE '%PHY%'`).

## Não Repetir (armadilhas já confirmadas, testadas e descartadas)

- Bug de polaridade no protocolo MDIO Clause 22 — **corrigido**, não é a causa raiz sozinha.
- Scan de `phy_addr` 0-31 via Clause 22 — estruturalmente incapaz de diferenciar endereços (as
  funções Orbis originais não têm parâmetro de endereço de PHY); não repetir esperando resultado
  diferente.
- Mascaramento de MSI em hardware análogo ao SATA — testado e refutado para a GBE especificamente.
- IMR (`irq_mask`) mascarando eventos reais — testado desmascarado (`0x7d`), sem efeito.
- Mudança de código em `ps4-bpcie.c`/`bpcie_handle_edge_irq` para a GBE — código já correto,
  GBE usa vetor único sem demux, não é o mesmo padrão do SATA/xHCI.
- "PHY ID Marvell 0x888103a2 confirmado" (2026-07-25) — **falso positivo**, dado residual do
  barramento MDIO (transação nunca completa, bus devolve o último valor latched).
