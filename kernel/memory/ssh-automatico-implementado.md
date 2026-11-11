---
name: ssh-automatico-implementado
description: SSH automático no final do boot (implementado 2026-07-22)
metadata:
  type: project
---

# SSH Automático — Implementação Completa

**Data:** 2026-07-22  
**Status:** ✅ Implementado (pronto para testar no próximo build)

## O que foi feito

Automatizou o início do SSH no final do boot do sistema, sem necessidade de intervenção manual via telnet.

### Arquivos criados/modificados

1. **`ssh-startup.sh`** — Script de inicialização que:
   - Aguarda `/dev/sdb2` ficar disponível
   - Monta o rootfs em `/mnt/ps4-rootfs`
   - Prepara pseudo-filesystems (proc, sys, dev, run)
   - Inicia `sshd` dentro do chroot

2. **`ssh-auto-startup.service`** — Serviço systemd que:
   - Executa após `network-online.target`
   - Roda o script `ssh-startup.sh` uma única vez no boot
   - Registra logs via journalctl

3. **`01-build-image-7.0.sh`** — Modificado para:
   - Copiar `ssh-startup.sh` para `/usr/local/bin/ssh-startup.sh` no rootfs
   - Copiar `ssh-auto-startup.service` para `/etc/systemd/system/`
   - Ativar o serviço automaticamente via symlink em `multi-user.target.wants/`

## Como funciona

No boot do sistema:
1. systemd carrega `ssh-auto-startup.service` após rede estar pronta
2. Script monta rootfs real e faz chroot
3. sshd inicia dentro do chroot na porta 22
4. Usuários podem conectar com `ssh root@<ps4-ip>` (senha: `ps4`)

## Próximas etapas

1. **Build novo:** Executar `sudo ./01-build-image-7.0.sh` para incorporar SSH automático
2. **Teste ao vivo:** Fazer boot com novo initramfs e confirmar que `ssh root@<ps4-ip>` funciona logo após boot
3. **Verificação:** `journalctl -u ssh-auto-startup.service` deve mostrar sucesso

## Notas

- Diferença da versão anterior: antes era necessário acessar via telnet (porta 23) e rodar manualmente os mounts + chroot + sshd
- Agora é automático e roda ao final do boot (After=network-online.target)
- Compatível com qualquer distro/kernel que tenha rootfs em `/dev/sdb2` com SSH configurado
- SSH ainda fica acessível via chroot, não há impacto em telnet ou outros serviços do initramfs
