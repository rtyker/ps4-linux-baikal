---
name: sda27-decriptacao-magic-incorreto-2026-07-30
description: monta_particao.sh decripta /dev/sda27 (Games/user) com magic PFS errado — chave/cipher provavelmente diferente da usada em sda13 (System)
metadata:
  type: project
---

`monta_particao.sh /dev/sda27` (897.6 GiB, partição Games/dados de usuário)
roda sem erro fatal (`cryptsetup create` + `mount` "sucesso" no sentido de não
travar), mas o conteúdo decriptado é lixo:

- `mount -t ufs` no mapper: `ufs: ufs_fill_super(): bad magic number`.
- `ps4_pfs_fuse /dev/mapper/ps4_sda27 /media/ps4_games`: `PFS Header Magic:
  0x01B9B25D (esperado: 0x1332A0B)`, `Version: 0xF1073D91`, `Basic Block Size:
  4231665034` — todos claramente não são valores de um header PFS válido, ou
  seja, a saída do `cryptsetup aes-xts-plain64` com `/etc/ps4_keys.bin` (mesma
  chave/cipher usados com sucesso em `sda13`, System) não é o plaintext
  correto para `sda27`.

**Why:** o BACKLOG.md marcava a feature de montagem nativa como concluída
2026-07-30 citando sucesso em `sda13` (System) **e** `sda27` (Games) juntos,
mas o teste ao vivo desta sessão mostra que só `sda13` de fato decripta
corretamente — `sda27` provavelmente usa uma derivação de chave/tweak
diferente (partição `user` vs `system` no esquema APA do PS4 costuma ter
slots de chave distintos, ou XTS tweak baseado no índice/offset da partição
que o script atual não está aplicando corretamente para `sda27`).

**How to apply:** antes de repetir o teste, revisar como
`/etc/ps4_keys.bin` foi derivado (chave EAP da NOR `nor_sflash0.bin` + tweak)
e se esse mesmo par funciona para todas as partições ou só para `system`. Não
assumir que a "montagem nativa" está 100% concluída para `sda27` até corrigir
isso — o `BACKLOG.md` precisa de correção/nota sobre este achado. Ver também
[[pfsfuse-binario-errado-ps2-nao-ps4-2026-07-30]] (achado relacionado, mas
independente, na mesma sessão de teste).
