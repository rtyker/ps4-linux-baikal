# Baikal DMAC (`dmac_mtk.c`) — mapa de registradores e sequência de uso (RE do Orbis)

**Fonte:** desmontagem direta (`objdump -D -b binary -mi386:x86-64`) do `outros/rea/dumps/kmem_dump_1252.bin`. O dump é um ELF com `LOAD` em offset 0: **endereço virtual = `0xffffffffdc350000` + offset do arquivo**. Código do driver: `0xffffffffdc7b2800–0xffffffffdc7b4a80` (aprox.).
**Estado:** RE estático **mais uma leitura somente-leitura ao vivo** (2026-11-13), registrada no banco (`readonly_verification`, 24 linhas). **Nenhuma escrita foi feita.**

## Registradores (offset a partir da base do recurso/BAR)

Todos 32 bits. Os offsets vêm das instruções `mov edx,<off>; add rdx,[rax+0x10]` e do `sub rdx,-0x80`.

| Offset | Nome | Evidência | Uso observado |
|---|---|---|---|
| `0x80` | `DMA_INT_FLAG` | ISR `0xdc7b4080` lê e escreve de volta | bit0 = transferência concluída (a ISR limpa o bit0 e regrava); bits `0x1e` = erro (`dma error detect`) |
| `0x84` | `DMA_INT` | `0xdc7b4a2a`, `0xdc7b3ea9`, `0xdc7b4029` | `= 0x3` ao iniciar (habilita interrupções); `= 0` ao desabilitar/desanexar |
| `0x88` | `DMA_EN` | só impresso no dump | **escrita não localizada** |
| `0x8c` | `DMA_RST` | `0xdc7b3b19`, `0xdc7b3b47`, `0xdc7b3f59`, `0xdc7b3f7b` | reset: escreve `0x2`, depois `0x0` |
| `0x90` | `DMA_DESC_ADDR` | `0xdc7b49d5` | endereço (32 bits) da lista de descritores, de `[obj+0x78]` |
| `0x94` | (não nomeado) | — | sem uso encontrado |
| `0x98` | `DMA_CON` | `0xdc7b4a0f` | seleção de unidade/burst (ver abaixo) |
| `0x9c` | `DMA_SRC_ADDR` | `0xdc7b4997` | zerado no modo descritor |
| `0xa0` | `DMA_DST_ADDR` | `0xdc7b49b6` | zerado no modo descritor |
| `0xa4` | `DMA_LEN` | `0xdc7b4978` | zerado no modo descritor |
| `0xa8` | `DMA_DESC_EN` | `0xdc7b4a4c` | `= 1` dispara a transferência |
| `0xac` | `DMA_DEBUG_ST` | só impresso no dump | leitura de depuração |

**Correção ao `hardware_report.txt`:** o "mapa antigo" (canal 1 em `0x00–0x1F`, page registers em `0x80–0x8F`, canal 2 em `0xC0–0xDF`) **nunca foi do Baikal DMAC**. Essas faixas estão na seção "I/O PORTS" do `/proc/ioports`, ao lado de `PIC1`, `PIT`, `8042` e `RTC CMOS`: são as portas do **DMA legado do PC (8237)**, rotuladas por engano como registradores do `00:14.5`. O `00:14.5` não tem BAR de I/O (só `Region 0` e `Region 2`, de memória). Os registradores reais vivem em `+0x80…+0xAC` de cada BAR. As linhas originais ficaram **anotadas como erro** no `hardware_report.txt`.

(A hipótese do "8237" que eu havia levantado antes nasceu da mesma leitura errada: o 8237 existe, mas é o DMA legado da plataforma, não o `00:14.5`.)

## Sequência de início de transferência (`0xdc7b4960–0xdc7b4a6a`)

