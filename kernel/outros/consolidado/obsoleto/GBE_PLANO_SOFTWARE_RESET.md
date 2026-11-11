# Relatório de Revisão Técnica: Driver Linux `ps4_mts` (`drivers_mts/mts.c`, `mts.h` & `mts-baikal-gbe-driver.patch`)

> **Data de Atualização:** 2026-07-22  
> **Arquivo Local de Controle:** `consolidado/GBE_PLANO_SOFTWARE_RESET.md`  
> **Arquivos Fonte:** `drivers_mts/mts.c`, `drivers_mts/mts.h`  
> **Patch Integrado:** `distros/arch_minimal_v2/patches/mts-baikal-gbe-driver.patch`  

---

## 📋 Resumo Executivo
Revisão técnica completa do driver C nativo para o controlador Ethernet Sony Baikal MTS (`[104d:90d8]`), empacotado em `drivers_mts/mts.c`, `drivers_mts/mts.h` e no patch de kernel `distros/arch_minimal_v2/patches/mts-baikal-gbe-driver.patch`.

O driver foi projetado com **excelência técnica impressionante**, aderindo estritamente ao pseudo-código de `mts_init()` (`fcn.ffffffffdc5a31f0`) e às lições aprendidas em todas as 15 fases de medição ao vivo.

---

## 💎 Destaques Técnicos & Pontos Fortes do Código

### 1. Sistema de Bring-up em 5 Estágios Seguros (`module_param stage`)
O parâmetro `stage` (default `1`) permite subir o driver em escada de segurança sem risco de travar o console:
- **`stage 0`**: Probe limpo + `pci_iomap` (4 KB). Zero escritas MMIO.
- **`stage 1`**: Dump de registradores da BAR0 + Sondagem MDIO Clause 45 falseável (`mts_mdio_probe`).
- **`stage 2`**: Alocação de anéis DMA no Linux (`dma_alloc_coherent`) + Programação dos registradores de anel (`0x44`/`0x3c` TX e `0x48`/`0x40` RX).
- **`stage 3`**: Habilitação dos MAC cores (`0x34`/`0x38`) + Configuração de IMR (`0x54`).
- **`stage 4`**: `pci_set_master()`, alocação de IRQ via `bpcie_assign_irqs`, leitura do endereço MAC na SPM e registro do `netdev` (`eth0`).

### 2. Blindagem Total da Memória RAM (`pci_set_master` exclusivo no Estágio 4)
O código aloca os anéis de DMA (`MTS_RING_BYTES = 4 KB`, `MTS_RX_BUF_TOTAL = 384 KB`) e programa a base/ponteiros em `0x44`/`0x3c` e `0x48`/`0x40` **ANTES** de invocar `pci_set_master()`. Isso garante que o hardware nunca faça DMA nos endereços legados do FreeBSD que apontavam para a RAM ativa do Linux.

### 3. Tratamento Preciso de Idiossincrasias do Silicon Baikal MTS
- **Tamanho Dinâmico da BAR0**: Uso correto de `pci_resource_len(pdev, 0)` (4 KB) em vez de `0x4000` fixo (evitando a falha de *resource sanity check* do `sky2`).
- **Comportamento de `0x34`/`0x38`**: Reconhece que `0x34` não retém o valor lido (lê `0`), enquanto a mudança de estado observável se manifesta em `0x38` (lê `8`), `0x50` e `0x70`.
- **Endereço MAC Nativo**: Leitura do MAC real gravado na SPM da função MEM (`00:14.6`) via `BAIKAL_FUNC_ID_MEM`, com fallback limpo para `eth_random_addr()`.
- **MDIO Clause 45 Falseável**: `mts_mdio_probe()` valida se os alvos devolvem valores distintos entre si e diferentes do resíduo de barramento (`0x8000`), evitando falsos positivos.

---

## 🔍 Análise e Recomendações Secundárias para Evolução Futura

1. **Atribuição do MDIO Clause 45 (`MTS_MDIO = 0x00`)**:
   - A rotina `mts_mdio_read` escreve a fase de endereço (`0x20`) e depois a fase de leitura (`0xe0`) em `BAR0 + 0x00` conforme `fcn.dc5a2680`. A validação ao vivo no estágio 1 confirmará a resposta do PHY.
2. **Tratamento de Interrupção (`mts_interrupt`)**:
   - Atualmente retorna `IRQ_HANDLED` e incrementa contador. À medida que o registrador de STATUS de interrupção (ACK) for refinado na RE, o ACK explícito pode ser adicionado.
3. **Fila de Transmissão (`mts_start_xmit`)**:
   - Atualmente descarta skbs com `NETDEV_TX_OK` e incrementa `tx_dropped`. Perfeito para o estágio inicial de validação de link/RX sem risco de travamento de TX ring.

---

## 📊 Matriz de Validação do Patch (`mts-baikal-gbe-driver.patch`)

| Componente Patch | Arquivo Alvo | Status da Integração |
|---|---|---|
| Kconfig Global | `drivers/net/ethernet/Kconfig` | ✅ Vendedor `sony` adicionado à árvore |
| Makefile Global | `drivers/net/ethernet/Makefile` | ✅ Vendedor `sony` compilado via `obj-$(CONFIG_NET_VENDOR_SONY)` |
| Kconfig Vendedor | `drivers/net/ethernet/sony/Kconfig` | ✅ Opção `CONFIG_MTS_GBE` criada sob `PCI && X86_PS4_BAIKAL` |
| Makefile Vendedor | `drivers/net/ethernet/sony/Makefile` | ✅ Objetos `mts.o` vinculados |
| Código Driver | `drivers/net/ethernet/sony/mts.c` | ✅ 634 linhas de C limpo e documentado |
| Header Driver | `drivers/net/ethernet/sony/mts.h` | ✅ 126 linhas com offsets RE + medidos |

---

## 🚀 Próximos Passos Recomendados para o Boot do Console

1. **Validação em Estágio 1 (`stage=1`)**:
   - Carregar o módulo `mts` (ou dar boot no kernel compilado) com `stage=1`.
   - Inspecionar o `dmesg` para validar o dump dos 28 registradores e o log do `mts_mdio_probe()`.
2. **Avanço Progressivo (`stage=2`, `stage=3`, `stage=4`)**:
   - Incrementar o parâmetro `stage` via linha de comando do kernel (`mts.stage=2`, `mts.stage=4`) para abrir gradualmente as capacidades do driver com total controle e segurança.
