---
name: gbe-hold-pulse-write-only-e-sequencia-correta
description: Registradores hold/pulse do BPCIE glue são WRITE-ONLY (leem sempre 0) e a sequência correta deixa hold=1 no final; descobertas de 2026-07-22 comparando com AHCI/xHCI que funcionam.
metadata:
  type: project
---

> ⛔ **CORREÇÃO CRÍTICA 2026-07-22 — AS SEÇÕES DE ESCRITA DESTE DOCUMENTO SÃO INVÁLIDAS.**
> Todos os testes de escrita aqui usaram `devmem`, que **não existe neste sistema** (exit 127,
> mascarado por `2>/dev/null`). **Nenhuma escrita chegou ao hardware.** Portanto:
> - a seção 5 ("sequência correta sem efeito nos dois offsets") **não mediu nada**;
> - a seção 8 ("o caminho hold/pulse está esgotado e eliminado") **não se sustenta** — a hipótese
>   nunca chegou a ser testada e continua **EM ABERTO**.
>
> **Continuam VÁLIDAS** (não dependiam das nossas escritas): seção 1 (write-only, provada pelo
> comportamento do driver xHCI que funciona), seção 2 (sequência correta lida no fonte), seção 3
> (offset errado do chip id), seção 6 (eco de barramento, só leitura), seção 7 (blips), seção 9
> (blocos de glue idênticos) e seção 10 (PCI COMMAND, só leitura).
>
> Ver [devmem-nao-existe-usar-dd-octal](devmem-nao-existe-usar-dd-octal.md).

Comparativo ao vivo (2026-07-22, baseline `20260720-sky2len-fix`, via `harness_gbe_compare_working.py`) entre os periféricos que FUNCIONAM (AHCI/xHCI/USB) e a GBE. Três descobertas que invalidam conclusões anteriores:

## 1. Os registradores hold/pulse são WRITE-ONLY (leem sempre 0x00000000)

`bpcie_baikal_sata_phy_init()` (`drivers/ps4/ps4-bpcie.c`) roda no boot — confirmado no dmesg ao vivo: `xhci_aeolia 0000:00:14.7: Baikal SATA PHY init` + `EFUSE VALUE: 0x24:0x0e:0x0e`. Esse código escreve `hold=1` no offset 48 (0x30) e **nunca zera**. Mesmo assim, ler `0xc8980030` devolve `0x00000000`.

**Portanto:** todo readback desses registradores é inútil como verificação — eles sempre leem 0, independente do que foi escrito. Todos os resultados `NO_CHANGE` dos testes anteriores desta sessão (`write_sweep_results`, blocos `GBE hold/pulse BPCIE`, `CHIPID_STEP_BY_STEP`, `REPEAT_SEQUENCE`) **não provam que as escritas não tiveram efeito** — só provam que não dá pra ver o efeito por leitura. A única verificação válida é indireta: BAR0 do MAC (chip id) ou rebind do sky2.

## 2. A sequência correta deixa `hold=1` no final — nunca zera

O código que comprovadamente funciona (AHCI/xHCI) faz exatamente três escritas:

```c
glue_write32(sc, BPCIE_USB_BASE + pulse_offset, 1);
glue_write32(sc, BPCIE_USB_BASE + hold_offset,  1);
glue_write32(sc, BPCIE_USB_BASE + pulse_offset, 0);
/* hold FICA em 1 — não existe quarta escrita */
```

O commit revertido `d3fa7b72c` copiou essas três e **acrescentou uma quarta** (`hold=0`), com o comentário "Dropping the hold is what actually lets the block out of reset" — interpretação não confirmada por nenhum código que funciona. Os testes via telnet desta sessão foram ainda mais longe do original: fizeram `hold=1 → pulse=1 → pulse=0 → hold=0`, ou seja **ordem trocada** (hold antes do pulse) mais a quarta escrita.

**Portanto:** a sequência exata do caminho que funciona, aplicada aos offsets da GBE, **ainda não foi testada** — nem no kernel, nem via telnet.

## 3. Estávamos lendo o registrador errado como "chip id"

Pelo `drivers/net/ethernet/marvell/sky2.h`: `B2_CONN_TYP=0x118`, `B2_PMD_TYP=0x119`, `B2_MAC_CFG=0x11a`, **`B2_CHIP_ID=0x11b`** — e o chip id é **1 byte**, não 32 bits. Um `dd` de 4 bytes em `0xc2000118` cobre os quatro, com o chip id no byte **mais alto** (little-endian).

Ou seja: em todas as amostras (`0x00000004`, `0x0000000d`, `0x00000000`), o byte alto foi **sempre `0x00`** — o chip id nunca deu sinal de vida, coerente com o dmesg `sky2 0000:00:14.1: unsupported chip type 0x0` / `probe failed with error -95`. Os "blips" `0x04`/`0x0d` que investigamos por três testes estavam em `B2_CONN_TYP`, não no chip id.

