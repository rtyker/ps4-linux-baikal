# Investigação Profunda: Habilitação da GBE (Ethernet) no PS4 Pro Baikal (Kernel 7.0)

> ## ⚠️ AVISO — SEÇÃO 3.6 E O "PLANO DE AÇÃO (VERSÃO 2)" ABAIXO ESTÃO REFUTADOS (2026-07-20)
> A premissa central deste documento — que `fcn.ffffffffdc5a3060` escreve no **espaço de configuração PCI padrão** (offsets `0x54`/`0x34`/`0x38`) e que isso "controla o power-gating/clock-gating do Yukon" — **foi verificada por decompilação direta e não se sustenta.**
>
> **O que a função realmente faz** (decompilado real em `consolidado/decompiled_dc5a3060.txt`, análise completa em `consolidado/RE_KERNEL_GBE_ATTACH.md` seção "`decompiled_dc5a3060.txt`"): os offsets `0x54`/`0x34`/`0x38` são relativos a `*(softc+0x3068)+0x10`, que é o par (bus_space tag, handle) da **BAR0 do MAC (MMIO), não o espaço de configuração PCI do dispositivo** (que seria acessado via `pci_write_config`, mecanismo completamente diferente). `dc5a3060` é a rotina de **"stop"** do MAC (par oposto de `dc5a31f0`, chamada no caminho `SIOCSIFFLAGS` down) — um reset/parada de bloco que só tem efeito útil se a rail/clock do MAC **já estiver ligada**. Não é um comando de power-gating do Syscon.
>
> **Portanto: NÃO compilar/testar o patch da Seção 4 (`sky2_probe`) como está.** Escrever nos offsets `0x54`/`0x34`/`0x38` do **PCI config space real** (via `pci_write_config_dword`, como o patch propõe) escreveria em registradores completamente diferentes dos que o Orbis realmente toca (capability/config header do dispositivo, não a BAR0 do MAC) — não tem lastro de RE e é exatamente o tipo de "tentativa às cegas" que devemos evitar. Na melhor hipótese seria inócuo (campo inválido ignorado); na pior, corrompe capabilities reais do link PCIe.
>
> Ver `memory/INVESTIGACAO_GBE_ETHERNET_BAIKAL.md` (log "rodada 2 — CORREÇÃO") para o histórico completo da correção. As seções 1-3 e 3.5 deste documento (diagnóstico do hardware, loop ICC `4/0x38`, registrador `BAR2+0x10a030`) continuam válidas — só a 3.6 e o plano derivado dela (Seção 4) é que estão refutados.

---

Este documento consolida a análise estática detalhada do kernel Orbis 12.52 (obtida via Engenharia Reversa do dump de memória `kmem_dump_1252.bin`) em comparação direta com o código-fonte do Kernel Linux 7.0 do nosso projeto. O objetivo é estabelecer um plano concreto e seguro para fazer o chip da rede cabeada (Yukon-2 / `sky2`) ser alimentado e reconhecido, sem recorrer a depurações intempestivas no console.

---

## 1. O Diagnóstico Atual do Hardware

Ao bootar o Linux seguro (`20260720-sky2len-fix`), o vídeo HDMI e a rede Wi-Fi funcionam estavelmente. A leitura do `dmesg` do barramento PCI revela que o dispositivo GBE está presente no barramento (`00:14.1`), mas o driver `sky2` falha ao tentar sondar o registrador do ID do chip:

```
[    0.683834] sky2: driver version 1.30
[    0.683936] sky2 0000:00:14.1: unsupported chip type 0x0
```

### A Causa Raiz Física:
O valor `0x0` indica que o bloco físico da GBE (MAC/PHY) no Southbridge está **sem alimentação ou sem clock**. No hardware do PS4 Pro, trilhos de energia secundários e clocks periféricos são controlados dinamicamente pelo **Syscon** via mensagens ICC (Interface Control Channel). Sem receber a ordem de inicialização do SO, a GBE permanece desligada por padrão.

---

## 2. Engenharia Reversa: O Fluxo de Bring-up no Orbis 12.52

Analisamos as rotinas de attach do driver de rede original da Sony descompiladas do dump de kernel Orbis:

### A. O Loop de Power-On via ICC (MAC & PHY)
Nas rotinas `SceGbeMtsCtrl_attach` (`0xffffffffdc5a41d0`) e `SceGbeMtsPhyCtrl_attach` (`0xffffffffdc5a44c0`), a Sony **não** escreve em registradores de energia diretamente. Em vez disso, ambas as rotinas entram em um loop de espera passivo consultando o Syscon:

