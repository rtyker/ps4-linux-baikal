# Plano de Ação GBE: Fase 3 — Neutralização do Shutdown do Orbis

## O Estado Atual
- **Teste M1-M7 (ICC/MMIO Power-on):** Refutados. Nenhum payload ICC liga a GBE via Linux.
- **Teste M8-M12 (BAR2 Pervasive):** Refutados. A GBE já tem status de energia idêntico ao de SATA/USB no barramento PCIe; não está presa num estado de hold/pulse da glue logic.
- **Teste M13 (Payloads seguros Major 5):** Refutados. WLAN/BT sobrevivem perfeitamente a comandos ICC, mas GBE continua com ChipID `00`.
- **A Grande Descoberta (Payload orbis-hw-dumper):** O nosso próprio payload executado em Ring 0 no Orbis ANTES do Linux bootar já relata o BAR0 da GBE como ZERADO. Isso significa que **a GBE não cai por causa do Linux, mas sim porque o kernel Orbis (FreeBSD) desliga o driver (`SceGbeMtsCtrl`) durante o preparativo do kexec (shutdown/detach).** O Linux apenas herda o hardware frio.

## Novo Objetivo (Fase 3)
Neutralizar a rotina de `detach` / `shutdown` do driver `SceGbeMtsCtrl` dentro da memória do Orbis *antes* que o payload do kexec a invoque. 
Se o Orbis for impedido de desligar a GBE, o Linux herdará o hardware no estado nativo funcional (energizado).

## Passos para Implementação
1. **Engenharia Reversa (Estática):** Analisar o `kmem_dump_1252.bin` para localizar a tabela de métodos do `SceGbeMtsCtrl`.
2. **Identificação do Alvo:** Encontrar o endereço exato das funções `detach` e `shutdown` deste driver.
3. **Criação do Patch (Em Memória):** Adaptar o payload do Orbis (ex: `orbis-hw-dumper` ou o loader do kexec) para escrever `0xC3` (`ret`) no primeiro byte da função `detach`/`shutdown` do `SceGbeMtsCtrl`.
4. **Teste ao Vivo:** Dar boot pelo payload modificado. Se funcionar, o Linux finalmente vai ler o ChipID corretamente no boot e o eth0 subirá.

## Próxima Ação Imediata
Executar análise no `kmem_dump_1252.bin` com `radare2` para mapear a `device_method_t` table da GBE.

---
## Registro de Testes e Descobertas da GBE Vaccine (Fase 3)

**Descoberta dos Offsets (SceGbeMtsCtrl em 12.52):**
- **Probe:** `0xffffffffdc59ff50`
- **Attach:** `0xffffffffdc5a0070`
- **Detach:** `0xffffffffdc5a0740`
- **Shutdown:** `0xffffffffdc5a0b10`