**Corrigido no SQLite** (2026-07-22): `hardware_registers` tinha `B2_CHIP_ID` em `0x11a` e `B2_MAC_CFG` em `0x11b` — off-by-one, invertidos. Agora id=1 é `B2_MAC_CFG` (0x11a), id=2 é `B2_CHIP_ID` (0x11b), e foi criada a entrada id=693 `B2_CONN_TYP` (0x118).

## 4. Anomalia nos offsets: o par da GBE quebra o padrão

| bloco | hold | pulse | delta | origem |
|---|---|---|---|---|
| USB0 | 0x24 | 0x64 | +0x40 | RE quiesce Orbis |
| USB1 | 0x28 | 0x68 | +0x40 | RE quiesce Orbis |
| AHCI | 0x2c | 0x6c | +0x40 | **confirmado no código Linux que funciona** |
| xHCI | 0x30 | 0x70 | +0x40 | **confirmado no código Linux que funciona** |
| GBE  | 0x20 | 0x74 | **+0x54** | RE quiesce Orbis, nunca confirmado |

Quatro de cinco seguem `pulse = hold + 0x40` exatamente. Só a GBE quebra. O par natural pelo padrão seria `hold=0x20 / pulse=0x60` — hipótese ainda não testada. `0x74` pode ser erro de transcrição do RE.

**Como aplicar:** o próximo teste de GBE deve (a) usar a sequência exata do código que funciona (`pulse=1, hold=1, pulse=0`, sem zerar o hold), (b) testar os dois candidatos de pulse (`0x74` e `0x60`), e (c) verificar por `B2_CHIP_ID` no byte correto (`0xc200011b`) + rebind do sky2, nunca por readback do próprio hold/pulse. Ver [baseline-oficial-sky2len-fix](baseline-oficial-sky2len-fix.md) e [incidente-2026-07-22-gbe-release-boot-travou-video](incidente-2026-07-22-gbe-release-boot-travou-video.md).

## 5. RESULTADO DOS TESTES DA SEQUÊNCIA CORRETA (Fase 10) — sem efeito nos dois offsets

Executado via `harness_gbe_correct_sequence.py` (test_history id=32, `write_sweep_results` block_label `CORRECT_SEQ_VAR_A`/`_B`). A sequência exata do código que funciona (`pulse=1, hold=1, pulse=0`, deixando hold=1) foi aplicada à GBE nos dois candidatos de pulse:

| variante | pulse | B2_CHIP_ID (0x11b) antes → depois | sky2 rebind | resultado |
|---|---|---|---|---|
| A | 0x74 | `00` → `00,00,00` | `unsupported chip type 0x0`, erro -95 | NO_EFFECT |
| B | 0x60 | `00` → `00,00,00` | `unsupported chip type 0x0`, erro -95 | NO_EFFECT |

Nenhuma das duas mudou nada. Nenhum travamento (ping/telnet OK o tempo todo). **O estado ficou com `hold=1` no bloco da GBE** (é o comportamento correto do código que funciona — não zera), e assim permanece até o próximo boot.

## 6. A BAR0 da GBE responde com ZEROS REAIS — não é barramento flutuante (Fase 11)

Hipótese levantada durante a variante A: a leitura do dword em `0xc2000118` devolveu `0x00000001` logo após escrevermos `0x00000001` no pulse — sugerindo que a BAR0 estaria flutuando e ecoando resíduo do barramento.

**Refutado** por `harness_gbe_bus_echo_test.py` (test_history id=33, block_label `BUS_ECHO_TEST`), 100% leitura: lendo no MESMO comando de shell um registrador-isca com valor bem distinto seguido imediatamente da BAR0 da GBE, em 8/8 pares a isca leu seu valor correto e a GBE leu `0x00000000`:

| isca | isca leu | GBE leu |
|---|---|---|
| `0xc900c06c` | `bfbf8787` | `00000000` |
| `0xc900c060` | `0d13b1a2` | `00000000` |
| `0xc900c064` | `492ce89d` | `00000000` |
| `0xc890a030` | `000016c9` | `00000000` |

**Conclusão:** o endpoint PCIe da GBE está vivo e completa as transações MMIO normalmente — quem devolve zeros é o **MAC core Yukon atrás dele**, sem clock/alimentação. Confirma (por medição direta, não por inferência) o que [baikal-gbe-e-sky2-nao-stmmac](baikal-gbe-e-sky2-nao-stmmac.md) já sustentava.

## 7. Os "blips" eram artefato de medição, não hardware

