# Plano: Reabilitar IRQ real (IMR não-zero) — tentativa de recuperar Full-duplex

## Contexto

O plano anterior (`PLANO_MAC_EN2_INVESTIGACAO_2026-07-23.md`) já foi
executado por completo: `MTS_MAC_EN2` foi descartado como suspeito de causa
raiz (não retém o bit desde a primeira escrita, independente de calibração),
e nem Clause 45 (MMD1/MMD7, sempre `0x0000`) nem Clause 22 (BMCR, scan
completo `phy_addr` 0-31: 0-15 timeout, 16-31 residual zero) conseguem tirar
sinal real do PHY. Conclusão registrada em
`memory/mac-en2-descartado-phy-nunca-acorda-2026-07-23.md`: o PHY nunca sai
de power-down, e o "Link UP: 1000 Mbps Half duplex" reportado pelo registrador
de status do MAC (`0x04`) é estado interno, não reflexo de negociação física
real.

Ao escrever essa conclusão, encontrei um achado arqueológico importante que
este plano investiga e funde com a linha de investigação anterior:
`memory/teste-5-resultado-calibracao-tabela-2026-07-23.md` (sessão da TARDE
do mesmo dia, ANTES desta investigação) documenta um boot que produziu
`"Link UP: 1000 Mbps Full duplex"` **genuíno**, com esta sequência de log:

```
timer de polling iniciado (intervalo 10ms)
NAPI habilitado
interrupt habilitada, IMR=0x0000007d
open concluido
Link UP: 1000 Mbps Full duplex
```

O código atual sempre escreve `MTS_IMR_DEFAULT = 0x00000000` (tudo mascarado,
`mts.c:1750`) e nunca revisita esse valor — depende só do timer de polling de
10ms (`mts_poll_timer`, `mts.c:1214-1222`), sem IRQ real habilitada de fato
(o `request_irq()` em `mts.c:1771` registra o handler, mas como tudo está
mascarado em `0x54`, a linha de IRQ nunca é de fato assinalada pelo
hardware). Busquei essa versão do driver com `git log -S` (strings
`"interrupt habilitada"`, `"0x7d"`) em todo o histórico deste repo e em
backups conhecidos no disco (`/mnt/hdauxiliar/temp/kbuild_backup_180042`) —
**não existe em nenhum lugar rastreável**. Foi perdida em algum refactor não
commitado no mesmo dia.

**Esta é a única correlação empírica positiva com duplex correto encontrada
no projeto até agora.** Este plano testa reabilitar IRQ real (escrever
`0x54` com o mesmo valor `0x7d` já comprovado não-fatal nessa sessão
histórica) para ver se isso muda o resultado da negociação de duplex/PHY.

### Risco real a levar a sério

O handler `mts_interrupt()` (`mts.c:1581-1593`) é um **placeholder
explícito**: só incrementa `mp->irq_count` e retorna `IRQ_HANDLED`, sem
nunca ler/limpar nenhum registrador de status de interrupção real (o
comentário no código admite que esse registrador "ainda não foi localizado
na RE"). Isso significa que, se o hardware for um IRQ de nível (level-
triggered, comum em controladores como o `bpcie` deste PS4) e a condição que
gera a interrupção nunca for de fato reconhecida/limpa, **a linha pode ficar
permanentemente assinalada e o CPU pode entrar em uma tempestade de
interrupções** (o handler é chamado repetidamente sem parar), degradando ou
travando o console. O projeto já tem precedente documentado de toques em
registradores da GBE Baikal travando/desligando o PS4
(`memory/baikal-gbe-toque-trava-desliga-ps4.md`).

**Mitigação adotada neste plano:**
1. Usar exatamente o valor histórico `0x7d` (não um valor novo/não testado)
   — é o único dado que sabemos, por evidência direta de dmesg, que não
   travou o console naquela sessão.
