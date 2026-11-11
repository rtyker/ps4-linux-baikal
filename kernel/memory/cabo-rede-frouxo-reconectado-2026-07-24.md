# Possível fator de confusão físico nos testes de RX Ethernet: cabo/conexão frouxa

## Relato do usuário (2026-07-24)

O usuário identificou que o cabo de rede (ou a conexão física dele) estava frouxo, e trocou/
refez a conexão antes de continuar os testes. Isso foi relatado **depois** de toda a
investigação de RX documentada em `CLAUDE.md` (seção "PHY nunca acorda", commits `ce145b8`,
`a948b4e`, sessão `sessao-2026-07-23-bar4-efuse-e-mdio-packed-fix.md`).

## Por que isso importa

Toda a cadeia de conclusões abaixo foi obtida com a conexão física em condição não confirmada
como boa:
- MDIO Clause 45/22 sempre retornando zero (`teste-2`, `teste-3` resultados)
- Diagnóstico "PHY nunca sai de power-down"
- Correção do BAR4 efuse (`ce145b8`) que corrigiu a leitura de calibração mas "não foi
  suficiente sozinha" — PHY continuou mudo mesmo assim
- Hipótese do IRQ real (`IMR=0x7d`) testada e "refutada" (Link DOWN, zero interrupções)
- `ping 192.168.0.1<->192.168.0.2` com 100% de perda

**Um cabo frouxo pode, em tese, explicar sintomas de "link down"/PHY sem carrier em Clause 22,
mas normalmente NÃO explica MDIO retornando zero em Clause 45** (MDIO é um barramento de gestão
separado do link de dados — funciona independente de haver link físico ativo do outro lado,
desde que o PHY local esteja alimentado). Ou seja: a suspeita de cabo frouxo é mais plausível
para explicar por que o `ping` sempre deu 100% de perda / por que nunca se observou link
"real" do outro lado, mas não invalida sozinha o diagnóstico de que o PHY não responde a MDIO
(que é comunicação local ao chip, não depende do outro lado do cabo estar plugado).

## Ação recomendada antes de aprofundar mais o driver

Antes de continuar investigando hipóteses de software/sequência de wakeup do PHY (próximos
passos listados no `CLAUDE.md`: reordenar diagnostic MDIO vs. tuning, revisar
`RE_KERNEL_GBE_ATTACH.md`), **re-testar o básico com o cabo/conexão corrigidos**:
1. `ping` simples `192.168.0.1 <-> 192.168.0.2` com o cabo nunca usado antes (esse já rodou e é o
   mais afetado por conexão física).
2. Se o ping continuar 100% de perda, reconfirmar o diagnóstico MDIO Clause 45/22 (esse
   provavelmente não muda com o cabo, já que é local ao chip — mas vale re-rodar pra descartar
   de vez).

**Não descartar nenhuma correção de código já feita** (BAR4 efuse, guarda de IRQ) — essas
permanecem válidas independente da causa do cabo. O que pode mudar é a conclusão de que "o PHY
nunca sai de power-down" — se isso era, no fim das contas, mascarado por uma conexão física
ruim, pode ser necessário reabrir essa hipótese.
