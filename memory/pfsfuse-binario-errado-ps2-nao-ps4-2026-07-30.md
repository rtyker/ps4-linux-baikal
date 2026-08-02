---
name: pfsfuse-binario-errado-ps2-nao-ps4
description: Binário /usr/local/bin/pfsfuse (deploy manual 2026-07-30) era a ferramenta PFS do PS2, não do PS4 — renomeado para .bak
metadata:
  type: project
---

Ao tentar montar `/dev/sda27` (partição Games/user, 897.6 GiB) via
`PLANO_MONTAGEM_NATIVA_HD_INTERNO_SDA.md`, existia em `/usr/local/bin/pfsfuse`
(root, datado de 2026-07-30, 125944 bytes) um binário que **não é** a ferramenta
PS4 PFS documentada no projeto. Ao rodar contra `/dev/sda27` ele se identifica como:

```
hdd: PS2 APA Driver v2.5 (c) 2003 Vector
pfs Playstation Filesystem Driver v2.2
ps2fs: (c) 2003 Sjeep, Vector and Florin Sasu
```

É a ferramenta APA/PFS de **PlayStation 2** (projeto de terceiros ps2sdk/PFS
toolkit), incompatível com o formato de disco do PS4 — por isso o erro
`hdd0:__common: No such device.`.

**Why:** nome de arquivo (`pfsfuse`) e semântica (`--partition=<s> PFS partition
in APA to mount`) são muito parecidos com a ferramenta real do PS4
(`ps4_pfs_fuse`, ver `PLANO_MONTAGEM_NATIVA_NEMO_NAUTILUS_FUSE.md`), o que gera
confusão fácil. Não há referência a ele em nenhum script de build
(`distros/arch_minimal_v2/*.sh`) — foi copiado manualmente para o PS4 fora do
fluxo oficial, não vai reaparecer em rebuilds.

**How to apply:** ignorar/não usar `pfsfuse` para montar partições do PS4. Usar
sempre `ps4_pfs_fuse` (`/usr/local/bin/ps4_pfs_fuse <dispositivo> <mountpoint>`).
Renomeado no PS4 para `pfsfuse.WRONG-PS2-TOOL.bak` em 2026-07-30 (não apagado,
para inspeção posterior se necessário). Ver também
[[sda27-decriptacao-magic-incorreto-2026-07-30]] para o problema real ainda
pendente (chave/cipher do `monta_particao.sh` não decripta `sda27`
corretamente — `ps4_pfs_fuse` deu magic `0x01B9B25D` em vez do esperado
`0x1332A0B`).
