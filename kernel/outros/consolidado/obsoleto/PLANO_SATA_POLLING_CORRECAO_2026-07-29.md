# Plano: Resolver SATA Interno via Polling do AHCI (Correção ao Glue IRQ)

> [!NOTE]
> **🏆 SUCESSO CONFIRMADO AO VIVO (2026-07-30, `test_history` id 73) — PLANO CONCLUÍDO.** Fase A+B compiladas na tag `20260730-sata-polling-fase-ab` e testadas em hardware real: `ata1.00: configured for UDMA/100` sem nenhuma exceção, zero `disable device` em todo o dmesg, leitura real confirmada (`dd` 50MB a 71.2 MB/s), `fdisk -l /dev/sda` retorna a tabela completa (931.51 GiB). Novo baseline oficial registrado em `AGENTS.md`. Detalhes completos em `memory/marco-sata-interno-funcional-2026-07-30.md`. **Este plano está encerrado com sucesso — não precisa de mais iteração**, exceto a limpeza opcional da instrumentação de debug (`ahci_dbg:`) num rebuild futuro.

> [!NOTE]
> **🔧 STATUS DE IMPLEMENTAÇÃO (2026-07-29, `test_history` id 69):** Fase A e Fase B **implementadas em código** em `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ata/{libahci.c,ahci.c,ahci.h}`, com as 3 correções técnicas da revisão já aplicadas (`hrtimer_setup`, ack de `HOST_IRQ_STAT`, guarda `ata_port_is_frozen`; filtro `vendor==SONY && device==BAIKAL_AHCI`). **Ainda NÃO compilado pelo script oficial nem testado em hardware.** Próximo passo: `00-build-kernel-7.0.sh 20260729-sata-polling-fase-ab`.

## Contexto e Problema

O HD interno do PS4 Baikal (Toshiba MQ04ABF100, `ata1` em `0000:00:14.7`) é detectado e funciona nos primeiros ~4.9 segundos de boot, mas a partir desse ponto **o controlador AHCI para de gerar interrupção porque `PxIE` (Port Interrupt Enable) é zerado** — confirmado por reconciliação direta com o log UART bruto (ver nota abaixo). O resultado é um timeout de 30 segundos seguido de `disable device` aos ~84s.

### Histórico Completo de Tentativas (todas refutadas)

| # | Tag / Teste | Hipótese | Resultado |
|---|------------|----------|-----------|
| 1 | `test_history` id 63 | AHCI sem handler de IRQ registrado | ❌ Refutada: handler existe como `xhci_aeolia[0000:00:14.7]` na IRQ 32 |
| 2 | `test_history` id 64 | IRQ compartilhada com USB (1 vetor MSI para 3 subfunções) | ❌ Refutada: 3 vetores alocados, AHCI isolado na IRQ 33, falha persiste |
| 3 | `test_history` id 65 | Corrida no registrador ACK compartilhado entre vetores | ❌ Refutada: hardware rota TUDO por 1 vetor MSI, vetor dedicado nunca disparou (0 chamadas) |
| 4 | `20260729-sata-globallock` | Corrida SMP no par `0x110084`/`0x110088` (spinlock global) | ❌ Refutada: spinlock funcionou, falha idêntica — Glue cessa sinalização da subfunção 1 aos 4.89s |

### Fatos Físicos Medidos (Irrefutáveis)

1. **PHY/link 100% saudável:** `SErr=0x0` em 100% das falhas. Link estável `3.0 Gbps` (SStatus `0x123`).
2. **Disco energizado e funcional:** Status `{ DRDY }` em todas as exceções. Os primeiros 10 comandos DMA completam com sucesso.
3. **🔴 DESCOBERTA CRÍTICA — `PxIE=0x00000000` durante o período de falha:**
   - No 1º EH entry (`t = 2.504s`, probe): `PxIE=0x00000000`, `PxIS=0x00400040` — esperado durante o probe (AHCI spec: PxIE é zerado antes do reset inicial).
   - No 2º EH entry (`t = 36.777s`, timeout): **`PxIE=0x00000000`**, `PxIS=0x00000001`, `IS=0x00000001` — **as interrupções da porta estão DESABILITADAS no próprio registrador AHCI**! O controlador AHCI vê a completação (`PxIS=1`), mas NÃO gera interrupção MSI porque `PxIE=0`.
   - No 3º EH entry (`t = 83.916s`, após hard reset): `PxIE=0x7840007f` — agora habilitado, mas tarde demais (`disable device` logo após).
