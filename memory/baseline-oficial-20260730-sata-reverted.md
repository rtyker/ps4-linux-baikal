---
name: baseline-oficial-20260730-sata-reverted
description: Novo baseline oficial confirmado ao vivo em 2026-07-30 — melhor versão até agora (boot completo, rootfs íntegro, SSH ok, GBE MDIO fix ativo). Ponto de rollback em caso de problema.
metadata:
  type: project
---

## MARCO — Novo baseline oficial (2026-07-30, tag `20260730-sata-reverted`)

**Confirmado ao vivo pelo usuário como a MELHOR versão até agora.** Em caso de qualquer
regressão/problema em builds futuros, **voltar para este ponto** com
`sudo ./deploy-boot-7.0.sh 20260730-sata-reverted` (boot-only, HD já particionado) —
não precisa refazer rootfs, só regravar os 4 arquivos de boot desta tag.

### O que está incluído
- Kernel `7.0.8-Strawberry-ThinLTO-Baikal-+ #23` (compilado `Thu Jul 30 09:48:35 -03 2026`).
- Fix de polaridade MDIO Clause 22 em `drivers_mts/mts.c` (ver
  [[mdio-clause22-bug-polaridade-corrigido-2026-07-29]]) — ATIVO.
- Mudanças de SATA polling-timer/instrumentação da noite de 29/07 — **revertidas** (não
  incluídas, ver [[build-deploy-20260730-sata-reverted-e-mecanismo-kexec-armed]]).
- `libata.force=1.00:3.0Gbps,noncq` (quirk hardcoded pré-existente do Toshiba MQ04ABF100) —
  mantido, não é parte do pacote revertido.
- Bootargs com UART (`earlycon=uart8250,mmio32,0xC890E000` + `console=uart8250,...` +
  `console=tty0`) e `rootwait` (não `rootdelay`) — já é o padrão do heredoc corrigido em
  `01-build-image-7.0.sh` (ver `AGENTS.md`).
- rootfs Arch completo (76.477 arquivos), reaproveitado sem alteração desta rodada.

### Validação ao vivo (log `tests/uart_logs/uart_20260730_102338.log`, captura manual do usuário)
- `kexec successfully armed` → shutdown normal da Orbis → salto real confirmado por
  `earlycon`/`Freeing unused kernel image`/**`Run /init as init process`**.
- `systemd[1]` completou o boot inteiro sem erros bloqueantes.
- **Vídeo HDMI confirmado** pelo usuário durante o boot.
- **SSH via WiFi (`192.168.6.128`) confirmado funcional** minutos após o boot (`uptime`:
  4 min, load normal). Host key mudou (esperado, kernel/rootfs novo) — resolvido com
  `ssh-keygen -R 192.168.6.128`.
- `uname -a`: `Linux ps4-baikal 7.0.8-Strawberry-ThinLTO-Baikal-+ #23 SMP PREEMPT_DYNAMIC
  Thu Jul 30 09:48:35 -03 2026 x86_64 GNU/Linux`.
- `mts.ko` carrega, `eth0` sobe com o MAC real (`2c:cc:44:3f:69:5f`), estado
  `UP, NO-CARRIER` — PHY continua sem link físico (bug de RX/PHY já conhecido e documentado
  em `PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md`, não é regressão desta tag).

### Achado novo a investigar (não bloqueia o baseline)
`dmesg` mostra `mts.ko` logando repetidamente, a cada ~16s, mesmo sem link:
```
mts 0000:00:14.1: RX_CLEAN idx=0 ctl=0x80000600 OWN=1 len=1536 cleaned=N
```
(`N` incrementando: 1000, 2000, ... 10000+ visto até agora). Indica alguma atividade
periódica de limpeza de descritor RX rodando sem carrier — precisa entender se é
comportamento intencional do driver (polling) ou sintoma de tráfego fantasma no anel RX.
Não visto documentado em sessões anteriores — primeira observação registrada aqui.

### Checksums dos artefatos (para conferência futura antes de um rollback)
```
bzImage-7.0-20260730-sata-reverted             bfd8e1714ad846107d4ff7ba0c447c31   15.844.352 bytes
initramfs-7.0-20260730-sata-reverted.cpio.gz   f6e413122f77b0720375ac0c9435fee9   14.428.842 bytes
bootargs-7.0-20260730-sata-reverted.txt        4038399f34266f6b795ae6fb0eb16d31   521 bytes
config-7.0-20260730-sata-reverted              62d60608fd4ac36ba2be56508ef6b2a3   139.290 bytes
```

### Pendências que continuam em aberto (não são regressão desta tag, são bugs conhecidos)
- PHY GBE ainda sem link físico (RX morto) — ver `PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md`.
- SATA interno (`ata1`) com IRQ mascarada no MSI (ver `DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md`)
  — mitigação via decoupling do `xhci-aeolia.c` continua deliberadamente adiada.
- S5 (desligamento completo) incompleto via ICC.
