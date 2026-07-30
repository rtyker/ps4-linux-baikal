# Plano em Fases — Driver GBE Baikal (mts.ko), pós-sessão 2026-07-24/25 (v2)

> **⚠️ SUBSTITUÍDO (2026-07-29) por [`PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md`](PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md)** — mantido aqui só como histórico. O plano novo corrige uma inconsistência séria achada neste documento: os testes #61/#62 (item "7. ❌ REFUTADO" abaixo) nunca tiveram a refutação refletida no SQLite `test_history` (corrigido agora). Ler o plano novo antes de continuar qualquer investigação do GBE.
>
> Substitui/atualiza `PLANO_FASES_GBE_2026-07-24.md` (mantido como histórico) — vários itens daquele plano já foram implementados nesta rodada, ver "Contexto" abaixo.

## Contexto — o que mudou desde o plano anterior (PLANO_FASES_GBE_2026-07-24.md)

O plano anterior já foi parcialmente executado. Releitura de `PHY_DEBUG_SESSION_20260724.md`, `memory/MEMORY.md`, `AGENTS.md` e `drivers_mts/mts.c` (código atual) confirma:

**Itens do plano anterior já implementados em código** (não repetir como "a fazer"):
1. `mts_mac_stop()` reescrito seguindo `dc5a3060`: `IMR=0x7ffffa` → `0x34=2` (poll bit1 até zerar) → `0x38=2` (poll bit1) → `mts_tx_drain_force()` → `0x1c8 &= ~0x440`. Código em `mts.c:1086-1112`.
2. `mts_mac_enable()` simplificado: `mts_write()` direto (sem RMW) em `0x34`/`0x38`, sem re-enable pós-calibração. Código em `mts.c:1114-1129`.
3. **TX doorbell corrigido**: `mts_start_xmit()` agora escreve o endereço completo do descritor (`tx_ring_dma + tx_idx*MTS_DESC_SIZE`) em `MTS_TX_RING_PTR` (0x3c), não mais o índice cru. Código em `mts.c:1406`. Isso é exatamente o item "Fase 2 #2" do plano anterior — já está na árvore, só falta validar ao vivo.
4. `0x200` não é mais escrito em lugar nenhum (nem calibração, nem enable) — confirmado por grep, zero ocorrências de escrita.
5. `AGENTS.md` atualizado com regras críticas do driver (MAC enable/stop, 0x200, PHY MDIO) e topologia SSH — deploy migrado de telnet para SSH (`scripts/deploy_mts.sh push|test`).

**Novo achado crítico desta rodada (Test 5/Test 6, ainda não neutralizado por completo):**
- `mts_set()` (read-modify-write) escrevia `0x09` em vez de `0x01` no re-enable do MAC — hardware rejeitava. Corrigido usando `mts_write()` direto (item 2 acima).
- Após ~4 ciclos rmmod/insmod com o `mts_mac_stop()` **antigo** (que escrevia 0, clear bit 0), o MAC enable parou de responder **permanentemente até power cycle** — dano já feito, ainda não revertido. **O estado atual do hardware pode estar corrompido** até o próximo power cycle completo, independente do fix já estar no código.

**O que continua em aberto (não resolvido pelas mudanças desta rodada):**
- PHY continua mudo: MDIO Clause 45 retorna `0x0000` em todos os registradores mesmo com `hold_val=0x10` + clock config (`0x10A030`) + soft-reset — este é o bloqueador central, atravessando múltiplas sessões (07-22 a 07-25).
- RX completamente morto: `OWN=1` permanentemente, 0 pacotes recebidos.
- TX só em software (contagem por software avança, contadores de hardware `MTS_CNT_PKTS` em zero) — mas isso foi testado **antes** do fix do doorbell (item 3) ter sido validado ao vivo; pode mudar.
- Link "1000 Mbps Half duplex" continua sendo uma combinação inválida para 1000BASE-T — sinal de que não há negociação real, é só o valor forçado em `mts.c:884` (`(link_save & 0x7fffcfff) | 0x61`) pegando parcialmente (bit 0 gruda, bit de full-duplex aparentemente não, conforme tabela de registradores do Test 4).
- **Ordem de operações ainda suspeita**: o diagnóstico MDIO pós-calibração (`mts.c:1033-1052`) roda **antes** do poll final de release do hold (`mts.c:1057-1069`) — ou seja, o teste de Clause 45/22 acontece com o hold ainda em `0x10`, não depois do release. O poll final (linhas 1061-1069) testa MDIO de novo após o release, mas **falha silenciosamente** se nunca sair do loop — não há `dev_warn`/log nesse caso, só o comentário implícito de sucesso. Isso nunca foi instrumentado.
- A varredura completa da janela Glue BAR2 `0x140000`-`0x180000+` por bits de power-gate/isolamento **continua nunca executada** (pendente desde a sessão de 07-23, repetida no plano de 07-24, ainda não feita).

