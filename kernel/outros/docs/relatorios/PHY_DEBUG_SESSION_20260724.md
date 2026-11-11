# PHY Debug Session - 2026-07-24 (Updated)

## Summary
Multiple breakthroughs achieved: clock config write works, hold_val=0x10 makes MDIO respond, 0x200=0 write was killing MAC enable. TX packets now queued (20), Link UP detected, but PHY still doesn't auto-negotiate or pass traffic.

## Test History

### Test 1: Original hold/pulse (released at end of calibration)
- hold_val=1, no clock config, 0x200=0 written
- Result: PHY dead, MDIO timeout -110

### Test 2: Hold kept asserted (never released)
- Same as test 1 but hold stays 1
- Result: PHY dead, BAR0 registers zeroed after test

### Test 3: SATA-pattern (pulse/hold/pulse=0 -> calib -> release hold -> poll)
- Same as test 1 but release at end
- Result: PHY still dead, MDIO timeout -110

### Test 4: Clock config + hold_val=0x10 + 0x200=0 restored (CURRENT)
- Added Orbis clock config write (0x10a030 = (reg & 0xfffffe07) | 0xd8)
- Added hold_val module param (default 1, test with 0x10)
- Removed 0x200=0 write from calibration
- MAC enable before calibration (old order), with re-enable after
- **Result: PHY responds to Clause 45 (ret=0), Link UP: 1000 Mbps Half duplex, TX queued (20 packets), MAC registers alive**

## Key Findings

### 1. Clock Config (0x10A030) Works
- Before write: `0x000016c9`
- After write: `0x000016d9` (bit 4 set)
- Value persists across module reloads — NOT self-clearing as previously thought
- Field [8:3] = 0x1b as expected from Orbis decompilation

### 2. hold_val=0x10 (bit 4) Enables MDIO Response
- With hold_val=0x10: Clause 45 MDIO reads return `0x0000` (ret=0) — first time MDIO succeeds!
- With hold_val=1: Clause 45 MDIO still returns timeout (-110) even with clock config
- Clause 22 still times out for phy_addr 0-15 in both cases
- This confirms GBE hold/pulse uses bit 4, NOT bit 0 like SATA

### 3. 0x200=0 Write Was Killing MAC Enable
- Writing 0 to BAR0+0x200 during calibration permanently prevents MAC enable (0x38 stays 0)
- Direct `/dev/mem` write to 0x38 also fails after 0x200=0
- Removing the 0x200=0 write restores MAC enable and register response
- 0x34 reads back as 1, 0x50 shows 0x10a0/0x1020, 0x70 shows 0x10040

### 4. 0x200=1 Write Changes Register State
- `0x200=1` readback = 1 (write succeeds)
- 0x50 changes: from 0x1000 → 0x10a0 (adds bits 5,7)
- 0x70 changes: from 0x00000000 → 0x00010040 (adds bits 6,16)
- 0x04 changes: from 0x80003b74 (link DOWN) → 0x00000b19 (link UP)

### 5. Current BAR0 Register State (Working)
| Offset | Value | Meaning |
|--------|-------|---------|
| 0x00 | 0x000081c0 | MAC control register |
| 0x04 | 0x00000b19 | Link UP (bit 0), 1000Mbps (bits 3:2=10), Half duplex (bit 6=0) |
| 0x34 | 0x00000001 | MAC_EN1 written, reads 1 (previously 0) |
| 0x38 | 0x00000000 | MAC_EN2 — still 0, read-only status |
| 0x50 | 0x000010a0 | Status reg — bit 12 set |
| 0x70 | 0x00010040 | Status reg — bits 6,16 set |
| 0x7c | 0x017d7840 | 25,000,000 (timer value from calibration) |

## Current Issues
1. **PHY not fully alive** — Clause 45 reads all registers as 0x0000 (including ID regs), real auto-negotiation never happens
2. **Link is forced, not real** — "1000 Mbps Half duplex" is invalid for 1000BASE-T, indicates no real link partner
3. **TX software-but-not-hardware** — 20 packets queued but hardware counters (MTS_CNT_PKTS) stay 0
4. **RX completely dead** — 0 packets received, host ARP shows (incomplete) for 192.168.0.2