1. `LEN (+0xa4) = 0`
2. `SRC (+0x9c) = 0`
3. `DST (+0xa0) = 0`
4. `DESC_ADDR (+0x90) = <endereço físico 32 bits da lista de descritores>`
5. `INT_FLAG (+0x80) = 0`
6. `CON (+0x98) = <unidade>` (abaixo)
7. `INT (+0x84) = 0x3`
8. `DESC_EN (+0xa8) = 1`  ← inicia

**`CON`:** calculado por `tzcnt` do OR de **todos** os endereços e comprimentos do trecho (com `|0x80` para limitar). A tabela de salto (`0xdcb55e38`):

| `tzcnt` (alinhamento) | Resultado |
|---|---|
| 0 ou 1 (não alinhado a 4 bytes) | **erro** `dmac: invalid alignment` |
| 2 (4 B) | `CON = 0x00000` |
| 3 (8 B) | `CON = 0x10000` |
| 4 (16 B) | `CON = 0x20000` |
| 5 (32 B) | `CON = 0x30000` |
| ≥ 6 (≥64 B) | `CON = 0x40000` |

Ou seja, `CON[18:16] = min(log2(alinhamento) − 2, 4)`, e **todo endereço e tamanho precisa ser múltiplo de 4 bytes**.

## Descritor (16 bytes, campos de 32 bits)

Construído a partir da lista de segmentos de `bus_dma` (`dmac_callback`, `nseg too large`):

| Offset | Campo |
|---|---|
| `+0x0`, `+0x4` | endereços das duas pontas (origem/destino); a ordem exata não foi confirmada (`DMA_DESCRIPTOR_BASE` imprime `bcount, src, dst, next`, mas o código grava o comprimento em `+0x8`) |
| `+0x8` | comprimento (`min(segmento, restante)`) |
| `+0xc` | endereço do **próximo** descritor (físico, 32 bits); o último recebe `0` |

**Consequências:** endereços de 32 bits (buffers e lista abaixo de 4 GiB); lista de descritores contígua.

## Leitura ao vivo (2026-11-13, 32 bits, somente leitura, via `/sys/bus/pci/devices/0000:00:14.5/resource{0,2}`)

| Offset | Nome | BAR0 (`ca000000`) | BAR2 (`ca800000`) |
|---|---|---|---|
| `0x80` | INT_FLAG | `0x00000000` | `0x00000000` |
| `0x84` | INT | `0x00000000` | `0x00000000` |
| `0x88` | EN | `0x00000000` | `0x00000000` |
| `0x8c` | RST | `0x00000000` | `0x00000000` |
| `0x90` | DESC_ADDR | `0x00000000` | `0x00000000` |
| `0x94` | (?) | `0x10000000` | `0x10000000` |
| `0x98` | CON | `0x00040000` | `0x00040000` |
| `0x9c` | SRC | `0x00000000` | `0x10040000` |
| `0xa0` | DST | `0x00100000` | `0xcbc00000` |
| `0xa4` | LEN | `0xffffffff` | `0x00000000` |
| `0xa8` | DESC_EN | `0x00000000` | `0x00000000` |
| `0xac` | DEBUG_ST | `0x00000013` | `0x00000013` |

**O que isto sustenta:**
- Os offsets do RE estão **certos no mínimo para `CON`**: `0x00040000` é exatamente um dos valores que o driver do Orbis grava (unidade ≥64 B). Os registradores respondem (não são `0xffffffff` nem `0x0` em bloco).
- **BAR0 e BAR2 são dois controladores com o mesmo layout** (mesmo `0x94`, `CON`, `DEBUG_ST`). Compatível com `DMA1` e `DMA2`. Falta confirmar qual é qual.
- `INT_FLAG`, `INT`, `EN`, `RST`, `DESC_ADDR` e `DESC_EN` em zero indicam controlador ocioso, desabilitado e sem transferência pendente.
- `SRC`/`DST`/`LEN` com valores diferentes de zero (em especial `BAR2`: `SRC=0x10040000`, `DST=0xcbc00000`) parecem **resíduo de uso anterior pelo Orbis**, antes do `kexec`. Isso é leitura, não está provado.
- Releitura do BAR2 (`INT_FLAG`, `CON`, `LEN`, `DEBUG_ST`) deu os mesmos valores. Nenhuma mensagem nova no `dmesg`.

