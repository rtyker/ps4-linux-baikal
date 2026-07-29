# Plano — SATA Interno (Toshiba MQ04ABF100) 100% Funcional, sem workarounds

> **Reescrito em 2026-07-28** a partir da releitura completa dos logs UART/dmesg e do código do driver.
> A versão anterior deste arquivo partia de três premissas factualmente erradas (documentadas na
> seção "Correções") e apontava para PHY/EFUSE — direção que **as evidências não sustentam**.

---

## 🔴 ERRATA 2026-07-28 (pós-teste ao vivo) — LEIA ANTES DO RESTO

Duas afirmações centrais deste plano foram **refutadas pelo próprio teste que ele propôs**.
O texto original segue preservado abaixo para rastreabilidade, mas **não confie nele sem ler esta errata**.

**ERRO 1 — "o AHCI não tem handler de interrupção registrado".** Falso. O AHCI **sempre teve**
handler. Ele não se chama `ahci[0000:00:14.7]`: o `ata_host_activate()` (`libata-core.c:6206`)
monta o nome com `dev_driver_string(host->dev)`, que é o driver ligado ao dispositivo PCI — e o
AHCI interno é instanciado de dentro do `xhci_aeolia`. Logo o handler aparece como
**`xhci_aeolia[0000:00:14.7]`**. Procurar por `ahci[...]` nesta função é falso negativo garantido.
(O Blu-ray aparece como `ahci[0000:00:14.2]` porque aquele dispositivo está ligado diretamente ao
driver `ahci`.)

**ERRO 2 — "a falha é específica de NCQ".** Falso. Com o `noncq` ativo a falha continua, agora como
`READ DMA` (opcode `0xc8`, `SAct 0x0`) — comando **não-enfileirado**. A explicação "conclusões NCQ
dependem do SDB FIS e se perdem" está derrubada: *qualquer* comando que dependa de interrupção
deixa de completar.

**O que se manteve verdadeiro:** o AHCI de fato *compartilhava* a IRQ 32 com os dois xHCI, e isso
foi corrigido — ele hoje tem o vetor dedicado hwirq 5345 (IRQ 33), exatamente como previsto. E o
`SErr 0x0` segue em 100% das falhas, o que continua descartando PHY/EFUSE.

**Correção adicional de escopo:** este plano dizia que o SATA "não é bloqueador de boot". **É.**
Medição de 2026-07-28: o boot leva 2min 15s, e ~78s disso é a cascata de EH do SATA — o
`Freeing unused kernel image` acontece 50 ms depois do `EH complete`. São 58% do tempo de boot.

**Estado real e próximos passos:** ver "RESULTADO DO TESTE AO VIVO" no fim deste arquivo.

---

## 1. O que os logs efetivamente provam

### 1.1 Tabela de evidências (todos os boots com o HD interno)

| Log | Quirks aplicados | Estado do NCQ | Resultado |
|-----|------------------|---------------|-----------|
| `dmesg.log` | *(nenhum)* | `NCQ (depth 32), AA` | Falha em **31.84s** — `READ FPDMA QUEUED` tag 2, LBA 0. Tabela de partição **nunca lida**. |
| `tests/uart_logs/kexec-warm-reboot-test-07-keep-bootcon_20260727_184659.bin` | `nolpm` | `NCQ (depth 32), AA` | Partições lidas OK em 3.88s. Falha em **36.58s** — `READ FPDMA QUEUED` tag 3, LBA `0x74706b08`. |
| `tests/uart_logs/kexec-warm-reboot-test-11-initcall-debug_20260728_074529.bin` | `nolpm` | `NCQ (depth 32), AA` | Partições lidas OK em 8.87s. Falha em **44.76s** — `READ FPDMA QUEUED` tag 22, LBA `0x747069e0`. |
| `tests/uart_logs/boot-medicao-welcome-archlinux_20260728_083215.bin` | **`noncq nolpm`** | **`NCQ (not used)`** | Partições lidas OK em 5.16s. **Zero erros ATA.** Log termina em 8.49s por travamento do kexec no `/init` — causa não relacionada ao SATA. |

### 1.2 Fatos que saem direto dessa tabela

1. **100% das falhas são comandos NCQ.** Sem exceção, o primeiro comando a falhar é sempre
   `READ FPDMA QUEUED` (opcode `0x60`). Nenhum comando não-enfileirado jamais falhou primeiro.

2. **Zero erros de link ou de PHY, em todos os casos.**
   A assinatura da falha é sempre idêntica:
   ```
   ata1.00: exception Emask 0x0 SAct 0x400000 SErr 0x0 action 0x6 frozen
   ata1.00: status: { DRDY }
   ```
   `Emask 0x0` = nenhuma classe de erro. `SErr 0x0` = **nenhum erro de SATA PHY**
   (sem CRC, sem disparidade, sem handshake perdido, sem decode error). `status: { DRDY }` = o
   drive está pronto e saudável. O link permanece `up 3.0 Gbps` inclusive **depois** da falha, e
   sobrevive a todos os hard resets seguintes. **O comando simplesmente nunca é reportado como
   completo** — não há erro nenhum, há uma conclusão que não chega.