## Next Steps
1. Verify TX doorbell register write and tx_idx advance
2. Try forcing full duplex (bit 6=1) in calibration 0x04 write
3. Investigate 0x7c timer value (25MHz) — should it be written before MAC enable?
4. RE Orbis dc5a31f0 MAC init for any missing register writes after calibration
5. Consider adding IMR write before MAC enable (Orbis sets 0x54 before 0x34/0x38)

## Files Modified (this session)
- `drivers_mts/mts.c`:
  - Added 0x10A030 clock config write before hold/pulse
  - Added hold_val module param (default 0x1)
  - hold/pulse uses hold_val instead of hardcoded 1
  - **CRITICAL:** REMOVED 0x200=0 write from calibration
  - MAC enable ordering: enable before calibration, re-enable after
  - Added `mts_program_rings` call after calibration (restore DMA regs)
- `scripts/deploy_mts.sh`: Complete rewrite from telnet to SSH (sshpass)
- `scripts/build_mts_module.sh`: Unchanged

## Rebuild Command
```bash
sudo /mnt/t/downloads/PS4/linux_in_ps4/scripts/build_mts_module.sh
```

## Deploy Command
```bash
sshpass -p ps4 scp drivers_mts/build/mts.ko root@192.168.6.128:/tmp/mts.ko
sshpass -p ps4 ssh root@192.168.6.128 "rmmod mts 2>/dev/null; insmod /tmp/mts.ko stage=4 hold_val=0x10"
```

---

# Sessão 2026-07-24/25 — Correção do `mts_mac_stop()` e Descobertas

## Test 5: MAC enable morre mesmo sem calibração
- Testado com `enable_phy_calib=0` (calibração completamente pulada)
- **Resultado:** MAC enable (0x38=8) aparece só no primeiro write e desaparece no segundo — mesmo sem nada entre os dois writes
- **Conclusão:** `mts_set()` (read-modify-write) escreve `0x09` em vez de `0x01` no re-enable — hardware rejeita
- **Fix:** Usar `mts_write()` direto (sem RMW) e **nunca re-escrever** MAC enable

## Test 6: MAC enable morre após múltiplos rmmod/insmod
- Após ~4 ciclos rmmod/insmod, MAC enable (0x38) para de responder completamente — mesmo no primeiro write
- **Causa raiz:** `mts_mac_stop()` usava `mts_clear(mp, MTS_MAC_EN1/2, BIT(0))` — escrevia 0 no bit 0
- O Orbis `dc5a3060` escreve **2** (bit 1 = soft-reset) e espera o hardware limpar o bit (ACK)
- Escrever 0 corrompe o estado de enable permanentemente até power cycle

## Fixes aplicados (drivers_mts/mts.c)
1. **`mts_mac_stop()` reescrito** — agora segue fielmente `dc5a3060`:
   - `0x54 = 0x7ffffa` (mascara IRQs)
   - `0x34 = 2`, espera bit 1 zerar (soft-reset, poll até 1s)
   - `0x38 = 2`, espera bit 1 zerar
   - `mts_tx_drain_force()` libera buffers TX/RX
   - `0x1c8 &= ~0x440`
2. **`mts_mac_enable()` simplificado** — `mts_write()` direto (sem RMW), sem re-enable pós-calib
3. **0x200 não é mais escrito** — removido da calibração (já em 07-24) e do enable (agora)

## Estado atual (antes do power cycle)
- MAC não recupera sem power cycle (dano do stop antigo já feito)
- PHY continua mudo (MDIO retorna 0x0000 em todos os registradores)
- TX conta 21 pacotes em software, hardware counters = 0
- RX nunca recebe nada (OWN=1 permanentemente)

## Pendente pós-power-cycle
1. Verificar se MAC enable persiste com stop fix
2. Verificar se TX doorbell fix (endereço do descritor em 0x3c) permite TX real
3. Diagnosticar por que PHY não acorda (hold_val=0x10, clock config, soft-reset já ok)