**O que isto NÃO prova:** que o controlador executa transferências no Linux. Isso exigiria escrita em `DESC_ADDR`/`CON`/`INT`/`DESC_EN` e não foi tentado.

## Varredura completa das duas páginas (2026-11-13, após reboot, somente leitura)

Dump bruto: `outros/rea/dma/scans/dmac_bars_full_20261113.json` (1024 palavras de 32 bits por BAR).

- **1018 de 1024 palavras são `0x00000000`** em cada BAR. O espaço é esparso, e **não há espelhamento** (testado em 0x100, 0x200, 0x400 e 0x800).
- **Um registrador novo, fora do que o Orbis usa: `+0x70 = 0x80000001`**, igual nos dois BARs. O `dmac_mtk.c` não o toca. Função desconhecida (bit31 e bit0 ligados). Registrado no banco.
- Os registradores `0x80–0xac` batem com a leitura anterior, **inclusive os resíduos**: BAR0 `DST=0x00100000`, `LEN=0xffffffff`; BAR2 `SRC=0x10040000`, `DST=0xcbc00000`. Esses valores **se repetiram idênticos depois de um reboot do Linux**, o que sustenta que são resíduo de uso pelo Orbis antes do `kexec`, e não algo deixado pelo Linux. (Inferência; o Orbis roda a cada boot.)
- Diferenças entre BAR0 e BAR2: apenas `SRC`, `DST` e `LEN`.

**Mapa real consolidado:** o espaço útil de cada controlador é `+0x70` (desconhecido) e `+0x80…+0xac`. Todo o resto lê zero.

## Teste de transferência com escrita (2026-11-13) — **FUNCIONA**

Harness: `outros/rea/dma/harness/baikal_dmac_test/` (módulo de kernel out-of-tree, compilado contra `kernel/kernel_build_7.0`, `vermagic` idêntico ao do PS4). Buffers próprios via `dma_alloc_coherent` (máscara de 32 bits; o `00:14.5` não está em grupo de IOMMU, então o endereço de DMA é o físico). Pré-condição do teste: controlador ocioso. Uma transferência de 256 bytes por BAR, sem interrupção (`INT=0`), com polling de `INT_FLAG`.

**Resultado (BAR0 e BAR2, idênticos):** buffer B recebeu os 256 bytes de A, A permaneceu intacto, em menos de 0,5 ms. Sem erro no `dmesg`, PS4 estável.

**Confirmado:**
- Sequência do Orbis vale: `LEN=SRC=DST=0` (releitura confere), `DESC_ADDR`, `INT_FLAG=0`, `CON=0x40000`, `INT`, `DESC_EN=1`.
- **Descritor:** `+0x0` = **origem**, `+0x4` = **destino**, `+0x8` = comprimento, `+0xc` = próximo (0 = fim).
- `INT_FLAG` bit0 sobe ao concluir **mesmo com `INT=0`** (não é preciso habilitar interrupção para detectar o fim por polling). Escrever o valor com o bit0 limpo zera o bit (limpa-escrevendo-0).
- **`DMA_EN` (`+0x88`) não é necessário**, nem o reset (`RST`).
- Após a transferência: `SRC`/`DST` avançam o tamanho copiado (ponteiros correntes), `LEN` = 0, `DESC_ADDR` volta a 0 (carregou o `next` = 0), `DESC_EN` lê 0. Isso explica os resíduos de `SRC`/`DST`/`LEN` lidos antes do teste: são os ponteiros finais de transferências do Orbis.
- **Os dois controladores (BAR0 e BAR2) funcionam e têm comportamento idêntico.**

### Suíte estendida (mesmo dia): 6/6 no BAR0, 8/8 no BAR2

