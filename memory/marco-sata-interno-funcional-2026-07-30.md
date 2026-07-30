---
name: marco-sata-interno-funcional-2026-07-30
description: MARCO — SATA interno (ata1, Toshiba MQ04ABF100) funcional pela primeira vez sob Linux, via polling timer de 1ms (Fase B do PLANO_SATA_POLLING_CORRECAO). Novo baseline oficial 20260730-sata-polling-fase-ab, ponto de rollback.
metadata:
  type: project
---

## MARCO — SATA interno funcional pela primeira vez (2026-07-30, tag `20260730-sata-polling-fase-ab`)

**Primeira vez neste projeto que o HD interno do PS4 (`ata1`, Toshiba MQ04ABF100,
`0000:00:14.7`) funciona de ponta a ponta sob Linux, sem exceção/timeout/disable device.**
Confirmado ao vivo com vídeo OK (usuário configurou a resolução do próprio PS4 manualmente
como 1080p, não automático, antes do boot) e SSH funcional.

### O que foi feito
Reaplicada a Fase A+B completa do `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md` (que na noite de
29/07 tinha sido implementada mas nunca compilada/testada, e foi revertida na manhã de 30/07 só
para isolar o teste do fix de GBE) sobre o kernel do baseline já confirmado
[[baseline-oficial-20260730-sata-reverted]]:
- `drivers/ata/{ahci.c,ahci.h,libahci.c}`: timer de polling `hrtimer` de 1ms como fallback
  quando `PxIE` é zerado fora do ciclo normal freeze→thaw, com as 3 correções técnicas da
  revisão de 29/07 (`hrtimer_setup` em vez de `hrtimer_init`, ack de `HOST_IRQ_STAT`, guarda
  `ata_port_is_frozen`) + instrumentação de debug (`ahci_dbg:` em `freeze()`/`thaw()`/EH).
- `drivers/usb/host/xhci-aeolia.c`: liga o mesmo polling timer para o dispositivo composto
  Baikal (func 7, xHCI+AHCI), já que é esse caminho — não o `ahci_init_one()` genérico — que
  efetivamente recebe o `ata1` do PS4.
- Build via `00-build-kernel-7.0.sh 20260730-sata-polling-fase-ab`, `taskset -c 0-3` (50% CPU),
  ~20min, sem erros.
- Deploy boot-only (`deploy-boot-7.0.sh`), rootfs reaproveitado do baseline GBE.

### Resultado ao vivo (dmesg completo salvo em `tests/uart_logs/dmesg_completo_20260730-sata-polling-fase-ab_SUCESSO.log`)
- `ata1.00: configured for UDMA/100` — probe limpo, sem nenhuma exceção.
- `PS4 Baikal: AHCI f7 polling timer started (1ms)` confirmado ativo em
  `xhci_aeolia 0000:00:14.7`.
- **Zero ocorrências de `exception`/`disable device`/panic real em 1322 linhas de dmesg**
  (as únicas 2 ocorrências de "panic" são o literal `panic=0` do cmdline).
- Padrão de freeze/EH/thaw do `ata1`: só **2 ciclos no probe** (t=2.48s e t=2.51s), depois
  `thaw()` em t=3.02s escreve `PxIE=0x7840007f` e **isso nunca mais zera** — ao contrário do
  padrão histórico (reincidência ~37s, `disable device` ~84s). O `ata2` (HD externo USB) segue
  o mesmo padrão saudável.
- **Leitura real confirmada:** `dd if=/dev/sda bs=1M count=50` → 52.428.800 bytes a 71.2 MB/s,
  sem erro.
- `fdisk -l /dev/sda` retorna a tabela de partições completa (931.51 GiB, GPT, Toshiba
  MQ04ABF100) — disco 100% acessível.
- 3+ minutos de uptime estável, sem sinal de regressão.

### Detalhe operacional — vídeo em monitor auxiliar
Durante os testes desta sessão, o `video=HDMI-A-1:...` do bootargs foi temporariamente ajustado
para `1360x768@60` (monitor auxiliar do usuário) e depois revertido para `1920x1080@60`
(monitor original, já homologado). **O usuário também configurou a resolução do próprio PS4
(menu de sistema/HDMI, antes do handoff para Linux) manualmente como 1080p, não automático** —
esse ajuste manual no PS4, combinado com `video=HDMI-A-1:1920x1080@60` no bootargs, é o que
produziu vídeo estável nesta e nas sessões anteriores. Vale lembrar disso ao trocar de monitor.

### Registrado como novo baseline oficial / ponto de rollback
Tag `20260730-sata-polling-fase-ab` — kernel do baseline GBE (`20260730-sata-reverted`) + fix de
SATA funcional. **Supera o baseline anterior**: agora GBE (com as limitações já conhecidas do
PHY) E SATA interno funcionam juntos. Ver `test_history` id 73 no `ps4_hardware_memory.db`.
Rollback: `sudo ./deploy-boot-7.0.sh 20260730-sata-polling-fase-ab` (boot-only) — se precisar
voltar a um ponto anterior sem o fix de SATA, `20260730-sata-reverted` continua disponível em
`boot_referencia/`.

### Observação para limpeza futura (não bloqueia nada)
A instrumentação de debug (`ata_port_warn` em `ahci_freeze()`/`ahci_thaw()`/`ahci_error_handler()`,
marcada "REMOVER quando a investigação terminar" no próprio código) ainda está ativa nesta tag.
Como a Fase B resolveu o problema, pode ser removida num próximo rebuild de limpeza — não é
urgente, só gera 2-4 linhas extras de log por conexão/desconexão de porta.