2. Adicionar uma guarda de tempestade em `mts_interrupt()`: se o handler for
   chamado mais que N vezes (ex. 5000) dentro de uma janela curta (ex.
   `jiffies` recentes), escreve `MTS_IMR = 0` de volta automaticamente e loga
   um aviso — interrompe a tempestade via software sem exigir intervenção
   externa.
3. Testar em uma sessão isolada, com o usuário avisado antes do
   `insmod`/reload que existe risco de precisar de power cycle físico se a
   guarda de software falhar.

---

## Fase 1 — Expor `irq_count` no sysfs `mts_regs` (baseline, zero risco)

**Arquivo:** `drivers_mts/mts.c` (`mts_regs_show`, ~linha 1328+).

Adicionar `mp->irq_count` à seção "Estado dos aneis (SW)" do sysfs já
existente. Confirma, antes de qualquer mudança de IMR, que hoje `irq_count`
fica em 0 (nenhuma IRQ real jamais dispara com tudo mascarado) — estabelece
a baseline "antes".

**Critério de sucesso:** `cat mts_regs` mostra `irq_count=0` com o código
atual (`IMR=0x00000000`).

---

## Fase 2 — Guarda de tempestade em `mts_interrupt()`

**Arquivo:** `drivers_mts/mts.c` (`mts_interrupt`, linhas 1581-1593).
**Arquivo:** `drivers_mts/mts.h` (`struct mts_priv`, novo campo
`unsigned long irq_storm_jiffies;` perto de `irq_count`).

No handler, antes de `mp->irq_count++`, checar se `irq_count` cresceu além de
um limite (ex. 5000) desde `irq_storm_jiffies` (marcado na primeira
interrupção de uma janela). Se estourar o limite dentro de, digamos,
`HZ/10` (100ms), escrever `mts_write(mp, MTS_IMR, 0)` imediatamente dentro do
próprio handler (é seguro escrever registrador MMIO em contexto de IRQ) e
logar `dev_warn(..., "tempestade de IRQ detectada, remascarando 0x54")`.
Reset do contador de janela a cada N interrupções processadas sem estourar.

**Critério de sucesso:** código compila, e (se não houver tempestade real)
não muda nenhum comportamento hoje, já que IMR continua 0 por padrão nesta
fase — a guarda só é exercitada na Fase 4.

---

## Fase 3 — Module param `imr_value` para testar sem recompilar toda vez

**Arquivo:** `drivers_mts/mts.c` (perto dos outros `module_param`, ~linha
101; e no ponto de uso, `mts.c:1750`).

Adicionar:
```c
static uint imr_value = MTS_IMR_DEFAULT;
module_param(imr_value, uint, 0644);
MODULE_PARM_DESC(imr_value, "Valor a escrever em MTS_IMR (0x54) no probe — default 0 (tudo mascarado)");
```
E trocar `mts_write(mp, MTS_IMR, MTS_IMR_DEFAULT);` (linha 1750) por
`mts_write(mp, MTS_IMR, imr_value);`. Isso permite testar
`insmod mts.ko stage=4 imr_value=0x7d` sem precisar editar/recompilar entre
tentativas — reduz o ciclo de iteração e o número de vezes que se mexe no
código-fonte por experimento.

**Critério de sucesso:** `insmod ... imr_value=0` continua com comportamento
idêntico ao atual (regressão zero no caminho default).

---

## Fase 4 — Teste ao vivo com `imr_value=0x7d`

**Pré-requisito:** avisar o usuário explicitamente antes do `insmod` — este
é o primeiro teste que reabilita IRQ real neste projeto reconstituído, com
risco (mitigado, não eliminado) de precisar de power cycle físico.

1. `sudo scripts/build_mts_module.sh`
2. `./scripts/deploy_mts.sh push` — **mas** o script hoje faz `insmod
   /tmp/mts.ko stage=4` sem parâmetro extra; ajustar o comando (ou rodar o
   `insmod` manualmente via telnet) para incluir `imr_value=0x7d`.