3. **Não existe "timer de 31.85s".** As falhas ocorrem em 31.84s, 36.58s e 44.76s. É um evento
   dependente de carga, não um timeout fixo de hardware.

4. **O cascateamento posterior é consequência, não causa.** Depois do primeiro NCQ perdido, o
   `libata` congela a porta e tenta revalidar; a partir daí até o `IDENTIFY` simples (`cmd 0xec`)
   estoura, porque a porta ficou travada esperando um tag que o host abandonou. Os 5s → 10s → 30s
   e o downshift para 1.5 Gbps são o algoritmo padrão de escalonamento do EH do libata, não um
   sintoma independente.

### 1.3 O achado no código — IRQ única compartilhada

`drivers/ps4/ps4-bpcie.c:246` (`bpcie_assign_irqs`):

```c
/* PCI MSI has one address/data pair — multi-MSI only works for the
 * glue device (func 4) which demuxes via bpcie_handle_edge_irq.
 * Other devices must use a single shared vector. */
if (PCI_FUNC(dev->devfn) != BAIKAL_FUNC_ID_PCIE)
    nvec = 1;
```

A função `00:14.7` **não** é a função 4 (glue), portanto recebe `nvec = 1`. Em consequência,
`drivers/usb/host/xhci-aeolia.c:78` (`xhci_aeolia_irqnum`) cai no primeiro ramo:

```c
if (axhci->nr_irqs <= 1 || index >= axhci->nr_irqs)
    return dev->irq;      /* devolve o MESMO vetor para todo mundo */
```

Isso é confirmado nos logs, onde três dispositivos distintos anunciam o mesmo vetor:

```
xhci_aeolia 0000:00:14.7: xhci_aeolia_probe_one 0 controller 90de irq 32
xhci_aeolia 0000:00:14.7: irq 32, io mem 0xce000000
ata1: SATA max UDMA/133 abar m65536@0xce800000 port 0xce800100 irq 32 lpm-pol 0
```

**O controlador AHCI do HD interno divide um único vetor MSI (IRQ 32) com os dois barramentos
xHCI da mesma função.** E o rootfs do sistema está justamente no **USB** — ou seja, o dispositivo
que mais gera interrupções nessa linha é o mesmo que precisa dela livre para entregar as
conclusões do SATA.

Como contraste útil: o segundo controlador AHCI (`0000:00:14.2`, o leitor Blu-ray) recebe
**IRQ 36 dedicada** e nunca apresentou nenhuma falha.

---

## 2. Hipótese de causa raiz

**Conclusões NCQ perdidas na linha MSI compartilhada.**

No AHCI, um comando NCQ é concluído por um *Set Device Bits FIS*, que limpa o bit correspondente
em `PxSACT` e sinaliza `PxIS.SDBS`. Diferente de um comando não-enfileirado, **não há nenhum outro
mecanismo que reporte a conclusão**: se a interrupção correspondente não for processada enquanto o
status ainda está válido, aquele tag fica pendente para sempre. O `libata` só descobre isso quando
o timeout de 30s do SCSI estoura — que é exatamente o que se vê nos logs.

Isso explica, ponto a ponto, toda a evidência:

- por que só comandos NCQ falham (só eles dependem exclusivamente do SDB FIS);
- por que `SErr` é sempre `0x0` (o link nunca teve problema algum);
- por que o instante da falha varia (depende de colisão com tráfego USB, não de um timer);
- por que a falha aparece uns 30s após o boot (é quando o systemd começa a martelar o rootfs USB);
- por que o `00:14.2`, com IRQ própria, nunca falha.

**Grau de confiança:** alto para os itens da seção 1 (são leitura direta dos logs e do código);
médio-alto para o mecanismo exato da perda. A Fase A abaixo é justamente o que converte essa
hipótese em fato medido, e custa zero rebuild.

### 2.1 Por que desabilitar NCQ não é a solução

Passar `noncq` reduz drasticamente a exposição — com um único comando em voo por vez, a janela de
perda encolhe e o `PxCI` oferece um caminho de conclusão alternativo — mas **não corrige a entrega
de interrupção**, apenas a torna menos provável. Além disso custa desempenho real num HD SMR, onde
o enfileiramento é o que permite ao firmware reordenar escritas. É um paliativo, e o objetivo aqui
é eliminar a causa.

> Observação sobre a evidência disponível: o único boot com `noncq` de fato ativo
> (`boot-medicao`, 08:32) durou apenas **8.49s de tempo de kernel** antes de travar no `/init` por
> um problema de kexec sem relação com SATA. Portanto ele mostra ausência de erro, mas **não prova
> estabilidade prolongada**. Não tratar esse log como validação.

