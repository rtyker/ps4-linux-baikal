---
name: GBE-VIVA-driver-errado-mts-nao-sky2
description: A GBE Baikal NUNCA esteve desalimentada — está viva e respondendo. O problema é driver errado: é um MTS (if_mts.c), não um Marvell Yukon/sky2.
metadata:
  type: project
---

# ⛔ DESCOBERTA QUE DERRUBA A PREMISSA CENTRAL DO PROJETO (2026-07-22)

**A GBE Baikal nunca esteve sem energia nem clock-gated.** Ela está viva, alimentada e respondendo com dados estruturados. Todo o esforço de "achar quem liga a rail da GBE" — que consumiu várias sessões — perseguia um problema que não existe.

## A prova

Leitura ao vivo da BAR0 da GBE (`0xc2000000`, função `00:14.1`, baseline `20260720-sky2len-fix`):

```
0x00: 79498100 00000000 0f597c00 03b0030c
0x10: 00000085 00002ccc 443f695f 00032079
0x20: 00000000 00000000 00000000 0000ff00
0x30: 00010100 00000000 00000000 10000f70
```

No SQLite, de varreduras anteriores: **36 registradores não-zerados** de 388 lidos nessa BAR (`0xc2000000`, `0xc2000008`, `0xc200000c`, `0xc2000010`, `0xc2000014`, `0xc2000018`, `0xc200001c`, `0xc200002c`, `0xc2000030`, `0xc200003c`, `0xc2000040`, `0xc2000044`, `0xc2000048`, `0xc2000050`, `0xc2000054`, `0xc200005c`, `0xc2000064`, ...). Esses dados sempre estiveram no banco — nunca foram cruzados com a hipótese de "MAC morto".

Além disso, `0xc2000118` leu `0x0000000c` agora, tendo lido `0x00000000` mais cedo na mesma sessão: é registrador **vivo e mutável**, não silício morto.

## A causa raiz real: driver errado

O kernel Orbis 12.52 usa **drivers diferentes** para a GBE de cada geração de southbridge — confirmado por strings no dump (`kmem_dump_1252.bin`):

| string (offset no dump) | driver | southbridge |
|---|---|---|
| `0x7a4907` "Aeolia GBE controller" | `msk`/`mskc` (Marvell Yukon) | Aeolia |
| `0x7a491d` "Belize GBE controller" | `msk`/`mskc` (Marvell Yukon) | Belize |
| `0x7bdbac` **"Baikal GBE controller"** | **`mts`/`mtsc_pci`** | **Baikal (PS4 Pro)** |

O driver Baikal vem de `W:\Build\J02690760\sys\freebsd\sys\dev\mts\if_mts.c` — arquivo, nome e register map completamente distintos do `msk` (que é o equivalente FreeBSD do `sky2` do Linux).

**Portanto: a GBE do Baikal NÃO é um Marvell Yukon 2.** O `sky2` lê o offset `0x11b` esperando `B2_CHIP_ID`, encontra o que quer que o MTS tenha ali (`0x00`), e aborta com `unsupported chip type 0x0` / `error -95`. O hardware respondeu o tempo todo — só que num register map que o `sky2` não conhece.

Isso também explica, sem precisar de nenhuma teoria de power-gating:
- por que a BAR0 tem 4 KB no Baikal e o `sky2` esperava 16 KB (`ioremap` de `0x4000` → `resource sanity check`) — **register maps diferentes**;
- por que nenhuma tentativa de reset/hold/pulse/ICC/efuse mudou nada — não havia nada para ligar;
- por que o efuse já indicava GBE válida (bits 23/31 setados em `0xc900c06c`).

## Arquitetura real do MTS (strings do dump, `0x7bdb00`+)

- kthreads: `gbe:ctrl`, `gbe:phy`, `gbe:phy_ctrl`, `gbe:rmu`
- classes: `SceGbeMtsCtrl`, `SceGbeMtsPhyCtrl`
- **L2 switch integrado** — string `"L2 switch has been reset."`
- **duas portas**: `gbe0.1` → `eth0` e `gbe0.2` → `dbg0`
- PHY por **SMI Clause 45** (`smi_cl45_read`/`smi_cl45_write`, com timeouts próprios), não o MDIO Clause 22 do Yukon
- interrupções próprias: `LSO_FIFO_EMPTY`, `LSO_PRO_ERR`, `RX_AXI_ERR`, `IP_CKS`, `TCP_CKS`, `UDP_CKS`, `RX_PCODE` — nomenclatura AXI, típica de IP integrado em SoC, não de NIC PCIe Marvell

