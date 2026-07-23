---
name: plano-teste-4-phy-power-up
description: Plano de Teste #4 - Investigação de Power-Up e Wake-Up do PHY Baikal
metadata:
  type: project
---

# 📋 TESTE #4 — Plano de Investigação de Power-Up/Wake-Up do PHY

**Data:** 2026-07-23 17:00 UTC  
**Status:** 📐 PLANEJAMENTO — Próximo Bloqueador Identificado

---

## Resumo Executivo

**Achado do Teste #3:** PHY Baikal está **powered-down** (retorna 0x0000 em todos os registradores).

**Bloqueador Identificado:** Falta sequência de **power-up/wake-up** do PHY antes de tentar lê-lo ou calibrá-lo.

**Estratégia Teste #4:** Investigação estática (disassembly) + implementação dinâmica (código) + validação ao vivo.

---

## Passo 1: Investigação Estática (Disassembly Kernel Orbis 12.52)

### Objetivo
Encontrar no dump do kernel Orbis (`consolidado/dumps_orbis/kmem_dump_1252.bin`) a sequência exata que Sony usa para ativar o PHY.

### Método A: Procurar por Função `SceGbeMtsCtrl`
```bash
# Procurar no dump (hexdump ou strings)
strings kmem_dump_1252.bin | grep -i "gbe\|mts\|phy" | head -20
hexdump -C kmem_dump_1252.bin | grep -A 10 "power\|reset\|enable" | head -30
```