4. **O problema NÃO é no Glue:** Se `PxIE=0`, o AHCI nunca gera a interrupção em primeiro lugar. O Glue `BAR2+0x110088` lendo `0x001e0103` (subfunção 1 não-pendente) é **correto** porque o AHCI não está sinalizando.
5. **Transição abrupta aos 4.89s:** Última interrupção SATA em `t = 4.891s`. O `PxIE` provavelmente foi zerado pelo driver entre `t = 3.138s` (configuração) e `t = 4.891s` (última IRQ processada).
6. **Não é NCQ:** O comando falho é `READ DMA EXT` (cmd `0x25`), não-enfileirado. O quirk `noncq` está ativo e confirmado.
7. **`vec_read` confirma:** Quando `vec_read=0x001c0103` (bit 17 = 0), a subfunção 1 **estava** pendente e foi despachada. Quando `vec_read=0x001e0103` (bit 17 = 1), a subfunção 1 **NÃO** está pendente — consistente com `PxIE=0` impedindo a geração de IRQ.

### Diagnóstico Revisado (com base em `PxIE=0`)

> [!CAUTION]
> **A causa raiz NÃO é o Glue PCIe.** O registrador `PxIE` (Port Interrupt Enable) do controlador AHCI está sendo zerado pelo driver Linux (`libahci`) em algum ponto após o probe. Com `PxIE=0`, o controlador AHCI não gera interrupções, e consequentemente o Glue não as propaga.

Possíveis causas de `PxIE=0`:
- **(A)** O `libahci.c` faz freeze/thaw da porta durante o EH (Error Handling), e o freeze zera `PxIE`. Se o EH é invocado durante o probe e o thaw não restaura `PxIE` corretamente, as interrupções ficam desabilitadas permanentemente.
- **(B)** O `ahci_port_start()` não está programando `PxIE` na sequência correta para o hardware PS4.
- **(C)** Interação com o quirk `noncq`/`nolpm` que força um caminho de código diferente no libahci onde `PxIE` não é restaurado.

> [!IMPORTANT]
> **Nova Hipótese Principal:** O `libahci` faz `ahci_freeze()` (que zera `PxIE`) durante o probe/EH, e o subsequente `ahci_thaw()` (que deveria restaurar `PxIE=0x7840007f`) NÃO está sendo chamado ou falha silenciosamente no PS4 Baikal. Isso explicaria por que as primeiras interrupções funcionam (antes do freeze) e depois param.

> [!NOTE]
> **✅ RECONCILIADO 2026-07-29 — dados deste plano CONFIRMADOS pelo log UART bruto.** Havia uma contradição aparente entre este plano e `memory/MEMORY.md` (que registrava `PxIS=0x2`/`IS=0x1` "interrupção ativa, Glue não propaga" para o mesmo evento). Reaberto e decodificado byte a byte o `tests/uart_logs/sata_teste_20260729_145146.log`: os 3 EH entries reais do `ata1` são exatamente os citados acima (`t=2,504898s`: `PxIS=0x00400040 PxIE=0x00000000`; `t=36,777086s`: `IS=0x00000001 PxIS=0x00000001 PxIE=0x00000000`, link 3.0Gbps; `t=83,916040s`: `PxIS=0x00000002 PxIE=0x7840007f`, link caído para 1.5Gbps). **A transcrição em `memory/MEMORY.md` estava imprecisa (já corrigida) — o diagnóstico correto é o deste plano: `PxIE=0` no momento da falha, não "Glue bloqueando interrupção ativa".** Ver `test_history` id 68 e `consolidado/LICOES_APRENDIDAS.md`.
>
> **Ressalva que continua válida (revisão técnica de código, 2026-07-29):** mesmo com `PxIE=0` confirmado, isso não implica bug em `ahci_freeze()`/`ahci_thaw()` — essas funções são código **100% stock upstream** neste kernel_build_7.0, sem nenhum patch/quirk PS4. O `ahci_thaw()` real escreve `pp->intr_mask` (não a constante `DEF_PORT_IRQ` direto, como o snippet abaixo sugere) — `pp->intr_mask` é inicializado com `DEF_PORT_IRQ` em `ahci_port_start()` e ajustado dinamicamente (PHYRDY por LPM, BAD_PMP por presença de PMP). O valor logado no 3º EH entry (`PxIE=0x7840007f`) é **matematicamente igual a `DEF_PORT_IRQ` (0x78C0007F) menos o bit BAD_PMP** — exatamente o valor esperado quando não há PMP conectado. Isso é evidência de que o `thaw`, quando roda, restaura o valor CORRETO — não evidência de bug nele. **A Fase A deveria ser tratada como instrumentação exploratória ("descobrir quem/o que zera `PxIE` fora do ciclo normal freeze→thaw"), não como "correção", já que não há bug de lógica identificado em `ahci_freeze`/`ahci_thaw` hoje — mas agora com a certeza de que `PxIE=0` é o fenômeno real a explicar.**

