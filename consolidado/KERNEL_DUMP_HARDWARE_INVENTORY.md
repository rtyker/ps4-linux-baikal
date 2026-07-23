# Inventário de Hardware — Kernel Orbis 12.52 Descriptografado

Extraído em 2026-07-20 de `consolidado/dumps_orbis/kmem_dump_1252.bin` (32.2MB, dump completo e descriptografado do kernel Orbis via TCP). Este documento é uma referência ampla para futuros ajustes de hardware (não só GBE) — complementa `consolidado/BAIKAL_HARDWARE_DISCOVERIES.md` (achados já confirmados) e `consolidado/RE_KERNEL_GBE_ATTACH.md` (RE detalhada do driver GBE).

## Ferramentas e metodologia
- `radare2` + plugin `r2ghidra` (ambos instalados via `pacman` nesta sessão — não vinham no ambiente).
- Extração de strings completa: `r2 -q -c "izz" kmem_dump_1252.bin` (324k linhas brutas).
- `baddr` do dump (base virtual do kernel no momento da captura) = `0xffffffffdc350000` — **muda a cada boot (KASLR)**, sempre reconfirmar com `r2 -q -c "i" arquivo.bin` antes de reusar qualquer endereço absoluto listado aqui ou em `RE_KERNEL_GBE_ATTACH.md`.
- Árvore completa de 588 arquivos-fonte do kernel (extraída dos caminhos `W:\Build\J02690760\...` embutidos em asserts/panics) salva em `consolidado/dumps_orbis/kernel_source_tree.txt`.

## 1. Drivers do South Bridge Sony (`dev\scesb\*`) — mapa completo
```
dev\scesb\dmac\dmac_mtk.c        — DMA controller (variante "mtk")
dev\scesb\dmac\dmac_mvl.c        — DMA controller (variante "mvl" = Marvell?)
dev\scesb\emc_timer\emc_timer_mtk.c
dev\scesb\emc_timer\emc_timer_mvl.c
dev\scesb\emc_timer\timer_common.c
dev\scesb\icc\icc.c              — núcleo do protocolo ICC (handshake, envio/recebimento)
dev\scesb\icc\icc_buttons.c      — botões físicos (power/reset/eject)
dev\scesb\icc\icc_device_power.c — power de wlan/bt/usb/hdd/bd (só esses 4 — GBE NÃO está aqui, confirmado)
dev\scesb\icc\icc_notification.c — despacho de notificações assíncronas
dev\scesb\icc\icc_nvs.c          — NVS (config persistente no Syscon)
dev\scesb\icc\icc_power.c        — shutdown/reboot DO SISTEMA (major 4). ⚠️ NÃO tem relação com a GBE — ver seção 9 (a alegação anterior vinha de leitura errada de string)
dev\scesb\icc\icc_sc_fw_update.c — atualização de firmware do Syscon
dev\scesb\icc\icc_snvs.c         — secure NVS
dev\scesb\icc\icc_thermal.c      — sensores térmicos via ICC
dev\scesb\rtc\rtc.c, rtc_mtk.c, rtc_mvl.c
dev\scesb\sbram\sbram.c          — SBRAM (RAM de backup/scratch do Syscon)
dev\scesb\sflash\sflash.c, sflash_mtk.c, sflash_mvl.c — NOR flash
dev\scesb\twsi\twsi.c            — I2C/TWSI (provável barramento do EDID/HDMI)
```
**Padrão `_mtk`/`_mvl`:** aparece em `dmac`, `emc_timer`, `rtc`, `sflash` — duas gerações de IP core (**MediaTek** e **Marvell**) selecionadas em build-time; **o Baikal é a família `_mvl`**. ⚠️ Correção 2026-07-21: não existe arquivo `gbe*.c` no `scesb` porque o driver da GBE **tem arquivo próprio, fora dessa árvore**: `dev\mts\if_mts.c` (e o Yukon-2 padrão do FreeBSD em `dev\msk\if_msk.c`). A afirmação anterior de que "a lógica está dentro de `icc_power.c`" está refutada — ver seção 9.

