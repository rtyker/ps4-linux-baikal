---
name: mts-c-corrupcao-de-edicao-sempre-compilar-antes
description: drivers_mts/mts.c ficou com erro de sintaxe real (string truncada fundida com a próxima função) no working tree por pelo menos uma sessão sem detecção — sempre rodar o build antes de considerar a sessão pronta para teste ao vivo.
metadata:
  type: feedback
---

Em 2026-07-25 o arquivo `drivers_mts/mts.c` continha um erro de sintaxe real que impedia a compilação: a string do `dev_warn()` em `mts_send_rmu_frame()` (por volta da linha 1409) estava truncada e fundida diretamente com `static void mts_mac_enable(struct mts_priv *mp)\n{`, e sobrava um trecho duplicado (fechamento antigo da função `mts_mac_enable`) logo depois do fechamento correto — provavelmente resultado de uma edição anterior que não limpou o texto residual. Havia ficado assim, sem detecção, até uma sessão de revisão explícita rodar `sudo bash scripts/build_mts_module.sh`.

Também foi encontrado, na mesma revisão, um `device_remove_file()` faltando para `dev_attr_trigger_rx_clean` em `mts_remove()` (criado em `mts_probe()` mas nunca removido no unbind/rmmod) — vazamento de sysfs, corrigido junto.

**Por quê:** o projeto usa muita edição incremental de `mts.c` entre sessões (frequentemente por agentes/sessões diferentes), e o arquivo é grande (~2800+ linhas) com muitas funções de diagnóstico via sysfs (`trigger_*`). Erros de sintaxe introduzidos por edições automatizadas (blocos de string cortados, duplicação de trechos ao mover código) não aparecem no `git diff` de forma óbvia — só o compilador pega.

**Como aplicar:** depois de qualquer edição em `drivers_mts/mts.c` (ou `mts.h`), rodar `sudo bash scripts/build_mts_module.sh` (usa a árvore em `/mnt/hdauxiliar/temp/kernel_build_7.0`, requer sudo) ANTES de propor deploy/teste ao vivo no console. Nunca assumir que o arquivo compila só porque o diff "parece" coerente — sobretudo depois de reordenar/mover funções inteiras (como aconteceu na sessão de 2026-07-24/25 movendo o diagnóstico MDIO pós-calibração e reescrevendo `mts_mac_enable`/`mts_mac_stop`). Ao adicionar um novo `DEVICE_ATTR_RW(trigger_x)` em `mts_probe`, sempre conferir que existe o `device_remove_file` correspondente em `mts_remove`.