**Hipóteses já refutadas — não repetir:** IRQ real `IMR=0x7d` isolado (testado, Link DOWN/zero IRQs), `MTS_MAC_EN2` como causa raiz, Clause 22 BMCR em qualquer `phy_addr`, forçar full-duplex via escrita direta em 0x04 fora da calibração (no-op confirmado em teste isolado anterior — mas note-se: dentro da calibração o resultado é diferente/parcial, ver acima), BAR2 vs BAR4 do efuse (corrigido), decoder MDIO packed trocado (corrigido), inversão ingênua do bit OWN em RX (corrigido), teste de eth0 via subnet WiFi (inválido).

**Regra de Ouro em vigor:** nenhum teste ao vivo roda sem o usuário confirmar "pronto" explicitamente, PS4 ligado e acessível via SSH.

---

## Fase 0 — Recuperação e validação pós-power-cycle (1 power cycle, sem mudança de código)

Prioridade máxima: o hardware pode estar num estado corrompido pelo `mts_mac_stop()` antigo (dano de sessões passadas). É preciso confirmar que os fixes já aplicados resolvem isso antes de investigar qualquer coisa nova.

1. Power cycle completo do PS4 (tirar da tomada 15-30s), subir com o kernel/initramfs já validado.
2. Deploy do `mts.ko` atual via `scripts/deploy_mts.sh push` (ou manual com `hold_val=0x10`), confirmar via dmesg que `0x34`/`0x38` leem `1` de forma estável (sem precisar de re-enable).
3. Rodar `scripts/deploy_mts.sh test` (ifconfig eth0 192.168.0.2, ping -I eth0 192.168.0.1, captura `mts_regs`) e registrar os valores de `0x04`, `0x34`, `0x38`, `0x50`, `0x70`, `MTS_CNT_PKTS`/`MTS_CNT_BYTES`.
4. Fazer **vários** ciclos `rmmod`/`insmod` (sem power cycle) para confirmar que o novo `mts_mac_stop()` não corrompe mais o estado do MAC (reproduzir o Test 6, mas com o fix aplicado) — critério de sucesso: MAC enable continua respondendo após 4+ ciclos.
5. Validar ao vivo o fix do doorbell TX: enviar pacotes (ping ou similar) e conferir se `MTS_CNT_PKTS`/`MTS_CNT_BYTES` (contadores de hardware) avançam agora que `0x3c` recebe o endereço completo do descritor em vez do índice cru.

## Fase 1 — Diagnóstico read-only ampliado do PHY mudo (mesmo power cycle da Fase 0, ou novo se necessário)

Objetivo: atacar o bloqueador central (Clause 45 sempre zero) com dados que nunca foram coletados.

