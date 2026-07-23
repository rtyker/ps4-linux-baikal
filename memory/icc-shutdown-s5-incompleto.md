---
name: icc-shutdown-s5-incompleto
description: poweroff -f encerra o SO mas não corta o S5 (luz azul fica acesa) — driver já tenta via ICC major=4/minor=1 e tem WARN_ON(1) antecipando essa falha
metadata:
  type: project
---

**Fato confirmado em código-fonte (2026-07-23), `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c`:**
- `pm_power_off = &icc_shutdown;` (linha 547) — `poweroff -f`/`sysrq o` já invoca esse handler automaticamente, não precisa de nada extra no userland.
- `icc_shutdown()` (linhas 404-414) envia comando ICC **major=4, minor=1**, payload `{0,0,2,0,1,0}` via `bpcie_icc_cmd()`, espera `mdelay(3000)` e depois faz `WARN_ON(1)`.
- O `WARN_ON(1)` é proposital: o autor original (fail0verflow) já esperava que a fonte cortasse energia (S5) dentro dos 3s: se o código chegar até o warning, é sinal de que o comando ICC não completou o desligamento total.
- Guarda `if (bpcie_status() != 1) return;` só pularia o envio se o canal ICC/bpcie nunca tivesse inicializado — no console atual (Baikal, com GBE/LED/firmware query ICC já funcionando via major=4/minor=0x38 etc., ver `consolidado/ICC_GBE_TEST_LOG.md`) é bem provável que `bpcie_status()==1` e o comando seja enviado normalmente.
- `icc_reboot()` (equivalente em `ps4-apcie-icc.c` ~linhas 421-431) usa o MESMO major/minor, só muda o 2º byte do payload (`0,1,...` em vez de `0,0,...`) — confirma que major=4 é o serviço de power/sistema e o payload de 6 bytes é a estrutura de comando (provavelmente algo como `[reserved, ação(0=shutdown/1=reboot), tamanho?, ...]`).

**Por que:** usuário observou (sessão 2026-07-22) que `sync && poweroff -f` derruba a rede (ping 100% perda) mas o PS4 fica com luz azul acesa/pulsando — S5 real não ocorre, exige botão físico ou comando ICC dedicado. Este achado explica exatamente esse sintoma: o comando ICC de shutdown já é tentado automaticamente pelo kernel, mas não é suficiente por si só nesse hardware/firmware do ICC — não é falta de integração Linux, é o comando/payload em si que está incompleto ou precisa de um passo anterior não replicado.

**Como aplicar / próximo passo:** capturar dmesg via netconsole durante um `poweroff -f` real ao vivo e conferir se aparece o stack trace do `WARN_ON(1)` em `ps4-bpcie-icc.c:413`. Se aparecer → confirma que o comando foi enviado e ignorado pela fonte, e o próximo passo é RE do `icc_power.c` real dentro do dump do kernel Orbis 12.52 (`consolidado/dumps_orbis/kmem_dump_1252.bin`) para achar a sequência real de comandos ICC que o firmware oficial usa para o S5 completo (pode precisar de mais de um comando, ou um payload diferente de 6 bytes). Ver também [[dump-kernel-1252-culpado-e-usb-nao-kmem]] para como já se fez RE nesse dump antes.