---

## 3. Correções à versão anterior deste plano

| Afirmação anterior | Status | Evidência |
|--------------------|--------|-----------|
| "Quirk `ATA_QUIRK_NONCQ` aplicado, `NCQ (not used)` confirmado, mas colapso **idêntico** ao baseline" | **Falso** | Os dois logs que falham (`test-07`, `test-11`) mostram `applying quirks: nolpm` — **sem `noncq`** — e `NCQ (depth 32), AA`, isto é, NCQ **ligado**. O único log com `noncq` realmente ativo não apresentou nenhum erro ATA. Houve mistura de logs de builds diferentes. |
| "Colapso em **exatos 31.85s** sugere timer de PHY/efuse" | **Falso** | 31.84s / 36.58s / 44.76s em três boots. Não é timer fixo. |
| "Causa raiz provável: calibração PHY SATA incompleta" / "PHY tem power domain separado" | **Não sustentado** | `SErr 0x0` em todas as falhas, link `up 3.0 Gbps` estável antes e depois. Um PHY mal calibrado produziria erros de CRC/disparidade em `SErr`, e nenhum aparece. As Fases 2 e 3 antigas investigavam um subsistema que os logs mostram saudável. |
| "Causa raiz provável: garbage collection do SMR" | **Não sustentado** | GC do drive se manifestaria como latência alta com o comando eventualmente completando, ou com erro reportado. Aqui o comando nunca retorna e o drive segue `DRDY`. Além disso a falha em `dmesg.log` foi no **LBA 0**, na primeiríssima leitura da tabela de partição — não há histórico de escrita para o firmware coletar ali. |
| "HD interno é soldado na placa-mãe, não dá para trocar" | **Falso** | A placa é **NVG-002** (PS4 Slim, visível em `consolidado/pictures/003.jpeg`). Nesse modelo o HD de 2,5" fica numa gaveta removível na lateral frontal esquerda, com conector SATA padrão. A troca é procedimento documentado de usuário. *Dito isso, o diagnóstico atual não indica troca de hardware* — fica registrado apenas para corrigir o histórico. |

---

## 4. Plano de execução

### FASE A — Medir a entrega de interrupções — ✅ **EXECUTADA EM 2026-07-28, RESULTADO CONCLUSIVO**

**Resultado: o AHCI interno não tem NENHUM handler de interrupção registrado.**

Coletado ao vivo via `sshpass -p ps4 ssh root@192.168.6.128` (kernel
`7.0.8-Strawberry-ThinLTO-Baikal`), `/proc/interrupts` completo:

```
  3:     26  ... Baikal-MSI 5251-edge   icc
 32:  10632  ... Baikal-MSI 5344-edge   xhci_aeolia[0000:00:14.7], xhci-hcd:usb1, xhci-hcd:usb3
 33:  12222  ... Baikal-MSI 5216-edge   mmc0
 34:    201  ... PCI-MSI-0000:00:01.1   snd_hda_intel:card0
 35: 154982  ... PCI-MSI-0000:00:01.0   amdgpu
 36:    537  ... Baikal-MSI 5184-edge   ahci[0000:00:14.2]
 37:      1  ... Baikal-MSI 5152-edge   mts
```

**Não existe `ahci[0000:00:14.7]` em linha nenhuma.** Todos os outros dispositivos Baikal
aparecem — `icc`, os três xHCI, `mmc0`, o AHCI do Blu-ray (`00:14.2`) e a GBE (`mts`). Só o
controlador SATA do HD interno está ausente da tabela.

Isso apesar de o boot anunciar que ele tem IRQ:
```
ata1: SATA max UDMA/133 abar m65536@0xce800000 port 0xce800100 irq 32 lpm-pol 0
```
A IRQ 32 existe e está viva (10.632 interrupções), mas seus três handlers são todos xHCI.
O `ata1` declara usá-la e **não está registrado nela**.

#### Decodificação do encoding de hwirq (confirma a arquitetura)

`bpcie_msi_domain_set_desc()` monta `hwirq = (PCI_SLOT << 8) | (FUNC << 5) + subfunção`.
Com slot `0x14` (20 → `5120`):

| hwirq | Cálculo | Função | Dispositivo |
|-------|---------|--------|-------------|
| 5152 | 5120 + (1<<5) | func 1 — GBE | `mts` |
| 5184 | 5120 + (2<<5) | func 2 — AHCI | `ahci[0000:00:14.2]` (Blu-ray) |
| 5216 | 5120 + (3<<5) | func 3 — SDHCI | `mmc0` |
| 5251 | 5120 + (4<<5) + 3 | func 4 — glue, subfunção 3 | `icc` |
| 5344 | 5120 + (7<<5) | func 7 — xHCI, **subfunção 0** | xHCI |
| **5345** | 5120 + (7<<5) + 1 | func 7, **subfunção 1** | **vago — deveria ser o AHCI interno** |

