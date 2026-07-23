---
name: plano-implementacao-phy-calib-2026-07-23
description: Plano técnico de implementação da calibração PHY (dc5a0ba0)
metadata:
  type: project
---

# Plano de Implementação: PHY Calibration (dc5a0ba0 → Linux)

**Status:** Pronto para análise e decisão do usuário  
**Complexity:** Médio-Alto  
**Risco:** Baixo (operações read-only + MDIO write isoladas)

---

## 1. Decodificação Necessária

### 1.1 Confirmar Offsets BAR2

Função `func_0xffffffffdc7187a0` chamada com offsets:
- `0x6c`, `0x68`, `0x60`, `0x5c`, `0x100`

Padrão esperado:
```c
uint32_t gbe_phy_read_calib_param(uint32_t offset)
{
    // Provavelmente: *(BAR2_VA + offset)
    // BAR2 já é mapeado em algum driver Orbis (baikal_pcie.c)
}
```

**Ação:** Verificar se esses offsets estão documentados em `consolidado/` ou se precisamos fazer uma busca no kernel Orbis completo.

### 1.2 Mapeamento MDIO Registers

Registradores PHY modificados (da decompilação):
```
0x12001e  0x16001e  0x17001e  0x18001e  0x19001e
0x20001e  0x21001e  0x22001e  0x37001e  0x39001e
0x96001e  0x107001f 0x171001e 0x172001e 0x173001e
0x174001e 0x175001e
```

Formato: `0xDDRRRR` onde DD = DEVAD (Clause 45), RRRR = registro.

**Esperado:** Estes devem ser mapeáveis via `mts_mdio_read(mp, devad, reg, &out)`.

### 1.3 Confirmar função 0xac (Enable)

Linha 67-70 da decompilação:
```c
BAR0[0xac] = 9  // (ou via MMIO se SPACE=memory)
```

**Ação:** Verificar se `0xac` tem significado conhecido no mts.c ou se é um novo registrador.

---

## 2. Estrutura da Calibração (Simplificada)

### 2.1 Pseudocódigo Linear

```c
void mts_phy_calibration(struct mts_priv *mp)
{
    // ===== FASE 1: INIT =====
    mts_write(mp, 0x200, 0);      // desabilita algo
    
    // ===== FASE 2: CONFIG =====
    u32 val = mts_read(mp, 0x50);
    mts_write(mp, 0x50, val);      // reescreve (confirma estado)
    
    // ===== FASE 3: MDIO CLEAR =====
    u16 dummy;
    mts_mdio_read(mp, 2, 0x0000, &dummy);   // devad=2
    mts_mdio_read(mp, 3, 0x0000, &dummy);   // devad=3
    
    // ===== FASE 4: ENABLE PHY =====
    mts_write(mp, 0xac, 9);
    
    // ===== FASE 5: CALIBRAÇÃO (loop complexo) =====
    // Lê parâmetros de BAR2 glue
    u32 p0 = gbe_calib_read(0x6c);
    u32 p1 = gbe_calib_read(0x68);
    u32 p2 = gbe_calib_read(0x60);
    // ...
    
    // Calcula valores de calibração (interpolação de bits)
    // Escreve via MDIO
    mts_mdio_write(mp, 0x01, 0x201e, CALC_0x12);
    mts_mdio_write(mp, 0x01, 0x161e, CALC_0x16);
    // ... (15+ registradores)
}
```

### 2.2 Fase de Calibração Detalhada (primeiro grupo)

Linhas 72-102 da decompilação (exemplo de um ciclo):

