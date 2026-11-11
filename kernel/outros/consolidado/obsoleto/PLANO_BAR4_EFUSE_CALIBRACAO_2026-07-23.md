# Plano: Corrigir leitura de efuse da calibração PHY (BAR2 errado → BAR4 correto)

## Contexto

As três hipóteses anteriores para o RX quebrado (`MTS_MAC_EN2`, MDIO Clause
45/22, IRQ real `IMR=0x7d`) já foram testadas ao vivo e deram todas
negativas — ver `PLANO_MAC_EN2_INVESTIGACAO_2026-07-23.md` e
`PLANO_IRQ_REAL_FULLDUPLEX_2026-07-23.md`, ambos executados e commitados
(`7c6bd01`, `2793233`, `0a9e8a6`, `a948b4e`). A conclusão até então era que
o PHY nunca sai de power-down e nenhuma pista barata restava, exigindo RE
mais pesado.

Uma exploração da documentação de RE do kernel Orbis original
(`consolidado/RE_KERNEL_GBE_ATTACH.md`, `decompiled_gbe_mac_attach.txt`,
cruzada com o código-fonte já funcional de `drivers/ps4/ps4-bpcie.c`)
encontrou um **candidato concreto e nunca testado**: o `mts.c` atual lê os
parâmetros de calibração do PHY do registrador **errado**.

### O bug

Em `mts_phy_calibration()` (`mts.c:566+`), o driver lê:

```c
p0 = mts_glue_read(mp, MTS_GLUE_CALIB_3);  /* MTS_GLUE_CALIB_3 = 0x6c */
...
if ((p0 & 0x80800000) == 0x80800000) {
    /* ~18 escritas MDIO Clause-45 (devad=30/31) — tuning analógico real do PHY */
    ...
}
```

`mts_glue_read()` lê de `mp->regs_glue`, mapeado em `mts_probe()`
(`mts.c:1747-1749`) como:

```c
mp->glue_phys = 0xc8800000ULL;             /* BAR2 de 00:14.4 */
mp->regs_glue = ioremap(mp->glue_phys, 0x200000);
```

Ou seja, `p0` vem de **BAR2 + 0x6c**.

Mas o código real do Orbis (RE em `RE_KERNEL_GBE_ATTACH.md`) e o driver
Linux `ps4-bpcie.c` que **já funciona em produção** (SATA/AHCI, `ata1`/`ata2`
sobem em todo boot) leem o efuse real de **BAR4 + 0xC000 + 0x6c**:

```c
// drivers/ps4/ps4-bpcie.c:438-442 (probe da função glue 00:14.4)
sc->bar2 = pci_ioremap_bar(dev, 2);
sc->bar4 = pci_ioremap_bar(dev, 4);
...
// drivers/ps4/ps4-bpcie.c:601-602 (bpcie_baikal_sata_phy_init, já em uso)
efuse0 = ioread32(sc->bar4 + 0xC000 + 72);
efuse1 = ioread32(sc->bar4 + 0xC000 + 108);   /* 108 = 0x6c */
```

`BAR2` e `BAR4` são **recursos PCI distintos** da mesma função `00:14.4`
(confirmado ao vivo: `cat /sys/bus/pci/devices/0000:00:14.4/resource` —
BAR2 = `0xc8800000`-`0xc89fffff` [2MB], **BAR4 = `0xc9000000`-`0xc91fffff`
[2MB], populado e presente**). `mts.c` nunca mapeia BAR4 — só existe o
mapeamento de BAR2.

**Consequência prática:** `p0` quase certamente não tem os bits 23/31
setados (é o registrador errado), então `(p0 & 0x80800000) == 0x80800000`
falha sempre, e o bloco inteiro de ~18 escritas MDIO que fazem o tuning
analógico real do núcleo do PHY (`mts.c` ~linhas 640-708: `0x201e`,
`0x211f`, `0x161e/171e/181e/191e`, `0x174001e/175001e`, `0x172001e/173001e`,
`0x12001e..0x22001e`, etc.) **nunca é executado no hardware real**. Isso
bate exatamente com o sintoma observado: o código que roda DEPOIS do `if`
(page-selects, escrita forçada em `MTS_LINK_STATUS`, loop indexado
`0x1bc-0x1d4`) produz "Link UP" só de estado interno do MAC, mas a única
etapa gated pelo efuse — que de fato manipula o PHY analógico — é pulada.

### Por que este candidato é mais forte que os anteriores