O vetor que o AHCI deveria ocupar (`5345`, subfunção 1 da função 7) simplesmente nunca é alocado.

#### Por que o vetor nunca é alocado — a cadeia completa

1. `subfuncs_per_func[7] = 3` (`ps4-bpcie.c:25`) — o hardware **tem 3 vetores MSI** na função 7.
2. `bpcie_handle_edge_irq()` (`ps4-bpcie.c:88`) **já implementa o demux da função 7**:
   ```c
   else if (func == 7)  { vector_to_write = 3; mask = 7; shift = 0x10; }
   ```
   `mask = 7` = três bits de subfunção. A infraestrutura de demultiplexação existe e está pronta.
3. `bpcie_msi_domain_info.flags` inclui `MSI_FLAG_MULTI_PCI_MSI` (`ps4-bpcie.c:186`) — multi-MSI
   está habilitado no domínio, e por isso `set_desc` **não** aplica o fallback `hwirq |= 0x1F`.
4. `xhci_aeolia_skip_index()` (`xhci-aeolia.c:73`) pula o índice 1 em Baikal — ou seja,
   **a subfunção 1 está deliberadamente reservada para o AHCI**, e `ahci_init_one()` de fato pede
   `xhci_aeolia_irqnum(axhci, pdev, 1)`.
5. **O bloqueio:** `bpcie_assign_irqs()` (`ps4-bpcie.c:273`) faz
   `if (PCI_FUNC(dev->devfn) != BAIKAL_FUNC_ID_PCIE) nvec = 1;`, clampando o pedido de 3 vetores
   para 1. Com `nr_irqs == 1`, `xhci_aeolia_irqnum()` cai no fallback `return dev->irq` e devolve
   o vetor do xHCI. O `hpriv->irq` do AHCI vira 32 — um vetor que pertence a outro dispositivo.

**Conclusão:** todo o caminho de interrupção dedicada para o SATA interno já está construído no
driver. Uma única linha o desativa.

<details>
<summary>Comandos usados (reprodutíveis)</summary>

```bash
sshpass -p ps4 ssh root@192.168.6.128 'cat /proc/interrupts'
sshpass -p ps4 ssh root@192.168.6.128 'dmesg | grep -iE "14\.7|ata1|ahci"'
```
</details>

---

### FASE A (registro do método original)

**Objetivo:** transformar a hipótese da seção 2 em fato medido, antes de escrever qualquer código.

Via SSH, com o sistema em regime (e **antes** de o `sda` ser desabilitado, ou seja, nos primeiros
30s, ou num boot com `noncq` para manter o disco vivo durante a medição):

```bash
# 1. Confirmar o compartilhamento e contar interrupções
cat /proc/interrupts | grep -E "ahci|xhci|^ *32:|^ *36:"

# 2. Amostrar a evolução sob carga de USB + SATA simultâneas
for i in $(seq 1 10); do grep -E "^ *32:" /proc/interrupts; sleep 2; done

# 3. Estado do controlador AHCI no momento da falha
cat /sys/class/scsi_host/host0/host_busy 2>/dev/null
```

**Critérios de leitura:**

- Se a linha 32 listar `xhci_hcd`, `xhci_hcd` **e** `ahci[0000:00:14.7]` juntos → compartilhamento
  confirmado, seguir para a Fase B.
- Se o contador da IRQ 32 **parar de crescer** no instante da falha do `sda`, ou se o AHCI aparecer
  em `/proc/interrupts` com contagem estagnada enquanto o xHCI continua subindo → perda de
  interrupção confirmada diretamente.
- Comparar com a IRQ 36 (Blu-ray, dedicada) como controle.

**Custo:** minutos, sem rebuild. Este é o passo que decide todo o resto.

---

### FASE B — IRQ dedicada para o AHCI interno — ✍️ **CÓDIGO EDITADO EM 2026-07-28, BUILD PENDENTE**

**Objetivo:** dar ao controlador SATA o vetor de interrupção próprio que o hardware já implementa.

**Arquivo alterado:** `drivers/ps4/ps4-bpcie.c` (em `/mnt/hdauxiliar/temp/kernel_build_7.0/`)

#### Alteração 1 — limite derivado da tabela, em vez de clamp fixo

```c
-	/* PCI MSI has one address/data pair — multi-MSI only works for the
-	 * glue device (func 4) which demuxes via bpcie_handle_edge_irq.
-	 * Other devices must use a single shared vector. */
-	if (PCI_FUNC(dev->devfn) != BAIKAL_FUNC_ID_PCIE)
-		nvec = 1;
+	/* PCI MSI has one address/data pair, so a function's subfunctions all
+	 * share it and must be demuxed by bpcie_handle_edge_irq via the glue
+	 * ACK register. Cap the request at what the function actually
+	 * implements, and fall back to a single vector where no demux branch
+	 * exists — an extra vector there would never be acked. */
+	nvec = min(nvec, bpcie_max_vectors(PCI_FUNC(dev->devfn)));
```