| Teste | Resultado |
|---|---|
| Cadeia de 3 descritores (stride 16 B, `next` = físico do seguinte, último = 0) | **PASS** (scatter-gather funciona) |
| 64 KiB em um descritor (BAR0) / **1 MiB** em um descritor (BAR2) | **PASS**; `LEN` é de 32 bits |
| Alinhamento 4/8/16/32/64 B com `CON` = 0 / 0x10000 / 0x20000 / 0x30000 / 0x40000 | **PASS** em todos |
| Região de guarda (4 KiB após o buffer destino) | **intacta** em todos |

**Vazão** (polling, uma transferência isolada): ~888 MB/s com 64 KiB, ~935 MB/s com 1 MiB; transferência curta de 256 B leva ~4,8 µs. `DEBUG_ST` muda com o uso (`0x13` → `0x40404013` → `0xc0c0c013`); significado desconhecido.

### Interrupção (MSI) — funciona no BAR0, **não** no BAR2

Harness com `irqmode=1`, `INT = 3`, espera por `completion`.

| Controlador | 1 vetor compartilhado (`bpcie_assign_irqs`) | 2 vetores (`pci_alloc_irq_vectors`) |
|---|---|---|
| **BAR0** | IRQ entregue em todas as transferências (latência ~20–30 µs; polling: ~5 µs) | entregue pelo **vetor 0** |
| **BAR2** | **não entregue** (o hardware conclui: `INT_FLAG = 1`) | **nenhum** dos dois vetores é chamado (contadores `vetor0=0`, `vetor1=0`) |

- Hipótese **não confirmada**: BAR0 = DMAC1 (subfunção 0), BAR2 = DMAC2 (subfunção 1), pelo `baikal.h`.
- A causa de o DMAC2 não interromper é desconhecida (demux/glue/ACK em `ps4-bpcie.c:88`, ou um passo de habilitação que o Orbis faz e eu não repliquei). **Pista de RE:** a rotina de attach do `dmac_mtk.c` (strings `Can't allocate IRQ`, `failed to set up interrupt`) mostra como cada controlador obtém a IRQ.
- Para `pci_alloc_irq_vectors(pdev, 2, 2, PCI_IRQ_MSI)` no `00:14.5`: funciona (IRQs 37 e 38).
- **Achado no código do projeto (causa NÃO resolvida):** no `rmmod` aparece um `WARNING` em `msi_device_data_release` (`kernel/irq/msi.c:294`, `WARN_ON_ONCE`). **Persiste também com `pci_free_irq_vectors(pdev)`**: foi visto no `remove` do driver `baikal-dmac`, no primeiro `rmmod` após o boot. *(Correção: esta linha dizia que `pci_free_irq_vectors()` "resolvia". Estava errada. O `WARN_ON_ONCE` imprime só uma vez por boot, e os testes do harness depois do primeiro aviso rodaram no mesmo boot, então a ausência do aviso não provava nada.)* O lado PCI fica limpo (MSI volta a `Enable-`, IRQ liberada e reutilizada em 3 ciclos). Provável origem: domínio MSI do `bpcie`. Sem efeito funcional observado.

**Ainda NÃO testado:** os dois controladores ao mesmo tempo, `CON` diferente do alinhamento (por ex. `0x40000` com dados alinhados a 4 B), `len=0` e erros induzidos.

## O que NÃO está confirmado

- Qual BAR é o `DMA1` e qual é o `DMA2` (hipótese: BAR0 `ca000000` e BAR2 `ca800000`, uma base por controlador).
- O papel de `DMA_EN` (`+0x88`) e do `+0x94`.
- A ordem origem/destino em `+0x0/+0x4` do descritor.
- Se há configuração prévia (glue ou clock) que o Orbis faz antes de o DMAC responder.
- Semântica exata de `INT_FLAG` (a ISR regrava o valor com o bit0 limpo, o que sugere limpar-escrevendo-0, não W1C).
