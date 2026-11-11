# PS4 RTYKER - SATA Interno Instavel (Kernel 7.0.8 Strawberry)

## Hardware

- **Disco:** TOSHIBA MQ04ABF100 (JU0G0A)
- **Tipo:** Drive-managed SMR, 1TB, 4K physical blocks
- **Features:** HIPM, DIPM, LBA48, NCQ depth 32, UDMA/100
- **Controller:** xhci_aeolia `0000:00:14.7` [104d:90de] — Baikal B1 function 7
- **AHCI:** v1.300, 32 command slots, 6 Gbps, ATA mode
- **SATA PHY:** Baikal EFUSE 0x24:0x0e:0x0e, Trace length 4

## Sequencia do Colapso

```
0.63s  xhci_aeolia: Baikal SATA PHY init → AHCI 6Gbps
1.10s  ata1: SATA link up 3.0 Gbps (SStatus 123 SControl 300)
1.16s  ata1.00: ATA-10 TOSHIBA MQ04ABF100, HIPM DIPM, NCQ 32
1.19s  ata1.00: configured for UDMA/100 — OK
       --- ~30s de operacao normal ---
31.8s  ata1.00: exception — READ FPDMA QUEUED tag 22 TIMEOUT (Emask 0x4)
32.3s  ata1: hard resetting link → link up 3.0 Gbps
37.5s  ata1.00: IDENTIFY timeout 5000ms → revalidation failed (errno=-5)
37.9s  ata1: hard resetting link → link up 3.0 Gbps
48.0s  ata1.00: IDENTIFY timeout 10000ms → revalidation failed
48.0s  ata1: limiting SATA link speed to 1.5 Gbps
48.4s  ata1: link up 1.5 Gbps
78.9s  ata1.00: IDENTIFY timeout 30000ms → disable device
79.4s  sda: unable to read partition table — MORTO
```

## Causa Provavel

**HIPM + DIPM power management.** O drive Toshiba entra em estado de baixo consumo ~30s apos deteccao. O controlador SATA Baikal (function 7) nao consegue acordar o drive corretamente. O timeout escala 5s → 10s → 30s → disable.

O link SATA fisico nunca cai — o drive so para de responder a comandos.

## Notas Importantes

- O disco USB (Kingston SV300S37A120G via JMicron bridge) funciona normalmente
- O Blu-ray SONY PS-SYSTEM na function 2 (ahci, 3Gbps) funciona normalmente
- O kernel 7.0 sobrevive ao colapso SATA — o rootfs esta no USB (sdb), nao no SATA (sda)
- O SDIO (WiFi MTK) esta na function 3, pode interferir com power states do SATA na function 7

## ATUALIZACAO (2026-07-17): fixes revisados contra o source real

As opcoes 1, 3 e 4 abaixo (na forma como estavam escritas originalmente) usavam
nomes de parametro/simbolo que **nao existem** no kernel deste projeto
(`rmuxnet/linux`, branch `baikal/7.0.8-Stable`, arvore em
`/mnt/hdauxiliar/temp/kernel_build_7.0`) — confirmado via `grep` direto no
source. Kernel ignora parametros de boot desconhecidos silenciosamente, entao
testar a Opcao 1/4 originais pareceria "nao resolveu" sem na verdade ter
mudado nada. A Opcao 3 original nem compilaria (`ATA_HORKAGE_*` foi renomeado
para `enum ata_quirks` / `ATA_QUIRK_*` faz tempo upstream, e esse kernel ja
usa a nomenclatura nova). Correcoes abaixo.

## Fix Opcao 1: Boot Params (mais facil, sem recompilar) — **INVALIDO nesta kernel**

~~`libata.fpm=0 libata.nohpa=1`~~ — nenhum dos dois existe como
`module_param` em `drivers/ata/libata-core.c` desta arvore (nem em
`libata-sata.c`). O unico parametro real relacionado a HPA e
`libata.ignore_hpa` (comportamento e o oposto do que o nome "nohpa" sugere).
Nao ha parametro de boot equivalente a "desabilitar HIPM" nesta kernel — LPM
e controlado por sysfs por-dispositivo (`/sys/class/scsi_host/hostX/link_power_management_policy`)
ou pela tabela de quirks (ver Opcao 3 corrigida).

## Fix Opcao 2: Forcar Velocidade — **valido, sintaxe confirmada**

```
libata.force=3.0Gbps
```

Confirmado em `Documentation/admin-guide/kernel-parameters.txt` desta arvore.
Evita o downshift para 1.5 Gbps que o kernel faz apos timeouts. Porem nao
resolve a causa raiz (power management).

## Fix Opcao 3: Quirk no Kernel (requer rebuild) — **corrigido**

Em `drivers/ata/libata-core.c`, o kernel deste projeto usa `enum ata_quirks`
(nao mais `ATA_HORKAGE_*`, que foi removido/renomeado upstream). A tabela
real de quirks por modelo e `__ata_dev_quirks[]`
(`{ "MODELO", "FIRMWARE_OU_NULL", ATA_QUIRK_FLAG }`), com dezenas de
entradas ja existentes como exemplo. Adicionar:

```c
/* Toshiba MQ04ABF100 SMR - desabilita LPM (HIPM/DIPM) no PS4 Baikal,
 * ver INTERNAL_SATA_FIX.md */
{ "TOSHIBA MQ04ABF100", NULL, ATA_QUIRK_NOLPM },
```

`ATA_QUIRK_NOLPM` ("Do not use LPM", confirmado em `include/linux/libata.h`)
e o equivalente direto do antigo `ATA_HORKAGE_NOLPM`. Nao existe quirk
`NO_HIBERNATE` separado nesta kernel (a lista completa de `enum ata_quirks`
nao tem essa flag) — `NOLPM` sozinho ja cobre o caso de HIPM/DIPM.

## Fix Opcao 4: Aumentar Timeouts (paliativo) — **INVALIDO nesta kernel**

~~`libata.eh_timeout=60 libata.acpi_timeout=30`~~ — nenhum dos dois existe
como `module_param` em `drivers/ata/` desta arvore.

## Recomendacao

**Testar Fix 2 primeiro** (`libata.force=3.0Gbps`, sem recompilar) — rapido
de testar, so nao ataca a causa raiz.

Se nao resolver (ou se quiser ir direto na causa raiz), aplicar o quirk
corrigido da Opcao 3 (`ATA_QUIRK_NOLPM`) — requer rebuild do kernel, mas e o
fix mais direto para o padrao HIPM/DIPM que o diagnostico deste documento
aponta.

**Nao e bloqueador no momento** — o rootfs mora no HD USB (`sdb`), nao no
SATA interno (`sda`); retomar isso so quando o disco interno for necessario
(ex: usar como storage).

## Referencias

- `PS4_DMESG_LATEST.txt` — log completo do boot 7.0.8 Strawberry com colapso SATA
- `BAIKAL_STATUS.md` — estado geral do projeto
- `HARDWARE.md` — PCI IDs e mapeamento Baikal B1