#### Alteração 2 — helper novo, logo abaixo de `subfuncs_per_func[]`

```c
static int bpcie_max_vectors(unsigned int func)
{
	if (func >= BAIKAL_NUM_FUNCS)
		return 1;

	switch (func) {
	case BAIKAL_FUNC_ID_PCIE:	/* glue, 31 subfunctions */
	case BAIKAL_FUNC_ID_DMAC:	/* 2 subfunctions */
	case BAIKAL_FUNC_ID_XHCI:	/* 3: xHCI x2 + internal AHCI */
		return subfuncs_per_func[func];
	default:
		return 1;
	}
}
```

#### Por que a generalização é gated (decisão de projeto)

`bpcie_handle_edge_irq()` só tem ramo de demux para as funções **4 (glue), 5 (DMAC) e 7 (xHCI)**;
todas as outras caem no `handle_edge_irq()` simples, **sem a sequência de ACK** no registrador do
glue. Como no Baikal as subfunções compartilham uma única mensagem MSI e só se distinguem lendo
esse ACK, um vetor extra numa função sem demux nunca seria reconhecido — ficaria morto ou geraria
interrupção não-acked.

Duas funções se encaixariam nesse risco: a **0 (ACPI, 2 subfunções)** e a **6 (MEM, 3 subfunções)**.
Nenhuma tem chamador hoje, então o perigo é teórico, mas o gate impede que um chamador futuro ative
silenciosamente um caminho sem ACK. **Manter `bpcie_max_vectors()` em sincronia com os ramos de
`bpcie_handle_edge_irq()`** — está anotado no comentário do helper.

#### Impacto real: exatamente um chamador muda

| Chamador | Função | Pede | Limite novo | Antes → Depois |
|----------|--------|------|-------------|----------------|
| `drivers/mmc/host/sdhci-pci-core.c:338` | 3 (SDHCI) | 1 | 1 | 1 → 1 |
| `drivers/ata/ahci.c:1785` | 2 (AHCI Blu-ray) | `n_ports` | 1 | 1 → 1 |
| `drivers/net/ethernet/sony/mts.c:2835` | 1 (GBE) | 1 | 1 | 1 → 1 |
| `drivers/usb/host/xhci-aeolia.c:90` | 7 (xHCI + AHCI interno) | 3 | 3 | **1 → 3** |

`mmc0`, `mts` e o AHCI do Blu-ray permanecem bit-a-bit idênticos ao comportamento atual — todos já
pediam menos que o próprio limite. Só a função 7 passa a receber os 3 vetores, o que faz
`xhci_aeolia_irqnum()` deixar de cair no fallback e entregar a subfunção 1 ao AHCI interno.

> Nota: nenhuma alteração foi necessária em `xhci-aeolia.c`. O `ahci_init_one()` já pedia o índice 1
> (`hpriv->irq = xhci_aeolia_irqnum(axhci, pdev, 1)`) e o `xhci_aeolia_skip_index()` já reservava
> esse índice em Baikal. O bug estava só no clamp do lado do `bpcie`.

#### Estado atual

- ✅ Código editado (`ps4-bpcie.c`, 24 inserções / 5 remoções)
- ✅ Build concluído 2026-07-28 09:14, exit 0 — `bzImage-7.0-20260728-sata-irq-dedicada`
      (15.844.352 bytes, kernel `7.0.8-Strawberry-ThinLTO-Baikal`)
- ✅ Alteração confirmada no binário: `ps4-bpcie.o` recompilado 09:00 (após a edição 08:55),
      `bzImage` 09:14, e MD5 diferente do baseline
      (`801b51e7…` vs `9ce93066…` do `sata-noncq-fix-20260728`).
      `bpcie_max_vectors` não aparece em `nm` porque é `static` e foi inlinado — esperado.
- ✅ Tag completa em `boot_referencia/` (4 arquivos):

  | Arquivo | Tamanho | Origem |
  |---------|---------|--------|
  | `bzImage-7.0-20260728-sata-irq-dedicada` | 16 MB | build novo |
  | `config-7.0-20260728-sata-irq-dedicada` | 140 KB | build novo |
  | `bootargs-7.0-20260728-sata-irq-dedicada.txt` | 512 B | derivado, **sem `noncq`** |
  | `initramfs-7.0-20260728-sata-irq-dedicada.cpio.gz` | 3,2 MB | cópia de `sata-noncq-fix-20260728` |

- ✅ **`noncq` removido do bootargs** — conferido: 0 ocorrências, e o `diff` token a token contra
      o baseline mostra **apenas** a remoção de `libata.force=1.00:3.0Gbps,noncq`. Nada mais mudou.