## 2. Outros drivers PCI/hardware relevantes
```
dev\pci\baikal_pcie.c   — driver PCIe do glue Baikal (correlato direto do nosso ps4-bpcie.c no Linux)
dev\pci\pci.c           — PCI genérico FreeBSD
dev\ahci\ahci.c         — SATA (genérico FreeBSD, sem customização visível no path)
dev\usb\controller\xhci.c, usb_controller.c — USB 3.0
dev\acpica\*            — ACPI genérico (bateria/térmico/CPU — pouco relevante, PS4 não tem bateria real mas reusa a árvore)
```
`baikal_pcie.c` é o candidato mais forte pra próxima RE se a pista do ICC major 4/minor 0x38 não fechar o caso — é o driver que originalmente configura as janelas de BAR/IRQ do barramento Baikal, correlato direto do que already existe como `ps4-bpcie.c` no fork Linux.

## 3. Classes de dispositivo/serviço (`Sce*`) relevantes a hardware
(Lista completa tem ~250 nomes, maioria é serviço de userland sem relação com bring-up de hardware Linux. Filtrado só o relevante:)
```
SceGbeMskCtrl      — GBE Aeolia/Belize (Marvell Yukon, já suportado em forks antigos)
SceGbeMtsCtrl       — GBE Baikal (MAC controller) — nosso alvo atual
SceGbeMtsPhyCtrl    — GBE Baikal (PHY controller) — par do MAC, ciclo de power separado (RE confirmada)
SceBtDriver         — Bluetooth
SceUsbus0/1/2       — instâncias USB
SceXhci0/1/2        — instâncias xHCI (associadas às usbus acima)
SceHmd*, Scehmddfu* — VR headset PSVR (câmera/DFU) — fora de escopo, mas hardware real presente no barramento
SceAcpiThermal, SceIccThermal — sensores térmicos (bate com `icc_thermal.c`)
SceSbram, SceSflash — NOR flash / SBRAM
SceUart             — UART (debug serial — relevante se algum dia quisermos log via serial real)
SceRegMgrHdd, SceRegmgrHddsync — registro/config do HDD interno
```

## 4. Kernel threads nomeados `algo:algo` (relevantes a hardware)
```
gbe:ctrl, gbe:phy, gbe:phy_ctrl, gbe:rmu, gbe:mdelay   — GBE (já mapeados)
mts:mdelay                                              — "MTS" = provável nome interno da geração Baikal do GBE (Gbe**Mts**Ctrl) — thread de delay dedicada, separada de gbe:mdelay
netabort:mdelay                                         — thread de timeout de abort de rede — pode ser relevante a debugging de link down
wlan:*                                                   — WiFi (já suportado, sem novidade)
sbl:cryptmgr                                             — gerenciador de criptografia (Secure Boot Loader) — não relevante a hardware bring-up
i5:tp, tj:l8                                             — não identificados, nomes curtos demais pra inferir
```

## 5. Dispositivos `/dev/*` relevantes
```
/dev/sbram, /dev/sflash, /dev/sflash0s0, /dev/sflash0s0x0, /dev/sflash0s0x32(b)
/dev/sflash0s1.crypt, .cryptx1, .cryptx2(b), .cryptx3(9,b), .cryptx40   — múltiplas partições cifradas da CoreOS na NOR
/dev/da0, /dev/da0x4b/.../da0x15.crypt, da0x6, da0x6x0/1/2   — HDD interno (SATA), partições GPT customizadas cifradas
/dev/notification, /dev/notification%d
```
Confirma o que já sabíamos do HDD interno (até partição 27 via GPT) e localiza exatamente quais partições da NOR/HDD são cifradas por padrão (`.crypt*`) — útil se algum dia quisermos montar algo do HDD interno real a partir do Linux.

## 6. Achados de RE já aplicáveis (ver `RE_KERNEL_GBE_ATTACH.md` para detalhe completo)
- Comando ICC **major=0x04, minor=0x38** — usado pelo attach() da GBE para esperar/consultar estado (candidato a testar via `/proc/ps4_icc`, nunca testado ao vivo antes — só major 5 foi testado e descartado).
- Existe uma função `icc_query(major, minor, len, buf)` genérica no kernel (`0xffffffffdc3f5bd0` neste dump específico) usada por múltiplos subsistemas — vale extrair TODOS os pares major/minor usados nela em uma sessão futura (não feito ainda, ver seção "Próximos passos" do RE doc).
- O protocolo ICC aceita minor de até 16 bits no request (campo `u16`), não necessariamente 8 bits como testamos ao vivo — vale revisar antes de descartar minors > 0xFF como "fora do espaço válido".

## 7. `icc_device_power.c` decompilado — RESOLVE O TODO ANTIGO (2026-07-21)

Este era o item pendente listado há sessões ("RE de fato, não só strings, de `icc_device_power_control` — confirmar por RE se existe um minor específico pra GBE no major 5"). **Feito. Resposta: NÃO EXISTE.**

