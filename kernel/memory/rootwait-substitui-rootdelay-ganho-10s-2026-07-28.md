---
name: rootwait-substitui-rootdelay-ganho-10s-2026-07-28
description: rootwait no lugar de rootdelay=10 economiza 10,5s de boot sem risco — validado ao vivo
metadata:
  type: project
---

**VALIDADO AO VIVO 2026-07-28.** Trocar `rootdelay=10` por `rootwait` nos bootargs
economiza **10,5 segundos** de boot, sem nenhum efeito colateral.

Medição isolando a fase de initramfs (entre o fim da init do kernel e o start do
systemd), que é onde o `rootdelay` atua:

| Boot | Fase initramfs | Bootarg |
|------|----------------|---------|
| tag `20260728-sata-irq-dedicada` | 79,5s → 101,2s = **21,7s** | `rootdelay=10` |
| tag `20260728-sata-demux-diag` | 84,5s → 95,7s = **11,2s** | `rootwait` |

Ganho de 10,5s, batendo exatamente com os 10s do `rootdelay` removido. E isso
**apesar** de o boot com `rootwait` carregar também console UART e instrumentação
de debug, ambos custosos — ou seja, o ganho real é ainda maior que o medido.

`dmesg | grep -ic "Waiting for root"` = **0**: o rootfs (`/dev/sdb2`, USB) foi
encontrado de imediato, sem nenhuma espera.

**Why:** `rootdelay=N` é uma espera cega — dorme os N segundos completos mesmo que
o dispositivo já esteja pronto em 1s. `rootwait` espera o dispositivo *aparecer* e
segue na hora. Como o rootfs deste projeto fica no USB (`sdb`), havia receio de a
enumeração demorar; a medição mostra que não demora.

**How to apply:** usar `rootwait` em todo bootargs novo; nunca voltar a
`rootdelay=N`. Modelo pronto:
`distros/arch_minimal_v2/boot_referencia/bootargs-7.0-20260728-sata-diag.txt`.
Único risco a conhecer: `rootwait` espera **indefinidamente** se o dispositivo
nunca aparecer, enquanto `rootdelay` seguiria e falharia. Na prática é mais seguro
(não há corrida), mas se o boot parar em "Waiting for root device" o problema é o
USB, não o bootarg. Relacionado: [[root-sempre-label-psxitarch]].
