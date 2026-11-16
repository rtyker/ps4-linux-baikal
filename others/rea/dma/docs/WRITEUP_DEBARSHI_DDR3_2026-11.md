# Writeup do Debarshi — PS4 Pro Belize DDR3 (v1, v2, Architecture)

**Data da leitura direta:** 2026-11-16  
**Fontes originais (não resumos):**
1. <https://dev.to/debarshis/ps4-pro-belize-ddr3-170m> (v1, 4 ago)
2. <https://dev.to/debarshis/ddr3-memory-engine-architecture-dg2> (v2, 11 ago)
3. <https://dev.to/debarshis/ps4-pro-belize-ddr3-patch-v2-4pb2> (v2 patch, 24 out)
4. Cobertura: <https://ps4linux.com/ps4-pro-ddr3-patch-linux-debarshi/> (5 nov 2026)

---

## 1. Resumo Técnico Extraído (valores para conferir)

| Item | Valor Citado | Observação |
|------|--------------|------------|
| **Dispositivo PCI (Belize)** | `104d:90cd` | **Não existe no nosso repo** (nosso DMAC é `104d:90dc` no Baikal Slim) |
| **Registrador de disparo (GO)** | `0x1d40` | **Fora dos 4 KiB dos nossos BARs** (BAR0/BAR2 do `90dc` são 4 KiB cada) |
| **Máscara de interrupção** | Escrever `0x11` | — |
| **Endereço DDR3 no barramento interno** | `0xC0000000 + offset` | **Não é o endereço PCI**. Nosso BAR2 da SPM está em `0x80000000` |
| **Chip DDR3** | 1 GB (Belize Pro) | Nosso Baikal Slim tem 256 MB |
| **Alinhamento obrigatório** | 32-bit (4 bytes) | Controlador rejeita acessos não alinhados → I/O error. Usar `ioread32`/`iowrite32` |
| **Kernel base** | 6.8.12 | — |
| **Exposição** | Disco blk-mq `/dev/ps4pro_ddr3` para swap | — |

### Arquitetura v2 (DMA Engine Architecture)
- **Escrita (posted)**: Rajada > 1 GB/s, sustentado ~156 MB/s
- **Leitura (non-posted)**: ~11 MB/s, latência média 85 ms
- **8 filas** (queues), zswap LZ4, prefetch de 4 MB
- **Sem registradores documentados** neste post

### Patch v2 (DMA no lugar de PIO)
| Métrica | Old Patch (PIO) | New Patch (DMA) |
|---------|-----------------|-----------------|
| Reads | 10.6 MB/s | **504 MB/s** |
| Writes | ~138 MB/s | **425 MB/s** |
| Teto | Desconhecido | **~1.4 GB/s** (jobs de 65,408 B @ 1,383 MB/s) |

**Mecanismo descrito:**
1. DMAC visto como PCI `104d:90cd`
2. Driver aloca **um buffer de staging fixo < 4 GB, coerente (DMA-visível)** — "loading dock" entre CPU e DDR3
3. Protocolo: byte-count exato, source, dest, registrador GO `0x1d40`, interrupt-mask `0x11`
4. Orbis OS usa esse chip via driver `sbram` (closed source); Debarshi usou IA para RE do binário do kernel Orbis

---

## 2. Diferenças Críticas para Nosso Caso (Baikal Slim)

| Aspecto | Belize (Pro) | Baikal Slim (Nosso) | Impacto |
|---------|--------------|---------------------|---------|
| Device ID DMAC | `104d:90cd` | `104d:90dc` | **Diferente** — registradores podem divergir |
| Registrador GO | `0x1d40` | N/A (BARs de 4 KiB = 0x0–0xFFF) | `0x1d40` **não existe** no nosso DMAC |
| DDR3 size | 1 GB | 256 MB | Janela menor |
| Endereço interno DDR3 | `0xC0000000 + off` | Desconhecido (resíduos Orbis: `0x10040000`, `0xcbc00000`) | H2 do plano |
| Janela PCI BAR2 SPM | `0x80000000–0xBFFFFFFF` (1 GiB) | `0x80000000–0x8FFFFFFF` (256 MB reais) | Mesma base `0x80000000` |
| Driver Orbis | `sbram` (closed) | MTS/GBE/ICC/glue (RE parcial) | Precisamos achar consumidor do DMAC para SPM no dump |

---

## 3. Pistas Aproveitáveis (do plano original)

1. **Base PCI `0x80000000` coincide** — mesma convenção de janela
2. **Hipótese H2**: Se DMA usa `0xC0000000 + off` (v2) e janela PCI é `0x80000000 + off` (v1), endereço DMA = PCI + `0x40000000`. **Dois números de fontes frágeis** — testar só depois de H1 falhar
3. **Alinhamento 32-bit**: Nosso `memcpy_fromio` não garante, mas funcionou nas leituras; DMAC já exige múltiplos de 4 B
4. **Assimetria posted/non-posted**: Escrita pode ser muito mais rápida que leitura por CPU — medir as duas no Passo 1

---

## 4. O que NÃO consta no writeup (não assumir)

- Mapa completo de registradores do DMAC `90cd`
- Tamanho do buffer de staging
- Sequência de init completa
- Patches / código fonte
- Versão exata do kernel além de "6.8.12"
- Se o DMAC `90cd` tem 1 ou 2 controladores (nós temos 2: BAR0 e BAR2)
- Como o buffer de staging é mapeado (coherent DMA allocation)
- Detalhes do interrupt-mask `0x11` (quais bits)
- Se há descriptor rings ou programação direta de registradores

---

## 5. Ações do Passo 0 (este arquivo = 0.1 concluído)

- [x] **0.1** Ler fontes originais e extrair registradores/sequência/tamanho/dispositivo → **ESTE ARQUIVO**
- [ ] **0.2** Consultar `ps4_hardware_memory.db` (`readonly_verification`, `hardware_registers`) para leituras prévias de `+0x70` (`0x80000001`) e BARs da SPM
- [ ] **0.3** Procurar no dump Orbis (`kmem_dump_1252.bin`) o consumidor do DMAC para SPM/ddr3swap: strings `SceDdr3Swap`, `ddr3swap_*`, `spm_pci`, `Baikal DDR3 memory` (ver `ACHADOS_MEMORIA_BAIKAL_FASE2.md`). Objetivo: descobrir **qual endereço** o Orbis entrega ao DMAC para a DDR3 (resolve H2 sem tocar hardware)

---

## 6. Próximos Passos (fora deste arquivo)

- **Passo 0.2**: `sqlite3 others/rea/ps4_hardware_memory.db ...`
- **Passo 0.3**: Ghidra headless no dump Orbis com `ExtractMtsNamespaceNoAnalysis.py` adicionando endereços candidatos de `ddr3swap`/`spm_pci` em `TARGET_ADDRS`
- **Passo 1**: Baseline CPU no PS4 (requer hardware)
- **Passo 2**: DMAC lendo SPM no PS4 (requer hardware)