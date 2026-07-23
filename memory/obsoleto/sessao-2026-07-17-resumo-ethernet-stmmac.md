---
name: sessao-2026-07-17-resumo-ethernet-stmmac
description: "Resumo da sessão 2026-07-17 — 4 builds/testes reais no PS4: fix Kconfig NET_VENDOR_STMICRO, fix MDIO, fix fixed-link do stmmac; último teste (tag fixedlink) com resultado ambíguo (possível travamento não confirmado por log)"
metadata:
  node_type: memory
  type: project
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

> **⚠️ SUPERADO em 2026-07-17 (noite): toda a abordagem stmmac deste memo foi descartada.** A GBE Baikal é um Marvell Yukon 2 (sky2), não Synopsys — o resultado "ambíguo" abaixo era na verdade um Oops real do stmmac (BAR0 4KB), provado com foto. Estado atual e fix: [[baikal-gbe-e-sky2-nao-stmmac]] e [[marco-2026-07-17-sky2baikal-pronto-teste]]. Este memo fica como histórico do caminho descartado.

Sessão longa (2026-07-17) focada em fazer a Ethernet Baikal (stmmac, `00:14.1`) funcionar, depois de retomar a pausa de 2026-07-16 (ver [[sessao-2026-07-16-pausada-onde-continuar]], já resolvida). Detalhe técnico completo de cada tag em `distros/arch_minimal_v2/TENTATIVAS_7.0.md` itens 9 e 10 — este memo é o resumo de alto nível pra retomar rápido.

## Estado atual do HD (tag ativa no PS4): `20260717-fixedlink`

**Resultado do último teste: AMBÍGUO.** Vídeo funcionou (3ª vez seguida), mas o usuário reportou aparente travamento (teclado sem resposta, luz mudou de branca pra azul) perto do fim do boot inicial. Pós-mortem do log (`PS4_DMESG_449.txt`) NÃO mostra nenhum panic/oops/lockup, e o `DEBUG LOOP` chegou exatamente ao mesmo número máximo (449, ~48,6min) de TODOS os testes anteriores — inclusive os que não travaram. Ou seja, pode não ter sido causado pelo patch novo, pode ser um limite/característica do próprio initramfs de debug em todo boot por volta dos 49min. Mas também achamos uma anomalia real não explicada: nenhuma linha `stmmaceth` apareceu no log dessa vez (nos 2 testes anteriores sempre aparecia), mesmo com o código confirmado presente no `vmlinux` (`nm | grep sony_baikal` mostra os símbolos).

**Próximo passo recomendado (não feito ainda):** reconectar o HD, ligar o PS4 de novo com a MESMA tag `fixedlink`, mas dessa vez conectar via telnet **desde o início do boot** (assim que a rede subir, ~80s) pra ver ao vivo se `stmmac_pci_probe()` chega a rodar e onde para — em vez de só inferir pelo log depois.

## Progressão dos fixes (do mais recente pro mais antigo)

1. **`sony_baikal_gbe_default_data()` + `phylink_set_fixed_link()`** (tag `fixedlink`, patch `distros/arch_minimal_v2/patches/stmmac-baikal-fixedlink.patch`, aplicado via `git apply` idempotente no `00-build-kernel-7.0.sh`) — força link fixo (chute: `SPEED_1000`/`DUPLEX_FULL`, sem datasheet) porque `phylink_expects_phy()` só ignora a exigência de PHY em modo `MLO_AN_FIXED`. **Resultado ambíguo, ver acima.**
2. **`plat->mdio_bus_data = NULL`** (tag `stmmacfix2`) — evita `stmmac_mdio_register()` falhar com `-EIO` (nenhum PHY responde via MDIO nesse silício). **Resultado: `eth0` passou a existir em `ip link`, sem crash, mas sem link (`no phy found`).**
3. **`scripts/config --enable CONFIG_NET_VENDOR_STMICRO`** (tag `stmmacfix`) — sem esse gate pai do Kconfig, `CONFIG_STMMAC_ETH` desaparecia silenciosamente do `.config` mesmo com o nome certo. **Resultado: probe rodou sem travar o console (derrubou a suspeita de travamento do item 8), mas falhou no MDIO (ver item 2).**

Cada fix foi cumulativo — o patch atual (`stmmac-baikal-fixedlink.patch`) já inclui as 3 camadas.

## Achado paralelo importante: suspeita de travamento do stmmac NÃO se confirmou

O medo documentado em [[baikal-gbe-toque-trava-desliga-ps4]] (que o driver Ethernet reproduziria o travamento visto ao ler `cat .../config` cru) **não aconteceu** nos testes `stmmacfix`/`stmmacfix2` — o probe rodou completo sem travar. Memória já atualizada.

## Outros achados desta sessão

- [[kernel-7.0-ssh-manual-debug-loop]] — SSH funciona manualmente no DEBUG LOOP via mount+chroot+sshd. Usuário quer isso automático no próximo build do initramfs de debug (script fonte ainda não localizado).
- `consolidado/INTERNAL_SATA_FIX.md` corrigido — a maioria dos fixes propostos originalmente usava nomes de parâmetro/símbolo que não existem neste kernel (`libata.fpm`, `libata.nohpa`, `ATA_HORKAGE_*`). Não é bloqueador (HD interno não é usado agora).
- `[[taskset-kbuild-recursivo-limitar-desde-o-inicio]]` — lição sobre limitar CPU de um build já em andamento (não funciona pós-hoc, kbuild é recursivo).
- Script `00-build-kernel-7.0.sh` teve DOIS bugs de Kconfig corrigidos nesta sessão + a injeção do driver movida de Python inline pra um patch file versionado (`patches/stmmac-baikal-fixedlink.patch`), mais fácil de manter.
- `01-build-image-7.0.sh`/`02-burn-image-7.0.sh` (caminho de imagem completa) continuam com bugs conhecidos e não corrigidos (bzImage genérico errado, bootargs sem `root=LABEL`, console em conflito, initramfs de produção) — não usados nesta sessão, só o `deploy-boot-7.0.sh` leve. Ver TENTATIVAS_7.0.md item 9 se for usar esse caminho no futuro.

## Fallback garantido

Tag `wifissh` (WiFi+telnet, SEM Ethernet, GPU sempre -110) continua preservada no HD como fallback: `sudo ./deploy-boot-7.0.sh wifissh`.
