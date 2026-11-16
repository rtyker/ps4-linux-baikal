# Plano de Desenvolvimento — Ethernet GBE Baikal (00:14.1) / Driver MTS

> **Dispositivo:** Sony Baikal Gigabit Ethernet | **PCI:** 104d:90d8 (00:14.1)
> **Driver atual:** `mts.ko` (em `kernel/drivers_mts/mts.c`, `kernel/drivers_mts/mts.h`)
> **Status:** MAC ligado via ICC, TX ~95% funcional, **RX BLOQUEADO — PHY nunca sai de power-down**

---

## 1. Contexto e Estado Atual

### O que FUNCIONA
- ✅ Probe PCI: device `104d:90d8` detectado
- ✅ ICC power-on: MAC core ligado (`BAR0+0x004 = 0xB19`)
- ✅ MAC address lido da SPM (`2c:cc:44:3f:69:5f`)
- ✅ Anéis TX/RX alocados, doorbell TX corrigido
- ✅ TX por software: ~95% pacotes saem (ping OUT funciona se forçar ARP)
- ✅ IRQ/MSI: alocada, handler registrado (`xhci_aeolia[0000:00:14.1]`)

### O que NÃO FUNCIONA (Bloqueador)
- ❌ **PHY nunca responde a MDIO** — Clause 45 (MMD1/MMD7) e Clause 22 (BMCR, scan 0-31) retornam 0/timeout
- ❌ **RX morto**: `MTS_CNT_PKTS=0`, ping 100% perda
- ❌ **Link nunca sobe**: `eth0` fica `NO-CARRIER`

### Investigação Encerrada (2026-07-30)
> **Conclusão formal:** O power-on físico do PHY é feito pelo **firmware/bootloader Sony ANTES do kernel Orbis assumir**. Não há sequência replicável via MDIO, ICC, SAMU ou RMU que um driver Linux possa executar.
>
> **Evidência:** RE completa da thread `gbe_phy_ctrl` (`dc5a44c0`) — 11 funções extraídas via Ghidra, **zero chamadas ICC/SAMU**, zero cross-refs. O PHY é ligado pelo firmware.

---

## 2. Documentação Existente (em `outros/rea/ethernet/`)

| Arquivo | Conteúdo |
|---------|----------|
| `docs/README.md` | Documentação consolidada do driver MTS |
| `docs/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` | Plano completo (histórico + encerramento) |
| `docs/RE_KERNEL_GBE_ATTACH.md` | RE do attach do kernel Orbis |
| `docs/ICC_GBE_TEST_LOG.md` | Logs de testes ICC ao vivo |
| `docs/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md` | Marco: eth0 com MAC real |
| `decompiled/` | 20+ funções decompiladas do `if_mts.c` Orbis |
| `scans/` | Varreduras BAR0, Glue, MDIO, PCI config |
| `harness/` | Scripts Python de teste ao vivo (MDIO, MAC enable, PCI cmd) |

---

## 3. Opções Futuras (Se Reabrir Investigação)

### Opção A: Firmware/Dump de SAMU (Requer fonte externa)
- Obter firmware do PHY Baikal (Marvell 88E1512/88E1340 ou similar)
- Dump da RAM do SAMU (Security and Management Unit)
- Documentação Marvell/Yukon para PHY Baikal

### Opção B: Hardware Mod (Risco Alto)
- Soldar fios no PHY para forçar power-on via GPIO
- Injetar clock/reset externo no PHY
- **Não recomendado** — risco de brick

### Opção C: Aceitar Limitação e Usar WiFi
- WiFi MT7668 já funcional (built-in no kernel)
- USB-Ethernet dongle como fallback
- Documentar limitação permanente

---

## 4. Melhorias no Driver Atual (MTS) — Mesmo Sem RX

Mesmo sem PHY, o driver pode ser melhorado para quando/ se houver solução:

### Pendentes no `kernel/drivers_mts/mts.c`
- [ ] **Cleanup MSI warning**: `rmmod mts` gera `WARNING: kernel/irq/msi.c:294` — corrigir `msi_device_data_release`
- [ ] **Power management**: `.suspend`/`.resume` para salvar/restaurar contexto MAC
- [ ] **ETHTOOL ops**: `get_link_ksettings`, `get_drvinfo`, `get_regs_len`, `get_regs`
- [ ] **Statistics**: contadores RX/TX/erros via `ndo_get_stats64`
- [ ] **VLAN offload**: `ndo_vlan_rx_add_vid` / `ndo_vlan_rx_kill_vid`
- [ ] **Checksum offload**: `NETIF_F_HW_CSUM` / `NETIF_F_IP_CSUM`

### Pendentes no Build
- [ ] Decidir estrutura fonte: `patch` autoritativo vs `drivers_mts/` como fonte única (ver BACKLOG)
- [ ] `CONFIG_MTS_GBE=m` já configurado — OK

---

## 5. Testes de Validação (Para Quando Houver PHY)

```bash
# Básicos
ip link set eth0 up
ethtool eth0          # Link detected: yes, Speed: 1000Mbps
ethtool -i eth0       # driver: mts

# MDIO
ethtool -m eth0       # Module EEPROM (se SFP)
mdio-tool read eth0 0x1e 0x0  # Clause 45

# Throughput
iperf3 -c 192.168.0.1 -t 30  # TX
iperf3 -s                    # RX (precisa PHY)

# Stress
ping -f -s 1472 192.168.0.1  # MTU 1500
```

---

## 6. Referências

- `outros/rea/ethernet/docs/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` — Plano completo com fases 1-4
- `outros/rea/ethernet/docs/RE_KERNEL_GBE_ATTACH.md` — RE do attach Orbis
- `outros/rea/ethernet/decompiled/` — Funções `dc5a0070` (mtsc_pci_attach) a `dc5a44c0` (gbe_phy_ctrl)
- `outros/rea/ethernet/harness/` — Scripts de teste ao vivo
- `kernel/drivers_mts/mts.c` — Driver Linux atual
- `kernel/patches/mts-baikal-gbe-driver.patch` — Patch autoritativo

---

## 7. Decisão Pendente (Do BACKLOG)

> **Estrutura da fonte do driver MTS** (`drivers_mts/mts.c` × patch):
> - Hoje: patch `kernel/patches/mts-baikal-gbe-driver.patch` = autoritativo; `kernel/drivers_mts/` = superfície de edição
> - Build copia `drivers_mts/` por cima do patch + falha alto se divergirem
> - **Decisão necessária**: Manter assim OU reduzir patch a `Kconfig`/`Makefile` e deixar `drivers_mts/` como fonte única real
> - Impacto: ~3.200 linhas duplicadas eliminadas, mas desafia regra "toda alteração via patch" do AGENTS.md

---

## 8. Próximo Passo Realista

> **Não investir mais tempo no PHY** sem fonte de dados nova.
>
> **Foco imediato:**
> 1. Corrigir warning MSI no `rmmod` (baixo risco, código conhecido)
> 2. Implementar ethtool ops básicos
> 3. Documentar limitação permanente no README do driver
> 4. Usar WiFi/USB-Ethernet para necessidades de rede cabeada
>
> **Reabrir apenas se:** vazamento de firmware Sony, dump SAMU, ou documentação Marvell Baikal PHY aparecer.