* **O Loop:** O driver executa até 100 iterações com um intervalo de 100ms entre elas (tempo total de espera de até 10 segundos).
* **O Comando ICC:** Em cada iteração, ele chama a função interna `icc_query(major=4, minor=0x38, len=1, &var_29h)`.
* **A Condição de Sucesso:** O driver só prossegue com a inicialização se a resposta de 1 byte retornada pelo Syscon for **`0x01`**.

#### Funcionamento Interno de `icc_query(4, 0x38)`:
A descompilação de `func_0xffffffffdc3f5bd0` (o wrapper de comandos ICC) revela que:
1. Ele limpa a estrutura de requisição (`bzero`).
2. Define o cabeçalho ICC com os campos correspondentes (`major=4`, `minor=0x38`, `arg=1`).
3. Envia o pacote de forma síncrona sem dados adicionais de entrada (payload de entrada = 0 bytes).
4. Copia o byte retornado na resposta para o buffer do chamador.

> **Nota:** No protocolo ICC do Syscon, consultas de estado (como `4 0x38`) frequentemente atuam como **gatilhos de transição de estado**. O envio dessa consulta informa ao Syscon que o sistema operacional está carregando o driver de rede, fazendo com que o firmware do Syscon ative a alimentação e o clock da GBE. Uma vez que o circuito físico estabiliza, as consultas seguintes retornam `0x01`.

---

### B. Inicialização do PCIe Host (`baikal_pcie`) e o Registrador de Clock
O driver PCIe da Sony (`baikal_pcie_attach`, `0xffffffffdc718eb0`) faz o mapeamento de três BARs: BAR0 (`rid=0x10`), BAR2 (`rid=0x18`) e BAR4 (`rid=0x20`).

* **Leitura de Identificação:** O driver lê a revisão e IDs do SoC a partir da BAR4 (offsets `0x4084`, `0xc020` e `0xc024`).
* **Verificação do Chip/Stepping:** A função `0xffffffffdc526e40` verifica o stepping do processador (se `val & 0xff0000 == 0x30000`).
* **A Escrita em `BAR2+0x10a030`:** Se for um Baikal Pro (stepping correspondente), ele chama a sub-rotina `0xffffffffdc7190d0`, que lê `BAR2+0x10a030` e escreve o valor `(reg & 0xfffffe07) | 0xd8`.

#### Por que isso causou Tela Preta no Linux?
Na primeira tentativa de hoje, o kernel Linux travou sem vídeo porque inserimos essa escrita incondicionalmente na função `bpcie_glue_init`. Essa função roda muito cedo no boot do Linux, antes de os subsistemas gráficos (amdgpu, bridge de display) estarem prontos. Como o registrador `BAR2+0x10a030` envia um strobe de clock para barramentos do pervasive glue compartilhados com o Southbridge, o strobe prematuro desativou o clock do display e congelou o sistema.

---

## 3. Comparação com Outros Dispositivos no Linux

No nosso driver Linux atual (`drivers/ps4/ps4-bpcie-icc.c`), a alimentação dos outros periféricos periféricos é ativada via mensagens ICC idênticas durante o boot:
* **Wi-Fi / Bluetooth:** Ativado via `bpcie_icc_cmd(5, 0, &on, sizeof(on), resp, 20)` (onde `on = 3`).
* **Portas USB:** Ativado via `bpcie_icc_cmd(5, 0x10, &on, sizeof(on), resp, 20)` (onde `on = 1`).

A GBE (Ethernet) foi completamente omitida da inicialização de energia do Linux por falta de documentação prévia dos comandos ICC específicos (`major=4, minor=0x38`).

---

## 3.5. A Desconexão dos Testes Anteriores (Causa das Falhas Individuais)