> ### ✅ EXECUTADO 2026-07-25 (itens 1-4) — ver `test_history` no sqlite (`consolidado/ps4_hardware_memory.db`) para o registro completo
>
> 1. **Varredura completa da janela Glue BAR2 `0x140000`-`0x180000`** feita via `/dev/mem` em userspace (sistema já bootado), 64 blocos de 4KB, com verificação de conectividade antes/depois — **sem incidente**. Dados brutos e análise em `consolidado/glue_140000_180000_raw.txt` / `consolidado/glue_140000_180000_analise.txt`. Achados: (a) tabela stride `0x400` em `0x140000-0x141fff` com 8 blocos "ricos" (campo ID em `+0x000` alternando `0x10206333`/`0x10106333`); (b) grandes runs `ALL_FFFFFFFF` (regiões não decodificadas); (c) tabela stride `0x1000` de `0xc896b000` a `0xc897c000` com 17 blocos "ricos" de 12 valores — candidato mais forte a tabela por-periférico, **mas os blocos amostrados são byte-a-byte idênticos entre si**, então a identidade "qual bloco é a GBE" **não é observável só por leitura passiva** (mesma limitação já documentada no `M11_identidade_blocos.md`). Nenhum bit de power-gate da GBE identificado com confiança nesta rodada — precisaria de correlação com a RE do `kmem_dump_1252.bin` ou teste ativo (fora do escopo read-only).
> 2. **Poll de release do hold instrumentado** (loga as 50 iterações + `dev_warn` se esgotar sem sucesso) — implementado em `drivers_mts/mts.c:mts_phy_calibration()`.
> 3. **Diagnóstico MDIO pós-calibração reordenado** para rodar depois do release do hold — **testado ao vivo, hipótese REFUTADA**: 50/50 tentativas do poll pós-release esgotadas (reg0 sempre `0x0000`), e o diagnóstico reordenado deu resultado idêntico ao anterior (Clause 45 `ret=0 val=0x0000`, Clause 22 timeout). A ordem não era a causa.
> 4. **`0x50` logado em 4 fases**: pré-hold=`0x18a0`, pós-hold=`0x18a0` (hold assert não muda), pós-tuning=`0x00000000`, pós-release=`0x00000000`. Cai para zero em algum ponto do loop de calibração/tuning (66 iterações); não virou pista de power-gate por si só, e diverge do padrão de uma sessão anterior registrado em `mts.h` — parece não ter comportamento fixo entre sessões.
> 5. Ainda não feito (retomar na próxima sessão).
>
> **TX/RX nesta rodada (Fase 0, pós-power-cycle):** MAC enable estável em 3 ciclos rmmod/insmod sem corrupção. TX avança em software (26 pacotes/1836 bytes no `ip -s link`) mas `MTS_CNT_PKTS`/`MTS_CNT_BYTES` (contador de hardware) continuam em 0 — sem confirmação de transmissão física real. RX confirmadamente morto (`OWN=1` permanente, 0 pacotes, ping do PS4 para o host deu "Destination Host Unreachable" por falha de ARP).

1. ~~Varredura completa da janela Glue BAR2 `0x140000`-`0x180000+`~~ **Feito 2026-07-25, ver acima.**
2. ~~Instrumentar o poll final de release do hold~~ **Feito 2026-07-25.**
3. ~~Reordenar o diagnóstico MDIO pós-calibração~~ **Feito e testado 2026-07-25 — hipótese refutada.**
4. ~~Logar o registrador `0x50` em cada fase~~ **Feito 2026-07-25, ver acima.**
5. ✅ **Feito 2026-07-25:** escrita forçada de full-duplex em `0x04` continua sem colar de forma útil — neste ciclo `pre 0x04=0x00000b19` e `post 0x04=0x00000b19` (idêntico, o OR com `0x61` não mudou nada visível; hardware parece re-afirmar seu próprio estado). Confirma o "no-op" já documentado em sessões antigas, com o pipeline atual.

## Fase 2 — Mudanças de código direcionadas (com base no que a Fase 1 revelar)

1. Fase 1 **não** achou um bit de power-gate confirmável na janela Glue (blocos candidatos são idênticos entre si, identidade não observável por leitura passiva) — item não aplicável ainda.
2. Reordenar o diagnóstico (Fase 1 item 3) **não mudou o resultado** — mantido no código por ser logicamente mais correto (testa depois do release), mas não é a causa raiz.
3. Full-duplex em `0x04` continua não colando (item 5 acima) — **ainda não implementada** a reescrita periódica via timer; baixa prioridade dado que é só cosmético (não afeta se o PHY responde de verdade).
4. TX real via hardware **ainda não confirmado** — `MTS_CNT_PKTS`/`MTS_CNT_BYTES` continuam em 0 mesmo após o fix do doorbell (2026-07-25), apesar do software reportar pacotes completados. RX continua sem investigação nova além do que Fase 1 já cobriu.

## Fase 3 — IRQ real