---

## Proposta: Duas Fases

### Fase A (Root Cause) — Forçar `PxIE` Ativo Após Cada Thaw

No `libahci.c`, a função `ahci_thaw()` é chamada pelo Error Handler após um reset para restaurar as interrupções da porta. O código padrão é:

```c
static void ahci_thaw(struct ata_port *ap)
{
    void __iomem *port_mmio = ahci_port_base(ap);
    u32 tmp;

    /* clear IRQ */
    tmp = readl(port_mmio + PORT_IRQ_STAT);
    writel(tmp, port_mmio + PORT_IRQ_STAT);
    writel(1 << ap->port_no, mmio + HOST_IRQ_STAT);

    /* turn IRQ back on */
    writel(DEF_PORT_IRQ, port_mmio + PORT_IRQ_MASK);  // PORT_IRQ_MASK = PxIE
}
```

**Hipótese:** Na sequência de probe do PS4 Baikal, o `ahci_thaw()` pode não estar sendo chamado, ou `DEF_PORT_IRQ` pode não incluir os bits necessários, ou existe um `ahci_freeze()` (que zera `PxIE`) sem `ahci_thaw()` correspondente.

**Ação:** Adicionar instrumentação para logar o valor de `PxIE` em cada ponto do ciclo de vida:
1. Após `ahci_port_start()`
2. Dentro de `ahci_freeze()` (antes de zerar)
3. Dentro de `ahci_thaw()` (após restaurar)
4. Após `ata_host_activate()` (estado final)

Se confirmarmos que `PxIE` fica zero, a correção é trivial: garantir que `ahci_thaw()` é chamado e que `DEF_PORT_IRQ` é applied.

> [!NOTE]
> Ver caixa de alerta acima: os dados atuais (`PxIE=0x7840007f` = `DEF_PORT_IRQ` menos `BAD_PMP`) já mostram que o `thaw`, quando executado, restaura o valor certo. O objetivo real desta fase é logar **dentro** de `ahci_freeze()`/`ahci_thaw()` (hoje só existe log em `ahci_error_handler()`) para descobrir se há um freeze "silencioso" (sem nova entrada de EH) entre `t=4.891s` (última IRQ OK) e `t=36.777s` (EH com `PxIE=0`) — não para aplicar uma correção de lógica já sabida.

### Fase B (Fallback) — Polling Timer

Caso a Fase A não resolva (ex: algum mecanismo de hardware do Baikal zera `PxIE` independentemente do driver), implementar o polling timer como fallback robusto.

> [!CAUTION]
> **Revisão técnica (2026-07-29) identificou 3 problemas no diff abaixo que precisam ser corrigidos antes de compilar:**
> 1. **Não compila neste kernel.** `hrtimer_init()` foi removido da árvore. A API atual é `hrtimer_setup(&hpriv->poll_timer, ahci_poll_timer_fn, CLOCK_MONOTONIC, HRTIMER_MODE_REL)` — confirmado pelo uso real em `drivers/ata/pata_octeon_cf.c:938` neste mesmo kernel_build_7.0.
> 2. **Falta o ack de `HOST_IRQ_STAT`.** `ahci_port_intr()` só limpa `PORT_IRQ_STAT` (por-porta); quem limpa o bit correspondente em `HOST_IRQ_STAT` (nível host) é o wrapper `ahci_single_level_irq_intr()`, não `ahci_port_intr()`. Sem isso, o timer pode deixar o bit host-level pendente e gerar uma IRQ real espúria depois. Adicionar `writel(1 << ap->port_no, hpriv->mmio + HOST_IRQ_STAT)` após o `ahci_port_intr()` no timer.
> 3. **Race genuína com o Error Handler, não coberta pelo lock.** `ap->lock == host->lock` (confirmado em `libata-core.c:5658`), então o `spin_lock_irqsave(&ap->lock, flags)` proposto serializa corretamente contra a IRQ handler real — mas NÃO contra o EH em si. Durante EH o hardware pode continuar setando `PORT_IRQ_STAT` mesmo com `PxIE=0` (é a própria premissa deste plano). Um polling incondicional pode completar um `qc` exatamente enquanto o EH está resetando o engine/reclamando o mesmo tag → risco de dupla completação/corrupção de estado libata. **Adicionar guarda `if (ata_port_is_frozen(ap)) continue;` (ou checagem equivalente de `ap->pflags`/EH em andamento) antes de chamar `ahci_port_intr()` no timer.**