- ✅ **Deploy concluído 2026-07-28** — MD5 conferido origem→destino pelo próprio script
      (`bzImage 801b51e79f7f260e09ec1e8a6ee7e6ff`, `bootargs e335aeb4…`, `initramfs 5d26f3b2…`).
      Tag anterior ativa era `sata-noncq-fix-20260728`. Rootfs `psxitarch` não foi tocado.
      Partições desmontadas com segurança.
- ⬜ Boot + critério de aceitação
- ⬜ Fase D (teste de carga)

> **Nota sobre a lição #23 (limite de ~10 MB do bzImage):** o binário novo tem 15.844.352 bytes,
> exatamente o mesmo tamanho do `sata-noncq-fix-20260728` e do `s5-poweroff-fix-20260725-v5`, que
> bootam normalmente (o log de kexec registra `sys_kexec(..., 15844352, ...)`). Não há regressão de
> tamanho aqui, mas a lição #23 aparenta estar desatualizada ou referir-se a outro loader — vale
> revisar quando houver evidência, não agora.

**Critério de aceitação imediato:** `/proc/interrupts` deve passar a mostrar
`Baikal-MSI 5345-edge  ahci[0000:00:14.7]` numa linha própria, com contador subindo durante I/O
no `sda`.

**Rollback:** `sudo ./deploy-boot-7.0.sh <tag-anterior>` restaura em 1 power cycle.

---

### FASE C — Robustecer o handler compartilhado (caminho alternativo)

**Só executar se a Fase B mostrar que o hardware não permite vetor dedicado para a `14.7`.**

Se o compartilhamento for inevitável, a correção passa a ser garantir que nenhuma conclusão se
perca na linha compartilhada:

1. Verificar se o handler AHCI está registrado com `IRQF_SHARED` e se `ahci_host_activate()` está
   usando o caminho de interrupção correto para um vetor compartilhado.
2. Garantir que o handler faça **laço até a porta ficar limpa** (reler `PxIS`/`PxSACT` até zerar)
   em vez de tratar um único evento por interrupção — é isso que fecha a janela de corrida com MSI
   disparada por borda.
3. Conferir a ordem da cadeia de handlers: se o handler do xHCI consumir a interrupção e retornar
   antes que o do AHCI examine seu próprio status, a conclusão do SATA se perde.

Esta fase é uma correção legítima, não um workaround — ela conserta o tratamento da interrupção,
não esconde o sintoma.

---

### FASE D — Validação sob carga (o teste que define "100% funcional")

Nenhuma das fases anteriores conta como resolvida sem passar aqui. Executar **com NCQ habilitado**
(sem `noncq` nos bootargs, sem o quirk):

```bash
# Leitura longa e contínua, com o rootfs USB sob carga simultânea
dd if=/dev/sda of=/dev/null bs=1M count=20000 status=progress &
# em paralelo, forçar tráfego no USB para disputar a IRQ
dd if=/dev/urandom of=/tmp/stress.bin bs=1M count=4000 status=progress

# monitorar
watch -n2 'dmesg -T | tail -20; grep -E "^ *3[0-9]:" /proc/interrupts'
```

**Critérios de aprovação (todos obrigatórios):**

- 30+ minutos de I/O contínuo sem uma única linha `exception Emask` em `dmesg`;
- zero `hard resetting link`;
- link mantido em 3.0 Gbps (sem downshift para 1.5);
- `ata1.00` continua listando `NCQ (depth 32)` em uso, não `(not used)`;
- montagem e escrita reais em partição do `sda` sobrevivendo a um ciclo completo de boot.

---

## 5. O que foi descartado e não deve ser retomado

| Linha de investigação | Por que foi descartada |
|-----------------------|------------------------|
| Calibração PHY SATA / comparação 1:1 com `dc72bfb0` | `SErr 0x0` em 100% das falhas; link estável a 3.0 Gbps antes e depois. O PHY está funcionando. Retomar só se a Fase A refutar a hipótese de IRQ **e** surgirem erros em `SErr`. |
| ICC minor separado para power domain do PHY SATA | Mesma razão. O MAC responde (`icc: SATA power-on OK`), o PHY inicializa (`EFUSE 0x24:0x0e:0x0e`, `Trace length 4`) e o link sobe. Não há sintoma de alimentação. |
| Aumentar `eh_timeout` do libata | Mascara o sintoma sem corrigir a perda de conclusão — o comando continuaria nunca completando, só demoraria mais para ser reportado. Workaround puro. |
| I/O periódico (`dd` a cada N segundos) para "manter o drive acordado" | Baseado na hipótese de GC do SMR, que a evidência não sustenta. Já testado e sem efeito. |
| Troca de hardware (SSD não-SMR) | O drive nunca reportou um único erro. Trocar o disco não corrige entrega de interrupção. |
| `libata.force=...` via cmdline | Já demonstrado sem efeito neste controller; e é configuração, não correção. |

---

## 6. Próximo passo imediato

