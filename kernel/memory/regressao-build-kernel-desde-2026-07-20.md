---
name: regressao-build-kernel-desde-2026-07-20
description: RESOLVIDO — desabilitar CONFIG_DEBUG_INFO_BTF quebra o boot deste console (tela preta). Nunca desabilitar; limitar o pahole com JOBS=2 em vez disso.
metadata:
  type: project
---

# ✅ RESOLVIDO — a causa era o BTF desabilitado (erro do assistente)

> **CAUSA CONFIRMADA (2026-07-22):** desabilitar `CONFIG_DEBUG_INFO_BTF` quebra o boot
> deste console. Dois builds limpos, sem nenhum código de risco, deram **tela preta**:
> `20260722-gbe-revertido` e `20260722-mts-clean`. Todos os builds com BTF **ligado** e
> sem código arriscado bootam normalmente.
>
> Medido com `readelf`: a seção `.BTF` vale **9,2 MB** do vmlinux (2,4 MB no bzImage
> comprimido), e desabilitá-la derruba junto `SCHED_CLASS_EXT`/`EXT_GROUP_SCHED` por
> dependência (`kernel/Kconfig.preempt`) — mais ~60 KB de `.text`.
>
> **Origem do erro:** o assistente desabilitou o BTF para contornar um OOM do pahole
> (9,4 GB de RSS). Mas o OOM era circunstancial — o pahole roda com `-j8` porque herda
> o `-j` do build (`scripts/Makefile.btf`: `JOBS := $(patsubst -j%,%,$(MAKEFLAGS))`),
> e havia uma VM libvirt ocupando 6 GB da máquina naquele momento. Tratou-se uma
> condição transitória do ambiente como propriedade do build, e removeu-se uma opção
> do kernel por causa disso.
>
> **Correção:** BTF religado + `JOBS=2` em `MAKE_OPTS` do `00-build-kernel-7.0.sh`
> (atribuição na linha de comando tem precedência sobre o `JOBS :=` do makefile),
> limitando o pahole sem sacrificar o BTF nem a velocidade do build.
>
> **Regra:** nunca desabilitar `CONFIG_DEBUG_INFO_BTF` neste projeto.

---

## Registro original da investigação (mantido para histórico)

# Regressão de build: nada compilado desde 2026-07-20 dá boot

## O padrão

| tag | build | data | resultado ao vivo |
|---|---|---|---|
| `20260717-sky2baikal` | **#17** | 17/07 20:52 | ✅ vídeo OK |
| `20260717-iccdbg` | **#19** | 17/07 23:31 | ✅ vídeo OK |
| `20260720-sky2len-fix` | **#19** (mesmo binário) | — | ✅ vídeo OK |
| `20260720-gbe-bpcie-init` | — | 20/07 | ❌ tela preta |
| `20260721-gbe-hold-release` | — | 21/07 | ❌ **congelou** |
| `20260722-gbe-release-safe` | — | 22/07 | ❌ tela preta |
| `20260722-gbe-revertido` | — | 22/07 | ❌ tela preta |

**Os únicos kernels que dão boot são os de 17/07.** Tudo compilado de 20/07 em diante falha.

## A tag `sky2len-fix` nunca teve kernel próprio

`md5sum` prova que `bzImage-7.0-20260720-sky2len-fix` é **byte a byte idêntico** a `bzImage-7.0-20260717-iccdbg` (`8283467782d2ec77d4c2a88c3f3dc660`), ambos com carimbo `#19 SMP PREEMPT_DYNAMIC Fri Jul 17 23:31:53 -03 2026`.

Consequências:
- a correção `pci_resource_len()` que dá nome à tag **nunca esteve** no kernel testado;
- isso explica o `resource sanity check: requesting [mem 0xc2000000-0xc2003fff]` que continua no dmesg e que foi anotado como "discrepância" em [gbe-hold-pulse-write-only-e-sequencia-correta](gbe-hold-pulse-write-only-e-sequencia-correta.md) — não é discrepância, é o kernel de 17/07;
- o baseline oficial registrado em [baseline-oficial-sky2len-fix](baseline-oficial-sky2len-fix.md) é, na prática, o **iccdbg de 17/07**.

Provável origem: o build de 20/07 não produziu binário novo e o script copiou o anterior, ou houve cópia manual.

## Causas já DESCARTADAS por medição

O `gbe-revertido` é o caso decisivo: build limpo, sem nenhuma escrita de hardware arriscada, e ainda assim tela preta. Comparado ao kernel #19 que funciona:

| suspeita | como foi descartada |
|---|---|
| **config** | apenas **6 diferenças**, todas de opções removidas: `DEBUG_INFO_BTF`, `DEBUG_INFO_BTF_MODULES`, `SCHED_CLASS_EXT`, `EXT_GROUP_SCHED`, `MFD_SYSCON`, `REGMAP_MMIO`. Nenhuma toca vídeo, DRM ou boot. Config real do kernel que funciona extraído do próprio binário via `CONFIG_IKCONFIG` (`scripts/extract-ikconfig`) |
| **toolchain** | `/proc/version` do kernel que funciona diz `clang version 22.1.8, LLD 22.1.8`; o ambiente de build atual tem exatamente `clang 22.1.8` / `LLD 22.1.8` |
| **initramfs** | md5 **idêntico** (`2e8140bd...`) em todas as tags, das que funcionam às que falham |
| **bootargs** | md5 **idêntico** (`896ed733...`) em todas as tags |

**Só o `bzImage` varia.** A causa está no binário do kernel, e ainda não foi localizada.

## Por que isso bloqueia o driver `mts`

O módulo `mts.ko` compilado hoje **não carrega** no kernel #19 em execução:

```
insmod: can't insert 'mts.ko': invalid module format
dmesg: module: x86/modules: Invalid relocation target, existing value is
       nonzero for sec 22, idx 1, type 1, loc ffffffffa0201540, val ffffffffa0400d60
```

O `vermagic` bate (`LOCALVERSION` é fixo e não inclui o número do build), `CONFIG_MODVERSIONS` está desligado e não há assinatura — mas o binário do kernel é de 17/07 e o módulo foi gerado contra a árvore de hoje. Módulo tem que ser compilado contra o kernel em que vai rodar.

Ou seja: **testar o driver exige deployar o kernel correspondente — que é justamente o que não dá boot desde 20/07.** A regressão de build é o bloqueador real, não o driver.

## Como aplicar

Antes de qualquer novo teste do `mts`, resolver a regressão. Pistas ainda não exploradas:
1. bisseccionar o `.config` entre o extraído do #19 e o atual (mesmo as 6 diferenças parecendo benignas, `MFD_SYSCON`/`REGMAP_MMIO` sumiram por efeito colateral de algum `select` — vale entender qual);
2. comparar o `System.map`/tamanho de seções entre #19 e um build atual;
3. verificar se o `make` incremental está reaproveitando objetos inconsistentes — um `make clean` completo nunca foi testado nesta série;
4. `CONFIG_SCHED_CLASS_EXT` depende de `DEBUG_INFO_BTF` (`kernel/Kconfig.preempt`), então desligar BTF derruba sched_ext junto — é a explicação de 4 das 6 diferenças, e mostra que desabilitar BTF tem mais efeito colateral do que parecia.

**Não gastar mais power cycles testando variações do driver enquanto isso não estiver resolvido** — nenhum kernel novo chega a bootar para carregá-lo.
