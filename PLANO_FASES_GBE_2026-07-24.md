# Plano em Fases — Driver GBE Baikal (mts.ko), pós-sessão 2026-07-24

## Contexto

A sessão de hoje (2026-07-24) trouxe 4 avanços reais sobre o driver `drivers_mts/mts.c`:
1. `hold_val=0x10` (bit 4, não bit 0 como no SATA) faz o MDIO Clause 45 responder (`ret=0`, antes timeout `-110`).
2. O write de clock config em `0x10A030` funciona e persiste (`0x16c9 → 0x16d9`).
3. Remover o `mts_write(mp, 0x200, 0)` da calibração destravou o MAC enable — TX agora enfileira 20 pacotes, Link UP é reportado.
4. Deploy migrado de telnet para SSH.

Mas ficam problemas sérios e um contraste importante com o histórico do projeto (levantado pelas duas explorações desta sessão):
- **O código já reflete a remoção do `0x200=0`** (está comentado, linhas 636-637 de `mts.c`), mas essa escrita era tratada em 07-23 como etapa **obrigatória** da sequência RE do Orbis, validada como "100% conforme" — removê-la contraria essa suposição antiga e nunca foi documentada formalmente como descoberta. Há também **comentários desatualizados** em `mts_mac_enable()` (linhas ~1074-1078, 1091) que ainda descrevem o `0x200=0` como comportamento ativo.
- **TX "funciona" só em software**: `mts_start_xmit()` escreve o índice cru (`tx_idx`, 0-255) no registrador `MTS_TX_RING_PTR` (0x3c) — só que esse é o **mesmo registrador** que recebeu o endereço físico de 32 bits da base do anel DMA em `mts_program_rings()`. Ninguém verificou se esse formato de doorbell (índice puro sobrescrevendo o que era um endereço) é o que o hardware realmente espera. `MTS_CNT_PKTS` nunca avança.
- **`MTS_LINK_STATUS` (0x04) é escrito forçando full-duplex** (`(link_save & 0x7fffcfff) | 0x61`, linha 880) durante a calibração — mas testes anteriores (`PLANO_DUPLEX_PHY_MDIO`) mostraram que escrever nesse registrador é um **no-op confirmado** (pré/pós idênticos). Isso explica por que o link aparece como "Half duplex" mesmo com o código tentando forçar full: a escrita simplesmente não gruda.
- **A cadeia real de power-on do bloco GBE nunca foi localizada na RE** — o próprio `RE_KERNEL_GBE_ATTACH.md` registra que escrever `0x10A030` sozinho não liga o chip (`B2_CHIP_ID` continua `00`), e a janela `0x140000`/`0x180000` do Glue (BAR2) nunca foi varrida por completo em busca de um bit de power-gate/isolamento — só os offsets pontuais de hold/pulse foram tocados.
- **Cabo de rede estava frouxo e foi reconectado em 2026-07-24** (`memory/cabo-rede-frouxo-reconectado-2026-07-24.md`), mas nenhum dos testes de RX/duplex documentados foi re-executado depois da correção física — pode não explicar o MDIO mudo (é um barramento interno ao chip, independente do cabo), mas é o teste mais barato possível e ainda está pendente.
- **Hipóteses já testadas e refutadas/descartadas** (não repetir): IRQ real `IMR=0x7d` sozinha (Link DOWN, zero IRQs — mas sob suspeita do cabo frouxo, testado antes da correção física), `MTS_MAC_EN2` como causa raiz (não-retenção normal, não é bug), Clause 22 BMCR em qualquer `phy_addr` 0-31 (timeout ou resíduo zero), forçar full-duplex escrevendo direto em 0x04 fora da calibração (no-op), decoder MDIO packed devad/reg trocados (já corrigido), BAR2 vs BAR4 do efuse (corrigido, mas insuficiente sozinho), inversão ingênua do bit OWN em RX sem corrigir a condição de break (causava loop infinito, já corrigido), testar eth0 via subnet errada do WiFi (metodologicamente inválido).

O objetivo deste plano é sequenciar os próximos testes em hardware real (PS4) minimizando power cycles e não repetindo o que já foi refutado, indo do mais barato/seguro (diagnóstico read-only) para o mais arriscado (mudanças de código especulativas).

**Regra de Ouro em vigor:** nenhum teste ao vivo (rmmod/insmod do `mts.ko`, escrita em `/dev/mem`, etc.) roda sem o usuário confirmar explicitamente "pronto" antes, com o PS4 ligado e acessível.

---

## Fase 0 — Higiene e re-verificação barata (sem rebuild, ou rebuild trivial)