#### [MODIFY] libahci.c — Timer de Polling (revisado 2026-07-29: API `hrtimer_setup`, ack de `HOST_IRQ_STAT`, guarda contra EH)

```diff
+#include <linux/hrtimer.h>
+
+/* PS4 Baikal: fallback polling if PxIE stays zero.
+ * NOTE: Must check PxIS directly because HOST_IRQ_STAT = PxIS & PxIE (which is 0 when PxIE=0).
+ * NOTE: skips ports frozen/under EH — PORT_IRQ_STAT can latch even with PxIE=0, and
+ * processing it here while the EH resets the engine risks double-completing a qc. */
+static enum hrtimer_restart ahci_poll_timer_fn(struct hrtimer *timer)
+{
+	struct ahci_host_priv *hpriv = container_of(timer,
+		struct ahci_host_priv, poll_timer);
+	struct ata_host *host = hpriv->poll_host;
+	unsigned long flags;
+	unsigned int i;
+
+	if (!host)
+		goto rearm;
+
+	for (i = 0; i < host->n_ports; i++) {
+		struct ata_port *ap = host->ports[i];
+		void __iomem *port_mmio;
+		u32 px_is;
+
+		if (!ap || !ata_port_is_active(ap) || ata_port_is_frozen(ap))
+			continue;
+
+		port_mmio = ahci_port_base(ap);
+		px_is = readl(port_mmio + PORT_IRQ_STAT);
+
+		if (px_is) {
+			spin_lock_irqsave(&ap->lock, flags);
+			ahci_port_intr(ap);
+			/* ack no nível host, que ahci_port_intr() não faz sozinho
+			 * (só o wrapper ahci_single_level_irq_intr() faz isso) */
+			writel(1 << ap->port_no, hpriv->mmio + HOST_IRQ_STAT);
+			spin_unlock_irqrestore(&ap->lock, flags);
+		}
+	}
+
+rearm:
+	hrtimer_forward_now(timer, ms_to_ktime(1));
+	return HRTIMER_RESTART;
+}
```


#### [MODIFY] ahci.h

Adicionar campos ao `struct ahci_host_priv`:

```diff
 struct ahci_host_priv {
 	/* ... campos existentes ... */
+	struct hrtimer	poll_timer;
+	struct ata_host	*poll_host;
+	bool		poll_enabled;
 };
```

---

### Componente 2: `drivers/ata/ahci.c` — Ativar o Polling para PS4

#### [MODIFY] ahci.c

Na função `ahci_init_one()`, após o `ata_host_activate()`, iniciar o timer de polling apenas para dispositivos PS4:

```diff
+	/* PS4 Baikal: Glue PCIe silently drops AHCI IRQs after ~5s.
+	 * Start a 1ms polling timer as fallback. The real IRQ handler
+	 * still works if/when interrupts resume (e.g. after EH reset). */
+	if (pdev->vendor == PCI_VENDOR_ID_SONY &&
+	    pdev->device == PCI_DEVICE_ID_SONY_BAIKAL_AHCI) {
+		hpriv->poll_host = host;
+		hpriv->poll_enabled = true;
+		hrtimer_setup(&hpriv->poll_timer, ahci_poll_timer_fn,
+			      CLOCK_MONOTONIC, HRTIMER_MODE_REL);
+		hrtimer_start(&hpriv->poll_timer, ms_to_ktime(1),
+			      HRTIMER_MODE_REL);
+		dev_info(&pdev->dev, "PS4 Baikal: AHCI polling timer started (1ms)\n");
+	}
```