```c
// Leitura de BAR2 (pervasive glue)
u32 reg_0x6c = gbe_calib_read(0x6c);

// Verificação de pré-condição
if ((reg_0x6c & 0x80800000) == 0x80800000) {
    // Prossegue com calibração
    
    // Lê outro parâmetro
    u32 reg_0x68 = gbe_calib_read(0x68);
    
    // Extrai campo de 6 bits e deslocar
    u32 field = (reg_0x68 & 0x3f) << 8;
    
    // Escreve via MDIO
    mts_mdio_write(mp, 0x01, 0x201e, field);
    
    // Próximo: mesmo padrão
    u32 reg_0x68_2 = gbe_calib_read(0x68);
    field = (reg_0x68_2 >> 6) & 7;
    mts_mdio_write(mp, 0x01, 0x211f, field);
}
```

**Observação:** Há **15+ escritas MDIO** nesta função. Todas seguem o padrão `read BAR2 → extract bits → write MDIO`.

---

## 3. Riscos e Mitigações

| Risco | Probabilidade | Mitigation |
|-------|---------------|-----------|
| BAR2 offsets diferentes em Baikal | Baixa | Verificar contra dump de kernel + medições ao vivo |
| DEVAD/registrador MDIO incorreto | Baixa | Comparar com `mts_mdio_probe()` já no código |
| Ordem de escrita MDIO importa | Média | Respeitar sequência exata de dc5a0ba0 |
| PHY já está calibrado (não faz diferença) | Baixa | Testar ao vivo — se não mudar carrier, é inócuo |
| Escrita errada causa glitch/desligamento | Muito Baixa | MDIO write-only não causa crash (provado com sky2) |

---

## 4. Estratégia de Verificação

### Antes de implementar no código:

1. **Leitura de BAR2:** Confirmar que os 5 offsets (`0x6c`, `0x68`, `0x60`, `0x5c`, `0x100`) podem ser lidos ao vivo (já com kernel rodando, via `/dev/mem` ou netconsole).

2. **Registradores MDIO:** Confirmar que devad=0x01 é válido (já usado por `mts_mdio_probe()`).

3. **Sequência minimal:** Implementar versão simplificada primeiro:
   ```c
   mts_write(mp, 0x200, 0);
   mts_write(mp, 0xac, 9);
   mts_mdio_read(mp, 2, 0x0000, &dummy);
   mts_mdio_read(mp, 3, 0x0000, &dummy);
   ```
   Testar se já melhora carrier detection.

4. **Full calibration:** Se acima funcionar, adicionar o loop completo.

---

## 5. Candidatos de Implementação

### Opção A: Transcrição Direta (Recomendada)

Copiar lógica de dc5a0ba0 linha por linha em um novo `mts_phy_calib()`. Mais trabalho, mas mais seguro.

**Entrada:** Ler completo de `decompiled_dc5a0ba0_gbe_phy_calib.txt`.  
**Saída:** `drivers_mts/mts_phy_calib.c` (arquivo separado) + integração em `mts.c`.

### Opção B: Pattern Matching

Buscar padrões MDIO já usados em drivers Linux (sky2, stmmac, etc.) que façam "PHY calibration" similar. Menos seguro, mas potencialmente mais rápido.

---

## 6. Próximos Passos (Decisão do Usuário)

**Pergunta:** Você quer que eu:

1. **Extraia os offsets BAR2 + valores MDIO** do dump decompilado em um documento técnico puro (hex/offset/operação)?

2. **Comece a implementação** já no `mts.c` com uma função stub que chama `mts_phy_calib()` em `mts_open()` ou `mts_mac_enable()`?

3. **Primeiro valide ao vivo** que os offsets BAR2 são leggibili/modificáveis?

Recomendo: **1 → 3 → 2** (validação antes de código).

---

## Referências

- [analise-profunda-phy-carrier-2026-07-23.md](file:///mnt/t/downloads/PS4/linux_in_ps4/memory/analise-profunda-phy-carrier-2026-07-23.md)
- `consolidado/decompiled_dc5a0ba0_gbe_phy_calib.txt` (200+ linhas)
- [tentativas-frustradas-mts-carrier.md](file:///mnt/t/downloads/PS4/linux_in_ps4/memory/tentativas-frustradas-mts-carrier.md) (histórico de testes)