**Os dois wrappers do serviço (major=5), decompilados:**
| Função | Papel | Layout da mensagem ICC |
|---|---|---|
| `0xffffffffdc7c8a70` | **SET** `(minor, valor, &out16)` | `msg[1]=5` (major), `msg[2]=minor` (u16), `msg[8]=0x20` (len), `msg[0xc]=valor` |
| `0xffffffffdc7c8fb0` | **GET** `(minor, &out8)` | idem, sem payload; resultado lido de `msg[0xa]` |

Confirma que **o major vai no offset 1 e o minor é u16 no offset 2** — bate com `bpcie_icc_cmd(5, 0x11, ...)` do nosso driver Linux.

**Enumeração exaustiva dos minors** (via xrefs dos dois wrappers + leitura do `mov edi, <minor>` em cada call site):
- SET usados: `0x10`, `0x20`, `0x30`
- GET usados: `0x01`, `0x11`, `0x21`, `0x31`

Ou seja, o serviço cobre **exatamente 4 domínios**, no padrão `0xN0` = SET / `0xN1` = GET:

| Domínio | SET | GET | Dispositivo | Como foi identificado |
|---|---|---|---|---|
| 0 | `0x00` | `0x01` | WLAN/BT | `bpcie_icc_cmd(5, 0, &on=3)` no Linux + `kern.wlanbt()` no payload kexec; confirmado ao vivo no teste #6 |
| 1 | `0x10` | `0x11` | USB | `resetUsbPort()` no nosso `ps4-bpcie-icc.c` |
| 2 | `0x20` | `0x21` | HDD | por eliminação |
| 3 | `0x30` | `0x31` | **Drive Blu-ray** | strings `icc_device_power_get_bd_power_state`, eventhandlers `bd_drive_operable`/`bd_drive_inoperable` na função `0xffffffffdc7c8b80` |

