# MAC_EN2 descartado / PHY nunca acorda — causa raiz do RX (2026-07-23 noite)

## Resumo

Depois de corrigir TX (tail pointer doorbell) e a lógica de software de RX
(bit `MTS_DESC_OWN` simétrico, loop infinito eliminado), o RX continuou sem
receber nenhum frame fisicamente. Uma sessão de 4 fases de diagnóstico
(`PLANO_MAC_EN2_INVESTIGACAO_2026-07-23.md`) isolou a causa raiz:

**O PHY nunca sai de power-down.** Nenhum dos dois protocolos MDIO
implementados no driver consegue extrair sinal real do chip:

- **Clause 45** (MMD=1 PMA/PMD Control1/Status1/ID1/ID2, MMD=7 AN Status,
  1000BASE-T AN Status): todos retornam `0x0000` com `ret=0` (transação
  completa, sem timeout, mas sem dado real).
- **Clause 22** (BMCR, reg=0x00): scan completo de `phy_addr` 0 a 31 —
  endereços 0-15 dão timeout (`-110`), 16-31 retornam `0x0000` com `ret=0`
  (resíduo, não é uma resposta real de PHY).

O registrador de status do MAC (`BAR0+0x04`, `MTS_LINK_STATUS`) reporta
`"Link UP: 1000 Mbps Half duplex"` de forma consistente, mas **isso é estado
interno do MAC, não reflexo de negociação física real** — já era sabido que
escrever nesse registrador para forçar full-duplex é um no-op comprovado
(`pre 0x04=0x00000b78` / `post 0x04=0x00000b78`, valores idênticos).

## `MTS_MAC_EN2` (0x38) — descartado como suspeito

Testado em 3 sessões seguidas: o registrador já nasce em `0x00000000` **antes**
de `mts_phy_calibration()` rodar — não é a calibração que zera, nunca reteve
o bit desde a primeira escrita. Mesmo padrão de "não retenção" já conhecido
do `MTS_MAC_EN1` (0x34). O comentário antigo no código ("escrito 1, lê 8")
não se reproduziu nenhuma vez nas 3 sessões — provavelmente obsoleto ou
condicional a um estado de PHY que não estamos alcançando hoje.

## Achado novo, não conclusivo: `0x50` é dinâmico de verdade

Ao contrário de `0x34`/`0x38` (sempre zero), `0x50` muda de valor entre
pré-calibração (`0xa4`), pós-calibração (`0x00`) e runtime (`0x04`).
Significado ainda desconhecido — não foi aprofundado.

## 🔑 Achado arqueológico mais importante: versão perdida com Full-duplex real

`memory/teste-5-resultado-calibracao-tabela-2026-07-23.md` (sessão da TARDE
do mesmo dia, ANTES desta investigação) documenta um boot que produziu:

```
IMR (0x54) = 0x00000000
...
timer de polling iniciado (intervalo 10ms)
NAPI habilitado
interrupt habilitada, IMR=0x0000007d
open concluido
Link UP: 1000 Mbps Full duplex
```

Ou seja: **uma versão do driver que rodou HOJE MAIS CEDO tinha tanto o timer
de polling/NAPI quanto uma IRQ real habilitada (`IMR=0x7d`) — e obteve
Full duplex genuíno**, não o "Half duplex" que vemos consistentemente desde
então.

**Busca por essa versão do código: inconclusiva.** `git log -S "interrupt
habilitada"` e `git log -S "0x7d"` não encontram nada em nenhum commit deste
repositório (incluindo o commit inicial `d49f085`, que já não tem essas
strings). Backups conhecidos em `/mnt/hdauxiliar/temp/kbuild_backup_180042`
(2026-07-22, anterior ao teste-5) também não têm. Como
`scripts/build_mts_module.sh` sempre sobrescreve a árvore de build com o
`drivers_mts/mts.c` atual antes de compilar, qualquer versão intermediária
que só existiu na árvore de build foi irremediavelmente sobrescrita por
builds subsequentes no mesmo dia.

**Hipótese mais promissora para a próxima sessão:** o código atual sempre
escreve `MTS_IMR_DEFAULT = 0x00000000` (tudo mascarado) e nunca habilita IRQ
real de fato — usa só o timer de polling de 10ms. A única evidência concreta
de full-duplex genuíno coincide exatamente com uma sessão que tinha IRQ real
habilitada. Vale testar reabilitar `MTS_IMR` com um valor não-zero (ex.
`0x7d`, testado com sucesso antes) e ver se isso muda o resultado da
negociação de duplex — mesmo que a explicação exata de por que IRQ afetaria
autonegociação PHY ainda não esteja clara, é a única correlação empírica
positiva encontrada até agora neste projeto.

## Ver também

- [[PLANO_MAC_EN2_INVESTIGACAO_2026-07-23]] (plano executado)
- [[TESTE_MAC_EN2_BMCR_RESULTADO_2026-07-23]] (resultado detalhado das fases 2-4)
- [[PLANO_DUPLEX_PHY_MDIO_2026-07-23]] (plano anterior, fases A/B)
- `memory/teste-5-resultado-calibracao-tabela-2026-07-23.md` (evidência do
  Full-duplex perdido)
