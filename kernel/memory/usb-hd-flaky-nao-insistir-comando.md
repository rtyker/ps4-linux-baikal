---
name: usb-hd-flaky-nao-insistir-comando
description: "Quando o HD USB do PS4 (sda) começa a dar timeout de I/O (180s, 'medium may have changed'), não ficar retentando comandos — é o cabo/porta, o usuário resolve fisicamente"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: dfd95c6f-d4a4-4437-929d-a734e0aa051c
---

Quando o SSD Kingston USB (boot disk do PS4, aparece como `sda` no PC de build — ver [[baikal-gbe-toque-trava-desliga-ps4]] e lição #27 de `LICOES_APRENDIDAS.md`) começa a dar erro de I/O (`timing out command, waited 180s`, `Sense Key: Unit Attention - Not ready to ready change, medium may have changed`, erros de ext4 no `sda2`), **não insistir tentando rodar o mesmo comando de novo ou outros comandos de leitura/diagnóstico no disco**.

**Por que:** É a ponte USB-SATA (JMicron) ou o cabo que está com mau contato — não é o SSD nem algo que se resolve por software/retry. Ficar tentando comandos só mantém o kernel tentando I/O que vai travar de novo (180s por tentativa) sem progredir, e cada escrita nesse estado arrisca corromper a partição `psxitarch`.

**Como aplicar:** Assim que aparecer esse padrão de erro (checar com `sudo dmesg | tail`), parar imediatamente de tocar no disco e avisar o usuário. O usuário mesmo desconecta e reconecta fisicamente o cabo/HD — ele confirmou que isso resolve. Só voltar a rodar comandos no disco depois que o usuário confirmar que reconectou.