- Tem lastro de RE real e cruzamento com código **já em produção** (SATA
  funciona em todo boot lendo exatamente esse padrão de BAR4+0xC000+offset).
- Explica coerentemente por que TODAS as tentativas anteriores (Clause
  45/22 MDIO, IRQ) deram negativo: se o bloco de tuning nunca roda, o PHY
  literalmente nunca recebe os parâmetros analógicos necessários para sair
  do estado zumbi — não importa o que se teste depois disso.
- Risco de leitura é baixo: o padrão `pci_ioremap_bar(dev, 4)` +
  `ioread32(bar4 + 0xC000 + offset)` já é exercitado com sucesso em **todo
  boot** pelo subsistema SATA — não é um mapeamento nunca testado neste
  hardware.
- Outras hipóteses (ICC major=5 power domains, ICC major=4/minor=0x38,
  patch de shutdown do Orbis) já foram exaustivamente testadas e
  formalmente descartadas em sessões anteriores (`consolidado/ICC_GBE_TEST_LOG.md`,
  `consolidado/obsoleto/`) — não repetir.

---

## Fase 1 — Mapear BAR4 de 00:14.4 em `mts_probe()`

**Arquivo:** `drivers_mts/mts.c` (`mts_probe`, ~linha 1747).
**Arquivo:** `drivers_mts/mts.h` (`struct mts_priv`, perto de `regs_glue`).

Adicionar novo campo `void __iomem *regs_glue_bar4;` (e `phys_addr_t
glue_bar4_phys;`) em `struct mts_priv`. No probe, logo após o mapeamento de
BAR2 já existente, mapear BAR4 com o mesmo padrão já usado para MAC address
(`mts_get_mac_address`, `mts.c:1552-1568`, via `pci_get_slot`) — mas aqui é
mais simples: como o glue físico já é acessado por endereço hardcoded, obter
o `pci_dev` da função glue via `pci_get_slot(pdev->bus, PCI_DEVFN(PCI_SLOT(pdev->devfn), BAIKAL_FUNC_ID_PCIE))`
(confirmar o valor exato de `BAIKAL_FUNC_ID_PCIE`, deve ser 4, já usado no
comentário de `mts.c:54`) e então `pci_ioremap_bar(glue_dev, 4)` — igual ao
padrão de `ps4-bpcie.c:442`. Isso deriva o endereço fisico corretamente em
vez de hardcodar `0xc9000000` (mais robusto, mas se `pci_get_slot` para essa
função falhar por algum motivo, fallback para `ioremap(0xc9000000, 0x200000)`
como plano B, já confirmado presente e do tamanho certo via
`/sys/bus/pci/devices/0000:00:14.4/resource`).

Adicionar log de confirmação (`dev_info`, mesmo padrão do log de BAR2 em
`mts.c:1752-1753`) e liberar (`iounmap`) no `mts_remove()`/paths de erro, nos
mesmos pontos onde `regs_glue` já é liberado (`mts.c:1849-1850, 1885-1886`).

**Critério de sucesso:** dmesg mostra `"Glue BAR4 (00:14.4) ioremapped em
0xc9000000 -> ... (2 MB)"` sem falha, no load do módulo.

---

## Fase 2 — Trocar a leitura de `p0..p4` para BAR4+0xC000+offset

**Arquivo:** `drivers_mts/mts.c` (`mts_phy_calibration`, ~linhas 627-638).

Adicionar uma variante de leitura (`mts_glue_bar4_read()`, mesmo padrão de
`mts_glue_read()`, `mts.c:472-477`, mas usando `mp->regs_glue_bar4`) e trocar:

```c
p0 = mts_glue_read(mp, MTS_GLUE_CALIB_3);  /* 0x6c, BAR2 — ERRADO */
```
por:
```c
p0 = mts_glue_bar4_read(mp, 0xC000 + MTS_GLUE_CALIB_3);  /* BAR4+0xC000+0x6c */
```
E o mesmo para `p1..p4` (`MTS_GLUE_CALIB_2/1/0/4`, offsets `0x68/0x60/0x5c/0x100`
— todos com `+0xC000` e lidos de `regs_glue_bar4` em vez de `regs_glue`).
**Não mexer** em nenhuma outra leitura de `mts_glue_read()` já existente
(as leituras de `0x10a030`/`0x140000`/`0x180020`/`0x180074` no
`mts_phy_wakeup()` continuam em BAR2 — só o efuse de calibração muda).

