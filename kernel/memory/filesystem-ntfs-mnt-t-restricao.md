---
name: filesystem-ntfs-mnt-t-restricao
description: /mnt/t (onde fica o projeto linux_in_ps4) é NTFS - não usar para builds/git/source de kernel
metadata: 
  node_type: memory
  type: project
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

`/mnt/t` (pasta raiz do projeto, `/mnt/t/downloads/PS4/linux_in_ps4`) é uma partição **NTFS** (`/dev/nvme1n1p6`, label DADOS), montada via ntfs-3g.

**Por isso o source do kernel 7.0 fica em `/mnt/hdauxiliar/temp/kernel_build_7.0` (ext4) e só existe um symlink** (`kernels/ps4-baikal-7.0.8-kernel -> /mnt/hdauxiliar/temp/kernel_build_7.0`) dentro da pasta do projeto — não dá pra manter o source real ali.

**Por quê:** NTFS via ntfs-3g não preserva permissões de execução, symlinks nem outros atributos POSIX que o `.git` e o build system do kernel exigem. Já documentado como Lição Crítica #4 no README.md do projeto: "Não extrair tarball em NTFS — Corrompe permissões Linux. Use ext4."

**Como aplicar:** qualquer coisa que precise de build (kernel source, chroot de rootfs, `arch-chroot`, `pacstrap`) deve rodar em `/mnt/hdauxiliar` (ext4) ou outro filesystem Linux nativo, nunca direto em `/mnt/t`. Artefatos finais (tarballs `.tar`, `bzImage`, `.cpio.gz`) podem ficar em `/mnt/t` normalmente, pois são arquivos binários simples sem depender de symlinks/permissões especiais.