**O Que Procurar:**
- Nome da função: `SceGbeMtsCtrl`, `gbe_init`, `phy_init`, `phy_power_up`
- Offsets de registrador: 0x00, 0x04, 0x0c, 0x08 (suspeitos por Teste #3)
- Palavras-chave: `power`, `enable`, `reset`, `wake`, `sleep`

### Método B: Disassembly Direto (Radare2 ou IDA)
```bash
# Se tiver Radare2 instalado:
r2 kmem_dump_1252.bin
> / / /gbe
> / / /phy
> pd @ <endereço-encontrado>
```

**Esperar:** Sequência de reads/writes MDIO que:
1. Ativa power supply (possivelmente via ICC)
2. Limpa reset bit
3. Aguarda status ready
4. Testa comunicação MDIO

### Método C: Análise de Sequência Esperada
Se disassembly for muito complexo, buscar padrão típico de power-up:
```c
// Padrão esperado
1. MDIO read 0x00 (status)           → verifica power-down bit
2. MDIO write 0x00 com soft-reset    → desperta PHY
3. Delay 100-1000ms                  → aguarda PLL estabilizar
4. MDIO read 0x00                    → verifica status ready
5. Continuar com calibração/teste
```

---

## Passo 2: Implementação Dinâmica (Código)

### Localização
Arquivo: `drivers_mts/mts.c`  
Função: `mts_phy_calibration()`  
Inserir antes: Do bloco de diagnóstico MDIO (linha 415)

### Código Candidato 1: Soft-Reset via MDIO

```c
/* PHY Power-Up e Wake-Up */
static int mts_phy_wakeup(struct mts_priv *mp)
{
	u16 val;
	int ret;
	
	dev_info(&mp->pdev->dev, "PHY wakeup: tentando acordar PHY...\n");
	
	/* Método 1: Limpar soft-reset bit (0x00 bit[15]) */
	ret = mts_mdio_read(mp, 0x01, 0x0000, &val);
	if (ret) {
		dev_err(&mp->pdev->dev, "  FALHA ao ler status (ret=%d)\n", ret);
		return ret;
	}
	dev_info(&mp->pdev->dev, "  Status antes: 0x%04x\n", val);
	
	/* Escrever valor com reset bit limpo */
	val &= ~(1 << 15);  /* Limpar bit 15 (soft reset) */
	ret = mts_mdio_write(mp, 0x01, 0x0000, val);
	if (ret) {
		dev_err(&mp->pdev->dev, "  FALHA ao escrever reset (ret=%d)\n", ret);
		return ret;
	}
	
	/* Aguardar 500ms para PLL estabilizar */
	msleep(500);
	
	/* Verificar se acordou */
	ret = mts_mdio_read(mp, 0x01, 0x0000, &val);
	if (ret) {
		dev_err(&mp->pdev->dev, "  FALHA ao verificar status (ret=%d)\n", ret);
		return ret;
	}
	dev_info(&mp->pdev->dev, "  Status depois: 0x%04x\n", val);
	
	if (val != 0x0000) {
		dev_info(&mp->pdev->dev, "  ✅ PHY acordado (val=0x%04x)\n", val);
		return 0;
	} else {
		dev_warn(&mp->pdev->dev, "  ⚠️  PHY ainda retorna zeros (poder-down persiste)\n");
		return -ETIMEDOUT;
	}
}
```

### Código Candidato 2: Reset via BAR0

```c
/* Alternativa: Reset via registrador BAR0 (se houver) */
static int mts_phy_reset_bar0(struct mts_priv *mp)
{
	u32 reset_reg;
	
	dev_info(&mp->pdev->dev, "PHY reset: tentando reset via BAR0...\n");
	
	/* Procurar registrador de reset (comum em 0xf8 ou 0xfc) */
	reset_reg = mts_read(mp, 0xf8);  /* Exemplo */
	dev_info(&mp->pdev->dev, "  Reset reg antes: 0x%08x\n", reset_reg);
	
	/* Ativar reset (geralmente bit[0] ou bit[31]) */
	mts_write(mp, 0xf8, reset_reg | (1 << 0));
	msleep(100);
	
	/* Desativar reset */
	mts_write(mp, 0xf8, reset_reg & ~(1 << 0));
	msleep(500);
	
	reset_reg = mts_read(mp, 0xf8);
	dev_info(&mp->pdev->dev, "  Reset reg depois: 0x%08x\n", reset_reg);
	
	return 0;
}
```

### Integração em `mts_phy_calibration()`

```c
/* Antes do diagnóstico MDIO, adicionar: */
ret = mts_phy_wakeup(mp);
if (ret) {
	dev_err(&mp->pdev->dev, "PHY wakeup falhou, continuando mesmo assim...\n");
	/* Não retornar erro para permitir diagnóstico */
}
```

---

## Passo 3: Teste ao Vivo (Validação)

### Sequência de Teste #4

1. **Recompile o módulo com power-up code**
   ```bash
   sudo bash scripts/build_mts_module.sh
   ```

2. **Transferir e carregar no PS4**
   ```bash
   wget -O /tmp/mts.ko http://192.168.6.100:8888/mts.ko
   insmod /tmp/mts.ko stage=4
   ```

3. **Capturar diagnóstico**
   ```bash
   dmesg | grep -i "wakeup\|power\|phy\|clause" | tail -30
   ```

### Esperado se Power-Up Funcionar
```
[...] PHY wakeup: tentando acordar PHY...
[...] Status antes: 0x0000
[...] Status depois: 0x3000  ← VALOR REAL (não zero mais!)
[...] ✅ PHY acordado (val=0x3000)
[...] MDIO diagnosis: testing Clause 45 vs Clause 22...
[...] Clause 45: ret=0 val=0x3000  ← VALOR MUDOU!
[...] Clause 22: ret=-110 val=0xffff
```

### Esperado se Power-Up NÃO Funcionar
```
[...] PHY wakeup: tentando acordar PHY...
[...] Status antes: 0x0000
[...] Status depois: 0x0000  ← AINDA ZERO
[...] ⚠️  PHY ainda retorna zeros
[...] MDIO diagnosis...
[...] Clause 45: ret=0 val=0x0000  ← NENHUMA MUDANÇA
```

---

## Passo 4: Análise de Resultado

### Cenário A: Power-Up Funcionou ✅
1. PHY acordado (ret=0 após wakeup)
2. Registradores agora retornam valores reais
3. **Próximo:** Re-implementar bloco de calibração MDIO com dados reais
4. **Teste #5:** Validar link detection com calibração funcional

### Cenário B: Power-Up NÃO Funcionou ❌
1. PHY continua em zeros
2. Precisa investigação mais profunda:
   - ICC power domain talvez ainda desligada (re-testar)
   - Sequência de clock/PLL mais complexa necessária
   - Possível: Hardware defeituoso no console teste
3. **Próximo:** Análise mais profunda do código Orbis ou testes de hardware

### Cenário C: Power-Up Parcial ⚠️
1. PHY acordado mas ainda alguns registradores zerados
2. Indica: Sequência incompleta ou registrador específico problemático
3. **Próximo:** Debug iterativo (modificar delays, testar outros bits)

---

## Recursos Disponíveis

### Kernel Orbis 12.52 (Dump Completo)
- **Localização:** `consolidado/dumps_orbis/kmem_dump_1252.bin` (32.2 MB)
- **Ferramentas:** Radare2, Ghidra, IDA, strings, hexdump
- **O que procurar:** `SceGbeMtsCtrl`, inicialização de PHY

### Documentação Sony (Se Disponível)
- Especificação do PHY Baikal (pode estar no dump como comentários)
- Documentação ICC para poder-up commands
- Datasheet do módulo GBE

### Testes de Validação
- Teste ao vivo no PS4 real (disponível via SSH)
- Captura de dmesg com múltiplas variações de código
- Possibilidade de power-cycle completo entre tentativas

---

## Timeline Estimado

| Fase | Tempo | Status |
|---|---|---|
| Investigação disassembly | 1-2 horas | ⏳ Próxima |
| Implementação código | 30 min | ⏳ Após disassembly |
| Compilação | 5 min | ⏳ Após implementação |
| Teste ao vivo | 10-30 min | ⏳ Após compilação |
| Análise resultado | 30 min | ⏳ Após teste |
| **Total** | **2-4 horas** | ⏳ **ESTE TESTE** |

---

## Próxima Fase (Teste #5 — Se Power-Up Funcionar)

Se power-up PHY funcionar com sucesso:
1. Re-implementar bloco de calibração MDIO
2. Usar dados reais do PHY em vez de zeros
3. Testar link detection com calibração completa
4. Validar `ethtool eth0` mostra link UP

---

## Referências

- [Teste #3 Resultado](teste-3-resultado-2026-07-23.md) — Descoberta de power-down
- [PLANO-CORRECAO-BAR2-PHY-CALIB](PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md) — Contexto original
- `consolidado/dumps_orbis/kmem_dump_1252.bin` — Kernel Orbis com código SceGbeMtsCtrl

---

**Pronto para iniciar?** Deixar eu saber quando deseja prosseguir com investigação disassembly ou se prefere abordagem diferente.

**Próximo Marco:** ✅ Teste #4 — Power-Up PHY (aguardando aprovação)
