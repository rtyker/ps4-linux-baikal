# Plano de Solução Consolidado — GBE Ethernet (mts.ko), pós-revisão UART + SQLite + código (2026-07-29)

## Contexto

O usuário pediu para revisar tudo que já temos (logs UART, banco `ps4_hardware_memory.db`, planos anteriores) e montar um plano **consistente** de solução para o bloqueador do driver `mts.ko`: o PHY da GBE Baikal nunca sai de power-down (MDIO Clause 22/45 sempre 0x0000/timeout), RX morto, TX só confirmado em software.

A revisão (3 investigações em paralelo) trouxe achados que mudam o quadro:

1. **As capturas UART não trazem nada novo.** As três capturas que atravessam o boot do `mts.ko` (`kexec-warm-reboot-test-07`, `test-11-initcall-debug`, `dmesg_sata-ackfix-ehdump-boot4`) são **idênticas byte a byte** na falha (MDIO sempre `0x0000`, calibração "conclui" mas hold/pulse nunca seta bit2 em 201/201 tentativas). As capturas de 2026-07-29 (`cachy_00X`, `sata_teste_002`, e a mais recente `sata005_20260729_175012`, conferida na revisão desta sessão) são sobre SATA/GoldHEN/vídeo `amdgpu` e **nunca chegam a carregar o `mts.ko`** (zero menções à string "mts"; as 4 ocorrências de "phy" em `sata005` são todas do `Baikal SATA PHY init`, não da GBE). Única curiosidade sem relação de causa: `mts-debug-01_20260727_204608.bin` ficou completamente vazia (sessão sem captura), sem documentação cobrindo o motivo.

2. **Inconsistência séria achada no SQLite:** os testes `#61`/`#62` (2026-07-25, "PHY_CLAUSE_22_MDIO_ATIVO_BMCR_0x1040" e "MARVELL_PHY_ID_CONFIRMADO_0x888103a2") ainda constam como **BREAKTHROUGH** no banco — mas o próprio `PLANO_FASES_GBE_2026-07-25.md` (seção "Testes de RMU e Glue", item 7) documenta que esse mesmo achado foi **retestado no mesmo dia e refutado**: no reteste, `Reg[02]` veio `0x0000` (não `0x8881`), e os 16 valores lidos vieram em blocos de 3 registradores consecutivos idênticos — a mesma assinatura de **dado residual do barramento MDIO** (transação nunca completa, bus devolve o último valor latched) já catalogada para o falso positivo anterior (`#38`, `memory/devmem-nao-existe-usar-dd-octal.md`). **O banco nunca foi atualizado para refletir essa refutação** — isso é uma dívida de documentação que precisa ser corrigida antes de qualquer nova sessão confiar cegamente no SQLite.

3. **A varredura completa da janela Glue BAR2 `0x140000`-`0x180000` JÁ FOI EXECUTADA** em 2026-07-25 (`test_history` id 48, `OK_SEM_INCIDENTE_ESTRUTURA_ENCONTRADA`, cruzada com o dump do kernel Orbis em id 49 `INCONCLUSIVO_SEM_CORRELACAO`) — **não precisa ser repetida**, ao contrário do que uma leitura apressada dos planos sugere.

4. **Achado de código, lendo `drivers_mts/mts.c` linhas 269-333 diretamente:** a função `mts_mdio_c22_read()`/`mts_mdio_c22_write()` (Clause 22, transcrita de `dc5a2840`/`dc5a2950`) monta o comando MDIO **sem nenhum campo de endereço de PHY** (`cmd = ((reg&0x1f)<<8)|0x4000` — o parâmetro `phy_addr` é recebido mas nunca entra no `cmd`). Isso quer dizer que o "scan de `phy_addr` 0-31" feito nos triggers de diagnóstico (`trigger_phy_trigger` opção 10, linha ~1884) **testa exatamente o mesmo comando 32 vezes** — não há como esse scan distinguir um PHY de outro. Combinado com o achado 2 acima (dado residual/latched), isso é consistente com uma hipótese concreta e nunca testada explicitamente: **o protocolo de "pronto" (bit 15/BUSY) nunca é de fato assertado pelo hardware**, e o driver está sempre lendo o último valor latched do barramento (residual), nunca um dado fresco de transação MDIO completa — independente de página, devad ou reg.

