# `mts` — driver da Gigabit Ethernet do southbridge Baikal (PS4 Pro)

**Este README é a fonte única sobre o driver MTS.** Tudo que era espalhado por
`consolidado/`, `docs/` e memórias de sessão sobre a GBE do Baikal está resumido e
indexado aqui. Documentos de dados brutos (RE, logs de teste) continuam em
`../../../outros/` e são linkados na seção [Onde está o resto](#onde-está-o-resto).

| | |
|---|---|
| **Arquivo** | `mts.c` (~2993 linhas) + `mts.h` |
| **Módulo** | `mts.ko`, `CONFIG_MTS_GBE` (tristate, `depends on X86_PS4_BAIKAL`) |
| **Dispositivo** | PCI `104d:90d8` — Sony Baikal GBE, função `0000:00:14.1` |
| **Autor** | **código do projeto** (`rtyker`, commits desde 2026-07-23). Não é código Linux mainline nem cópia do driver FreeBSD do Orbis — é reimplementação em API Linux a partir de RE |
| **Licença** | `GPL-2.0` (SPDX no topo) |
| **Estado** | MAC/DMA funcionam, `eth0` sobe com MAC real; **PHY nunca estabelece link** |

---

## 1. TL;DR do estado (2026-07-30, `test_history` id 72)

| Camada | Estado | Evidência |
|---|---|---|
| Enumeração PCI (`0000:00:14.1`) | ✅ | `lspci`, driver `mts` carrega |
| MAC core power-on (ICC `major=4 minor=0x38`) | ✅ | `BAR0+0x004` vai de `0` para `0xb19` |
| MAC enable (`0x34`/`0x38`) | ✅ | one-shot por power cycle; stop/start validado |
| DMA TX (anel + doorbell) | ✅ ~95% | frames RMU in-band completam, `OWN` devolvido |
| MAC lido da SPM (endereço físico real) | ✅ | `2c:cc:44:3f:69:5f` |
| DMA RX | ❌ | anel sempre `OWN=1`, `MTS_CNT_PKTS=0`, nunca completa |
| IRQ real entregue | ❌ | `/proc/interrupts` `irq_count=0` com MSI e IMR desmascarados |
| MDIO Clause 22 (protocolo) | ✅ corrigido | bug de polaridade em `mts_mdio_wait_write()` |
| MDIO Clause 45 | ⚠️ | "sucede" mas devolve `0x0000` sempre |
| **PHY / link físico** | ❌ | `link=0`, `AN_complete=0`, `eth0` sempre `NO-CARRIER`, ping 100% perda |

**Conclusão registrada:** o bloqueador **não é software**. Não é MDIO (corrigido,
insuficiente sozinho), não é MSI mascarado em hardware, não é IMR, não é demux de
IRQ no glue. O PHY simplesmente **nunca gera evento**. A hipótese final — PHY tem
domínio de energia separado (`SceGbeMtsPhyCtrl`) ligado pelo **firmware/bootloader
Sony antes do kernel**, fora do alcance de MDIO/ICC/SAMU/RMU — foi fechada em
2026-07-30 com RE completa. Detalhes: [`PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md).

---

## 2. Por que não usar `sky2` (identidade do hardware)

O Orbis tem **dois drivers de GBE diferentes**:

| Silício | Driver Orbis | Equivalente Linux |
|---|---|---|
| Aeolia / Belize | `msk` / `mskc` (Marvell Yukon) | `sky2` |
| **Baikal (PS4 Pro)** | **`mts` / `mtsc_pci`** (`sys/dev/mts/if_mts.c`) | **`mts` (este)** |

São silícios distintos. O `sky2` lê `B2_CHIP_ID` em `BAR0+0x11b`, encontra `0x00`
no MTS e aborta com `unsupported chip type 0x0`. Forçar o `sky2` a dar probe nesse
dispositivo **congelou o barramento PCIe e o vídeo** (patch `sky2-baikal-gbe.patch`,
banido desde 2026-07-22 — ver [`../../AGENTS.md`](../../AGENTS.md)).

---

## 3. Arquivos desta pasta

| Arquivo | Papel |
|---|---|
| `mts.c` | o driver (fonte única editável) |
| `mts.h` | mapa de registradores da BAR0 + `struct mts_priv` |
| `Kconfig` / `Makefile` | `NET_VENDOR_SONY` / `MTS_GBE` → `mts.o` |
| `README.md` | este documento |
| `build/` | saída do build out-of-tree (`build/mts.ko`), gitignored |

> ⚠️ **Duas cópias, uma autoritativa — e o build agora verifica.**
> O `mts.c`/`mts.h` também existem **byte a byte** dentro de
> [`../patches/mts-baikal-gbe-driver.patch`](../patches/mts-baikal-gbe-driver.patch)
> (2993 + 185 linhas). O contrato do projeto ([`../../AGENTS.md`](../../AGENTS.md),
> "Idempotência de Alterações no Kernel") é: **o patch é a implementação
> autoritativa** (fonte única, applied via `git apply --check`); `drivers_mts/`
> é a **superfície de edição** — o build copia `drivers_mts/{mts.c,mts.h}` por
> cima da árvore depois de aplicar o patch.
>
> Para que a cópia não esconda uma edição esquecida, o `00-build-kernel-7.0.sh`
> agora compara os dois **logo após aplicar o patch** e **aborta com erro fatal**
> se divergirem (divergência = patch obsoleto). Ao editar o driver:
>
> 1. edite `drivers_mts/mts.c` (e/ou `mts.h`);
> 2. regenere o patch a partir da árvore limpa (comandos no erro do build e em
>    [`../../AGENTS.md`](../../AGENTS.md));
> 3. rebuild — o build confere a consistência sozinho.
>
> *(Alternativa estrutural — manter só `drivers_mts/` e reduzir o patch a
> `Kconfig`/`Makefile` — continua em aberto; mudá-la exige decisão explícita,
> porque o padrão "implementação dentro do patch" é o que a regra do projeto
> exige.)*

---

## 4. Build e deploy

### In-tree (build oficial do kernel)

`kernel/00-build-kernel-7.0.sh` aplica o patch do driver e copia `drivers_mts/{mts.c,mts.h}`
para `drivers/net/ethernet/sony/` da árvore; o `mts.ko` sai em `make modules`.
Nada a fazer além do build oficial.

### Out-of-tree (debug ao vivo, mais rápido)

```bash
# compila contra a árvore já construída -> drivers_mts/build/mts.ko
sudo ../../outros/scripts/build_mts_module.sh

# push via SSH (root/ps4 em 192.168.6.128, rede WiFi) + insmod stage=4
../../outros/scripts/deploy_mts.sh push

# configura eth0 192.168.0.2, ping -I eth0 192.168.0.1, coleta dmesg + mts_regs
../../outros/scripts/deploy_mts.sh test
```

`01-build-image-7.0.sh` também sobrescreve o `mts.ko` do rootfs com
`drivers_mts/build/mts.ko` **se ele existir** — ou seja, um `.ko` velho esquecido
ali vence o módulo do build oficial. Apague `build/` se não estiver testando.

---

## 5. Parâmetros do módulo

| Param | Default | Efeito |
|---|---|---|
| `stage` | `4` | escada de bring-up (§6) |
| `force_mac_reset` | `0` | roda a rotina de stop antes do init |
| `enable_carrier` | `1` | detecção de carrier/link |
| `enable_rx` | `1` | recepção ligada |
| `enable_tx` | `1` | transmissão ligada |
| `poll_interval_ms` | `10` | timer de polling (NAPI por software, já que a IRQ não chega) |
| `enable_phy_calib` | `1` | calibração PHY (Orbis `dc5a0ba0`) |
| `enable_phy_calib_table` | `1` | tabela indexada `0x1bc`–`0x1d4` (SAFE, 128 entradas) |
| `force_carrier` | `0` | força carrier ON para testar TX/RX via DMA |
| `irq_mask` | `0x0` | valor escrito em `BAR0+0x54` (IMR); `0` = tudo mascarado |
| `irq_storm_threshold_ms` | `0` | janela da guarda de tempestade de IRQ (`0` desliga) |
| `irq_storm_max_count` | `5000` | IRQs permitidas na janela antes de desligar a linha |
| `hold_val` | `0x1` | valor do hold da GBE (`0x180020`) / pulse (`0x180074`) |

Exemplo (o padrão do projeto é `stage=4`):

```bash
insmod /tmp/mts.ko stage=4 hold_val=0x10 enable_phy_calib_table=0
```

## 6. Escada de bring-up (`stage`)

Existe porque este hardware já congelou vídeo e travou boot em tentativas anteriores.
`pci_set_master()` só entra no **stage 4**, depois de os anéis apontarem para memória
do Linux (os anéis herdados do Orbis ficam em `0x10000000`/`0x10004000`, que o Linux
usa como System RAM).

| stage | O que faz |
|---|---|
| 0 | só probe: mapeia BAR0/glue, sem escrita |
| 1 | + dump de registradores e sonda MDIO |
| 2 | + `dma_set_mask_and_coherent(32 bits)`, aloca anéis e buffers, programa `0x3c/0x40/0x44/0x48` + `0x34/0x38`, cria os sysfs |
| 3 | + `mts_mac_enable()` e escreve a IMR (`0x54`) |
| 4 | + `pci_set_master()`, `bpcie_assign_irqs()`, `request_irq()`, MAC da SPM, `register_netdev()` |

---

## 7. Mapa do hardware

### BARs usados

| Região | Onde | Para quê |
|---|---|---|
| BAR0 (4 KB) | `0000:00:14.1` | registradores do MAC/MDIO/contadores |
| BAR2 (2 MB em `0xc8800000`) | glue `0000:00:14.4` | clock/reset: `0x10a030`, hold `0x180020`, pulse `0x180074` |
| BAR4 | glue `0000:00:14.4` | efuse de calibração do PHY (`bar4+0xC000+off`, mesmo padrão do SATA) |
| SPM (`resource 5` da função MEM) | `BPCIE_SPM_BP_BASE` | MAC address real (`ioremapped`, 6 bytes) |

⚠️ `BAR0` tem **4 KB** — mapear 16 KB (como o `sky2` fazia) gera
`resource sanity check ... spans more than 0000:00:14.1`. Use `pci_resource_len()`.

### Registradores da BAR0 (`mts.h`)

Procedência: `[RE]` = decompilação do Orbis 12.52; `[MEDIDO]` = varredura da BAR0 ao
vivo (1024/1024 dwords, 3 passadas, tabela `bar0_register_map` no SQLite); `[?]` =
desconhecido, **não escrever**.

| Offset | Macro | Notas |
|---|---|---|
| `0x00` | `MTS_MDIO` | comando/status MDIO; `0x8000` = clear busy / ready (half baixo) |
| `0x04` | `MTS_LINK_STATUS` | bit 0 = link, `[3:2]` = speed, bit 6 = full duplex |
| `0x10` | `REG_10` | `0x00000085`; bit 4 = carrier control (comutado no `trigger_phy_trigger` 2) — **cuidado: já causou tela preta fora de hora** |
| `0x14` | `REG_14` | `0x00002ccc` |
| `0x18` | `REG_18` | `0x443f695f` (pedaço do MAC) |
| `0x1c` | — | trigger do MAC/PHY: escrever `0x80000000`, poll do bit 17 (`0x20000`) |
| `0x30` | `REG_30` | `0x10100` |
| `0x34` | `MTS_MAC_EN1` | enable core 1 — **write-only** (lê 0), one-shot |
| `0x38` | `MTS_MAC_EN2` | enable core 2 — após enable lê `0x8` |
| `0x3c` | `TX_RING_PTR` | ponteiro corrente TX (hardware avança) |
| `0x40` | `RX_RING_PTR` | ponteiro corrente RX |
| `0x44` | `TX_RING_BASE` | base física do anel TX |
| `0x48` | `RX_RING_BASE` | base física do anel RX |
| `0x50` | `REG_50` | `0x02` → `0x42` após enable |
| `0x54` | `MTS_IMR` | máscara de interrupção |
| `0x5c` | `REG_5C` | `0x00100054` → `0x00101000` |
| `0x70` | `REG_70` | `0x00014000` → `0x00014003` |
| `0x74` | `REG_74` | `0x2277` |
| `0x7c` | `MTS_CLOCK` | `0x017d7840` = 25 MHz (MAC clocado) |
| `0xac` | `REG_AC` | `9` |
| `0x100/0x104` | `CNT_PKTS/BYTES` | estatísticas **clear-on-read** |
| `0x118` | — | `CHIP_ID` nos bytes `[1:0]` (`00 00` = power-gated; volátil, não usar como estado) |
| `0x128/0x12c` | `CNT_PKTS2/BYTES2` | idem |
| `0x140`–`0x200` | `PHY_*` | calibração do PHY (`0x200` **nunca** escrever) |

### Anéis DMA

| Item | Valor |
|---|---|
| Descritores | 256 por anel, 16 B cada → 4 KB por anel |
| Buffers RX | 256 × 1536 B (`0x600`) = 384 KB |
| Bits do descritor | `31` OWN, `30` WRAP, `29` SOP, `28` EOP, `[10:0]` tamanho |
| TX | `desc[0] = 0x80000000` (OWN=hw), `desc[+8] |= 0xffff0000` |
| RX | `desc[0] = 0x80000600`, `desc[+4] =` físico do buffer, último com WRAP |
| Ordem | anéis → `0x3c/0x44` → `0x40/0x48` → `0x34`/`0x38` → IMR → **só então** `pci_set_master()` |

---

## 8. MDIO

| Via | Como | Estado |
|---|---|---|
| Clause 45 | `MTS_MDIO` com fases `OP_ADDR` (`0x20`) / `OP_READ` (`0xe0`), timeout `10000` | retorna `0x0000` sempre |
| Clause 22 | `cmd = (phy<<9) | (reg<<5) | op`, op `0x02` read / `0x01` write, dados em `[31:16]` | **funciona** (após o fix de polaridade) |
| Packed (Orbis) | endereço empacotado (`0xa2001e`) via `mts_mdio_read_packed()` | usado pela thread `gbe_phy_ctrl` |

**Bug de polaridade (corrigido 2026-07-29/30):** `mts_mdio_wait_write()` esperava o
bit 15 **zerar**; o correto é esperar **setar**. Antes do fix o "sucesso" era dado
residual do barramento (valor latched da transação anterior), o que gerou o falso
positivo de "PHY ID Marvell `0x888103a2` confirmado" (2026-07-25). Depois do fix o
eco é limpo (`0x1000`).

---

## 9. Diagnóstico por sysfs

Criados no `stage >= 2` em `/sys/bus/pci/devices/0000:00:14.1/`:

| Atributo | O que mostra/ Faz |
|---|---|
| `mts_regs` (RO) | registradores-chave, contadores, descritores RX ao redor do `rx_idx`, hexdump dos buffers RX, linhas MDIO/Clause 22 |
| `trigger_rmu` (RW) | envia quadro RMU de 34 B: `1` = fase 1 (`cmd=0x0000`), `2` = fase 2 (`cmd=0x800b`), `3` = comuta bit 4 do `0x10`, `4` = sub-header `0x9807` |
| `trigger_pci` (RW) | relê estado PCI/`pci_set_master` sem reload |
| `trigger_loopback` (RW) | frame de loopback interno do MAC |
| `trigger_phy_trigger` (RW) | 1 = `0x1c = 0x80000000` + poll bit 17; 2 = comuta `0x10` bit 4; 3 = sequência completa Orbis; 4 = restart Clause 22 + AN (`0x1200`); 7 = força 10M FD; 9 = força link no `0x04`; 10 = dump Marvell 16–31; 11 = RGMII RX clock delay |
| `trigger_rx_clean` (RW) | roda o `mts_rx_clean()` sob demanda |

---

## 10. Histórico

### Linha do tempo (commits do driver)

| Data | Commit | Marco |
|---|---|---|
| 2026-07-22 | — | Bring-up ao vivo: `eth0` registrado, MAC real da SPM, DMA TX/RX alocados, vídeo OK ([`MARCO_HISTORICO_ETH0_MTS_BAIKAL.md`](MARCO_HISTORICO_ETH0_MTS_BAIKAL.md)) |
| 2026-07-23 | `d49f085` | `initial: mts.c driver source` |
| 2026-07-23 | `24ed74b` | MDIO Clause 22 como fallback |
| 2026-07-23 | `b90be75` | RX/TX ligados por padrão |
| 2026-07-23 | `ac02af6` | calibração glue 2 MB, safe table 128, link detection |
| 2026-07-23 | `20dd14b` | corrige reclamação TX e estatísticas |
| 2026-07-23 | `b449c0e`–`7c6bd01` | leituras PHY Clause 45 / BMCR ao vivo no sysfs |
| 2026-07-23 | `0a9e8a6` | `irq_mask` como param + guarda de IRQ storm + `irq_count` |
| 2026-07-23 | `ce145b8` | efuse de calibração lido do **BAR4** (era BAR2) |
| 2026-07-24 | `9aa9980` | consolida sessão RMU/PHY |
| 2026-07-29/30 | — | fix de polaridade MDIO Clause 22; RE completa de `gbe_phy_ctrl`; PHY declarado pré-kernel |
| 2026-08-01 | `f5f4efc` | fix idempotente no build (patch + fonte) |
| 2026-11-11 | `86c0d0d` | repo dividido em `kernel/` e `distro/`; driver isolado aqui |

### Implementação do Clause 22 (2026-07-23) — changelog absorvido

O antigo `CHANGES_CLAUSE22_2026-07-23.md` foi incorporado a esta seção (o texto
integral está no histórico do git). Resumo:

- adicionadas `MTS_MDIO_C22_OP_READ` (`0x02`) / `MTS_MDIO_C22_OP_WRITE` (`0x01`) e
  `mts_mdio_c22_read()` / `mts_mdio_c22_write()`, com formato
  `[12:9]=phy_addr`, `[8:5]=reg`, `[4:0]=opcode` e dados de escrita em `[31:16]`;
- adicionado diagnóstico automático no início de `mts_phy_calibration()` comparando
  Clause 45 × Clause 22;
- o _warning_ de compilação `mts_mdio_c22_write not used` era esperado na época;
- **desfecho:** as leituras que motivaram o trabalho (PHY ID `0x888103a2`, BMCR
  `0x1040`) foram **refutadas** em 2026-07-25 como dado residual do barramento
  (`test_history` id 70). O código de Clause 22 permaneceu e é útil; o que não se
  sustenta é a conclusão de "PHY identificado".

---

## 11. Testes ao vivo registrados

O histórico narrativo completo (o que valeu, o que foi refutado, por quê) está em
[`TESTES_HISTORICO.md`](TESTES_HISTORICO.md). A fonte estruturada é a tabela
`test_history` do `../../outros/rea/ps4_hardware_memory.db`
(consulta útil: `SELECT id, timestamp, phase, test_name, status FROM test_history
WHERE lower(phase||test_name) LIKE '%gbe%' OR lower(phase||test_name) LIKE '%mts%'`).

| id | Teste | Resultado |
|---|---|---|
| 39–41 (2026-07-22) | `stage=1` bring-up | falhas iniciais de insmod (caminho do módulo) |
| 51–54 (2026-07-25) | RE hold/pulse + handshake RMU | TX DMA processa, PHY mudo |
| 55–58 | RMU fase 1/2, loopback interno | sem retorno de RX |
| 59 | trigger `BAR0+0x1c = 0x80000000` | **confirmado no hardware** (bit 17 ACK) |
| 61–62 | Clause 22 / PHY ID Marvell | **refutado** (dado residual) |
| 70 | reteste do dump Clause 22 | `REFUTADO_DADO_RESIDUAL_BARRAMENTO` |
| 72 (2026-07-30) | reload com `irq_mask=0x7d` + MSI desmascarado | `irq_count=0`, `NO-CARRIER`, ping 100% perda |
| 73 | boot da tag `20260730-sata-polling-fase-ab` (GBE do baseline) | sucesso de boot; GBE com PHY mudo |

---

## 12. Regras de segurança (não repetir erros)

- **NUNCA** escrever `0` em `BAR0+0x34`/`0x38` — corrompe o estado permanentemente.
  Stop = escrever **`2`** (bit 1, soft reset) e poll até zerar; enable = escrever
  **`1`** direto com `mts_write()` (nunca `mts_set()`, que manda `0x09` e é rejeitado).
- **NUNCA** reescrever o enable do MAC depois de ativado — é **one-shot** por power cycle.
- **NUNCA** escrever em `BAR0+0x200` — trava o MAC enable até o próximo power cycle.
- **NUNCA** varrer minors ICC com `data=1` — causou reset/crash do console.
- Registradores de hold são **write-only** (sempre leem 0): GBE hold `0x180020`,
  pulse `0x180074` (o `0x180034` era palpite errado). Toggle sozinho **não** acorda o PHY.
- Escrever `0xc890a030` (`BAR2+0x10a030`) cedo no boot **congela o southbridge e o
  vídeo** (tela preta, exigiu power cycle). Não repetir.
- `mts_mdio_c22_*` não tem parâmetro de endereço de PHY útil para varredura: as
  funções originais do Orbis não distinguem `phy_addr` — varrer 0–31 é inútil.
- Não confundir **WiFi** (`wlan0`, `192.168.6.0/24`, SSH) com **eth0** (rede sob
  teste, IP fixo `192.168.0.2`, host `192.168.0.1`). Ping na subnet do WiFi não
  prova nada sobre o `mts`.

---

## 13. Onde está o resto

**Nesta pasta (documentação do MTS):**

| Documento | Conteúdo |
|---|---|
| [`MTS_INIT_SEQUENCE_dc5a31f0.md`](MTS_INIT_SEQUENCE_dc5a31f0.md) | sequência de init do Orbis decompilada (`mts_init`) |
| [`RE_KERNEL_GBE_ATTACH.md`](RE_KERNEL_GBE_ATTACH.md) | RE do attach/probe, ICC, glue PCIe (dados brutos) |
| [`RE_IF_MSK.md`](RE_IF_MSK.md) | RE do `if_msk` (Aeolia/Belize) × `if_mts` (Baikal) |
| [`ICC_GBE_TEST_LOG.md`](ICC_GBE_TEST_LOG.md) | todos os comandos ICC/MMIO testados (não retestar) |
| [`PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md) | plano consolidado e conclusão do PHY |
| [`MARCO_HISTORICO_ETH0_MTS_BAIKAL.md`](MARCO_HISTORICO_ETH0_MTS_BAIKAL.md) | marco de 2026-07-22 (dmesg, `ifconfig`, artefatos) |
| [`TESTES_HISTORICO.md`](TESTES_HISTORICO.md) | consolidação dos testes ao vivo 2026-07-22 → 2026-07-30 (o que vale e o que foi refutado) |

**Fora desta pasta:**

| Documento | Conteúdo |
|---|---|
| [`../../outros/rea/decompiled/INDEX.md`](../../outros/rea/decompiled/INDEX.md) | catálogo de funções decompiladas (consultar antes de pedir RE nova) |
| [`../../outros/rea/ps4_hardware_memory.db`](../../outros/rea/ps4_hardware_memory.db) | `bar0_register_map`, `test_history`, `decompiled_functions` |
| [`../../outros/scripts/build_mts_module.sh`](../../outros/scripts/build_mts_module.sh) · [`deploy_mts.sh`](../../outros/scripts/deploy_mts.sh) | build out-of-tree e deploy por SSH |
| [`../patches/mts-baikal-gbe-driver.patch`](../patches/mts-baikal-gbe-driver.patch) | patch in-tree (duplicata — ver §3) |
| [`../00-build-kernel-7.0.sh`](../00-build-kernel-7.0.sh) | build oficial (copia `drivers_mts/` para a árvore) |
