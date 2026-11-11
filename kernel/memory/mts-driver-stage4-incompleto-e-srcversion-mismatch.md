---
name: mts-driver-stage4-incompleto-e-srcversion-mismatch
description: mts.ko precisa ser recompilado na árvore exata do kernel rodando (srcversion, não só vermagic); driver stage=4 não implementa TX nem detecção de carrier — NO-CARRIER é esperado, não é bug de cabo
metadata:
  type: project
---

## Descoberta 1: "invalid module format" pode ser srcversion, não vermagic

Ao tentar carregar `drivers_mts/build/mts.ko` (build antigo, da tag `20260723-mts-autoeth0`) num PS4 rodando o kernel `7.0.8-Strawberry-ThinLTO-Baikal-+ #33` (branch `baikal/7.0.8-Stable`, commit `811184c1f` + 2 uncommitted changes locais), o `insmod` falhou com `invalid module format` — **mesmo com `vermagic` idêntico** (`7.0.8-Strawberry-ThinLTO-Baikal-+ SMP preempt mod_unload` nos dois módulos).

**Causa:** `CONFIG_MODVERSIONS` está ativo neste kernel. O `srcversion` (checksum do código-fonte + headers exatos usados no build) dos dois `.ko` divergia:
- `drivers_mts/build/mts.ko` (standalone, Makefile próprio em `drivers_mts/`): `srcversion: AE99E28A92F4920CA455AE0`
- `drivers/net/ethernet/sony/mts.ko` (in-tree, já dentro de `/mnt/hdauxiliar/temp/kernel_build_7.0`, buildado junto com o kernel #33 às 07:16): `srcversion: EB8B81DD0EBD61693E62E6B`

Os dois vêm do **mesmo `mts.c`** (só 2 linhas de diff, `stage` default 1→4, não commitado), mas foram compilados contra `Module.symvers`/headers de árvores diferentes — o suficiente para os CRCs de modversions não baterem com os símbolos exportados pelo kernel rodando.

**Correção que funcionou:** recompilar o módulo **dentro da própria árvore `kernel_build_7.0`** (mesmo `Module.symvers` do build #33), com a mesma toolchain do `00-build-kernel-7.0.sh` (`LLVM=1 ARCH=x86_64`):
```bash
cd /mnt/hdauxiliar/temp/kernel_build_7.0
sudo make LLVM=1 ARCH=x86_64 M=drivers/net/ethernet/sony modules
```
Resultado: novo `mts.ko` (`srcversion: BB8751FB113FD797CE1CE9F`) carregou sem erro e registrou `eth0` com sucesso.

**Regra geral daqui pra frente:** para carregar um módulo `.ko` via `insmod` num PS4 já rodando, **sempre recompilar dentro da árvore de build que gerou o `vmlinux`/kernel atualmente ativo** (checar `uname -r` bate com `include/config/kernel.release` da árvore) — nunca reutilizar um `.ko` de outra sessão de build, mesmo que o `vermagic` pareça igual. `vermagic` sozinho NÃO garante compatibilidade quando `CONFIG_MODVERSIONS=y`.

**Como transferir o `.ko` pro PS4:** telnet/nc com heredoc e base64 tem timeout curto demais para arquivos >20KB (trava, `nc` cai). O método que funcionou: servir o arquivo via `python3 -m http.server` no host (rede `192.168.6.100`) e rodar `wget` de dentro do PS4 via telnet.

## Descoberta 2: driver `mts.c` stage=4 NÃO implementa TX nem detecção de carrier — `NO-CARRIER` é esperado

Depois de `insmod mts.ko stage=4` + `ip link set eth0 up`, a interface fica permanentemente em `NO-CARRIER`, **mesmo com o cabo Ethernet fisicamente conectado** (confirmado pelo usuário) e com o host mostrando link físico ativo (`ethtool enp60s0`: `Link detected: yes`, 1000Mb/s Full Duplex).

Lendo `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/net/ethernet/sony/mts.c` (linhas 408-457), três lacunas confirmadas no próprio código (comentários do autor):

1. **`mts_open()` (linha 422-429) chama `netif_carrier_off(dev)` incondicionalmente**, sem nenhuma lógica de leitura de status de link do PHY nem chamada a `netif_carrier_on()` em lugar nenhum do driver. **A interface nunca vai reportar carrier, independente do estado real do cabo.**
2. **`mts_start_xmit()` (linha 439-449) não implementa TX de verdade** — todo pacote é descartado (`tx_dropped++`), comentário no código: *"TX ainda nao implementado: falta mapear o registrador de doorbell e o layout completo do descritor de transmissao"*.
3. **`mts_interrupt()` (linha 408-420) não processa o registrador de status de IRQ** — só incrementa contador e retorna `IRQ_HANDLED`, comentário: *"o registrador de STATUS de interrupcao ainda nao foi localizado na RE"*.

Isso é consistente com os logs de MDIO vistos no mesmo teste (`MDIO: SEM leitura valida (1 distintos) — transacao nao completou`, todos os registradores PMA/PMD/PCS lidos como `0x0000`) — a leitura do PHY via SMI Clause 45 também ainda não funciona corretamente, então mesmo que a lógica de carrier existisse, não haveria como determinar o link real hoje.

**Conclusão prática:** o estágio atual do driver (`stage=4`) prova só: PCI probe, enable de MAC, leitura de MAC da SPM, alocação/programação de anéis DMA, `register_netdev()`. **RX/TX de pacotes reais e detecção de link são trabalho de driver ainda não feito** — não é um problema de configuração de rede, cabo, ou switch. Não repetir troubleshooting de "por que não pinga" até o TX/RX e carrier detection serem implementados no driver.

Ver também [GBE-VIVA-driver-errado-mts-nao-sky2](GBE-VIVA-driver-errado-mts-nao-sky2.md) (contexto de por que `mts` é o driver certo) e `../consolidado/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md` (marco de registro da eth0).