> 🔴 **SUPERADO — ver a ERRATA no topo e a seção "RESULTADO DO TESTE AO VIVO" no fim do arquivo.**
> A Fase B foi implantada e testada: o vetor dedicado foi conquistado (hwirq 5345, `ata1 ... irq 33`),
> mas a falha persiste e a hipótese de NCQ caiu. A Fase C, que este parágrafo arquivava, **volta a
> ser relevante** — o problema agora é a entrega de interrupção cessar após o probe, provavelmente
> por corrida no ACK compartilhado do glue entre os três vetores.

Fase A **concluída** (2026-07-28) — ~~o AHCI interno não tem handler de interrupção registrado~~
*(afirmação incorreta, ver errata)*, e a causa está isolada em uma única linha de
`bpcie_assign_irqs()`. ~~A Fase C (robustecer handler compartilhado) fica arquivada.~~

**Próximo passo: implementar a Fase B.** A alteração é pequena e cirúrgica — permitir que a função
7 aloque as `subfuncs_per_func[7] = 3` vetores que o hardware implementa, em vez do clamp para 1.
Toda a demultiplexação já existe e já funciona (é o mesmo mecanismo que serve `icc` na subfunção 3
da função 4).

Ordem de execução:

1. Editar `drivers/ps4/ps4-bpcie.c` (com `sudo`, em `/mnt/hdauxiliar/temp/kernel_build_7.0/`).
2. Compilar pelo script oficial — **nunca `make bzImage` direto** (`AGENTS.md`, regra crítica):
   ```bash
   cd /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2
   sudo ./00-build-kernel-7.0.sh 20260728-sata-irq-dedicada
   ```
3. Reaproveitar o initramfs de uma tag existente (só o bzImage muda) e completar os 4 arquivos da
   tag em `boot_referencia/`.
4. Com o HD USB `psxitarch` plugado neste PC: `sudo ./deploy-boot-7.0.sh 20260728-sata-irq-dedicada`
5. **Remover `noncq` do `bootargs`** desta tag — a validação tem que ser com NCQ ligado, senão não
   prova nada.
6. Bootar e conferir o critério de aceitação abaixo, depois rodar a Fase D.

**Critério de aceitação imediato (antes mesmo do teste de carga):** `/proc/interrupts` deve passar
a mostrar uma linha nova, `Baikal-MSI 5345-edge  ahci[0000:00:14.7]`, com contador subindo durante
I/O no `sda`.

**Rollback:** `sudo ./deploy-boot-7.0.sh <tag-anterior>` restaura em 1 power cycle.

---

## 7. Referências

**Logs (fonte primária deste diagnóstico):**
- `dmesg.log` — baseline sem quirks, falha em 31.84s no LBA 0
- `tests/uart_logs/kexec-warm-reboot-test-07-keep-bootcon_20260727_184659.bin`
- `tests/uart_logs/kexec-warm-reboot-test-11-initcall-debug_20260728_074529.bin`
- `tests/uart_logs/boot-medicao-welcome-archlinux_20260728_083215.bin` — único com `noncq` ativo

> Os `.bin` são captura UART crua; ler com `strings -n 4 <arquivo>.bin | grep -i ata`.
> Os `.log` de mesmo nome são hexdump e **não** servem para grep de texto.

**Código:**
- `drivers/ps4/ps4-bpcie.c:246` — `bpcie_assign_irqs()`, o `nvec = 1` que força o compartilhamento
- `drivers/usb/host/xhci-aeolia.c:78` — `xhci_aeolia_irqnum()`, o fallback `return dev->irq`
- `drivers/usb/host/xhci-aeolia.c:216` — `ahci_init_one()`, atribuição de `hpriv->irq`
- `drivers/usb/host/xhci-aeolia.c:447` — máscara DMA de 31 bits, aplicada corretamente ao
  `struct device` compartilhado **antes** de `ahci_init_one()` (verificado — não é problema)

**Hardware:**
- Placa **NVG-002** (PS4 Slim) — `consolidado/pictures/003.jpeg`
- AHCI interno: `0000:00:14.7`, `104d:90de`, BAR2 `0xce800000`, AHCI 1.300, 32 slots, 6 Gbps
- AHCI Blu-ray: `0000:00:14.2`, IRQ 36 **dedicada**, sem falhas — controle experimental
- Drive: TOSHIBA MQ04ABF100, rev JU0G0A, 1 TB, SMR gerenciado pelo drive, blocos físicos de 4K

---

## RESULTADO DO TESTE AO VIVO — 2026-07-28, tag `20260728-sata-irq-dedicada`

### O que funcionou

A alocação de vetores fez exatamente o previsto. `/proc/interrupts` após o deploy:

```
32:  8212  Baikal-MSI 5344-edge  xhci-hcd:usb1
33:     7  Baikal-MSI 5345-edge  xhci_aeolia[0000:00:14.7]   <- ESTE é o AHCI interno
34:     1  Baikal-MSI 5346-edge  xhci-hcd:usb3
38:   158  Baikal-MSI 5184-edge  ahci[0000:00:14.2]          <- Blu-ray, controle
```

