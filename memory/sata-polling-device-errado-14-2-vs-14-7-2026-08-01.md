---
name: sata-polling-device-errado-14-2-vs-14-7-2026-08-01
description: Causa raiz real de por que o patch de SATA polling não resolvia o ata1 mesmo aplicado e rodando — o timer nascia no PCI function .2 (AHCI genérico), mas ata1 pertence à function .7 (xhci_aeolia, composto). Corrigido, ainda não testado em hardware.
metadata:
  type: project
---

## Contexto

Depois de reconstruir o `ahci-baikal-polling-fallback.patch` (perdido na regressão de 2026-08-01,
ver [[regressao-sata-2026-08-01-diagnostico-e-solucao]]) e validar exaustivamente em compilação
isolada, um boot ao vivo (18:08, kernel compilado 15:24:38, já incluindo os 4 commits de
consolidação idempotente do usuário + minha correção do RTC) mostrou a **mesma assinatura de
falha original**: `ata1.00: exception` → `qc timeout` escalando 5s/10s/30s → `disable device`.

O usuário inicialmente interpretou isso como "perdi o patch de novo". **Não era isso.**

## Diagnóstico real (evidência ao vivo via SSH)

`dmesg` confirmou que o patch **estava presente e rodando**:
```
[    7.534516] ahci 0000:00:14.2: PS4 Baikal: AHCI polling timer started (1ms)
```

Mas o `ata1` continuou falhando. `lspci` revelou por quê:
```
00:14.2 System peripheral: Sony Corporation Baikal SATA AHCI Controller — driver: ahci
00:14.7 System peripheral: Sony Corporation Baikal USB 3.0 xHCI Host Controller — driver: xhci_aeolia
```

E o decisivo:
```
$ readlink -f /sys/class/scsi_host/host0
/sys/devices/pci0000:00/0000:00:14.7/ata1/host0/scsi_host/host0
```

**`ata1` é filho de `0000:00:14.7` (xhci_aeolia), não de `0000:00:14.2`.** O timer de polling
nasceu no dispositivo errado — um controlador AHCI genérico separado (provavelmente o Blu-ray,
"O Blu-ray SONY PS-SYSTEM na function 2 (ahci, 3Gbps) funciona normalmente" já citado em
`memory/MEMORY.md` desde 2026-07-29) — e nunca tocou o device real que hospeda o HD interno.

## Por que isso passou despercebido

1. O `ahci-baikal-polling-fallback.patch` original (o de 30/07, nunca preservado) provavelmente
   JÁ sabia disso — o marco `marco-sata-interno-funcional-2026-07-30.md` diz explicitamente:
   *"drivers/usb/host/xhci-aeolia.c: liga o mesmo polling timer para o dispositivo composto
   Baikal (func 7, xHCI+AHCI), já que é esse caminho — não o `ahci_init_one()` genérico — que
   efetivamente recebe o `ata1` do PS4."* Essa frase estava lá, documentada, mas na reconstrução
   apressada de 2026-08-01 eu só recriei a metade do mecanismo (o timer em si, em
   `drivers/ata/{ahci.c,ahci.h,libahci.c}`) e nunca a parte que o conecta ao `xhci-aeolia.c`.
2. **`consolidado/ps4_hardware_memory.db`, tabela `bar_regions`, id 7, tinha uma entrada ERRADA**:
   `0000:00:14.2` estava documentado como *"Controlador AHCI SATA do disco interno"* — reforçando
   a suposição errada de que o `ahci_init_one()` genérico bastava. Corrigido nesta sessão (ver
   abaixo).
3. Todos os testes de compilação isolada + `git apply --check` passaram sem erro, porque o código
   estava sintaticamente correto — só não fazia a coisa certa fisicamente. Isso é uma lacuna de
   verificação: compilar limpo prova que o C é válido, não prova que resolve o hardware certo.

## Correção aplicada

`drivers/usb/host/xhci-aeolia.c` tem sua **própria** função `ahci_init_one()` local (linha ~216),
usada quando `xhci_aeolia_is_baikal(pdev)` é verdadeiro — essa é a função real chamada para a
function `.7`. Ela já usa `struct ahci_host_priv` (mesma struct que os helpers de polling já
manipulam), então bastou reaproveitar as funções já exportadas de `libahci.c`
(`ahci_baikal_start_poll_timer()`/`ahci_baikal_stop_poll_timer()`, criadas na correção anterior
desta mesma sessão) e chamá-las:
- logo após `ahci_host_activate()` ter sucesso, dentro de `ahci_init_one()` (guardado por
  `if (baikal)`)
- em `ahci_remove_one()`, antes do `iounmap(hpriv->mmio)`

`ahci-baikal-polling-fallback.patch` atualizado para conter os 4 arquivos: `drivers/ata/ahci.h`,
`drivers/ata/ahci.c`, `drivers/ata/libahci.c` (inalterados desde a correção anterior) +
`drivers/usb/host/xhci-aeolia.c` (novo).

## Validação feita (rigor de sempre)

- `git apply --check` a partir de árvore pristina (`git reset --hard origin/branch`): OK
- Compilação isolada de `ahci.o`, `libahci.o`, `xhci-aeolia.o`: sem erro
- `nm`: `ahci_baikal_start_poll_timer` é `T` (definido) em `libahci.o`, `U` (referenciado) em
  **ambos** `ahci.o` (function .2) e `xhci-aeolia.o` (function .7) — os dois call sites resolvem
  certo
- Fluxo completo (SATA + MTS + RTC, 4 patches) testado junto do zero: todos aplicam limpos,
  todos os `.o` afetados compilam sem erro

## ⚠️ Ainda NÃO validado em hardware

Esta correção nunca foi testada num boot real — o achado da causa raiz (device errado) e a
correção aconteceram na mesma sessão, sem tempo para novo build+deploy+power-cycle. **Próximo
passo:** build oficial completo com o patch v2, deploy, boot, e confirmar via `dmesg` que a
mensagem agora é `"PS4 Baikal: AHCI polling timer started on xhci-aeolia (func .7, 1ms)"` (não
mais em `0000:00:14.2`), seguido de `ata1.00: configured for UDMA/100` sem nenhuma exceção pelos
próximos 90+ segundos (o ponto onde a cascata de falha historicamente começava).

## Correção no banco de dados

`consolidado/ps4_hardware_memory.db`, tabela `bar_regions`:
- id 7 (`0000:00:14.2`): descrição corrigida, deixa de dizer "disco interno"
- id 8 (nova, `0000:00:14.7`): registra o device real do `ata1`, com a evidência ao vivo

`test_history` id 78 registra este ciclo completo (teste do device errado → refutado → causa raiz
encontrada → correção aplicada, pendente de validação em hardware).

## Lição

Consultar o SQLite antes de assumir onde um dispositivo está mapeado — mas também **desconfiar de
entradas antigas do próprio banco** quando a evidência ao vivo contradiz (aqui, `bar_regions` id 7
estava errado desde antes desta sessão, e ninguém tinha cruzado com `/sys/class/scsi_host` para
confirmar). "Compila limpo" e "aplica sem conflito" provam que o patch é sintaticamente válido,
não que resolve o problema físico certo — só o teste em hardware real prova isso.