**Teste V1 (Injeção direta de `0xC3` nas funções):**
- **Ação:** O payload `orbis-hw-dumper` foi modificado para injetar `0xC3` (`ret`) no `detach` e `shutdown` da GBE. Compilado com `-masm=intel`.
- **Resultado:** O console travou no Orbis (Kernel Panic / Deadlock) imediatamente após o "INICIANDO...". O Payload Guest UI respondeu mas não carregou.
- **Causa:** O assembly inline `mov %%cr0, %0` compilado com `-masm=intel` inverteu os operandos (`mov cr0, reg`). Isso escreveu lixo não inicializado no registrador de controle CR0, causando um General Protection Fault (#GP) em Ring 0 e pânico imediato na thread do kernel.

**Teste V2 (Injeção de `31 C0 C3` e correção do ASM):**
- **Ação:** Corrigimos o inline ASM (com `pushf / cli` para evitar interrupts e `mov %0, cr0`) e injetamos `xor eax, eax; ret` para que as funções retornassem `0` (sucesso), satisfazendo o framework newbus.
- **Resultado:** O Payload de vacina aplicou COM SUCESSO! Porém, ao lançar o Linux kexec em seguida, **o PS4 sofreu um hard panic total**.
- **Causa (Corrupção de DMA):** Ao anular por completo a função `shutdown`, nós impedimos que o motor de DMA e os anéis de rede fossem parados. Quando o Linux assumiu a memória, o DMA da GBE continuou escrevendo pacotes da rede em cima da memória do kernel Linux em tempo real, corrompendo o boot.

**Solução Cirúrgica Final (V3 - Atual):**
- **Ação:** Ao descompilar `shutdown` (`0xffffffffdc5a0b10`), descobrimos que ela faz todo o clean-up do DMA corretamente chamando `dc5a3060`, e só no final envia um comando ICC explícito chamando `dc5a24d0` (com o argumento mágico `0x147001E`).
- **Patch:** Substituímos apenas a instrução `call fcn.ffffffffdc5a24d0` (`e8 5d 19 00 00` no offset `0x250b6e` do kernel) por 5 bytes de NOP (`90 90 90 90 90`). 
- **Resultado:** Payload aplicou com sucesso. Porém, ao lançar o `linux-1024mb`, ocorreu um PANIC idêntico ao V2.
- **Conclusão Crítica:** Qualquer alteração no fluxo de `shutdown` (seja pulando a função inteira ou apenas o power down) causa um Kernel Panic durante a rotina de reboot/kexec do FreeBSD. O kernel Orbis ou o Hardware não tolera que o dispositivo GbE permaneça em estado diferente do esperado quando o PCI entra em D3 ou quando o kexec assume.

## Nova Estratégia (Fase 4): Patch no `ps4-kexec`
Se não podemos impedir o Orbis de desligar a GBE, devemos deixar o Orbis desligá-la normalmente e, em seguida, **ligá-la de volta** pelo próprio kexec!
Tentativa 1 (Concluída 21/07): Fizemos um loop em `linux_boot.c` iterando por todo o barramento PCI 0 e forçando o estado `D0` via Power Management Control/Status Register (PMCSR).
- **Resultado:** O Linux bootou e pudemos inspecionar via Telnet. A GbE continuou reportando `unsupported chip type 0x0`, indicando que a energia física do chip (rail) continua cortada, não se tratando apenas de PCI `D3hot`. Além disso, forçar o D0 em todo o barramento congelou o HD SATA (ata1) do PS4.

## Próximo Passo para Amanhã (Fase 5 - PCI ECAM Wakeup no cpu_quiesce_gate)

### Correção Fundamental da Hipótese
A documentação em `RE_KERNEL_GBE_ATTACH.md` esclarece que:
- `dc5a24d0` **NÃO é ICC** — é uma escrita MDIO Clause 45 no PHY da Ethernet
- `dc5a0ba0` é calibração de PHY via MDIO — pressupõe o MAC já vivo
- O `0x147001e` no shutdown é `(reg=0x1470, devad=0x1E)` MDIO, não comando ICC
- **Não existe comando ICC para ligar/desligar a GBE** (Major 5 controla apenas WLAN/BT)
- O power-on da GBE é via BAR4 (Baikal glue logic MMIO), não via ICC
- O kernel Linux coloca o dispositivo PCI `00:14.1` em D3hot porque nenhum driver o reivindica rapidamente

### Implementação (22/07/2026)
1. ✅ **Removido o Loop Genérico PCI D0** (que travava o SATA)
2. ✅ **Injeção cirúrgica no `cpu_quiesce_gate`** (dentro de `linux_boot.c`), logo após o `disableMSI` da seção Baikal:
   - Acessa o PCI Config Space da GbE via ECAM MMIO (`0xf80a1000`)
   - Força D0 no PMCSR (limpa bits [1:0] do Power Management capability)
   - Habilita Memory Space (bit 1) e Bus Master (bit 2) no PCI Command Register
   - Lê e imprime o BAR0 e o ChipID (`BAR0+0x11a`) para diagnóstico
3. **Diagnóstico ao Vivo via Telnet (22/07/2026):**
   - **PCI Config Space Dump (`00:14.1`):** Confirmou Vendor `104d` (Sony), Device `90d8` (Baikal GbE), BAR0 `0xc2000000`, Command Register `0x0542` (Memory Space HABILITADO) e PMCSR em `0x0000` (estado **D0 - Full Power**).

4. **Falha do Payload Fase 5 (22/07/2026):**
   - **O que foi feito de errado:**
     1. Chamadas a `kern.printf()` foram inseridas dentro da função `cpu_quiesce_gate()` em `linux_boot.c` APÓS as interrupções serem limpas e as CPUs secundárias congeladas. Tentar imprimir no console do FreeBSD nesse ponto provoca um **Deadlock/Spinlock Panic** porque o subsistema TTY exige IRQs/mutexes que foram desativados.
     2. Escrita direta no PCI ECAM MMIO (`0xf80a1000`) dentro de `cpu_quiesce_gate` logo após desativar a IOMMU do Baikal (`0xfc000018 &= ~1`), desestabilizando o barramento durante o congelamento dos núcleos.
   - **Ação de Correção Definitiva:** Reverter `linux_boot.c` completamente para o estado original e limpo, sem nenhuma modificação no `cpu_quiesce_gate` ou chamadas `kern.printf`.

## Descoberta de Engenharia Reversa Bit a Bit (Compare Bits - 22/07/2026)
- **Máscara XOR Identificada:** A comparação bit a bit entre `BAR2_RESET_CTRL` (`0x00001249`) e `BAR2_CLOCK_PULSE` (`0x000016c9`) revelou a **diferença exata na máscara `0x00000480`**:
  - **Bit 7 (`0x0080`):** Chave de controle de reset/clock do controlador USB 3.0.
  - **Bit 10 (`0x0400`):** Chave de controle de liberação de Hard Reset/clock do controlador **GbE (Marvell Yukon)**.
- **Sequência de Ativação no Harness (`harness_gbe.py`):**
  1. Hold Mask Bit 10 (`BAR2_CLOCK_HOLD 0xc890a034 = 0x00000400`).
  2. Clock Strobe (`BAR2_CLOCK_PULSE 0xc890a030 = 0x000016c9`).
  3. Release Hold Mask (`BAR2_CLOCK_HOLD 0xc890a034 = 0x00000000`).
  4. Leitura MMIO do `BAR0 + 0x118` e rebind dinâmico do `sky2`.