> [!NOTE]
> Correções aplicadas em 2026-07-29 sobre o diff original: `hrtimer_init()` foi trocado por `hrtimer_setup()` (a API antiga foi removida deste kernel — confirmado pelo uso real em `drivers/ata/pata_octeon_cf.c:938`); o filtro por `pdev->vendor == 0x104d` foi trocado por `vendor==PCI_VENDOR_ID_SONY && device==PCI_DEVICE_ID_SONY_BAIKAL_AHCI` (`0x104d`/`0x90d9`), seguindo o padrão idiomático já usado em todo o resto de `ahci.c` (linhas 1782, 1985, 2020, 2089, 2271, 2273) — não corrige um bug funcional (só o AHCI Baikal chega a `ahci_init_one` com vendor Sony), mas evita side-effect caso outro dispositivo Sony compartilhe o driver no futuro.

E no `ahci_remove_one()` (ou via `devm` cleanup), cancelar o timer:

```diff
+	if (hpriv->poll_enabled)
+		hrtimer_cancel(&hpriv->poll_timer);
```

---

### Componente 3: Build e Deploy

Conforme as regras do `AGENTS.md`:

```bash
cd /mnt/t/downloads/PS4/linux_project/distros/arch_minimal_v2

# 1. Editar drivers/ata/libahci.c e drivers/ata/ahci.c no kernel_build_7.0
# 2. Compilar via script oficial:
sudo JOBS=1 ./00-build-kernel-7.0.sh 20260729-sata-polling

# 3. Criar bootargs (copiar do baseline com UART para diagnóstico):
cp boot_referencia/bootargs-7.0-20260729-sata-globallock.txt \
   boot_referencia/bootargs-7.0-20260729-sata-polling.txt

# 4. Reaproveitar initramfs:
cp boot_referencia/initramfs-7.0-20260729-sata-globallock.cpio.gz \
   boot_referencia/initramfs-7.0-20260729-sata-polling.cpio.gz

# 5. Deploy:
sudo ./deploy-boot-7.0.sh 20260729-sata-polling
```

---

## User Review Required

> [!IMPORTANT]
> **Abordagem de Correção da Causa Raiz vs. Fallback:** A Fase A investiga a desativação indevida do `PxIE` no AHCI — dado agora **confirmado** pela reconciliação com o log UART bruto (ver nota acima), tratar como instrumentação exploratória, não como "correção" pronta. A Fase B (polling) fica como salvaguarda, agora com as 3 correções técnicas aplicadas (API `hrtimer_setup`, ack de `HOST_IRQ_STAT`, guarda contra EH/frozen).

## Gaps de Documentação (status em 2026-07-29)

- [x] Testes `20260728-sata-ackfix-ehdump` (nome real da tag que existe em `boot_referencia/`, diferente do nome aspiracional `sata-glue-ack-debug` do plano original) e `20260729-sata-globallock` registrados em `test_history` como ids 67 e 68.
- [x] Contradição `PxIE`/`PxIS` entre este plano e `memory/MEMORY.md` reconciliada com o log UART bruto — `memory/MEMORY.md`, `test_history` id 68 e `consolidado/ESTADO_E_HISTORICO.md` corrigidos.
- Ainda pendente: registrar lição correspondente em `consolidado/LICOES_APRENDIDAS.md` (✅ já feito — ver seção "SATA interno (ata1, Baikal)..." no final do arquivo) e revisar se algum outro documento aponta para a tag `sata-glue-ack-debug` (nome que nunca existiu de fato em `boot_referencia/`).
- Atualizar `consolidado/ESTADO_E_HISTORICO.md` (parado no estado dos ids 63/64) para incorporar a refutação do id 65 (vetor dedicado inútil, deveria ser revertido) e a descoberta `PxIE=0`/teste globallock.
- Registrar uma lição em `consolidado/LICOES_APRENDIDAS.md` sobre esta saga de SATA/AHCI (hoje não há nenhuma menção lá).

---

## Verification Plan

### UART Capture
```bash
scripts/uart_start.sh 900 sata_polling_teste
```

### Critérios de Sucesso
1. **`ata1.00: configured for UDMA/100`** aparece normalmente (probe OK)
2. **ZERO exceções ATA** (`exception Emask`) no log UART em 120+ segundos de boot
3. **`sda`** permanece ativo e acessível: `fdisk -l /dev/sda` via SSH retorna a tabela de partições
4. **Boot total < 30s** (eliminação dos ~78s de cascata EH)
