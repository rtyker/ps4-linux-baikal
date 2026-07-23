---
name: dump-kernel-1252-culpado-e-usb-nao-kmem
description: "PROVADO 2026-07-19: os dumps parciais do kernel 12.52 morriam no write()/open() do USB, NAO em 'memória protegida'. Os 3 parciais têm ZERO chunks zerados => /dev/kmem nunca falhou. Solução = payload TCP (scene-kmem-dumper, porta 9020), sem filesystem"
metadata: 
  node_type: memory
  type: project
  originSessionId: dfd95c6f-d4a4-4437-929d-a734e0aa051c
  modified: 2026-07-19T18:25:29.121Z
---

Análise forense dos 3 dumps parciais em `consolidado/dumps_orbis/` (`kernel_partial_1252.bin` 3.9MB, `kernel_partial_1_4MB.bin` e `kernel_partial_mine_field.bin` 1.4MB — os dois últimos **byte a byte idênticos**, md5 `7063b935...`, e iguais ao `PS4/1100/kernel.bin` do pendrive):

**A teoria da "mina terrestre" (memória protegida/SAMU) do CLAUDE.md está ERRADA para este caso.** Provas:
- O payload tinha fallback que grava 16KB de zeros quando o `read()` do `/dev/kmem` falha. Varredura dos 3 arquivos: **zero chunks zerados**. O `read()` nunca falhou uma única vez.
- Os arquivos terminam no meio de uma sequência de instruções (`...483b5cc120760848`), não numa fronteira de região.
- Pontos de morte determinísticos POR BUILD, não por endereço de RAM: 0x3BC000 num build, 0x160000 (exato, reproduzido 2x) noutro. Se fosse buraco de memória, o offset seria o mesmo.

**Culpado real: o caminho de gravação em USB.** Confirmado por um segundo experimento: um payload de diagnóstico que só fazia `open("/mnt/usb0/kmem_test.txt")` + escrever "USB_OK" **não gerou arquivo nenhum** no pendrive (exFAT, label PS4DUMP). Como ele só escreve depois de abrir com sucesso, o `open()` do USB está falhando — sintoma do `rootvnode` corrompido pelo `jailbreak()` com offsets do 11.00 (CLAUDE.md, Acertos Recentes #3).

**Solução implementada 2026-07-19:** `scene-kmem-dumper/source/main.c` reescrito para **TCP na porta 9020**, sem tocar em filesystem nenhum. PS4 escuta, PC conecta e envia 16 bytes `[u64 start][u64 size]` (LE, offsets relativos à kernel_base), PS4 transmite o cru sequencial. Receptor: `ps4-linux-payloads/receive_kmem_dump.py`, **retomável** (imprime a linha de comando exata para continuar). Chunk ilegível vira 16KB de zeros para preservar alinhamento.

Regras cravadas no payload (não regredir):
- **`initNetwork()` antes de qualquer socket** (senão null deref = Travamento 5).
- **Base do kernel = `__readmsr(0xC0000082) - 0x1C0` (LSTAR).** NÃO usar `get_kernel_base()` (passa pelo kexec com offsets do 11.00) nem `jailbreak()`. Verificado no .map: `get_kernel_base` tem 0 ocorrências no binário.
- **Buffer via `mmap`, nunca na stack** (4KB na stack já matou o payload silenciosamente).
- **`send_payload_loop.py` só pode injetar na 9090.** A 9020 agora é a porta de dump do próprio payload — injetar nela corrompe a transferência.

**Alvo e por que precisamos do dump inteiro:** o `LOAD` R+E do kernel vai de 0 a **0xcfe758 (13.6 MB)**; os parciais cobrem só os primeiros 28%. `grep` por `gbe`/`Yukon`/`Marvell`/`sky2`/`bpcie` nesses 28% = **0 hits** (as strings do driver estão no .rodata, mais adiante). Tamanho padrão do dump = 0x2034af0 (~33MB, R+E + RW com folga). Objetivo final: achar a sequência de power/clock da GBE — ver [[dumps-orbis-nao-tem-power-gbe-kernel-cifrado]] e [[baikal-gbe-e-sky2-nao-stmmac]].