> ### ✅ EXECUTADO 2026-07-25 (item 2) — hipótese refutada de novo
> Retestado `irq_mask=0x7d` com **todos** os fixes atuais (`hold_val=0x10`, `mts_mac_stop()` corrigido, doorbell TX corrigido) e guarda de tempestade ativa como rede de segurança. `IMR` confirmado em `0x7d` via log, IRQ `Baikal-MSI` registrada em `/proc/interrupts` (linha 37) — mas **contagem 0 em todas as 8 CPUs**, `irq_count=0` no driver. Nenhuma interrupção real disparou. Isso reforça a conclusão de que a ausência de IRQ não vinha de nenhum dos fixes de software aplicados desde o teste original refutado — é consistente com o PHY genuinamente não gerar nenhum evento físico (sem sinal = sem IRQ, independente do IMR). **Não repetir sem nova teoria.**
> Item 1 (localizar o registrador real de ACK/status de IRQ) continua pendente — seria só relevante se algum dia uma IRQ real chegasse a disparar.

1. Localizar o registrador real de ACK/status de IRQ via decompilação `dc5a31f0`/funções vizinhas. **Ainda pendente, baixa prioridade agora** (sem IRQ disparando, não há o que "confirmar via ACK").
2. ~~Re-testar `IMR` do zero~~ **Feito 2026-07-25 — hipótese refutada novamente, ver acima.**

## ✅ Correção de RE 2026-07-25 (após reler a descompilação já existente no projeto)

`consolidado/decompiled/baikal_glue_block_reset_dc6df.txt` (descompilação de `fcn.ffffffffdc6df850`, já existia, nunca tinha sido cruzada com o offset de hold usado no driver) mostra `fcn.dc59fe10()` — a rotina de *stop* do MAC da GBE, já confirmada por RE anterior — chamada **imediatamente antes** do bloco `0x2000`, cujo par é `hold=0x20, pulse=0x74`. O driver e o `AGENTS.md`/`LICOES_APRENDIDAS.md` usavam `hold=0x180034`, valor que veio de uma inferência por padrão (`hold = pulse - 0x40`) nunca checada contra essa descompilação — `0x180034` pertence a um bloco diferente e não identificado (`0x3c00`), que nem tem par hold/pulse.

**Corrigido:** `drivers_mts/mts.c` agora usa `hold=0x180020` (confirmado, bloco `0x2000`). Testado ao vivo: escrita no registrador correto executada sem incidente (console permaneceu estável, confirmado por `uptime` + ping), mas **o PHY continuou completamente mudo** (MDIO zero antes e depois, Clause 22 timeout) — toggling hold/pulse sozinho não é suficiente, consistente com o achado antigo do M8 (o registrador já lia "liberado" mesmo sem nenhuma escrita nossa). A correção vale por si (documentação e código agora batem com a fonte real), mas não resolveu o RX.

## RE adicional 2026-07-25 (mineração dos decompiled_*.txt já existentes, sem gerar nada novo)

Reli a fundo `decompiled_gbe_phy_attach.txt` (thread `gbe_phy_ctrl`, `fcn.dc5a44c0`) e `decompiled_dc5a58d0.txt` (handshake RMU), ambos já existiam no projeto mas nunca tinham sido cruzados com os timeouts/registradores que o driver Linux usa. Dois testes ao vivo saíram daí:

1. **Poll de PHY estendido de 500ms para ~20s** (201×100ms, copiando literalmente o loop de `fcn.dc5a44c0`), testando bit 2 específico (não "qualquer valor não-zero"). **Testado — refutado**: 20 segundos completos, registrador em `0x0000` do início ao fim, nem um valor transitório. Descarta definitivamente "só faltava esperar mais".
2. **Bit 2 (`0x4`) de `BAR0+0x34`** — achado em `dc5a58d0`, setado pelo Orbis ao enviar um frame de gerenciamento pro firmware RMU embarcado, nunca testado antes (só bit0=enable e bit1=soft-reset eram conhecidos). Testado um OR pontual isolado (sem o frame RMU completo). **Inconclusivo**: `0x34` não retém valor nenhum na leitura (confirma o padrão já documentado em `mts.h`), MDIO não mudou. O handshake RMU completo (montar o frame de 34 bytes, enviar via TX, esperar resposta) **não foi implementado** — a resposta depende de um contador que só um handler de RX ou IRQ incrementaria, e os dois já foram confirmados mortos nesta mesma sessão. Não vale implementar o frame completo sem resolver isso primeiro.