Atualizar o log existente (`mts.c:636-638`, "PHY calibration: BAR2 params:
...") para refletir que agora vem de BAR4.

**Critério de sucesso:** `p0` lido agora vem de um endereço físico diferente
(`0xc9000000+0xc06c` em vez de `0xc880006c`) — confirmar via log que o valor
mudou em relação ao anterior (não precisa ser exatamente `0x80800000`, só
precisa ser diferente do que já víamos, o que já seria evidência de estar
lendo outro registrador).

---

## Fase 3 — Teste ao vivo

1. `sudo scripts/build_mts_module.sh`
2. `./scripts/deploy_mts.sh push`
3. Capturar dmesg do load: procurar `"Glue BAR4 ... ioremapped"`, o novo
   valor de `p0` (`"PHY calibration: BAR4 params: ..."`), e **se a condição
   `(p0 & 0x80800000) == 0x80800000` finalmente for verdadeira** — nesse
   caso o dmesg vai mostrar uma sequência bem maior de escritas MDIO
   (`0x201e`, `0x211f`, etc.) que hoje não aparece.
4. Rodar `./scripts/deploy_mts.sh test` (ping `192.168.0.1↔192.168.0.2`,
   captura `mts_regs` antes/depois) — conferir se `MTS_CNT_PKTS` sai de 0,
   se os registradores PHY Clause 45/22 no sysfs (já instrumentados,
   `mts.c` ~1370+) finalmente retornam valores não-zero, e se o duplex
   reportado muda.

**Critério de sucesso:** qualquer um dos seguintes já é sinal valioso:
condição do `if` virar verdadeira pela primeira vez, registradores PHY
Clause 45 pararem de ser `0x0000`, ou `MTS_CNT_PKTS` incrementar.

---

## Fase 4 — Decisão

- **Se o bloco de tuning passar a rodar E o PHY responder no MDIO depois
  disso:** vitória — era exatamente essa a peça faltante. Próximo passo
  (fora deste plano): validar RX/TX completos, DHCP, remover logs de debug
  acumulados, consolidar documentação final da causa raiz real do projeto.
- **Se o bloco passar a rodar mas o PHY continuar em zero:** a leitura
  estava mesmo incompleta, mas há mais alguma etapa faltando — voltar para
  `RE_KERNEL_GBE_ATTACH.md`/`decompiled_dc5a0ba0_gbe_phy_calib.txt` em busca
  da próxima peça (fora de escopo aqui).
- **Se `p0` continuar sem bater `0x80800000` mesmo vindo de BAR4:**
  confirmar se o offset `+0xC000` está certo (RE aponta isso com confiança
  alta, mas vale conferir o valor bruto lido antes de assumir falha) — pode
  ser necessário reler `RE_KERNEL_GBE_ATTACH.md` para checar se o offset
  base não é diferente para a leitura específica de calibração PHY vs.
  efuse SATA (mesmo bar4, mas possivelmente offset não-idêntico).

---

## Riscos e observações

- Risco de mapear/ler BAR4 é baixo: mesmo padrão já exercitado com sucesso
  pelo subsistema SATA em todo boot deste console — não é território novo.
- Nenhuma mudança nas ~18 escritas MDIO em si (RE já confiável, valores
  vindos do binário Orbis) — só a fonte dos parâmetros `p0..p4` que
  controlam se elas rodam ou não.
- Nenhuma mudança em TX (funcional), lógica de anéis RX (já corrigida), ou
  no restante da sequência de calibração fora do bloco condicional.
- Reaproveita infraestrutura já existente (`pci_get_slot`, padrão usado em
  `mts_get_mac_address`) — sem introduzir dependências novas.

### Arquivos principais

- `drivers_mts/mts.c` — `mts_phy_calibration` (566+, condicional em
  627-708), `mts_glue_read`/`mts_glue_write` (472-483), `mts_probe`
  (mapeamento de glue ~1747), `mts_get_mac_address` (1552-1568, padrão de
  `pci_get_slot` a reaproveitar)
- `drivers_mts/mts.h` — `struct mts_priv` (novos campos `regs_glue_bar4`,
  `glue_bar4_phys`), `MTS_GLUE_CALIB_0..4` (offsets 0x5c/0x60/0x68/0x6c/0x100)
- `drivers/ps4/ps4-bpcie.c` (árvore de build
  `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/`) — referência do
  padrão correto de leitura (`bpcie_baikal_sata_phy_init`, linhas 549-665)
- `consolidado/RE_KERNEL_GBE_ATTACH.md` — RE original do offset de efuse
- `scripts/build_mts_module.sh`, `scripts/deploy_mts.sh`
