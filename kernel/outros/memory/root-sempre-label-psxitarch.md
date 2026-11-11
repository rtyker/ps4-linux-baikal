---
name: root-sempre-label-psxitarch
description: "REGRA IMPERATIVA: o rootfs do PS4 sempre monta por root=LABEL=psxitarch, NUNCA por /dev/sdaX — a enumeração de disco no PS4 não é confiável"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

**REGRA IMPERATIVA do projeto** (documentada em `distros/arch_minimal_v2/LICOES_APRENDIDAS.md` lição #7): a partição raiz SEMPRE é montada por `root=LABEL=psxitarch`, nunca por caminho de device (`/dev/sda2`, `/dev/sdb2`). A partição root SEMPRE é formatada com `mkfs.ext4 -L psxitarch`.

**Por quê:** a ordem de enumeração de disco dentro do PS4 NÃO é a mesma que no PC. No PC de gravação, o HD de boot é `/dev/sda`. Dentro do PS4:
- `/dev/sda` = HDD INTERNO do PS4 (TOSHIBA, ~1TB, na SATA nativa Baikal `ata1`) — não usamos, e ele frequentemente falha/`disable device` durante o boot (irrelevante para nós).
- `/dev/sdb` = NOSSO HD de boot, conectado via adaptador USB-SATA JMicron (vid 152d pid 2329). É onde está o rootfs `psxitarch` (sdb2) e a partição BOOT FAT32 (sdb1).

Portanto `root=/dev/sda2` no cmdline aponta para o disco interno errado (vazio + com falha de SATA), e o boot "morre" sem nunca montar o rootfs real. `root=LABEL=psxitarch` resolve via udev/by-label e acha o device correto independente de ser sda/sdb.

**Como aplicar:** todo bootargs de produção e de teste deve conter `root=LABEL=psxitarch rw rootdelay=10`. Conferir com `blkid` que a partição tem `LABEL="psxitarch"`. O initramfs de produção 5.4 original (`distros/initramfs.cpio.gz`) já tem `mount LABEL=psxitarch` hardcoded; o initramfs de produção 7.0 (mkinitcpio) depende do `root=` do cmdline, então o cmdline PRECISA trazer o LABEL. Ver [[kernel-7.0-status-subsistemas]]. A antiga memória sobre "SATA desconexão no boot" descreve o disco INTERNO do PS4 morrendo — é um falso problema, não afeta o nosso HD USB.