3. Observar dmesg em tempo real (`dmesg -w` ou leituras repetidas) logo após
   o `insmod` — procurar por:
   - `"tempestade de IRQ detectada"` (guarda disparou — parar e reportar)
   - `mp->irq_count` no sysfs subindo de forma razoável (não milhões em
     segundos)
   - `"Link UP: 1000 Mbps ..."` — comparar duplex contra o `Half duplex` de
     hoje
4. Se o console parar de responder ao telnet: aguardar ~15s: se não
   recuperar, será necessário power cycle físico (avisar o usuário do
   resultado antes de insistir em mais comandos).
5. Se estável: rodar `./scripts/deploy_mts.sh test` normalmente (ping
   `192.168.0.1↔192.168.0.2`, capturar `mts_regs` antes/depois).

**Critério de sucesso:** `irq_count` sobe de forma limitada (não-tempestade)
E/OU duplex muda para Full — qualquer um dos dois já é sinal valioso.

---

## Fase 5 — Decisão

- **Se duplex virar Full E `MTS_CNT_PKTS` começar a incrementar com o ping
  de teste:** vitória — IRQ real habilitada era a peça faltante. Próximo
  passo (fora deste plano): localizar o registrador real de status/ack de
  interrupção (para o handler parar de ser um placeholder) e então
  reconsiderar reintroduzir IRQ real como default (`MTS_IMR_DEFAULT`) em vez
  de round-trip por module param.
- **Se `irq_count` subir de forma controlada mas duplex continuar Half:**
  a correlação com a sessão `teste-5` era coincidência (talvez causada por
  outro fator daquela sessão específica, não pela IRQ em si) — descartar
  essa hipótese, documentar, e não há mais pista concreta conhecida hoje
  para perseguir (fim de linha das hipóteses baratas; qualquer próximo passo
  vira RE pesado de `mts_phy_calibration`/wakeup, fora de escopo).
- **Se a guarda de tempestade disparar (`mts_write(IMR,0)` automático):**
  confirma que há de fato uma fonte de interrupção real por trás desse bit,
  mas que não pode ficar habilitada sem um handler de verdade — valioso para
  focar o próximo projeto de RE especificamente em achar o registrador de
  status/ack, em vez de duplex.
- **Se o console travar apesar da guarda:** reverter para
  `imr_value=0` permanentemente até se localizar o registrador de ack via
  outros meios (RE estático do binário Orbis, não ao vivo).

---

## Riscos e observações

- Único plano desta investigação que mexe em caminho de IRQ real — todos os
  anteriores eram só leitura/diagnóstico. Requer aviso explícito ao usuário
  antes do `insmod` com `imr_value` não-zero (mesmo espírito da Regra de
  Ouro, ainda que não seja literalmente injeção de payload).
- `force_mac_reset`, `enable_phy_calib`, `enable_carrier` etc. continuam
  como estão — nenhuma mudança nesses caminhos.
- Nenhuma mudança nas sequências de calibração PHY reverse-engenheiradas.
- Se o teste falhar/travar, o dado ainda é valioso (confirma existência de
  fonte de interrupção real) — não é um teste "tudo ou nada".

### Arquivos principais

- `drivers_mts/mts.c` — `mts_interrupt` (1581-1593), `mts_regs_show`
  (~1328+), `mts_probe` (escrita de IMR ~1750), `module_param` existentes
  (~64-103)
- `drivers_mts/mts.h` — `struct mts_priv` (novo campo
  `irq_storm_jiffies`), `MTS_IMR`/`MTS_IMR_DEFAULT`
- `scripts/build_mts_module.sh`, `scripts/deploy_mts.sh` (pode precisar de
  ajuste manual para passar `imr_value=0x7d` no `insmod`)
- `memory/teste-5-resultado-calibracao-tabela-2026-07-23.md` (evidência
  histórica do Full-duplex)
- `memory/mac-en2-descartado-phy-nunca-acorda-2026-07-23.md` (contexto desta
  investigação — mesclado com este plano)