## O que fica INVALIDADO

- [baikal-gbe-e-sky2-nao-stmmac](baikal-gbe-e-sky2-nao-stmmac.md): a conclusão "sky2 é o driver CORRETO" está **refutada**. A parte que continua válida é a refutação do `stmmac` (aquele realmente dava Oops). O acerto foi descartar stmmac; o erro foi assumir que Yukon/sky2 era a alternativa certa só porque o fork já tinha `sky2` para Aeolia/Belize e o PCI ID era vizinho.
- Toda a linha "GBE desalimentada / rail off / syscon devpm gbe off / power-on via SAMU/bootloader/ICC" — **não há evidência de que exista tal bloqueio**. A evidência que a sustentava era o `chip id 0x0`, que agora se sabe ser leitura de um offset sem significado nesse hardware.
- Os testes de hold/pulse, ICC major 5, efuse, PCI COMMAND desta sessão: todos deram "sem efeito" **porque não havia o que ligar**, não porque o método estava errado.

## Mapeamento COMPLETO da BAR0 — 100% (Fase 13, 2026-07-22)

Feito por `harness_gbe_bar0_full_map.py`: **1024/1024 dwords** (`0x000`–`0xFFC`, os 4 KB inteiros do BAR), 3 passadas para classificar volatilidade. Zero falhas de leitura, console estável. Gravado na tabela nova `bar0_register_map` e espelhado em `hardware_registers` (nomes `BAR0_MTS_XXX`).

| classificação | qtd |
|---|---|
| estáveis não-zero (config/ID/capability) | **30** |
| estáveis zero | 982 |
| **voláteis** | **12** |

Toda a metade alta (`0x300`–`0xFFC`) é zero — o register map útil está concentrado em `0x000`–`0x2FF`.

### ⭐ O clock do MAC: `0x7c = 0x017D7840 = 25.000.000 = 25 MHz`

Prova direta e definitiva de que **o MAC está clocado e rodando**. Encerra qualquer resquício da teoria de clock/power-gating. (Nota histórica: a menção a "25 MHz" existia na análise antiga do `dc5a0c80`, que foi corretamente descartada como decompilação inválida — mas o *valor* estava certo; aqui ele aparece medido no hardware real.)

### Os 12 voláteis são contadores CLEAR-ON-READ

Todos leram não-zero na passada 1 e **zero nas passadas 2 e 3** — assinatura clássica de contador de estatística que zera na leitura:

| offset | valor na 1ª leitura | decimal |
|---|---|---|
| `0x100` | `0000022a` | 554 |
| `0x104` | `00046b80` | 289.664 |
| `0x110` | `00000006` | 6 |
| `0x128` | `000001f8` | 504 |
| `0x12c` | `0000f60d` | 62.989 |
| `0x1d8` | `00000049` | 73 |
| `0x1dc` | `00000228` | 552 |
| `0x1e4` | `00000002` | 2 |
| `0x1ec` | `000001ce` | 462 |
| `0x1f0` | `00000028` | 40 |
| `0x1f4` | `00000002` | 2 |
| `0x218` | `0000002e` | 46 |

**Os pares saltam aos olhos:** `0x100`/`0x104` = 554 pacotes / 289.664 bytes (≈523 B/pacote) e `0x128`/`0x12c` = 504 pacotes / 62.989 bytes (≈125 B/pacote). São contadores de pacotes + bytes, quase certamente RX e TX — ou as duas portas do switch L2 (`gbe0.1`/`gbe0.2`).

**Consequência:** o MAC não só está ligado — ele **processou tráfego real** desde o boot. Silício desalimentado não conta 554 pacotes.

### Os 30 estáveis não-zero (candidatos a config/ID)