Analisando a tabela de depuração em [ICC_GBE_TEST_LOG.md](file:///mnt/t/downloads/PS4/linux_in_ps4/consolidado/ICC_GBE_TEST_LOG.md#L21), identificamos por que os testes anteriores falharam de forma independente:

* **Nos Testes #3 e #4 (ICC sem Clock):** O comando `4 0x38` foi enviado com sucesso, mas o registrador de clock `BAR2+0x10a030` **não** tinha sido ativado. A GBE permaneceu sem clock, lendo `ChipID = 00 00`.
* **No Teste M3 (Clock sem ICC):** A escrita do strobe de clock em `BAR2+0x10a030` foi realizada, mas o comando ICC `4 0x38` **não** foi enviado naquela sessão. O bloco físico permaneceu power-gated pelo Syscon, lendo `ChipID = 00 00`.

**A Chave do Sucesso:** A GBE Yukon só é habilitada por completo quando **ambos** os trilhos (Clock em `BAR2+0x10a030` e Power via ICC `4 0x38`) são ativados em conjunto.

---

## 3.6. A Revelação: Inicialização do Config Space PCIe da GBE (Orbis)

Ao decompilarmos a função [fcn.ffffffffdc5a3060](file:///mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled_dc5a3060.txt) do driver `SceGbeMtsCtrl` (chamada durante a inicialização em [decompiled_dc5a3810.txt:L213](file:///mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled_dc5a3810.txt#L213)), descobrimos que a Sony realiza uma sequência de escritas em registradores proprietários dentro do **espaço de configuração PCI padrão** da GBE (dispositivo `00:14.1`):

1. **Configuração de Energia/Filtro (`0x54`):** Escreve `0x7ffffa` no offset de configuração `0x54`.
2. **Reset/Habilitação do Bloco 1 (`0x34`):** Escreve `2` no offset `0x34` e entra em um loop de polling até que o bit 1 (`val & 2`) seja limpo pelo hardware.
3. **Reset/Habilitação do Bloco 2 (`0x38`):** Escreve `2` no offset `0x38` e entra em um loop de polling até que o bit 1 (`val & 2`) seja limpo pelo hardware.
4. **Acoplamento do Clock/Status:**
   * Lê o offset `0x34`, faz `val | 1` (seta bit 0) e escreve de volta.
   * Lê o offset `0x38`, faz `val | 1` (seta bit 0) e escreve de volta.
5. **Finalização do Strobe (`0x54`):** Escreve `0` no offset `0x54`.

### Por que esta descoberta é crucial e segura?
* **Sem Risco de Travamento:** Estes registradores estão na faixa padrão de 256 bytes do PCI Config Space (offsets `0x00`-`0xff`), cuja leitura e escrita são 100% seguras no Baikal (o dmesg de boot já as lê com sucesso). A "mina terrestre" de desligar o console só ocorre ao acessar o espaço *estendido* (`config` > `0x100`) ou fazer leituras contíguas no pervasive `BAR2`.
* **Causa do ID = 0x00:** Como o Linux nunca realizava este handshake de inicialização proprietário do slot PCIe GBE no boot, o núcleo físico do Yukon continuava power/clock gated, fazendo com que a leitura de `B2_CHIP_ID` em `BAR0 + 0x11a` retornasse sempre zero.

---

## 4. Plano de Ação Concreto e Seguro (Versão 2)

Para prosseguirmos com segurança total e sem chutes, faremos a integração direta desta máquina de estados no driver Linux:

### Fase 1: Implementação da Inicialização no `sky2_probe`
Adicionar a sequência exata de inicialização do slot PCIe da GBE no início da função `sky2_probe` em [sky2.c](file:///mnt/hdauxiliar/temp/kernel_build_7.0/drivers/net/ethernet/marvell/sky2.c#L4915), logo após `pci_enable_device(pdev)` e antes de ler ou mapear qualquer recurso do Yukon.

```c
	/* Inicialização do slot PCIe GBE Baikal (Orbis fcn.ffffffffdc5a3060) */
	if (pdev->vendor == PCI_VENDOR_ID_SONY && pdev->device == 0x90d8) {
		u32 val;
		int timeout;

		dev_info(&pdev->dev, "Applying Baikal GBE PCIe slot initialization...\n");

		pci_write_config_dword(pdev, 0x54, 0x7ffffa);

		pci_write_config_dword(pdev, 0x34, 2);
		timeout = 1000;
		do {
			pci_read_config_dword(pdev, 0x34, &val);
			if (!(val & 2))
				break;
			udelay(10);
		} while (--timeout);

		pci_write_config_dword(pdev, 0x38, 2);
		timeout = 1000;
		do {
			pci_read_config_dword(pdev, 0x38, &val);
			if (!(val & 2))
				break;
			udelay(10);
		} while (--timeout);

		pci_read_config_dword(pdev, 0x34, &val);
		pci_write_config_dword(pdev, 0x34, val | 1);

		pci_read_config_dword(pdev, 0x38, &val);
		pci_write_config_dword(pdev, 0x38, val | 1);

		pci_write_config_dword(pdev, 0x54, 0);
	}
```

### Fase 2: Compilação e Deploy (Apenas sob sua autorização)
* Aplicar a alteração no código fonte `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/net/ethernet/marvell/sky2.c`.
* Compilar a nova tag do kernel (ex: `20260720-gbe-config-init`).
* Gerar a imagem e aguardar seu sinal de "pronto" antes de qualquer tentativa no console real.