Os valores esporádicos (`0x04`, `0x0d`, `0x01`) que investigamos em três testes **nunca reapareceram** nos testes com leitura limpa: 12 leituras seguidas (noise check), 24 (passo a passo), 40 (8 ciclos repetidos) e 8 (eco, pareadas no mesmo comando de shell) — todas `0x00000000`. Os blips só surgiram nas rodadas com escrita e leitura intercaladas, onde o stream do telnet pode dessincronizar e devolver fragmento de saída anterior. **Não gastar mais tempo perseguindo blips sem antes reproduzi-los num teste de leitura limpa.**

## 8. Veredito sobre o mecanismo hold/pulse

O caminho "liberar a GBE do reset pelo par hold/pulse do BPCIE glue" está **esgotado e eliminado** como hipótese:
- os registradores estão no mesmo estado dos periféricos que funcionam (todos leem 0, write-only);
- a sequência correta do código que funciona não produz efeito nenhum, em nenhum dos dois offsets candidatos;
- o MAC continua devolvendo zeros reais depois de tudo.

O bloqueio está **antes** disso — na alimentação/clock do MAC core, que não é controlada por esses registradores. Próximas linhas devem focar em quem liga essa rail (fora do driver GBE: SAMU/bootloader/`icc_device_power`), não em mais variações de reset via glue.

## 9. Blocos de glue por periférico são IDÊNTICOS (0xc894xxxx)

Dados históricos de `consolidado/M12_revalidacao.md` (48 bytes por bloco):

| bloco | endereço | conteúdo |
|---|---|---|
| USB1 | `0xc8944400` | `10106333 0×5 zeros 00200001 000050c5 06040400 00000000 **0000c000** 00000000` |
| SATA | `0xc8943800` | idem, mas **`0000a000`** |
| xHCI | `0xc8944800` | idem, mas **`00007000`** |
| GBE  | `0xc8942000` | idem, mas **`0000e000`** |

Todos os 12 words são iguais entre os quatro, exceto o word de índice 10 (offset 0x28), que parece ser um campo de ID/roteamento por bloco. **A GBE está estruturalmente idêntica aos periféricos que funcionam nessa camada** — mais uma evidência de que o glue não é o bloqueio.

## 10. PCI COMMAND (Fase 12): MSE ligado — os zeros são do MAC, confirmado

Hipótese alternativa que precisava ser descartada: se o bit **Memory Space Enable** estivesse limpo na função 00:14.1 (plausível, já que o probe do sky2 falha com -95 e o caminho de erro chama `pci_disable_device()`), a GBE não decodificaria a BAR0 e os zeros seriam de ciclo não reclamado — invalidando toda leitura de BAR0 já feita.

Medido via `harness_gbe_pci_command.py` (test_history id=34, block_label `PCI_COMMAND_COMPARE`), lendo só os 64 bytes seguros do config space:

| função | dispositivo | COMMAND | BAR0 | Bus Master |
|---|---|---|---|---|
| 00:14.1 | GBE `0x90d8` | **`0x0542`** | `0xc2000004` | **DESLIGADO** |
| 00:14.2 | AHCI `0x90d9` | `0x0546` | `0xc4000004` | ligado |
| 00:14.7 | xHCI `0x90de` | `0x0546` | `0xce000004` | ligado |
| 00:14.4 | glue/bpcie `0x90db` | `0x0546` | `0xc8000004` | ligado |

**Memory Space Enable está LIGADO na GBE** (bit 1 setado em `0x0542`) — ela decodifica a BAR0 de verdade. Hipótese descartada: os zeros vêm mesmo do MAC core sem clock. Todas as leituras de BAR0 continuam válidas.

**Única diferença de config encontrada:** a GBE é a única com **Bus Master Enable (bit 2) desligado** — `0x0542` vs `0x0546` dos outros três. Isso é consequência esperada do probe ter falhado (`pci_set_master()` nunca chegou a rodar), e **não explica** os zeros: o BME controla o dispositivo iniciar DMA, não a resposta dele como alvo de leitura MMIO. Registrar como observação, não como pista de power-on. O `status` de todos os quatro é idêntico (`0x4010`).

**Observação adicional:** o dmesg desta baseline ainda mostra `resource sanity check: requesting [mem 0xc2000000-0xc2003fff], which spans more than 0000:00:14.1 [mem 0xc2000000-0xc2000fff]` — ou seja, o kernel `20260720-sky2len-fix` em uso **não tem** a correção de `pci_resource_len()` ativa, apesar do nome da tag. Discrepância com o que `sessao-2026-07-20-bpcie-clock-init.md` afirma; não é bloqueador (o chip id está dentro dos primeiros 0x1000), mas o nome da tag engana.