**Achado estrutural importante (não testado, é leitura de código):** tanto a thread MAC (`gbe:ctrl`, `fcn.dc5a41d0`) quanto a thread PHY (`gbe:phy_ctrl`, `fcn.dc5a44c0`) são **máquinas de estado orientadas a evento** — dormem indefinidamente (MAC) ou com timeout de ~3s (PHY) esperando bits externos (`0x1`, `0x2`, `0x100`, `0x10000`, `0x20000`) que só um handler de IRQ real (ou a própria RMU) seta. Como IRQ real está confirmado morto (Fase 3, 0 interrupções), **todo esse caminho de código real do Orbis nunca chega a rodar de fato nas condições que estamos reproduzindo** — o que é consistente com (não prova, mas encaixa) a hipótese de que o bloqueador é anterior a qualquer coisa que o driver, MAC ou PHY software façam: energia/clock físico do PHY que nunca chega, ponto.

## Handshake RMU implementado e testado 2026-07-25 (item 1 da lista de próximos passos)

Reconstruí byte a byte o frame de gerenciamento de 34 bytes que `fcn.ffffffffdc5a5ec0` (Orbis) monta e envia pro firmware RMU embarcado, cruzando `consolidado/decompiled_dc5a5ec0.txt` (linhas 131-148) com as constantes reais lidas de `kmem_dump_1252.bin`:

```
[0:6]   01 50 43 00 00 00   "destino" (constante ROM @0xdcb0e02c)
[6:12]  00 00 00 00 00 00   "origem" (softc+0x30d6, campo condicional -- config rara ausente neste HW, assumido zero)
[12:14] 91 00               campo fixo (ROM @0xdcb0e01f)
[14:16] 00 00               zero
[16:18] 42 fa               MAGIC 0xfa42 (little-endian)
[18]    0f
[19]    01 (seq, incrementa) 
[20:34] zero / constantes ROM zeradas
```

Implementado `mts_send_rmu_frame()` em `drivers_mts/mts.c`, escrevendo esse frame direto num descritor TX (mesmo mecanismo do doorbell já validado). Testado ao vivo: **enviado sem incidente** (console permaneceu estável), **mas sem nenhuma reação observável** — `BAR0+4` (link) e MDIO idênticos antes/depois do envio + 300ms de espera.

**Achado colateral importante:** o descritor TX só é reciclado (`OWN` volta a 1) quando o timer/NAPI está rodando (ou seja, depois de `mts_open()`/`ifconfig up`) — durante o `probe()`, sem nenhum reclaim ativo, o hardware **nunca** marca sozinho um descritor como concluído. Isso reforça (não é bug do teste, é dado real) que a "conclusão" de TX neste driver é inteiramente uma contabilidade de software (`tx_reclaim` assume sucesso ao ver `OWN=0`, sem esperar confirmação real de hardware) — consistente com `MTS_CNT_PKTS` (contador de hardware) nunca ter saído de zero em nenhuma sessão.

**Não implementado:** a validação completa do handshake (esperar o contador de resposta `softc+0x3108`/`+0x3109`, que só um handler de RX real incrementaria) — não implementada porque depende de RX ou IRQ real, ambos confirmados mortos nesta mesma sessão. Mesmo que o firmware RMU tenha processado o frame de alguma forma, não temos como detectar isso sem resolver RX/IRQ primeiro. Variante não testada: usar o MAC real (`2c:cc:44:3f:69:5f`) no campo "origem" em vez de zero, caso o campo do softc não seja realmente zero neste hardware.

## Estado no fim da sessão 2026-07-25 (honesto)

RX continua morto. Nesta sessão foram eliminadas concretamente 3 hipóteses (ordem do diagnóstico MDIO, IRQ real com os fixes atuais, correlação estática do bloco de 12 valores da janela Glue com o dump do kernel Orbis) e mapeada com segurança toda a janela `0x140000-0x180000` da BAR2 (sem incidente, dados salvos). Não foi encontrado nenhum novo candidato concreto de "bit que falta". Os caminhos que restam, em ordem de custo/benefício:
1. ~~RE mais profunda do `kmem_dump_1252.bin` para tentar mapear a tabela de 17 blocos (stride `0x1000`) encontrada na varredura~~ **Feito 2026-07-25 (sessão seguinte), resultado NEGATIVO — ver abaixo.**
2. Aceitar que o PHY pode depender de uma sequência de bring-up que a Sony faz fora do driver `SceGbeMtsCtrl` (SAMU/bootloader/sequenciamento fixo em hardware) e que não é replicável via software do Linux — nesse caso o bloqueador pode não ter solução por essa via.

