# Kernel 7.0 — Baikal (frente 1)

Build do kernel Linux **7.0.8-Strawberry-ThinLTO-Baikal-+** para o PS4 Slim/Pro
Baikal (CUH-2xxx), mais tudo o que existe para descobrir e validar o hardware
dele: patches, driver `mts.ko`, engenharia reversa do kernel Orbis, banco de
registradores e diagnósticos.

> A distro que roda **em cima** deste kernel é a frente 2, em [`../distro/`](../distro/).

## Build

```bash
cd kernel
sudo ./00-build-kernel-7.0.sh [TAG]   # sem TAG usa <data>-sky2builtin
```

O script:
1. Reseta a árvore **local** do kernel em `/mnt/hdauxiliar/temp/kernel_build_7.0`
   (ext4, **nunca** em NTFS) no branch `baikal/7.0.8-Stable`; se a árvore não
   existe, **aborta** e instrui a restaurar do snapshot (o upstream não publica
   mais esse branch — ver seção abaixo);
2. aplica os patches em uso — `ahci-baikal-polling-fallback`, `ps4-icc-rtc-wrapper`,
   `mts-baikal-gbe-driver` e `ps4-icc-proc-debug` — com `git apply --check` +
   aborto em caso de falha (sem fallback silencioso). Os demais arquivos em
   `patches/` são **legado não aplicado** (ver abaixo);
3. copia `drivers_mts/{mts.c,mts.h}` para `drivers/net/ethernet/sony/`;
4. confere que **todos** os firmwares de `CONFIG_EXTRA_FIRMWARE` existem em
   `extra_firmware/` — falha cedo, antes do `make`, listando o que falta;
5. compila com ThinLTO (`LLVM=1`, `JOBS=2`) e faz `make modules`;
6. grava `boot_referencia/bzImage-7.0-<TAG>` e `boot_referencia/config-7.0-<TAG>`
   (com aviso se o bzImage passar de ~10 MB — limite de alguns loaders kexec,
   lição #23);
7. gera snapshot de segurança da árvore fonte em
   `/mnt/hdauxiliar/kernel_source_snapshots/kernel-src-<DATA>-<TAG>.tar.zst`.

`boot_referencia/` é o **único** lugar onde os artefatos de boot por tag vivem —
a frente 2 lê de lá (`PS4_BOOT_REF` sobrescreve o caminho). É build output: não
vem no clone.

## Restaurar a árvore a partir de um snapshot

O snapshot é a rede de segurança do build (o `boot_referencia/` é build output e
não vem no clone). Para voltar a compilar a partir dele:

```bash
cd /mnt/hdauxiliar/temp
tar -I 'zstd -d' -xf /mnt/hdauxiliar/kernel_source_snapshots/kernel-src-<DATA>-<TAG>.tar.zst   # ~6 s, 2,1 GB
cd kernel_build_7.0
# o tar exclui os produtos de link do topo (vmlinux*, por padrão ancorado no topo);
# nada a restaurar se o snapshot for >= 2026-11-11, senão ver nota abaixo
make -j2 LLVM=1 CC="ccache clang" ARCH=x86_64 prepare                       # ~21 s
```

⚠️ **Duas armadilhas já pagas (2026-11-11):**

1. **Snapshots antigos perderam arquivos-fonte.** O padrão `--exclude='vmlinux*'`
   do script (antes de 2026-11-11) casava pelo basename e derrubava **52 arquivos
   de fonte** (`arch/*/kernel/vmlinux.lds.S`, `vmlinux.lds.h`, `vmlinux-xip.lds.S`)
   — a árvore restaurada compila objetos mas **não linka**. Correção aplicada no
   `00-build-kernel-7.0.sh`: o exclude agora é ancorado no topo
   (`--exclude="kernel_build_7.0/vmlinux*"`). Em snapshot antigo, restaurar só os
   deletados: `git status --porcelain | awk '$1=="D"{print $2}' | xargs git checkout --`.
2. **NUNCA rodar `git checkout -- .` na árvore restaurada.** As alterações dos
   patches (`drivers/ata/{ahci.c,ahci.h,libahci.c}`, `drivers/ps4/*`,
   `drivers/rtc/{Kconfig,Makefile}`, `drivers/usb/host/xhci-aeolia.c`) estão
   **não commitadas** no `.git` do snapshot — um checkout amplo reverte todos os
   patches em silêncio. Verificação rápida depois de restaurar:
   `grep -c ahci_baikal_start_poll_timer drivers/ata/libahci.c` (espera `2`) e
   `grep RTC_DRV_PS4_ICC drivers/rtc/Makefile` (espera `1`). Se der zero,
   reextrair o snapshot ou aplicar `patches/*.patch`.

## Conteúdo

| Caminho | O que é |
|---|---|
| `00-build-kernel-7.0.sh` | Único script de build do kernel (nunca rodar `make` direto) |
| `patches/` | Fonte única dos patches. **Aplicados pelo build:** `ahci-baikal-polling-fallback` (SATA polling), `ps4-icc-rtc-wrapper` (RTC via ICC), `mts-baikal-gbe-driver` + `ps4-icc-proc-debug` (driver GBE e `/proc/ps4_icc`, só quando `mts.c` ainda não está na árvore). **Legado, NÃO aplicado:** `sky2-baikal-gbe` (congelava o PCIe/vídeo — ver AGENTS.md), `stmmac-baikal-fixedlink` e `sky2-fake-chipid` (sem referência no script; só histórico da época em que o driver errado era tentado) |
| `drivers_mts/` | Driver Ethernet GBE do Baikal (`mts.ko`), escrito do zero |
| `boot_referencia/` | Artefatos de boot por tag (gitignored, gerado pelo build) |
| `kernels/` | Symlink para a árvore fonte (gitignored, criado localmente — não vem no clone) |
| `scripts/` | Diagnóstico e validação: `build_mts_module.sh`, `deploy_mts.sh`, UART (`uart_start/stop/capture`), netconsole, telnet, Ghidra |
| `consolidado/` | Documentação consolidada, **SQLite de RE** (`ps4_hardware_memory.db`), decompilado, `obsoleto/` |
| `memory/` | Registro cronológico por sessão (índice em `memory/MEMORY.md`) |
| `docs/` | `planos/` (frentes ativas) e `relatorios/` (resultados de teste) + docs legados (`MIGRACAO_7.0.md`, `TENTATIVAS_7.0.md`) |
| `tools/` | Harnesses de varredura de registradores e `ps4_hdd_tools` (PFS/EAP) |
| `tests/` | Capturas UART e ciclos de teste |

## Regras que valem para esta frente

- Toda mudança de kernel é **idempotente via patch**: editar a árvore, compilar
  o arquivo isolado, `git diff HEAD -- <arquivos> > patches/<nome>.patch`,
  revalidar `git apply --check` de árvore limpa, e só então rodar o build.
- **Proibido** heredoc/`sed` inline no script de build para injetar código.
- Antes de qualquer varredura de registradores ao vivo, consultar o SQLite
  (`consolidado/ps4_hardware_memory.db`) — cada teste custa um power cycle.
- Regras completas e procedimentos: [`../AGENTS.md`](../AGENTS.md).
