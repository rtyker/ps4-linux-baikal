---
name: kernel-7-0-ssh-manual-debug-loop
description: "Como ligar SSH manualmente enquanto o PS4 está preso no DEBUG LOOP do initramfs de debug (wifissh); usuário quer isso automático no próximo build"
metadata:
  node_type: memory
  type: project
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

O initramfs de debug (tag `wifissh` e derivadas) só tem `telnetd` (porta 23, root sem senha) embutido — não tem binário `sshd`. Mas o rootfs real (`psxitarch`, `/dev/sdb2` do ponto de vista do PS4) já tem `sshd` completo + host keys configurados (via `01-build-image-7.0.sh`), só nunca é montado automaticamente porque o initramfs de debug fica preso no `DEBUG LOOP` por design (não faz pivot pro rootfs).

**Procedimento testado com sucesso em 2026-07-17 (tag `20260717-stmmacfix`), via telnet (porta 23):**
```sh
mkdir -p /mnt/root
mount -o ro /dev/sdb2 /mnt/root      # sdb2 = psxitarch do ponto de vista do PS4 (ver root-sempre-label-psxitarch)
mount -t proc proc /mnt/root/proc
mount --bind /dev /mnt/root/dev
mount --bind /sys /mnt/root/sys
chroot /mnt/root /usr/sbin/sshd -D -p 22 &
```
Depois disso, `ssh root@<ip-do-ps4>` (senha `ps4`) funciona normalmente — confirmado com `uname -a` retornando o kernel 7.0 rodando. Não precisou de `switch_root`/produção; o chroot reaproveita a rede já configurada pelo initramfs de debug (mesma stack de rede, não é namespace separado).

**Pedido do usuário (2026-07-17): no próximo build, deixar o SSH ligado automaticamente** no initramfs de debug (em vez de precisar rodar esse procedimento manual via telnet toda vez). Provavelmente significa: adicionar esse mesmo mount+chroot+sshd (ou embutir `sshd` direto no initramfs, como já foi feito com `wpa_supplicant`/`telnetd`) ao script/processo que gera o initramfs de debug. **Ainda não implementado** — não encontrei/localizei o script fonte do initramfs de debug nesta sessão (é diferente do `rebuild-initramfs-7.0.sh`, que é pro initramfs de produção via mkinitcpio). Achar esse script antes de tentar automatizar.
