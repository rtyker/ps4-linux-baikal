# Otimização de tempo de boot 2026-07-24: `libata.force` para o HD interno (ata1/sda)

## Problema

O usuário pediu para investigar como reduzir o tempo da fase de initramfs (mkinitcpio) antes do
`switch_root` para o rootfs real (`LABEL=psxitarch`, `sdb`, SSD USB).

Cruzando com um dmesg de boot real já coletado nesta sessão (ver conversa 2026-07-24, screenshot
do erro de initramfs zstd), o gargalo dominante identificado é o **HD interno do PS4**
(`sda`/`ata1`, `TOSHIBA MQ04ABF1`, controlador SATA/AHCI **builtin** no kernel —
`CONFIG_SATA_AHCI=y`, não é módulo, não pode ser evitado via initramfs/blacklist). Ele entra numa
tempestade de timeouts de comando NCQ (`READ FPDMA QUEUED`) a partir de t≈31.8s, faz 3 rounds de
"hard resetting link" com timeouts crescentes (5000ms → 10000ms → 30000ms) tentando renegociar
velocidade (3.0Gbps → 1.5Gbps), e só desiste (`ata1: disable device`) em t≈62s. O rootfs real só
é montado depois disso (mensagens de root em t≈79s no dmesg observado).

Hipótese técnica: o hook `udev` do mkinitcpio chama `udevadm settle` antes do hook
`block`/`filesystems`, e esse settle fica preso esperando a fila de eventos do udev drenar — o
que só acontece quando o kernel desiste do `ata1`. Ou seja, o HD interno nunca impediu o boot
(por isso foi classificado como "não bloqueador" em
[kernel-7.0-sata-desconexao-boot](kernel-7.0-sata-desconexao-boot.md)), mas continua consumindo
~30-45s de tempo real a cada ciclo de boot.

Esse mesmo sintoma já tinha diagnóstico técnico mais fundo em
`consolidado/INTERNAL_SATA_FIX.md` ("HIPM+DIPM mata o drive") e está listado como pendência de
prioridade média em `consolidado/BACKLOG.md` (SATA interno) — nunca foi mitigado nem via
patch de kernel nem via cmdline.

## Correção aplicada (sem rebuild de kernel)

Adicionado ao cmdline em `distros/arch_minimal_v2/01-build-image-7.0.sh` (heredoc
`bootargs-7.0.txt`):

```
libata.force=1.00:3.0Gbps,noncq
```

- `3.0Gbps`: fixa a velocidade do link SATA do `ata1.00`, evitando a renegociação 3.0→1.5Gbps
  que hoje consome 2 dos 3 rounds de hard-reset.
- `noncq`: desliga NCQ nesse dispositivo — o comando que trava (`READ FPDMA QUEUED`) é
  especificamente NCQ; sem NCQ o driver tende a falhar mais rápido/previsível em vez de
  re-tentar em fila.
- Mudança puramente aditiva no cmdline — não mexe em `rootdelay=10` (que
  [root-sempre-label-psxitarch](root-sempre-label-psxitarch.md) marca como obrigatório), não
  precisa de rebuild de kernel, não afeta `sdb` (nosso rootfs) nem vídeo/GPU/eth0/WiFi já
  validados.

**Não elimina o problema na raiz** — o drive pode continuar falhando o `IDENTIFY`, só que sem o
ciclo de renegociação de velocidade. Precisa ser validado ao vivo comparando os timestamps do
bloco `ata1`/`ata1.00` contra o baseline (storm t≈31.8-62s, root em t≈79s).

## Correção de causa raiz (NÃO aplicada — requer rebuild + autorização explícita)

Fix mais completo, nunca aplicado: quirk `ATA_QUIRK_NOLPM` para `"TOSHIBA MQ04ABF100"` em
`drivers/ata/libata-core.c` (mecanismo que já existe no código para outros modelos, ex. `ADATA
SU680`), atacando o HIPM/DIPM que mata o drive. Requer editar código do kernel + rebuild completo
(Regra Crítica #6 do projeto — proibido rodar `make`/build sem autorização explícita) + um power
cycle inteiro só para esse teste. Só vale a pena perseguir se `libata.force` sozinho não for
suficiente.