### RE mais profunda do dump — resultado NEGATIVO (2026-07-25)

Investigação via `radare2`+`r2ghidra` no `kmem_dump_1252.bin` (`baddr=0xffffffffdc350000`), tentando achar a função que indexa a tabela de 17 blocos (stride `0x1000`, `0xc896b000`-`0xc897c000`, offset BAR2 `0x16b000`-`0x17c000`):
- Confirmado que `fcn.ffffffffdc6df850` (já documentada em `consolidado/decompiled/baikal_glue_block_reset_dc6df.txt`) só cobre a janela pequena `0x140000`-`0x142000` (9 blocos, offsets hardcoded `0x4000/0x4400/0x3800/0x4800/0x2000/0x3c00/0xc00/0x1000/0x1400`, sem loop) — **não é** a função da tabela grande.
- Busca exaustiva no binário inteiro por constante imediata em código, tanto do offset absoluto da tabela (`0x16b000`/`0x17c000`, várias codificações) quanto do valor de cabeçalho característico dos blocos "ricos" (`0x000b0331`) e do padrão de sub-registradores (`0x00090010`/`0x00090008`/etc): **zero ocorrências no segmento executável** (`LOAD0`, `0xffffffffdc350000`-`0xffffffffdd04e758`). Os únicos hits caíram no segmento de dados (`.data`/`.bss`, `LOAD1`), coincidência de bytes, não referência de código.
- **Conclusão:** essa tabela não é referenciada por nenhuma função do kernel FreeBSD/Orbis dumpado — é programada/lida por firmware fora do kernel (SAMU ou bootloader, antes do FreeBSD rodar). RE estática deste dump específico não vai revelar a ordem dos periféricos nessa tabela; não há função pra decompilar.
- **Achado colateral (não resolve o bloqueador, mas reforça uma identificação já feita):** o bloco `0xc8942000` (offset `0x2000`, já suspeito = GBE pela adjacência com `dc59fe10`/stop-MAC na função de reset) leu dado estruturado no teste M11 (07-23) mas `ALL_FFFFFFFF` na varredura completa (07-25) — mais provável reflexo do estado do nosso próprio driver no momento do teste (MAC parado vs. rodando) do que uma pista nova de power-gate externo, mas consistente com `0x2000` = GBE.
- **Item 1 dado como esgotado** com as ferramentas/dump disponíveis. Restam: item 2 (aceitar limite de hardware) ou novas alternativas ainda não tentadas (ver seção seguinte).

---

## Arquivos principais