`0x00`=`79498100` · `0x08`=`0f597c00` · `0x0c`=`03b0030c` · `0x10`=`00000085` · `0x14`=`00002ccc` · `0x18`=`443f695f` · `0x1c`=`00032079` · `0x2c`=`0000ff00` · `0x30`=`00010100` · **`0x3c`=`10000f70` · `0x40`=`100042a0` · `0x44`=`10000000` · `0x48`=`10004000`** (grupo com padrão `0x10xxxxxx`) · `0x50`=`00000002` · `0x54`=`00001018` · `0x5c`=`00100054` · `0x64`=`a0000200` · `0x70`=`00014000` · `0x74`=`00002277` · **`0x7c`=`017d7840` (25 MHz)** · `0x80`=`000002bb` · `0x98`=`00000002` · `0x9c`=`0000006f` · `0xac`=`00000009` · `0xb0`=`001f03ff` · `0xb4`=`001fffff` (os dois últimos com cara de máscara) · `0x1c8`=`00a00000` · `0x1d4`/`0x208`/`0x210`=`00000001`.

## ✅ MARCO — o MAC responde ao enable `BAR0+0x34`/`0x38` (Fase 14 REAL, 2026-07-22)

Primeiro teste de escrita **de fato executado** nesta investigação (os anteriores usavam `devmem`, que não existe — ver [devmem-nao-existe-usar-dd-octal](devmem-nao-existe-usar-dd-octal.md)). Escritas confirmadas pelo `dd` (`records out=1+0`, `4 bytes copied`, `exit=0`), replicando a rotina "up" do Orbis (`dc5a31f0`: `0x34 |= 1`, `0x38 |= 1`).

**Sem Bus Master e sem rebind do sky2** — ambos descartados por medição prévia.

Resposta do hardware, medida por diff completo dos 1024 dwords contra o baseline da Fase 13:

| offset | antes | depois | leitura |
|---|---|---|---|
| `0x38` | `00000000` | **`00000008`** | escrevemos `1`, leu `8` — status do hardware, não eco |
| `0x40` | `100042a0` | `100043c0` | avançou `0x120` |
| `0x50` | `00000002` | `00000042` | bit 6 setado |
| `0x5c` | `00100054` | `00101000` | mudou |
| `0x70` | `00014000` | `00014003` | bits 0 e 1 setados |

Total: 12 dwords mudaram (6 fora dos voláteis conhecidos), **5 novos não-zero**, não-zero total 33 → 37. Console estável o tempo todo (ping + telnet).

Escrever em `0x34`/`0x38` alterou **outros** registradores em cadeia — comportamento incompatível com registrador ignorado. Verificação de acompanhamento (4 leituras em 6s): o novo estado é **persistente e estável**, não transiente.

**Conclusão sustentada por dado:** `BAR0+0x34`/`0x38` são de fato o enable dos MAC cores, como a decompilação indicava. `0x34` não retém o valor escrito (lê 0), mas produz efeito — semântica de trigger, com o status aparecendo em `0x38`/`0x50`/`0x70`.

**O que isto NÃO significa:** ainda não há `eth0` (esperado — depende de driver), e não foi demonstrado que o MAC está funcionalmente operante nem que passa tráfego. Os contadores clear-on-read leem zero porque as próprias varreduras os zeraram e não houve tráfego novo na janela de segundos.

## Como aplicar (próximo passo real)

Parar de tratar isso como problema de energia e tratar como o que é: **falta um driver**. O caminho é escrever/portar um driver `mts` para Linux a partir da RE do `if_mts.c` do Orbis — o dump já está em mãos e já existem artefatos decompilados (`mts_attach_dc5a34f0.txt`, `mtsc_pci_attach_asm.txt`, além da rotina de calibração de PHY `dc5a0ba0` já mapeada em `consolidado/RE_KERNEL_GBE_ATTACH.md`).

Antes de escrever código, mapear pela RE: register map da BAR0 (4 KB), sequência de init do `mtsc_pci_attach`, acesso SMI CL45 ao PHY, configuração do L2 switch e das duas portas, e o layout dos descritores DMA de RX/TX.

**Regra prática que emerge disso:** antes de aceitar "o hardware está morto/desalimentado" a partir de UM registrador lendo zero, varrer a BAR inteira e cruzar com o que já está no SQLite. Os 36 registradores vivos estavam gravados no banco desde as varreduras da Fase 6 — a conclusão errada sobreviveu sessões inteiras porque ninguém confrontou a hipótese com os dados já coletados.
