# Snapshot: duas armadilhas na restauração + teste de compilação (2026-11-11)

## Contexto

`boot_referencia/` estava vazio (nenhuma tag em nenhum disco) e a árvore
`/mnt/hdauxiliar/temp/kernel_build_7.0` não existia. A única cópia do kernel
validado é o snapshot
`/mnt/hdauxiliar/kernel_source_snapshots/kernel-src-20260801-20260801-kvm-rtc-sata-final.tar.zst`
(520 MB comprimido, 2,1 GB extraído, com `.config` + `.git` + `bzImage`).

## Teste de compilação (baixo custo de CPU, `-j2` + `nice -n 19`)

| Etapa | Tempo | Resultado |
|---|---|---|
| Extração do snapshot (`zstd -d`) | 6,1 s | OK (2,1 GB) |
| `make olddefconfig` | 10,1 s | OK |
| `make prepare` | 21,0 s | OK |
| Objetos com patch: `ahci.o`, `libahci.o`, `xhci-aeolia.o`, `ps4-bpcie-icc.o` | 6,0 s | **exit 0, zero warnings** |
| `M=drivers/rtc` `rtc-ps4-icc.ko` | 2,1 s | link OK (270 KB) |
| `M=drivers/net/ethernet/sony` `mts.ko` | 4,7 s | link OK (816 KB) |

Notas:

- Os dois módulos só linkam com `KBUILD_MODPOST_WARN=1`: sem `Module.symvers` do
  `vmlinux` (que exige build completo + link), o `modpost` acusa símbolos
  indefinidos (`devm_kmalloc`, `ps4_icc_rtc_cmd`, …) e o BTF é pulado. Isso é
  esperado num teste parcial, **não** é erro de código.
- `drivers/net/ethernet/sony` **não** está ligado em
  `drivers/net/ethernet/{Kconfig,Makefile}` na árvore — `mts.ko` é compilado
  out-of-tree (`scripts/build_mts_module.sh` / `make M=...`), como planejado.
- `CONFIG_RTC_DRV_PS4_ICC` não está setado no `.config` do baseline; o módulo
  existe em `drivers/rtc/rtc-ps4-icc.c` + Kconfig/Makefile, mas não entra no
  `make modules` do build oficial.
- Não foi feito link do kernel (`make bzImage`) nem deploy — teste de compilação
  apenas, conforme pedido ("só teste, use pouca cpu").

## Armadilha 1 — snapshot antigo perdia arquivos-fonte

O `00-build-kernel-7.0.sh` usava `--exclude='vmlinux*'`. Em GNU tar esse padrão,
sem `/`, casa pelo **basename** de qualquer membro: derrubou **52 arquivos
tracked** — `arch/{alpha,arc,arm,arm64,csky,x86,...}/kernel/vmlinux.lds.S`,
`vmlinux-xip.lds.S`, `include/.../vmlinux.lds.h`. A árvore restaurada compila
objetos, mas **não linka** (o `.git` do snapshot ainda tem os arquivos, então
`git status` mostra 52 `D`).

Corrigido no script:

```diff
-    --exclude='vmlinux*' --exclude='System.map' --exclude='.tmp_*' \
+    --exclude="$(basename "$KERNEL_SRC_DIR")/vmlinux*" --exclude='System.map' --exclude='.tmp_*' \
```

Validado com árvore de teste em `/tmp`: o padrão ancorado continua excluindo
`vmlinux`, `vmlinux.o`, `vmlinux.a` da raiz e **preserva**
`arch/x86/kernel/vmlinux.lds.S`.

Em snapshot antigo, restaurar apenas os deletados (não usar `git checkout -- .`):

```bash
git status --porcelain | awk '$1=="D"{print $2}' | xargs git checkout --
```

## Armadilha 2 — `git checkout -- .` reverte os patches em silêncio

As alterações dos patches ficam **não commitadas** no `.git` do snapshot
(`drivers/ata/ahci.c`, `ahci.h`, `libahci.c`, `drivers/ps4/*`, `drivers/rtc/{Kconfig,Makefile}`,
`drivers/usb/host/xhci-aeolia.c` + arquivos novos untracked). Um
`git checkout -- .` "amplo" desfaz todos os patches sem avisar — o build seguinte
compila um kernel **sem SATA polling e sem RTC**.

Foi exatamente o que aconteceu nesta sessão: depois do checkout, os objetos
compilaram com exit 0 mas eram do código *sem* patch (`grep -c
ahci_baikal_start_poll_timer drivers/rtc/Makefile` → 0; antes → 1). Detectado
pela checagem de conteúdo, corrigido reextraindo o snapshot com `--overwrite`
e restaurando só os `D`.

**Checagem de sanidade obrigatória depois de restaurar:**

```bash
grep -c ahci_baikal_start_poll_timer drivers/ata/libahci.c   # espera 2
grep -c ahci_baikal_start_poll_timer drivers/ata/ahci.c      # espera 1
grep RTC_DRV_PS4_ICC drivers/rtc/Makefile                    # espera 1 linha
git status --porcelain | grep -c '^ M'                        # espera 10
```

## Armadilha 3 — objeto compilado à mão fica "up to date" com flags divergentes

O teste de compilação foi feito com `make ... <arquivo>.o` **sem** `KCFLAGS`, mas o
`00-build-kernel-7.0.sh` exporta `KCFLAGS`/`KAFLAGS="-march=btver2 -mtune=btver2 -Os"`
(linhas 29-30). Os objetos gerados no teste ficam com flags diferentes das oficiais, e
`make` **não rastreia mudança de flag** — um build oficial na mesma árvore pularia esses
arquivos com `INSTALL`/`CC` ausente e linkaria objetos inconsistentes. Antes de qualquer
build oficial, a árvore precisa voltar ao estado pristino (é o que o `git reset --hard`
do próprio script faz, então na prática já está coberto — mas não reaproveite objetos de
teste manual).

Medição do ccache (2026-11-11, `CCACHE_DIR=/mnt/hdauxiliar/ccache`, mesmo do script):
recompilar `drivers/ata/libahci.o` com as flags oficiais deu **direct_cache_hit**
(205687 → 205699 hits, `cache_miss` parado em 118274), 1,10 s contra ~6 s de compilação
real. Hit histórico acumulado: 67,4%. O cache **está** sendo aproveitado — inclusive para
o conjunto sem `KCFLAGS`, porque essa combinação já existia na cache.

## Conclusão

O snapshot é uma rede de segurança **utilizável** para recompilar (patches
presentes, `.config` e `.git` íntegros), mas com as duas ressalvas acima — ambas
agora documentadas em `kernel/README.md` (seção "Restaurar a árvore a partir de
um snapshot") e corrigidas no gerador.
