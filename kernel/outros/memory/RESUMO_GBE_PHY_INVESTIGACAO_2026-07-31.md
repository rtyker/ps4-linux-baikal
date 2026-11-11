# Resumo Completo — Investigação GBE PHY (2026-07-23 a 2026-07-31)

## Objetivo
Fazer o PHY da GBE Baikal ligar/linkar no Linux (kexec) — hoje `eth0` sobe com MAC real, DMA TX funciona, mas PHY mudo (MDIO timeout/zeros, link down, IRQ=0).

---

## O que foi testado e CONFIRMADO (funciona)

| Camada | Status | Evidência |
|--------|--------|-----------|
| PCI enumeração (0000:00:14.1) | ✅ | `lspci`, driver `mts` carrega |
| MAC core power-on (ICC 4/0x38) | ✅ | `BAR0+0x004`: 0 → 0xb19 |
| MAC enable (BAR0+0x34/0x38) | ✅ | one-shot por power cycle, stop/start validado |
| DMA TX (RMU frames) | ✅ ~95% | Frames 34B magic `0xfa42` completam, bit `OWN` devolvido |
| MDIO Clause 22 (protocolo) | ✅ corrigido | Bug polaridade fixado 2026-07-29/30, eco limpo `0x1000` |
| MSI hardware | ✅ | `Enable+ Count=1/1 Maskable+ Masking=00000000` |
| IMR software | ✅ | `irq_mask=0x7d` aplicado, `mts_regs` confirma |
| Glue block reset | ✅ | `0x142020=0x06040400` (bits 0/4 limpos), hold/pulse=0 — **não em reset** |
| SATA interno | ✅ 2026-07-30 | Polling timer 1ms, `ata1.00: UDMA/100`, `dd`/`fdisk` OK |

---

## O que foi testado e REFUTADO (não é a causa)

| Hipótese | Teste | Resultado |
|----------|-------|-----------|
| GBE block em reset no glue | 7+ boots, `0x142020`, `0x180020`, `0x180074` | **Não** — idêntico a SATA/USB/xHCI |
| Syscon rail via devmem | Syscon = chip `A06-COL2`, só ICC SPI | **N/A** — sem MMIO |
| ICC major=5 device_power | Todos minors (wlan/bt/usb/hdd/bd) | **NAK** — GBE não está lá |
| Clock config `0xc890a030` (M3) | `devmem2` write `0x16d9` | **Falhou** — registrador self-clearing, volta a 0 |
| RMU PHY power-up | RE completa `gbe_phy_ctrl`: zero RMU | **Não existe** |
| MSI mascarado (como AHCI) | `lspci -vv`: `Masking=00000000` | **Não mascarado** |
| IMR mascarando IRQ | `0x54=0x7d` aplicado ao vivo | **Sem efeito** — `irq_count=0` |
| PHY ID Marvell 0x888103a2 | Reteste mesmo dia: Reg[02] 0x8881→0x0000 | **Falso positivo** — dado residual MDIO |

---

## Conclusão da RE (2026-07-30/31)

| Descoberta | Evidência |
|------------|-----------|
| **PHY power-on é pré-kernel** | Firmware/bootloader Sony liga PHY ANTES do kernel Orbis |
| **Thread `gbe_phy_ctrl` só monitora** | 11 funções decompiladas: zero ICC/SAMU/RMU, só MDIO reads + sleep |
| **ICC 4/0x38 só liga MAC core** | `BAR0+0x004` muda, mas ChipID continua `00 00` |
| **ICC device_power (major=5) não tem GBE** | 7 funções decompiladas: dispatcher só trata types 0/1 |
| **SAMU não envolvido** | Cross-ref dump: 0 referências no range GBE |

---

## O que NÃO foi testado (e por que é difícil)

| Ideia | Bloqueador |
|-------|------------|
| Capturar Orbis quiesce/shutdown | UART censurado no Orbis (bytes `0x20`), só vemos Linux pós-kexec |
| Ver se Orbis desliga PHY no quiesce | Sem visibilidade do Orbis |
| Sequência completa Orbis no Linux | Requer replicar attach+up+RMU handshake+MDIO init — complexo, sem garantia |
| Hardware probe (oscilloscópio no rail Syscon GBE) | Requer acesso físico + equipamento |

---

## Baselines oficiais (NUNCA sobrescrever)

| Tag | Descrição | Deploy |
|-----|-----------|--------|
| `20260730-sata-reverted` | Melhor versão até 07-30: boot completo, SSH WiFi OK, eth0 MAC real, SATA funcional | `deploy-boot-7.0.sh 20260730-sata-reverted` |
| `20260730-sata-polling-fase-ab` | **MAIS RECENTE/RECOMENDADO**: + SATA interno 100% funcional (polling 1ms) | `deploy-boot-7.0.sh 20260730-sata-polling-fase-ab` |
| `20260730-s5-poweroff-fix` | ICC shutdown framing corrigido + pré-sync major=4 minor=4 — **PRONTO, NÃO TESTADO** | `deploy-boot-7.0.sh 20260730-s5-poweroff-fix` |

---

## Próximos passos viáveis (ordem de esforço)

| # | Ação | Esforço | O que responde |
|---|------|---------|----------------|
| 1 | **Testar S5 poweroff fix** | 1 deploy + 1 boot | Se ICC shutdown completo funciona (major=4 minor=4 + minor=1) |
| 2 | **Declarar GBE PHY "bloqueado sem firmware Sony"** no `BACKLOG.md` | 0 | Encerra via formalmente, foca no que funciona |
| 3 | Testar sequência completa Orbis no Linux (script SSH) | ~1h | Se attach+up+RMU+MDIO completo liga PHY |
| 4 | RE estática no dump: procurar `SceGbeMtsPhyCtrl` power-down no quiesce | ~2h | Se Orbis desliga PHY no quiesce |
| 5 | Hardware probe rail Syscon GBE | Acesso físico | Se rail físico está off após kexec |

---

## Decisão recomendada

**Testar #1 (S5 poweroff fix)** — é o único "grande teste" pendente com build pronto, responde sobre protocolo ICC de shutdown, e pode revelar se a sequência Orbis de power-off é replicável.

**Ou declarar #2** — GBE PHY está esgotado com dados atuais. SATA, S5, GPU, WiFi, vídeo HDMI, áudio, SSH, desktop — tudo isso funciona. O único bloqueador restante é o link físico da Ethernet cabeada, que requer firmware Sony ou documentação Baikal PHY que não temos.

---

## Arquivos de referência

- `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` — plano único, conclusão final no Passo 4
- `consolidado/decompiled/INDEX.md` — catálogo RE (seções 1-4.B)
- `memory/sessao-ghidra-java-passo1-2026-07-30.md` — Passo 1/2 (gbe_phy_ctrl + SAMU cross-ref)
- `memory/sessao-icc-device-power-2026-07-31.md` — ICC device_power (major=5) completo
- `consolidado/ps4_hardware_memory.db` — SQLite com todas funções + test_history
- `memory/ESTADO_SESSAO_2026-07-30_FINAL.md` — estado consolidado fim de 07-30