- `drivers_mts/mts.c` — `mts_phy_calibration()` (586-1070), `mts_mac_stop()` (1086-1112), `mts_mac_enable()` (1114-1129), `mts_start_xmit()`/doorbell (1358-1428), `mts_interrupt()` (1711+), module_params (63-124).
- `scripts/deploy_mts.sh` (push/test via SSH), `scripts/build_mts_module.sh`.
- `PHY_DEBUG_SESSION_20260724.md` — atualizar a cada novo resultado.
- `AGENTS.md` — regras críticas do driver, manter atualizado.
- `memory/MEMORY.md` — registrar cada achado imediatamente (regra #2 do projeto).

## Verificação

Cada fase é validada em hardware real via SSH (`scripts/deploy_mts.sh`), com:
- dmesg/log do módulo para a sequência de calibração e stop,
- `mts_regs` sysfs para dump de registradores BAR0/BAR2/BAR4,
- ping `192.168.0.1↔192.168.0.2` via `eth0` (nunca via subnet WiFi) como teste de RX,
- `MTS_CNT_PKTS`/`MTS_CNT_BYTES` (hardware, clear-on-read) como teste de TX real.

## Testes de RMU e Glue 0x142020 executados ao vivo (2026-07-25)

1. **Gatilho sysfs `trigger_rmu` (Fase 1 e Fase 2)**:
   - Com `eth0` ativada (`ifconfig eth0 192.168.0.2 up`), o controlador DMA da GBE processou pela **PRIMEIRA VEZ** os quadros RMU in-band de 34 bytes (magic `0xfa42`), tanto Fase 1 (`cmd=0x0000`) quanto Fase 2 (`cmd=0x800b`, descoberto em `dc5a6290`).
   - O hardware consumiu os quadros e devolveu o bit `OWN` do descritor de TX ao driver em ambas as transmissões (`RMU frame: descritor completou (OWN de volta ao driver)`). Prova que a fila DMA TX no nível físico funciona 100%.
   - `LINK_STATUS` em `BAR0+0x04` permaneceu em `0x80003b74` e MDIO continuou em `0x0000`.

6. **Quadro RMU com Sub-header `0x9807` (`trigger_rmu` opção 4)**:
   - Decompilação de `fcn.ffffffffdc5a5200` revelou o construtor de quadros RMU contendo o sub-cabeçalho `0x9807` nos offsets 26/27 (`buf[26]=0x07, buf[27]=0x98`).
   - Testado no PS4 real via `echo 4 > trigger_rmu`: O controlador DMA aceitou e processou o quadro in-band via DMA, devolvendo o descritor (`OWN`) ao driver com 100% de sucesso.
   - Registrado como entrada 60 na tabela `test_history` do SQLite.

7. **❌ REFUTADO no reteste (mesmo dia): "Descoberta do PHY Autêntico de Hardware" era falso positivo.**
   - Achado original: leitura dos 16 registradores Clause 22 MDIO via `trigger_phy_trigger` (opção 4) supostamente revelou `Reg 2 = 0x8881` e `Reg 3 = 0x03a2` (`PHY ID = 0x888103a2`), `BMCR = 0x1040`.
   - **Reteste (mesmo `trigger_phy_trigger` opção 4, módulo recém recarregado):** `Reg[02]` veio `0x0000` (não `0x8881`) — um registrador de PHY ID é hardwired no silício, não pode variar entre leituras. Além disso os 16 valores aparecem em blocos de 3 registradores consecutivos idênticos (`Reg3=Reg4=Reg5=0x03a2`, `Reg6=Reg7=Reg8=0x0de1`, `Reg10=Reg11=Reg12=0x0200`, `Reg13=Reg14=Reg15=0x0000`) — a mesma assinatura de dado residual do barramento MDIO (transação nunca completa, bus devolve o último valor latched) já catalogada em `memory/devmem-nao-existe-usar-dd-octal.md`.
   - **Conclusão corrigida:** não há prova de PHY vivo. O achado da entrada 62 do SQLite deve ser tratado como falso positivo, não como confirmação de hardware.

### ⚠️ CORREÇÃO sobre a entrada 59 do `test_history` (`BAR0+0x1c`, "trigger_phy_trigger") — 2026-07-25

Decompilei `fcn.ffffffffdc5a4950` por completo com `r2ghidra` (a função só tinha sido parcialmente lida quando a entrada 59 foi registrada). Resultado: **`BAR0+0x1c` não é um trigger de energização do PHY** — é a rotina de **programação do filtro de hash multicast/unicast do MAC** (padrão clássico tipo `setmulti()` de drivers BSD `msk`/`sky2`):

- Escrever `0x80000000` em `+0x1c` e esperar bit 17 (`0x20000`) = **reset/init da tabela de filtro de endereços**, não wake-up do PHY.
- Em seguida, pra cada endereço MAC numa lista ligada (`softc+0x150`), a função calcula um **CRC-32 padrão de Ethernet** (polinômio `0x4c11db7` explícito no disassembly) sobre os 6 bytes do MAC, deriva um índice (`(crc&7)+0x7000+(crc>>0x1b)*8`), escreve esse valor de volta em `+0x1c` e espera bit 14 (`0x4000`) — escrita indireta, entrada por entrada, da tabela de hash de endereços.

`BAR0+0x1c` é portanto um **registrador de acesso indireto ao filtro de endereços do MAC** (nível MAC, não PHY analógico). O ACK visto ao vivo (entrada 59) prova que esse mecanismo indireto está vivo, mas não é o "botão que acorda o PHY" — é uma feature de filtragem de pacotes, ortogonal ao bloqueador de RX morto. **Não investir mais nessa trilha para o problema do PHY** — pode ser útil só se algum dia precisarmos de filtro multicast/promíscuo no `mts.ko` (baixa prioridade, não relacionado ao RX morto).
