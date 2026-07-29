---
name: uart-solda-validada-eletricamente
description: Solda TTL UART VALIDADA E FUNCIONAL — PS4 transmite stream contínuo de 0x20 (espaços), assinatura de console CEX/retail sem patch de NOR; GND ausente era a causa dos zeros
metadata:
  type: project
---

# Solda UART TTL — VALIDADA E FUNCIONAL (2026-07-27)

## Resultado final

✅ **A solda do usuário funciona.** O PS4 transmite um **stream contínuo de bytes `0x20` (espaço ASCII)** pela UART, capturado com sucesso em `/dev/ttyUSB0` @ **115200 8N1**.

Provas capturadas:
- Captura 1 (durante boot Orbis): **68.685 bytes**, 99,998% `0x20` (1 único `0x00` de transiente).
- Captura 2 (reprodução, PS4 já ligado): **15.321 bytes**, **100,000% `0x20`**, 1 valor distinto, zero lixo. Fluxo contínuo ~11 KB/s (compatível com 115200 saturado).

## Interpretação

O stream puro de espaços é a **assinatura documentada de console CEX/retail**: o firmware transmite o log de debug pela UART mas **substitui todo o texto por espaços** até que se aplique o patch de habilitação no NOR flash. Ver pesquisa: threads Badcaps / repair.wiki / psxhax (flag no offset `0x1C931F`, `FF`→`01`).

Isso significa: **hardware, solda, adaptador e parâmetros seriais estão todos corretos.** Só o conteúdo é censurado pelo firmware.

## Causas dos falsos negativos anteriores (2 bugs reais, ambos meus, não do usuário)

1. **GND não conectado** — a causa principal. Sem terra comum o receptor não tem referência para decidir nível alto/baixo; nada é decodificado. Ao conectar o GND, os dados fluíram imediatamente.
2. **Termios sendo resetado** — `stty -F` seguido de `cat` não é confiável aqui: o adaptador re-enumerava no USB (visto no `dmesg`: vários `converter now disconnected`/`now attached`) e o termios voltava ao padrão **9600 baud + modo canônico (`icanon`)**. Em modo canônico o `cat` só entrega dados após um `\n` — como o stream de espaços não tem newline, **tudo ficava no buffer e era descartado** quando o `timeout` matava o processo, resultando em arquivo de 0 bytes mesmo com dados reais chegando.
   - **Solução:** usar **pyserial**, que abre e configura a porta atomicamente. Script pronto: `uart_capture.py` (com reabertura automática se o adaptador re-enumerar).

## Armadilha diagnóstica importante — LED do adaptador NÃO é indicador de dados

O usuário observou que o **LED azul piscava mesmo com o GND desconectado, só com o TX ligado**. Isso prova que o LED **não** indica recepção válida: uma entrada de RX flutuante (sem referência de terra) capta ruído/acoplamento capacitivo e oscila, e o LED (ligado direto na linha) segue essa oscilação. **Nunca usar o LED como prova de que há dados chegando.**

## Hardware usado

- Adaptador: **PL2303** `067b:2303`, `bcdDevice 3.00` (geração HXA/TA). Funcionou normalmente — a suspeita de clone defeituoso foi infundada.
- Parâmetros: **115200 8N1**, sem controle de fluxo. Só **TX (PS4) → RX (adaptador) + GND** são necessários para leitura.

## Próximo passo (se quiser log legível, tarefa NOVA e separada)

Para ver texto real em vez de espaços seria necessário patchear a flag de debug no NOR flash (offset `0x1C931F`, `FF`→`01`) e regravar — **operação de risco real (pode brickar o console)**. Não iniciar sem pedido explícito e planejamento, conforme Regra de Ouro do `CLAUDE.md`.

---

## 🎉 ATUALIZAÇÃO 2026-07-27 (pós-deploy tag `20260727-uart-debug`)

**Kernel Linux bootando via UART confirmado!** Com bootargs:
```
earlycon=uart8250,mmio32,0xC890E000 console=ttyS0,115200n8 console=tty0
```

Captura na UART mostrou:
- `kernel_init()`
- `kexec_init() successful`
- Extração de firmware amdgpu (gladius_pfp/me/ce/mec/rlc/sdma)
- Trap 9 (general protection fault) em driver gráfico — **UART funcionando**, o crash é pós-early-boot

A UART Baikal (MMIO `0xC890E000`) é o caminho correto. O `console=ttyS0` sozinho falhou antes por apontar à porta 8250 legada x86 inexistente no PS4.