Os 3 vetores da função 7 foram alocados (hwirq 5344/5345/5346), o AHCI ficou sozinho no 5345 e
`ata1: ... irq 33` confirma. **Zero regressão:** USB, `mmc0`, `mts` e o Blu-ray seguem normais,
o boot completou e o SSH subiu.

### O que continua falhando

```
[   31.843849] ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6 frozen
[   31.844999] ata1.00: failed command: READ DMA
[   31.846102] ata1.00: cmd c8/00:08:00:00:00/00:00:00:00:00/e0 tag 22 dma 4096 in
[   78.943144] ata1.00: disable device
```

### Medição de registradores AHCI (via `/dev/mem`, leitura pura)

| Registrador | Valor | Leitura |
|-------------|-------|---------|
| `GHC` | `0x80000002` | AHCI habilitado, **interrupção global ligada** (IE) |
| `PxIE` | `0x7840007f` | Interrupções da porta **habilitadas**, nada mascarado |
| `PxIS` / `IS` | `0x00000000` | Nenhuma interrupção pendente presa |
| `PxSERR` | `0x00000000` | Zero erro de link |
| `PxSSTS` | `0x113` | Dispositivo presente, link ativo (1.5 Gbps pós-downshift) |
| `PxTFD` | `0x150` | Drive `DRDY`, sem erro |

**Conclusão:** a configuração de interrupção está correta. Não é máscara, não é AHCI desabilitado,
não é link. O hardware pede interrupção do jeito certo — ela não chega ao handler.

### Hipótese principal atual: corrida no registrador de ACK compartilhado

`bpcie_handle_edge_irq()` foi escrito assumindo **um único vetor pai**:

```c
u32 initial_hwirq = desc->irq_data.hwirq & ~0x1fLL;   // 5344 para os três
glue_write32(sc, BPCIE_ACK_WRITE, vector_to_write);   // registrador COMPARTILHADO
u32 vector_read  = glue_read32(sc, BPCIE_ACK_READ);
subfunc_mask = mask & ~(vector_read >> shift);
```

Com 3 vetores, os três descritores rodam esse mesmo código, todos calculam `initial_hwirq = 5344`
e todos leem/limpam **o mesmo** registrador de ACK do glue. O USB dispara 8.212 vezes; cada disparo
consome os bits pendentes de todas as subfunções, inclusive a do SATA. Quando o vetor do SATA roda,
o ACK já foi limpo e ele não despacha nada.

Casa com o placar observado (8212 no USB × 7 no SATA) e com o SATA ter recebido interrupções só
durante o probe, antes de o USB começar a martelar. **É hipótese, não fato** — o passo 1 abaixo
existe para convertê-la.

### Próximos passos

1. **Instrumentar o demux** (1 rebuild): logar `hwirq`, `vector_read`, `subfunc_mask` e contador por
   subfunção em `bpcie_handle_edge_irq()`. Com o console UART ativo, ver ao vivo se o vetor do SATA
   roda e sai com máscara zerada (confirma a corrida) ou se sequer é invocado.
2. **Escolher a correção conforme o resultado** — caminhos mutuamente exclusivos:
   - **(A) Não demultiplexar quando há vetor dedicado:** cada vetor chama `handle_edge_irq` direto
     na própria subfunção. É a correção limpa. Risco: se o ACK no glue for necessário para rearmar
     a interrupção, pular o ACK trava tudo — o passo 1 tem que esclarecer isso.
   - **(B) Tornar o demux seguro para multi-vetor:** despachar só a própria subfunção e **preservar**
     os bits alheios em vez de consumi-los.
3. **Reavaliar os 3 vetores:** a mudança não regrediu nada e atingiu o objetivo declarado, mas não
   resolveu sozinha. Se o passo 1 mostrar que o demux não suporta multi-vetor com segurança, voltar
   a 1 vetor e corrigir o ACK pode ser mais sólido.
4. **Deploy único** com a correção do demux + `bootargs-7.0-20260728-sata-diag.txt`
   (console UART + `rootwait`), para gastar um só ciclo físico.

### Armadilhas confirmadas (não repetir)

- **`noncq` NÃO sai pelo bootargs.** O quirk está hardcoded em `libata-core.c:4199`
  (`{ "TOSHIBA MQ04ABF100", NULL, ATA_QUIRK_NOLPM | ATA_QUIRK_NONCQ }`). Remover do cmdline não
  reativa NCQ — o boot ainda mostrou `applying quirks: noncq nolpm`.
- **Não procurar `ahci[0000:00:14.7]` em `/proc/interrupts`.** O nome é `xhci_aeolia[0000:00:14.7]`.
- **O bootargs do baseline não tem console serial.** `bootargs-7.0-sata-noncq-fix-20260728.txt` só
  tem `console=tty0`; derivar dele deixa a UART cega ao kernel. Usar o `-sata-diag`.
