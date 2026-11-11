# BAR4 efuse corrigido, mas PHY continua mudo — 2026-07-23 (noite)

## Resumo

Executado o plano `PLANO_BAR4_EFUSE_CALIBRACAO_2026-07-23.md`: encontrado e
corrigido um bug real — `mts_phy_calibration()` lia os parâmetros de
calibração (`p0..p4`) de `BAR2+offset` (`0xc8800000`), quando o efuse real
usado pelo Orbis e pelo driver SATA já em produção
(`bpcie_baikal_sata_phy_init`, `drivers/ps4/ps4-bpcie.c:601-602`) fica em
`BAR4+0xC000+offset` — recurso PCI completamente separado da mesma função
glue `00:14.4`.

## Resultado ao vivo

- `BAR4` mapeado com sucesso (`pci_get_slot`+`pci_ioremap_bar`, mesmo padrão
  de `mts_get_mac_address`): `0xc9000000`, 2 MB, confirmado presente via
  `/sys/bus/pci/devices/0000:00:14.4/resource`.
- `p0` (antes `0x331250b5` via BAR2) agora lê `0xbfbf8787` via BAR4 —
  **bits 31 e 23 setados**, condição `(p0 & 0x80800000) == 0x80800000`
  **finalmente bate** (nunca batia antes).
- Confirmado via log dedicado (`"condicao efuse bateu"`) que o bloco de
  ~18 escritas MDIO de tuning analógico do PHY **agora executa de fato**
  — algo que nunca acontecia com o valor de BAR2.

## Mas o resultado é negativo para conectividade

Mesmo com o bloco de tuning executando:
- PMA/PMD Control1/Status1/ID1/ID2 (Clause 45): continuam `0x0000`
- AN Status / 1000BASE-T AN Status: continuam `0x0000`
- Clause 22 BMCR (scan completo phy_addr 0-31): timeout/residual zero, igual
  a antes
- `MTS_CNT_PKTS`: continua `0`
- Ping `192.168.0.1↔192.168.0.2`: continua 100% de perda
- Link status (`0x04`): oscila entre `Link DOWN` e o "Half duplex" já visto
  antes — sem mudança de padrão

Testado estável (sem crash, sem regressão em TX/RX, throttling de log
RX_CLEAN intacto).

## Conclusão

A correção do BAR era um bug real e válido (confirmado por comparação
direta com código já em produção), mas **não é suficiente sozinha** para
acordar o PHY. Isso significa que há pelo menos mais uma etapa faltando na
sequência de wakeup/calibração — as ~18 escritas MDIO de tuning agora
rodam, mas não bastam por si só.

## Hipóteses descartadas nesta mesma investigação (não repetir)

Ver `consolidado/ICC_GBE_TEST_LOG.md` e `consolidado/obsoleto/` para o
histórico completo já testado e refutado:
- ICC major=4/minor=0x38: só um "liveness ACK" genérico, não distingue
  sub-serviços, não é gatilho de power-on
- ICC major=5 (`icc_device_power`): só 4 domínios (wlan/bt, usb, hdd, bd),
  nenhum para GBE
- Hipótese "GBE no mesmo domínio elétrico que WLAN/BT": testada e refutada
- Teste de sanidade nativa (Orbis puro, sem Linux): ping funciona
  perfeitamente — **a rail elétrica já vem ligada por padrão**, não existe
  "comando de ligar" a descobrir; o problema é uma etapa de
  calibração/wakeup ainda incompleta no driver Linux, não energia ausente

## Próximos passos (fora de escopo desta sessão)

Voltar para `consolidado/RE_KERNEL_GBE_ATTACH.md` e
`decompiled_dc5a0ba0_gbe_phy_calib.txt` em busca de outra etapa da
calibração ainda não incorporada — o efuse corrigido é necessário mas não
suficiente. Considerar também se a ORDEM das operações (wakeup → diagnostic
Clause45/22 → leitura de efuse → tuning) bate exatamente com a ordem real
do Orbis, já que o diagnostic MDIO roda ANTES do tuning neste driver (pode
ser que o PHY só responda a MDIO depois do tuning, não antes — o
diagnostic atual testa cedo demais).

## Ver também

- `PLANO_BAR4_EFUSE_CALIBRACAO_2026-07-23.md` (plano executado)
- `mac-en2-descartado-phy-nunca-acorda-2026-07-23.md` (investigação anterior)
- Commit `ce145b8` (correção do BAR)