1. **Atualizar comentários desatualizados em `mts.c`** (linhas ~1074-1078 e 1091 de `mts_mac_enable()`) para refletir que o `0x200=0` está removido/comentado — evita que a próxima sessão reintroduza a escrita por engano achando que é "etapa obrigatória".
2. **Registrar formalmente em `memory/`** a descoberta de hoje (remoção do `0x200=0` destrava MAC enable) como um novo achado que **contradiz** a implementação "100% conforme" de 07-23 — está documentado só em `PHY_DEBUG_SESSION_20260724.md`, ainda não em `memory/MEMORY.md`/`CLAUDE.md` (regra #2 do projeto: atualização contínua).
3. **Re-teste do básico com o cabo já corrigido**: subir o módulo atual (`hold_val=0x10`), rodar o mesmo ping 192.168.0.1↔192.168.0.2 e o scan Clause 45 já feito, só para confirmar se algo mudou com o cabo bom — é o teste mais barato, pode ser feito na mesma sessão/power-cycle da Fase 1 (não precisa ser um power cycle isolado).

## Fase 1 — Diagnóstico read-only ampliado (1 power cycle, sem mudança funcional de código)

Objetivo: coletar o máximo de dado antes de especular mudanças de comportamento.

1. **Varredura completa da janela Glue BAR2 `0x140000`–`0x180000+`** (não só os offsets pontuais de hold/pulse) via `mts_regs` sysfs ou `/dev/mem`, procurando por bits de power-gate/isolamento do PHY — passo explicitamente recomendado em `sessao-2026-07-23-bar4-efuse-e-mdio-packed-fix.md` e nunca executado.
2. **Instrumentar/logar o registrador `0x50`** (único registrador confirmado como genuinamente dinâmico: `0xa4` pré-calib → `0x00` pós-calib → `0x04` runtime) em cada fase da calibração — nunca foi aprofundado, pode ser status real do PHY/MAC.
3. **Log completo do poll de release do hold** (linhas 1040-1055 de `mts.c`) — hoje só reporta o valor final; logar todas as ~50 iterações (10ms cada, até 500ms) do MDIO devad=1 reg=0x0000 para ver se algum valor não-zero aparece transitoriamente.
4. **Clause 45 com `hold_val=0x10` em devad/endereços ainda não testados** — hoje só devad 0x01/0x02/0x03/0x07 foram tentados; ampliar para os demais devads MMD padrão (0x1e/0x1f vendor já usados na calibração, mas vale testar leitura pós-hold-release nesses também).
5. **Confirmar a hipótese do doorbell TX**: comparar valor de `0x3c` logo após `mts_program_rings()` (endereço DMA) vs. logo após o primeiro `mts_start_xmit()` (índice cru) — já é previsível pelo código, mas confirmar ao vivo com `mts_regs` fecha a dúvida antes de decidir corrigir.

## Fase 2 — Mudanças de código direcionadas (com base no que a Fase 1 revelar)

Cada item abaixo é uma mudança pequena e isolada, testável via module_param quando possível (sem rebuild):

1. **Se a Fase 1 achar um bit de power-gate na janela Glue**: adicionar o write de liberação antes da calibração; testar se Clause 45 passa a retornar dados não-zero.
2. **Corrigir o formato do doorbell TX**: hoje `mts_write(mp, MTS_TX_RING_PTR, tx_idx)` sobrescreve o que era um endereço DMA com um índice pequeno. Testar escrever o endereço completo do descritor atual (`base + tx_idx * desc_size`) em vez do índice cru, atrás de um novo `module_param` (`tx_doorbell_mode`, 0=índice atual / 1=endereço completo) para não perder o comportamento atual como fallback. Critério de sucesso: `MTS_CNT_PKTS` avança.
3. **Reordenar o diagnóstico MDIO pós-calibração** (linhas 1019-1038) para rodar só depois do poll completo de release do hold, não antes — hipótese registrada em `bar4-efuse-corrigido-mas-phy-continua-mudo-2026-07-23.md` de que o diagnóstico roda cedo demais.
4. **Reforçar a escrita de full-duplex em 0x04**: já que a escrita única durante a calibração é no-op confirmado, testar reescrever periodicamente (ex. dentro do timer de `poll_interval_ms`, condicionado a `enable_carrier`) enquanto `hold_val=0x10` mantém o MDIO respondendo — ver se agora "gruda" dado que mais do pipeline de wakeup está correto que em 07-23.

## Fase 3 — IRQ real (só se Fase 1/2 não resolverem RX)

1. Localizar o registrador real de ACK/status de IRQ (ainda não identificado — hoje o handler só conta e retorna `IRQ_HANDLED` sem processar nada) via a decompilação `dc5a31f0`/funções vizinhas no dump Orbis.
2. **Re-testar `IMR=0x7d` do zero**, já que o teste anterior (refutado) rodou (a) antes da descoberta do `hold_val=0x10` e (b) possivelmente com o cabo frouxo ainda não corrigido — as circunstâncias mudaram o suficiente para justificar um re-teste, não é repetição do mesmo teste.

---

## Arquivos principais

- `drivers_mts/mts.c` — todo o driver; funções-chave: `mts_phy_calibration()` (586-1056), `mts_mac_enable()` (1070-1105), `mts_start_xmit()` (doorbell TX ~1379-1385), `mts_program_rings()` (481-492), `mts_interrupt()` (1698-1722), module_params (63-124).
- `scripts/deploy_mts.sh` — deploy via SSH (já migrado hoje).
- `scripts/build_mts_module.sh` — rebuild do módulo.
- `PHY_DEBUG_SESSION_20260724.md` — log da sessão de hoje, deve ser atualizado a cada novo resultado.
- `consolidado/RE_KERNEL_GBE_ATTACH.md` — RE do Orbis, referência para `dc5a31f0`/`dc5a0ba0`.
- `memory/MEMORY.md` e `CLAUDE.md` — atualizar imediatamente após cada teste ao vivo (regra #2 do projeto).

## Verificação

Cada fase é validada em hardware real via SSH (`scripts/deploy_mts.sh`), com:
- `dmesg`/log do módulo para a sequência de calibração,
- atributo sysfs `mts_regs` para dump de registradores BAR0/BAR2/BAR4 sob demanda,
- ping `192.168.0.1↔192.168.0.2` e captura de ARP como teste funcional de RX,
- leitura de `MTS_CNT_PKTS`/`MTS_CNT_BYTES` como teste funcional de TX real (não só enfileiramento).

Nenhum teste ao vivo roda sem o usuário confirmar "pronto" antes (Regra de Ouro do projeto), com o PS4 ligado e acessível via SSH/telnet.
