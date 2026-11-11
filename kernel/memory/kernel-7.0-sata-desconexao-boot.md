---
name: kernel-7-0-sata-desconexao-boot
description: "CORRIGIDO: 'sda' que perde conexão SATA ~31s após boot é o HD INTERNO do PS4 (irrelevante p/ nós), não nosso disco de boot (sdb, SSD Kingston via USB) — não é mais bloqueador"
metadata: 
  node_type: memory
  type: project
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

**ATUALIZAÇÃO (tag `20260716-wifissh`, mesma sessão 2026-07-16): a hipótese original abaixo estava parcialmente errada.** Via shell root real (telnet, WiFi funcionando) confirmou-se que `sda` = **HD interno do PS4** (`TOSHIBA MQ04ABF1`, ~932 GiB) — não o nosso disco de boot. Nosso disco de boot é `sdb`, um **SSD Kingston SV300S37A120G** (120GB) conectado via bridge USB JMicron (`152d:2329`), com `sdb1`=BOOT FAT32 e `sdb2`=rootfs ext4 label `psxitarch`. Ver [[root-sempre-label-psxitarch]] (lição #24 do `LICOES_APRENDIDAS.md`).

Isso muda a conclusão: a queda de SATA do `sda` (interno) descrita abaixo é um fenômeno real do HD interno do console, mas **irrelevante para o boot do nosso rootfs** — não é mais tratado como bloqueador prioritário. A causa real dos "boots mortos" anteriores (item 5-6 de `TENTATIVAS_7.0.md`) foi identificada como `root=/dev/sda2` no `bootargs-7.0.txt`, que apontava pro disco interno (vazio/errado) em vez do `sdb2` real — corrigido para `root=LABEL=psxitarch` em todos os bootargs do projeto. Depois da correção (tag `wifissh`), o rootfs de debug montou e o WiFi+telnet funcionaram normalmente, sem qualquer sinal de queda de SATA no `sdb`.

---

**Achado original (contexto histórico, mantido por precaução):** Durante o teste da tag `20260716-wifidebug`, o dmesg mostrou que `sda`/`ata1` é detectado normalmente em t=1.1s (`TOSHIBA MQ04ABF100`, link SATA 3.0 Gbps, UDMA/100), mas em t=31.8s começa a falhar: `READ FPDMA QUEUED` timeout → resets em cascata → downgrade de velocidade (3.0→1.5 Gbps) → em t=62s `ata1.00: disable device` e `sda: detected capacity change from 1953525168 to 0`. Isso é o comportamento do HD interno do PS4, não do nosso SSD de boot.

**Como aplicar:** não investigar mais isso como bloqueador de boot — o disco relevante (`sdb`) já provou montar e funcionar normalmente na tag `wifissh`. Se algum dia precisarmos acessar o HD interno (`sda`) por outro motivo, aí sim vale reabrir essa investigação (cabo/alimentação/controlador sob carga). Bloqueadores reais atuais: GPU GFX/CP sem firmware gladius real (ver [[kernel-7.0-gladius-firmware-ausente]]), Ethernet sky2 que não cria `eth0`, e WiFi "load manufacture data fail" (não fatal, mas sem regdomain). Ver [[kernel-7.0-status-subsistemas]].
