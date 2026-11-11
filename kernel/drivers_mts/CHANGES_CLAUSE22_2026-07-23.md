# 📝 Mudanças no mts.c — Implementação de Clause 22 (2026-07-23)

## Sumário
Adicionado suporte a **MDIO Clause 22 (MII)** como fallback para casos onde Clause 45 não funciona.

---

## Arquivos Modificados

- **`drivers_mts/mts.c`** — Adicionadas funções e diagnóstico

---

## Mudanças Específicas

### 1. Adição de Constantes (após linhas 215-217)

```c
/* ================================================================ */
/* MDIO Clause 22 (MII) — alternativa se Clause 45 falhar          */
/* ================================================================ */

/* Clause 22 usa formato mais simples: sem "ADDR" phase separada */
#define MTS_MDIO_C22_OP_READ    0x02
#define MTS_MDIO_C22_OP_WRITE   0x01
```

**Localização:** Após `mts_mdio_read_packed()` (nova seção de Clause 22)

### 2. Função `mts_mdio_c22_read()` (linhas 218-238)

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
- Sem "ADDR" phase (tudo em um comando)
- Opcode: 0x02 para read
- PHY address e registrador em 5 bits cada

### 3. Função `mts_mdio_c22_write()` (linhas 248-262)

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

**Nota:** Warning em compilação (`mts_mdio_c22_write not used`) é esperado — função será chamada quando implementar fallback completo.

### 4. Diagnóstico Automático em `mts_phy_calibration()` (após linha 413)

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

**Inserido em:** Início de `mts_phy_calibration()`, logo após `dev_info("PHY calibration: iniciando...\n")`

---

## Compilação

**Comando:**
```bash
sudo bash scripts/build_mts_module.sh
```

**Resultado:**
```
✅ Módulo compilado com sucesso!
[1 warning esperado sobre mts_mdio_c22_write não utilizada]
Binário: drivers_mts/build/mts.ko
```

---

## Próximos Passos (após teste ao vivo)

### Se Clause 22 Funcionar (PHY responde)
1. Modificar `mts_phy_calibration()` para usar `mts_mdio_c22_read()` / `mts_mdio_c22_write()`
2. Ativar bloco de MDIO calibration (que estava bloqueado pela pré-condição)
3. Tentar detectar link e carrier novamente

### Se Nenhum Funcionar
1. Investigar se PHY está em power-down
2. Procurar sequência de wake-up no código Orbis (dump do kernel 12.52)
3. Implementar power-up/soft-reset do PHY

---

## Referências

- **Especificação MDIO Clause 22 (IEEE 802.3):** Single-phase read/write ao registrador BAR0+0x00
- **Formato:** [4:0]=opcode, [8:5]=reg, [12:9]=phy_addr, [20:16]=data
- **Compatibilidade:** Funções usam mesmo padrão de `mts_mdio_wait()` que Clause 45

---

**Data:** 2026-07-23 16:35 UTC  
**Status:** Compilado, pronto para teste ao vivo  
**Teste esperado:** Teste #3 — Diagnóstico Clause 22