**➡️ CONCLUSÃO DEFINITIVA: não há minor `0x40` nem qualquer outro domínio. A GBE NÃO é gerenciada pelo `icc_device_power` (major 5).** Isso fecha por RE — não mais por tentativa e erro ao vivo — a linha inteira de testes de major 5 (testes #1, #2, #6 e a varredura de minors do `ICC_GBE_TEST_LOG.md`). O NAK que o teste #1 recebeu em `5 0x41` está explicado: esse minor simplesmente não existe.

## 8. Status de decompilação por driver (atualizar a cada sessão)

| Driver / fonte | Arquivos salvos | Status |
|---|---|---|
| `if_mts.c` (GBE `SceGbeMts*`) | `decompiled_dc5a*.txt`, `decompiled_dc5a0ba0_gbe_phy_calib.txt` | Cadeia principal mapeada (attach, ioctl up/down, init MAC/DMA, RMU, calibração de PHY) |
| `icc_device_power.c` | `decompiled/icc_device_power_main_dc7c8b80.txt`, `icc_devpower_set_dc7c8a70.txt`, `icc_devpower_get_dc7c8fb0.txt` | **Completo** — 4 domínios enumerados, sem GBE |
| `baikal_pcie.c` / glue | `decompiled_baikal_pcie_attach.txt`, `decompiled_dc7190d0.txt`, `decompiled/baikal_glue_block_reset_dc6df.txt`, `decompiled/baikal_glue_write_dc718710.txt` | **Hold/pulse da GBE ENCONTRADO** (bloco `0x2000`, hold `0x20`, pulse `0x74`) — ver `GBE_ACTION_PLAN.md` seção 4 |
| `ahci.c` (SATA PHY init Orbis) | `decompiled/baikal_sata_phy_init_dc72bfb0.txt` | Completo — é a fonte original do nosso `bpcie_baikal_sata_phy_init()` |
| USB PHY init (Orbis) | `decompiled/baikal_usb_phy_init_dc7db0b0.txt` | Completo |
| `icc_power.c` | `decompiled/icc_power_dc528760.txt` | **Completo** — é shutdown de sistema (major 4), NÃO energia de periférico; ver seção 9 |
| `if_msk.c` (GBE Aeolia/Belize) | `decompiled/msk_dc4cdee0.txt`, `decompiled/msk_attach_dc4cdfc0.txt` | **Parcial** — probe decompilada e confirmada (Aeolia/Belize apenas); attach ainda não localizado. Ver `RE_IF_MSK.md` |
| `icc_notification.c` | — | Pendente — handler assíncrono do Syscon |
| `twsi.c` (I2C) | — | Pendente — candidato a controle de rails de energia |
| `dmac_mvl.c`, `emc_timer_mvl.c`, `rtc_mvl.c`, `sflash_mvl.c` | — | Pendente (nota: sufixo `_mvl` = Marvell = nossa família Baikal; `_mtk` = MediaTek = outra geração) |
| `scenb/dct.c`, `scenb/sbi.c` | — | Pendente — northbridge |
| `ahci.c`, `sdhci.c`, `xhci.c` | — | Pendente (baixa prioridade: já funcionam no Linux) |

## 9. `icc_power.c` decompilado (2026-07-21) — é SHUTDOWN DE SISTEMA, não energia de periférico

`icc_power.c` tem **uma única** referência em todo o kernel (a string do arquivo aparece 1 vez, usada por 1 função: o init em `0xffffffffdc528600`). Decompilado em `decompiled/icc_power_dc528760.txt`.

O que o init faz:
1. Registra 5 hooks de shutdown do FreeBSD — os nomes das funções não deixam dúvida:
   | Evento | Handler | Timeout |
   |---|---|---|
   | `shutdown_pre_sync` | `icc_power_shutdown_pre_sync` | — |
   | `shutdown_post_sync` | `icc_power_shutdown_post_sync` | — |
   | `shutdown_final` | `icc_power_shutdown_final` | 20000 |
   | `shutdown_force` | `icc_power_shutdown_final` | 20000 |
   | `icc_available` | `init_last_shutdown_cause` | 10000 |
2. Registra um handler de **notificação ICC assíncrona para o major 4** (`fcn.ffffffffdc797f00(4, 0, handler, 0)`).
3. Envia `major=4, minor=4, payload=1` como anúncio de inicialização.

**➡️ `icc_power.c` = serviço de energia DO SISTEMA (desligar/reiniciar/causa do último shutdown), major 4.** Bate com o nosso `ps4-apcie-icc.c`, que já usa `major=4, minor=1` em `icc_shutdown()`/`icc_reboot()`. **Não tem absolutamente nada a ver com ligar rails de periféricos.**

### ⚠️ CORREÇÃO: a afirmação "o attach da GBE usa locks do `icc_power.c`" é FALSA
`RE_KERNEL_GBE_ATTACH.md` afirmava (item 9 da análise do attach, e de novo na seção do `SceGbeMtsPhyCtrl`) que os locks dentro do attach da GBE citavam `icc_power.c` nas linhas 2127/2130/2133, e concluía: *"reforçando que a GBE Baikal depende do `icc_power`"*. **Isso foi um erro de leitura da string.** Verificado: a string passada aos locks no attach é `0xffffffffdcb0dc47` = **`sys\dev\mts\if_mts.c`** — o próprio arquivo do driver da GBE, o que é o comportamento normal e não carrega informação nenhuma. A string de `icc_power.c` fica em `0xffffffffdcb0025b`, endereço completamente diferente, e **não é referenciada em ponto algum do código da GBE**. Desassemblando o attach (`pD 0x300 @ 0xffffffffdc5a41d0`), a única string citada na região é `gbe_ctrl` (nome de kthread).

### ➡️ CONCLUSÃO COMBINADA (seções 7 + 9): o ICC não controla a energia da GBE, ponto final
Os dois — e únicos — serviços ICC candidatos foram agora enumerados exaustivamente por RE:
- **`icc_device_power.c` (major 5):** exatamente 4 domínios (WLAN/BT, USB, HDD, Blu-ray). Sem GBE.
- **`icc_power.c` (major 4):** shutdown/reboot do sistema. Sem periféricos.

**Portanto: nenhuma sequência de comandos ICC vai ligar a GBE.** Toda a família de testes ICC do `ICC_GBE_TEST_LOG.md` (#1 a #6) está encerrada por prova estática, não por tentativa e erro. O controle da GBE é necessariamente **MMIO via glue (BAR2/BAR4)** — que é onde a investigação deve continuar.

## 10. ACHADO ESTRUTURAL (2026-07-21): a GBE do PS4 é MAC + **L2 switch** + PHY

Descoberto ao listar a tabela de strings do `if_msk.c`. **Os dois** drivers de GBE — `msk` (Aeolia/Belize) e `mts` (Baikal) — contêm o mesmo conjunto:

- `gbe0.1` → **`eth0`** (porta LAN física)
- `gbe0.2` → **`dbg0`** (porta de depuração)
- `L2 switch has been reset.`
- kthread `gbe:rmu`

E só no `msk`: `switch_rmu_reg_read`/`_write`/`_exec`/`_get_id`, `Switch ID = 0x%04x`, `VTU Busy` (VLAN Table Unit), `%s: no response from L2 Switch`.

**O subsistema de rede é `MAC Yukon → L2 switch Marvell → PHY`**, com o switch gerenciado **in-band via RMU** (comandos como quadros Ethernet pelo caminho de DMA, não por MMIO). Isso explica retroativamente o mecanismo de `fcn.dc5a58d0` já mapeado em `RE_KERNEL_GBE_ATTACH.md` (mbuf + TX + espera de contador de resposta, magic `0xfa42`): **aquilo é conversa com o L2 switch**, não com o MAC.

O `sky2` do Linux não tem nenhuma noção de switch L2, RMU, VTU ou porta `dbg0`. Em Aeolia/Belize isso não impede o MAC de funcionar. **Não está estabelecido** que seja a causa da falha no Baikal — o `B2_CHIP_ID = 00` é anterior a qualquer questão de switch. Registrado como contexto arquitetural que faltava, não como causa. Detalhe: `RE_IF_MSK.md`.

### Achados soltos da varredura de strings (2026-07-21) — anotados para não se perderem
- **`intr_event_handle_baikal_wa`** — existe uma rotina de *workaround* de tratamento de interrupção **específica do Baikal** no kernel Orbis. Nosso `ps4-bpcie.c` tem o `bpcie_handle_edge_irq()` com demux manual por subfunção; vale comparar se o `wa` da Sony trata algum caso que não replicamos.
- **`if_msk.c` coexiste com `if_mts.c`** — o kernel traz tanto o driver Yukon-2 padrão do FreeBSD (`msk`) quanto o customizado da Sony (`mts`, o `SceGbeMts*` que viemos analisando). Como `msk` é o ancestral direto do `sky2` do Linux, comparar o attach dos dois é o caminho mais barato para descobrir o que o `sky2` deixa de fazer.
- **Sufixos `_mvl` vs `_mtk`** nos drivers do southbridge (`dmac`, `emc_timer`, `rtc`, `sflash`): **Marvell** e **MediaTek**. O Baikal é a família **`_mvl`** (consistente com a GBE ser um Marvell Yukon). Ao ler qualquer um desses drivers, usar sempre a variante `_mvl` — a `_mtk` é de outra geração de console.
- **`Baikal Func 4 BAR 2`** aparece como string de recurso — confirma a nomenclatura de BARs usada pela Sony e que a func 4 (glue) é quem publica a BAR2 pervasive.

## Ferramenta obrigatória antes de decompilar: `tools/re_find_func.sh`

**Nunca chame `pdg` direto num endereço sem validar que ele é início de função.** O r2ghidra decompila qualquer endereço sem reclamar e produz pseudo-código plausível porém falso — foi exatamente assim que nasceu o arquivo inválido `decompiled_dc5a0c80.txt` (endereço no meio de uma instrução), que gerou uma "descoberta" inteira depois refutada.

```bash
consolidado/tools/re_find_func.sh dumps_orbis/kmem_dump_1252.bin 0xVADDR [saida.txt]
```
Resolve o início real da função (trata funções sem `push rbp` via detecção de alvo de CALL), imprime tamanho/blocos e avisa se a saída contiver marcadores de decompilação inválida (`unaff_*`, `in_RAX`).

## Como continuar a extração no futuro
```bash
cd consolidado/dumps_orbis
r2 -q -c "i" kmem_dump_1252.bin                    # confirmar baddr antes de reusar qualquer endereço
r2 -q -c "izz" kmem_dump_1252.bin > strings.txt     # strings completas (~324k linhas, grep pontual)
r2 -q -c "/r 0xVADDR" kmem_dump_1252.bin            # achar quem referencia um endereço/string
../tools/re_find_func.sh kmem_dump_1252.bin 0xVADDR saida.txt   # decompilar com validação (preferir a pdg direto)
```
Árvore completa de source paths: `consolidado/dumps_orbis/kernel_source_tree.txt` (588 arquivos).

**Truque útil para enumerar constantes de um serviço:** achar os xrefs de CALL para a função wrapper e ler o `mov edi, <const>` imediatamente anterior a cada call — foi assim que os 4 minors do `icc_device_power` foram enumerados sem precisar decompilar cada chamador.
