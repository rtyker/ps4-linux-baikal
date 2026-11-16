# Otimização do build do kernel — 2026-11-16

**Motivo:** o build completo levava ~41 min (`20261112-cifs`: 41m11s) e o ciclo kernel → teste chegava a ~1h30 quando o `01-build-image` rodava junto.

## Medição (antes)

| Etapa | Tempo | Observação |
|---|---|---|
| Compilação dos `.c` | ~1 min | O ccache funciona: 75% de acerto acumulado, 15 GB |
| **Link ThinLTO (`LD vmlinux.o`)** | **~35 min** | Codegen do kernel inteiro refeito do zero a cada build, com `--thinlto-jobs=2`. O kernel 7.0 não passa `--thinlto-cache-dir` |
| `01-build-image --incremental` (Docker) | ~46 min (tag `btf-disabled-s5`) | Desnecessário quando só o bzImage muda. Ainda reinstala todos os pacotes (`pacman -Sy` sem `--needed`) |

Árvore: **4106 objetos**, 1688 `=y` e 13 `=m`. Quase tudo é built-in e passa pelo link LTO.

| Bloco | Objetos | Uso no Baikal |
|---|---|---|
| AMD Display Core (`drivers/gpu/drm/amd/display`) | **470 (11%)** | **Não usado**: Liverpool/Gladius usam o caminho legado `dce_v8` (`amdgpu_device.c`: DC só com `amdgpu.dc=1`). dmesg: `ip block <dce_v8_1_0>` |
| WiFi mt76 (mt7615/76x0/76x2/7601u/7603/7663/7915/7921) | ~100 | Não usado: o MT7668 é o driver `MT76X8` (`depends on CFG80211`, independente da família mt76) |
| WiFi Marvell (mwifiex/mwl8k) | ~30 | Só Aeolia/Belize |
| btrfs, NFS + lockd + sunrpc | ~140 | Rootfs ext4; NFS foi trocado por CIFS em 2026-11-12 |
| batman-adv, x25, ieee802154, mptcp, wireguard | ~80 | Sem uso |
| virtio (convidado) | ~20 | O PS4 roda em bare metal |

## Aplicado no `kernel/00-build-kernel-7.0.sh`

1. **Cache do ThinLTO** em `kernel/.thinlto-cache` (fora da árvore, gitignored), com política de 20 GB e 30 dias. Passado por `vmlinux-o-ld-args-y` com espaços escapados no `MAKEFLAGS` (testado num sub-make).
2. **`DEBUG_INFO` desligado** (`DEBUG_INFO_NONE`). O BTF já estava desligado. Perde-se só o número de linha em `addr2line`; kallsyms continua.
3. **Enxugamento:** os blocos da tabela acima. Os símbolos com letra minúscula (`MT76x0U` etc.) precisam de `scripts/config --keep-case`: sem isso o script os converte para maiúsculas e a linha não faz nada.
4. Comentários desatualizados sobre o BTF ("LIGADO, NÃO DESABILITAR") corrigidos.

**Validação do config, sem build:** as linhas novas foram aplicadas a uma cópia do `.config` e passaram pelo `olddefconfig` do kernel. Resultado: 96 símbolos saem (1688 → 1593 `=y`). **Ficam** amdgpu/CIK, MT76X8 + cfg80211/mac80211, BT_MTKSDIO, UFS, ext4, vfat, dm-crypt, KVM_AMD, vhost/vfio (lado host; qemu/virt-manager estão no rootfs), HDA + codec HDMI ATI, AHCI, CIFS (`=m`).

**Observar no teste:** o `SND_HDA_COMPONENT` sai junto com o DC. É o elo GPU↔HDA para avisos de áudio HDMI; o caminho legado não deveria depender dele, mas vale testar o áudio HDMI.

## Fluxo (sem mudança de script)
- **Mudou só código built-in → não rodar `01-build-image`.** Reaproveitar o initramfs e o bootargs de uma tag que funciona, por `cp` explícito (AGENTS.md). Economiza ~45 min.
- Para mudar módulo `=m` ou o rootfs, aí sim `01-build-image --incremental`.

## Não aplicado (decisão do usuário, 2026-11-16)
- `--thinlto-jobs` 2 → 4 (risco de OOM no `LD vmlinux.o`, já visto em 2026-07-21).
- `pacman --needed` no `01-build-image --incremental`.
- Perfil "dev" sem LTO.

## Resultado
### Build `20261116-s5-dma` (primeiro com o config novo; 17:13 → 17:43)

| Fase | Antes | Agora |
|---|---|---|
| Compilação | ~1 min (ccache cheio) | **25,5 min** (ccache frio: 144 acertos / 2009 falhas, porque o config mudou) |
| **`LD vmlinux.o` (ThinLTO)** | **~35 min** | **2,5 min** (sem DWARF e com ~800 objetos a menos; o cache ainda estava vazio) |
| bzImage + módulos + snapshot | — | ~1,5 min |
| **Total** | ~41 min | **~29,5 min** |

- bzImage: **10,6 MiB** (antes: 13,7 MiB `btf-disabled-s5`, 16,1 MiB `keep-mode-aplicado`).
- Cache do ThinLTO populado: 68 MB, 3066 entradas.

**Lição sobre o ccache:** ele só acerta com o **mesmo config**. Toda mudança de config altera o `autoconf.h`, que todo arquivo inclui, e custa uma recompilação completa (~25 min a `-j8`). Só em 2026-11-16 o config mudou três vezes (BTF ligado → BTF desligado → enxugamento). **Congelar o config** e juntar mudanças de config numa rodada só.

_Pendente: medir o próximo build com o config igual (esperado: ~1 min de compilação + link com cache)._