5. **Pista estrutural nova e não testada no contexto GBE:** a investigação paralela de SATA interno (28-29/07, `test_history` #63-69) achou um bug real de **demux de MSI multi-função no glue Baikal** (`bpcie_assign_irqs()` em `ps4-bpcie.c` fazia `nvec=1` incorreto para função com múltiplas subfunções) que explica por que a sinalização de IRQ "cessa" depois de alguns segundos. A GBE (`0000:00:14.1`) está na mesma família de dispositivos com IRQ MSI (`hwirq 5152` registrado mas **contagem sempre 0**, confirmado `test_history` #50) — **essa correção nunca foi testada/adaptada para a função da GBE**, e é a pista mais forte ainda em aberto porque explicaria tanto o RX morto quanto o PHY "sem eventos" (a thread `gbe_phy_ctrl`/`dc5a44c0` do Orbis é orientada a evento — dorme esperando bits que só um IRQ real ou RMU setaria, confirmado por RE em `#52`).

## Plano de execução (em ordem de custo/risco crescente)

### Fase 0 — Higiene de documentação/banco (sem hardware, sem risco, fazer primeiro)

Objetivo: parar de arriscar que uma sessão futura (ou um outro agente) confie no SQLite achando que o PHY já foi identificado.

1. ✅ **Feito 2026-07-29.** `consolidado/ps4_hardware_memory.db`: `test_history` id 61/62 marcados `REFUTADO_MESMO_DIA_DADO_RESIDUAL_MDIO` com `complementary_info` citando o reteste que os invalidou; nova linha id 70 registra o reteste/refutação em si (antes invisível na tabela, só documentado em markdown).
2. ✅ **Feito 2026-07-29.** `decompiled_functions`: `dc5a2840`, `dc5a2950`, `dc5a4950`, `dc5a4e90`, `dc5a5050`, `dc5a5200`, `dc5a6290` promovidas de `bruto` para `revisado`, com nota explícita de que a identificação de PHY via `dc5a2840`/`dc5a2950` foi refutada (o formato de opcode em si permanece em uso, sem confirmação de que o hardware completa a transação).
3. ✅ **Feito 2026-07-29.** `consolidado/decompiled/INDEX.md`: removidas as 7 funções da lista "ainda não decompiladas" (seção 8, restou só `dc3f5bd0` + funções de prioridade média); tabela de testes confirmados (seção 7) atualizada para marcar #61 como refutado.
4. ✅ **Feito 2026-07-29.** `memory/MEMORY.md` linha 15: removido o link quebrado para `orbis-payload-sequencia-boot-capturada-live-2026-07-28.md` (arquivo nunca existiu), mantendo o resumo em uma linha como única fonte do achado.
5. ✅ **Feito 2026-07-29.** `consolidado/BACKLOG.md` (item GBE) e `PLANO_FASES_GBE_2026-07-25.md` com adendo apontando para este plano consolidado (`PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md`).

### Fase 1 — Auditoria fria do protocolo MDIO busy/ready (sem power cycle, só leitura de código/RE)

**✅ Concluída 2026-07-29.** Resultado mais forte do que a hipótese original do achado 4 previa — não é "o hardware nunca assere BUSY", é um **bug de polaridade confirmado no driver Linux**:

1. **Bug de polaridade confirmado.** `mts_mdio_wait_write()` (Clause 22, `drivers_mts/mts.c:277-287`) espera bit 15 do word baixo **ZERAR** (`!(val & 0x8000)`). A decompilação real (`dc5a2840`/`dc5a2950`, `if (sVar3 < 0) break` com `sVar3 = (short)uVar4`) espera o bit 15 **SETAR** — exatamente o oposto. Comparação direta: `mts_mdio_wait()` (Clause 45, linha 164-174, usa `MTS_MDIO_READY`/`0x8000` com polaridade SET) está **correto**; só o caminho Clause 22 está invertido. Como o comando escrito nunca tem bit 15 setado, a primeira iteração do poll Clause 22 já "sucede" sem o hardware processar nada — isso sozinho explica o padrão de dado residual/latched (mesma assinatura da refutação dos testes #61/#62) sem precisar invocar hipótese de PHY sem energia/IRQ para esse sintoma específico.
2. **`phy_addr` confirmado como não-bug.** As funções Orbis originais (`FUN_ffffffffdc5a2840`/`FUN_ffffffffdc5a2950`) não têm parâmetro de endereço de PHY na assinatura — só `(contexto, reg, dado)`. O campo `phy_addr` no driver Linux é um artifact de API do port, não uma omissão; o hardware Clause 22 da GBE Baikal é single-PHY fixo por design. O scan de phy_addr 0-31 (`trigger_phy_trigger`, linha ~1884) é estruturalmente incapaz de diferenciar endereços — confirmado e documentado no comentário do código.
3. Comentários adicionados em `drivers_mts/mts.c` (funções `mts_mdio_wait_write`, `mts_mdio_c22_read`, `mts_mdio_c22_write`, e no scan da linha ~1884) e `decompiled_functions.role` de `dc5a2840`/`dc5a2950` atualizado no SQLite para refletir a conclusão real (antes descrevia a polaridade errada como comportamento esperado).

**Novo item de baixo risco para a Fase 2 (adicionar ao passo 2.3 antes/junto do fix de MSI):** corrigir a polaridade de `mts_mdio_wait_write()` para usar `MTS_MDIO_READY` (igual à Clause 45) antes de reavaliar se o fix de MSI é sequer necessário para o MDIO — é possível que o Clause 22 comece a retornar dado real assim que a polaridade for corrigida, independentemente do estado do IRQ.

**✅ Fix testado em hardware 2026-07-30 (via telnet, SSH indisponível na sessão — módulo transferido por HTTP ad-hoc + `wget`).** Resultado: o bug de polaridade era real e o fix eliminou o falso-positivo de dado residual — o scan `phy_addr` 0-31 agora retorna eco limpo e uniforme (`0x1000`, o próprio valor escrito pelo driver) em vez do ruído variável que antes gerava "PHY ID Marvell" falso. Mas **isso sozinho não é suficiente**: sem link, `ping 192.168.0.1↔192.168.0.2` falha 100%, `/proc/interrupts` mostra `irq_count=1` desde o boot. Ver detalhes completos em `memory/mdio-clause22-bug-polaridade-corrigido-2026-07-29.md` (seção "Teste ao vivo 2026-07-30 — RESULTADO"). **Conclusão: a Fase 2 (fix de MSI) continua necessária — a hipótese de bug de software isolado no MDIO está descartada como causa única.**

### Fase 2 — Adaptar o fix de demux MSI (achado no SATA) para a função GBE (1 power cycle)

Esta é a pista de maior potencial ainda não tentada. **Reforçada pelo teste da Fase 1 (2026-07-30): `irq_count=1` no `/proc/interrupts` da `mts` bate exatamente com a hipótese de MSI mal roteado/demux incorreto.**

1. Ler `ps4-bpcie.c` (ou onde `bpcie_assign_irqs()` estiver no kernel 7.0 atual) e comparar o tratamento dado à função `00:14.1` (GBE) com o que foi corrigido para `00:14.7` (AHCI, func7) na investigação SATA de 28-29/07 — confirmar se a GBE sofre do mesmo `nvec=1` incorreto quando há múltiplas subfunções compartilhando vetor MSI.
2. Se o mesmo padrão for confirmado, aplicar o fix análogo (mesma lógica usada no SATA) para a função da GBE.
3. Instrumentar `mts_mdio_c22_read()` para logar o valor bruto de `MTS_MDIO` **imediatamente após a escrita do comando, antes do primeiro poll** — isso testa diretamente se o bit BUSY chega a ser assertado pelo hardware (dado da Fase 1).
4. Recompilar via `00-build-kernel-7.0.sh <TAG-nova>` (nunca `make bzImage` direto, ver `AGENTS.md`), deploy via `deploy-boot-7.0.sh`, 1 power cycle.
5. No mesmo power cycle, aproveitar para fechar a pendência esquecida entre 07-24→07-25 (reteste pós-cabo-de-rede-reconectado) — de baixo valor esperado (MDIO é interno ao chip, não devia depender de link físico), mas documentar explicitamente o resultado para fechar a pendência de uma vez.
6. Testes a rodar nesse boot: `scripts/deploy_mts.sh push` com `irq_mask=0x7d`, confirmar via `dmesg`/`/proc/interrupts` se `irq_count` sai de 0; rodar `mts_regs` e `trigger_phy_trigger` opção 4 (Clause 22 AN restart + dump) e checar se o BUSY bit chega a ser observado assertado no log novo da Fase 2.3; testar ping `192.168.0.1↔192.168.0.2` via `eth0` e `MTS_CNT_PKTS`/`MTS_CNT_BYTES`.

### Fase 3 — Decisão de continuidade (pós-teste da Fase 2) — ✅ CONCLUÍDA 2026-07-30, ENCERRADA COM REFUTAÇÃO

**Resultado real (sem precisar de rebuild/fix de código):** antes de tocar em `ps4-bpcie.c`, um teste ao vivo de baixo custo (sem power cycle) já decidiu a questão:

1. `lspci -vv 00:14.1` confirmou que o MSI da GBE **NÃO está mascarado em hardware** (`Masking=00000000`, diferente do AHCI `Masking=000000fe`) — refuta de cara a hipótese de "mesmo bug de masking do SATA".
2. Reload do `mts.ko` com `irq_mask=0x7d` (IMR real desmascarado — o default `0x0` mascara tudo, achado só nesta sessão) confirmado via `mts_regs`, mas `/proc/interrupts` ficou em `irq_count=0` por 5+s, sem nenhuma mudança em ping/carrier.
3. **Conclusão: nem MSI (hardware) nem IMR (software) explicam o bloqueador — o PHY genuinamente nunca gera nenhuma condição de IRQ.** Isso fecha com evidência direta a hipótese já registrada em `PLANO_FASES_GBE_2026-07-25.md` (seção final): o bloqueador é anterior a qualquer coisa que o driver Linux possa fazer — energia/clock físico do PHY que nunca chega, ou uma sequência de bring-up feita pela Sony fora do alcance replicável via software (SAMU/bootloader). **A mudança de código em `ps4-bpcie.c` cogitada na Fase 2 não é necessária — o código de demux já está correto para a GBE (single-vetor, `bpcie_assign_irqs(pdev, 1)`, não passa por nenhum caso especial de `bpcie_handle_edge_irq`).**

Documentado formalmente o encerramento desta via de investigação em `consolidado/BACKLOG.md` e `test_history` id 72. **Não reabrir sem novo dado concreto** (ex: RE da sequência de bring-up SAMU/ICC do PHY, ainda não tentada). Prioridade do projeto redirecionada para as frentes já ativas (SATA interno, S5 shutdown). Achado colateral: `rmmod mts` sempre gera `WARNING: kernel/irq/msi.c:294 at msi_device_data_release` (não-fatal, sistema permanece vivo) — bug real de cleanup de MSI no driver, não documentado antes, sem relação com a causa raiz do PHY.

## Arquivos principais a tocar

- `consolidado/ps4_hardware_memory.db` (Fase 0, via `sqlite3` — updates pontuais, não regravar o banco inteiro)
- `consolidado/decompiled/INDEX.md`, `memory/MEMORY.md` (Fase 0)
- `drivers_mts/mts.c` — `mts_mdio_c22_read()`/`write()` (linhas 289-333), comentário do scan (linha ~1884) (Fase 1/2)
- `ps4-bpcie.c` (localizar caminho exato no kernel 7.0 durante a Fase 2.1) — fix de demux MSI
- `consolidado/BACKLOG.md`, `PLANO_FASES_GBE_2026-07-25.md` (adendo apontando para este plano)

## Verificação

- Fase 0: `sqlite3 consolidado/ps4_hardware_memory.db "SELECT status FROM test_history WHERE id IN (61,62);"` deve refletir a refutação; grep no `INDEX.md` não deve mais listar as 7 funções como pendentes.
- Fase 2: `dmesg` + `/proc/interrupts` (contagem de IRQ da GBE), sysfs `mts_regs`, ping `192.168.0.1↔192.168.0.2` via `eth0` (nunca WiFi), `MTS_CNT_PKTS`/`MTS_CNT_BYTES` — mesma metodologia já validada em sessões anteriores (`scripts/deploy_mts.sh test`).
- Nenhuma ação da Fase 2 roda sem o usuário confirmar "pronto" explicitamente com o PS4 ligado e acessível via SSH (regra de ouro já em vigor no projeto).
