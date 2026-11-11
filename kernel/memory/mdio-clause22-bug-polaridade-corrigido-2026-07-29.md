---
name: mdio-clause22-bug-polaridade-corrigido-2026-07-29
description: Bug de polaridade confirmado e corrigido em mts_mdio_wait_write() (Clause 22) — driver nunca esperava o hardware de verdade, explicando o dado residual do MDIO. Fix aplicado e TESTADO em hardware 2026-07-30 — corrigiu o bug de software mas PHY continua sem responder (aponta para MSI/power do PHY).
metadata:
  type: project
---

Na auditoria fria da Fase 1 do `PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md`, comparando a decompilação Orbis (`dc5a2840`/`dc5a2950`) com `drivers_mts/mts.c`, foi confirmado um bug real de polaridade (não uma hipótese de hardware):

- `mts_mdio_wait_write()` (caminho Clause 22, `drivers_mts/mts.c` por volta da linha 295) esperava o bit 15 do MDIO **ZERAR** (`!(val & 0x8000)`).
- A decompilação Orbis (`if (sVar3 < 0) break`, onde `sVar3` é o word baixo como `short`) espera o bit 15 **SETAR** — exatamente o oposto.
- O caminho Clause 45 (`mts_mdio_wait()`) já usava a polaridade correta (`MTS_MDIO_READY`/`0x8000` esperando SET) — serviu de controle/contraprova direta.
- Como o comando escrito nunca seta o bit 15, o polling Clause 22 "sucedia" já na primeira iteração, sem o hardware processar a transação — isso sozinho explica o padrão de dado residual/latched que gerou os falsos positivos dos testes #61/#62 (PHY ID Marvell "confirmado" e depois refutado).
- Bônus confirmado: as funções Orbis originais (`dc5a2840`/`dc5a2950`) não têm parâmetro de `phy_addr` na assinatura — o campo no driver Linux é artifact de API, não bug; GBE Baikal Clause 22 é single-PHY fixo por design.

**Fix aplicado 2026-07-29:** `mts_mdio_wait_write()` corrigida para usar `MTS_MDIO_READY` igual à Clause 45. Módulo recompilado com sucesso (`scripts/build_mts_module.sh`). **Ainda NÃO testado em hardware** — aguardando deploy + power cycle (Fase 2 do plano).

**Why:** este achado é mais forte que a hipótese anterior do plano ("PHY nunca sai de power-down por falta de IRQ/MSI") — pode ser que o MDIO Clause 22 comece a retornar dado real assim que a polaridade for corrigida, independente do estado do IRQ/MSI.

**How to apply:** antes de investigar mais a fundo o fix de demux MSI (`bpcie_assign_irqs`) do [[plano-mts-solucao-consolidado-2026-07-29]], rodar primeiro o teste da polaridade corrigida sozinha — pode isolar se o problema do MDIO era só esse bug de software, sem precisar do fix de MSI junto.

## Próximo passo (retomar aqui)

Fase 2 do plano: `scripts/deploy_mts.sh push`, checar `dmesg`/`mts_regs`/`trigger_phy_trigger` (Clause 22 AN restart, opção 4, e o scan de phy_addr 0-31, linha ~1884) para ver se o BUSY/READY agora reflete transação real (valores distintos por registrador, não mais "likely residual"). Regra do projeto: nenhuma ação de deploy/power cycle roda sem o usuário confirmar explicitamente com o PS4 ligado e acessível via SSH.

## Teste ao vivo 2026-07-30 — RESULTADO

**Contexto:** SSH (porta 22) estava recusando conexão nesta sessão; `telnetd` estava ativo em `192.168.6.128:23` (sem prompt de login, shell root direto). Como não há `scp` sem SSH, o `mts.ko` corrigido foi transferido servindo `drivers_mts/build/mts.ko` via `python3 -m http.server` na interface WiFi do host (`wlp0s20f3`, `192.168.6.100:8899`) e baixado no PS4 via `wget` (MD5 conferido igual nos dois lados: `6af902ab87b4b00f85a9a1a6c0d200fc`).

`insmod /tmp/mts.ko stage=4` — carregou com sucesso (ficou em estado "Loading" por ~30s durante o polling pós-release, não é trava; completou e foi para "Live"). `eth0` registrado normalmente, MAC `2c:cc:44:3f:69:5f`, IP `192.168.0.2` configurado.

**O fix de polaridade funcionou tecnicamente — mudou o comportamento observável:**
- `poll pos-release [0..200/201]: ret=0 val=0x0000` — a espera agora completa de verdade (bit 15 setado, sem timeout), diferente do "sucesso instantâneo falso" de antes.
- Scan `phy_addr` 0-31 (via `mts_regs` sysfs): **todos os 32 endereços retornam exatamente `0x1000`** — o mesmo valor que o próprio driver escreveu no BMCR durante o AN restart. Antes do fix, o padrão era dado residual/variado (que gerou o falso-positivo de "PHY ID Marvell" nos testes #61/#62). Agora é um eco limpo e consistente do último valor escrito, não mais ruído — comportamento de barramento sem PHY respondendo eletricamente (mestre lê de volta o que ele mesmo escreveu, sem ACK real de um escravo).
- `ping -I enp60s0 -c 5 192.168.0.2` do host → **100% perda, "Host de destino inalcançável"**. Sem link.
- `/proc/interrupts`: linha `mts` mostra **apenas 1 IRQ total** desde o boot (`Baikal-MSI 5152-edge`) — consistente com a hipótese antiga de MSI mal roteado/demux incorreto para a função GBE (`00:14.1`).
- Contadores HW (`MTS_CNT_PKTS`/`BYTES`) = 0, RX/TX rings normais mas vazios (nenhum pacote real).

**Conclusão:** o bug de polaridade era real e o fix está correto — eliminou os falsos positivos de dado residual/latched no MDIO Clause 22. Mas **não é suficiente sozinho**: o PHY continua sem responder de fato (leitura = eco do próprio comando, não ACK de hardware), e o IRQ count de 1 reforça a hipótese de MSI/demux ou power domain do PHY como próxima causa raiz a investigar (Fase 2 original do plano: `bpcie_assign_irqs()` em `ps4-bpcie.c`, adaptar fix já usado no SATA).

**Próximo passo real:** investigar o fix de demux MSI para `00:14.1` (GBE), já que a hipótese de bug de software no MDIO está descartada como causa única — o problema agora aponta para IRQ/power do PHY, não mais para o polling.
