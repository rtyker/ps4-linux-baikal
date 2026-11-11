---
name: teste-3-clause22-implementacao
description: Implementação de MDIO Clause 22 (MII) para fallback quando Clause 45 falha
metadata:
  type: project
---

# 📋 TESTE #3 — Implementação de MDIO Clause 22 (MII)

**Data:** 2026-07-23 16:45 UTC  
**Status:** ✅ Compilação bem-sucedida, ⏳ Aguardando teste ao vivo

---

## Resumo da Implementação

**Objetivo:** Investigar se PHY responde em Clause 22 (MII) em vez de Clause 45 (que retorna sempre 0x0000)

**Achados da Fase 2 (Teste #2):**
- PHY **não responde** em Clause 45 MDIO
- Leituras sempre retornam 0x0000
- Suspeita: PHY usa Clause 22 (protocolo alternativo)

**Solução Implementada:**
1. Adicionadas funções `mts_mdio_c22_read()` e `mts_mdio_c22_write()` em mts.c (linhas 218-262)
2. Adicionado diagnóstico automático que tenta ambos os protocolos (linhas 415-432)
3. Módulo compilado com sucesso via Docker (toolchain ps4sdk correto)

---

## Funções Adicionadas

### 1. `mts_mdio_c22_read()` (linhas 218-238)
```c
static int mts_mdio_c22_read(struct mts_priv *mp, u8 phy_addr, u8 reg, u16 *out)
{
	int ret;
	u32 cmd;

	/* Formato Clause 22: [4:0]=opcode, [8:5]=reg, [12:9]=phy */
	cmd = (phy_addr & 0x1f) << 9 | (reg & 0x1f) << 5 | MTS_MDIO_C22_OP_READ;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO, cmd);

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	*out = mts_read(mp, MTS_MDIO) >> 16;
	return 0;
}
```

**Diferenças vs Clause 45:**
- Não usa "ADDR" phase separada (tudo em um comando)
- Opcode simples: 0x02 (read) ou 0x01 (write)
- PHY address: 5 bits (0-31)
- Registrador: 5 bits (0-31)

### 2. `mts_mdio_c22_write()` (linhas 248-262)
```c
static int mts_mdio_c22_write(struct mts_priv *mp, u8 phy_addr, u8 reg, u16 val)
{
	int ret;
	u32 cmd;

	/* Formato Clause 22 */
	cmd = (phy_addr & 0x1f) << 9 | (reg & 0x1f) << 5 | MTS_MDIO_C22_OP_WRITE;

	mts_write(mp, MTS_MDIO, MTS_MDIO_CLEAR_BUSY);
	mts_write(mp, MTS_MDIO, ((u32)val << 16) | cmd);

	ret = mts_mdio_wait(mp);
	if (ret)
		return ret;

	return 0;
}
```

### 3. Diagnóstico Automático (linhas 415-432)
```c
/* Diagnostic: Test MDIO Clause 45 vs Clause 22 (MII) */
dev_info(&mp->pdev->dev, "MDIO diagnosis: testing Clause 45 vs Clause 22...\n");
{
	u16 c45_val, c22_val;
	int ret_c45 = mts_mdio_read(mp, 0x01, 0x0000, &c45_val);
	int ret_c22 = mts_mdio_c22_read(mp, 0x00, 0x00, &c22_val);

	dev_info(&mp->pdev->dev, "  Clause 45: ret=%d val=0x%04x\n", ret_c45, ret_c45 ? 0xffff : c45_val);
	dev_info(&mp->pdev->dev, "  Clause 22: ret=%d val=0x%04x\n", ret_c22, ret_c22 ? 0xffff : c22_val);

	if (ret_c45 != 0 && ret_c22 == 0) {
		dev_info(&mp->pdev->dev, "  ✅ PHY responds to Clause 22 (MII), will use fallback\n");
	} else if (ret_c45 == 0 && ret_c22 != 0) {
		dev_info(&mp->pdev->dev, "  ✅ PHY responds to Clause 45, continuing normal path\n");
	} else if (ret_c45 == 0 && ret_c22 == 0) {
		dev_info(&mp->pdev->dev, "  ⚠️  Both Clause 45 and Clause 22 return data, PHY may work\n");
	} else {
		dev_warn(&mp->pdev->dev, "  ⚠️  PHY not responding to either Clause 45 or Clause 22!\n");
	}
}
```

---

## Compilação

**Data:** 2026-07-23 16:35 UTC  
**Comando:**
```bash
sudo bash /mnt/t/downloads/PS4/linux_in_ps4/scripts/build_mts_module.sh
```

**Resultado:**
```
✅ Módulo compilado com sucesso!
'/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/net/ethernet/sony/mts.ko' -> '/mnt/t/downloads/PS4/linux_in_ps4/drivers_mts/build/mts.ko'
```

**Warning Esperado:**
```
mts.c:248:12: warning: 'mts_mdio_c22_write' defined but not used
```
(Normal: função será usada quando implementar fallback completo)

**Módulo:** `/mnt/t/downloads/PS4/linux_in_ps4/drivers_mts/build/mts.ko` (pronto para teste)

---

## Próximos Passos

### Imediato
1. **Transferir módulo ao PS4:**
   ```bash
   scp drivers_mts/build/mts.ko root@192.168.0.2:/tmp/
   ```
   (Nota: SSH credential necessária — aguardando password de root@192.168.6.128 ou 192.168.0.2)

2. **Carregar módulo e capturar saída:**
   ```bash
   ssh root@192.168.0.2 "insmod /tmp/mts.ko stage=4"
   ssh root@192.168.0.2 "dmesg | tail -30 | grep -i 'clause\|mdio\|diagnosis'"
   ```

### Esperado
Se PHY responder em Clause 22:
```
[...] Clause 45: ret=... val=0x0000
[...] Clause 22: ret=0 val=0x00XX  ← dados reais
[...] ✅ PHY responds to Clause 22 (MII), will use fallback
```

Se PHY não responder em nenhum:
```
[...] Clause 45: ret=... val=0x0000
[...] Clause 22: ret=... val=0x0000
[...] ⚠️  PHY not responding to either Clause 45 or Clause 22!
```

### Se Clause 22 Funcionar
Próximo: Implementar fallback automático na lógica de calibração PHY para usar Clause 22 quando Clause 45 falhar. Isso permitirá que o código de calibração execute com dados reais do PHY.

---

## Referências

- **Especificação MDIO:**
  - Clause 45: Address phase + Read/Write phase (usado atualmente)
  - Clause 22 (MII): Single-phase read/write (alternativa em teste)
  
- **Formato Clause 22 no BAR0+0x00:**
  - Bits [4:0] = Opcode (0x02=read, 0x01=write)
  - Bits [8:5] = Registrador (PHY reg, 5 bits)
  - Bits [12:9] = PHY address (5 bits, tipicamente 0x00 ou 0x1f)
  - Bits [20:16] = Dados (para write) ou resultado (para read)

---

## Status

- ✅ Código compilado sem erros
- ✅ Diagnóstico automático integrado
- ⏳ Teste ao vivo pendente (transferência ao PS4)
- 🔴 Fallback de calibração não implementado ainda (depende de resultado do diagnóstico)
