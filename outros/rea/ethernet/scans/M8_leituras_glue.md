# M8 — Leitura dos registradores hold/pulse da glue (BAR2+0x180000) via /dev/mem

Console: 192.168.6.128 (IP fixo por reserva DHCP), tag `20260720-sky2len-fix`, telnet root.
Método: `dd if=/dev/mem bs=4 count=1 skip=$((ADDR/4)) | od -An -tx4`
**Um acesso por vez**, com verificação de vida (ping) após cada um, para não perder o dado
caso um acesso trave o console.

| # | Endereço | Registrador | Valor | Console após |
|---|---|---|---|---|
| 1 | `0xc898002c` | SATA hold | `00000000` | OK |
| 2 | `0xc898006c` | SATA pulse | `00000000` | OK |
| 3 | `0xc8980030` | xHCI hold | `00000000` | OK |
| 4 | `0xc8980070` | xHCI pulse | `00000000` | OK |
| 5 | `0xc8980020` | **GBE hold** | `00000000` | OK — leitura NÃO trava |
| 6 | `0xc8980074` | **GBE pulse** | `00000000` | OK — leitura NÃO trava |
| 7 | `0xc2000118` | B2_CHIP_ID/MAC_CFG (BAR0 real) | `00 00 00 00` | OK |

**Console permaneceu vivo nas 7 leituras.** Houve dois eventos `DEAUTH` do WiFi durante a
sessão, observados na tela nos **loops 19 e 44** (`wlanIdx[255]`), mas o contador
`DEBUG LOOP` continuou subindo e o ping respondeu — são eventos de rede, não travamento.

> Nota: os DEAUTH não coincidem com nenhuma das leituras (que foram esparsas e sempre
> seguidas de ping OK). Parecem instabilidade do WiFi independente do teste — vale observar
> se reaparecem em sessões sem acesso a MMIO, para descartar de vez qualquer relação.

## Conclusões

### 1. ❌ Hipótese `hold=0x20` / `pulse=0x74` REFUTADA
A GBE lê **exatamente os mesmos valores** (`00000000`) que SATA e xHCI, que estão
funcionando. **A GBE não está presa em reset por esses registradores** — o `hold` já está
solto — e ainda assim o `B2_CHIP_ID` lê `00`. Escrever ali não vai resolver: já está no
estado que se queria alcançar.

Isso não invalida o mapeamento de blocos extraído de `fcn.ffffffffdc6df850` (os offsets de
USB/SATA/xHCI batem com o código de produção); apenas mostra que **o bloco `0x2000` estar
"solto" não é condição suficiente** para a GBE responder — ou que o bloco `0x2000` não é a
GBE, e a associação feita pela vizinhança da chamada a `dc59fe10` estava errada.

### 2. ✅ As leituras NÃO travam o console — revisa a análise do M7
Todas as 7 leituras rodaram de userspace sem travar. Portanto o travamento do M7b
(`gbe_release=0`, só leituras) **não foi causado pelas leituras em si**. A causa está no
contexto: fazê-las de dentro do `sky2_probe`, no caminho de boot. Hipóteses remanescentes
para o M7 — nenhuma verificada:
- o `pci_get_slot()`/`pci_get_drvdata()` do glue dentro do probe do `sky2` (ordem de
  inicialização entre `baikal_pcie` e `sky2`);
- `dev_info()` com 6 argumentos formatados muito cedo no boot;
- o próprio ponto de inserção no `sky2_probe`, antes de `sky2_init()`.

### 3. ⚠️ CORREÇÃO: o BAR0 da GBE é `0xc2000000`, não `0xc900c000`
Confirmado pela fonte autoritativa, o sysfs do próprio console:
```
$ head -1 /sys/bus/pci/devices/0000:00:14.1/resource
0x00000000c2000000 0x00000000c2000fff 0x0000000000140204
```
Ou seja, BAR0 = `0xc2000000`–`0xc2000fff` (4 KB, consistente com o fix M5 do `ioremap`).
**O endereço `0xc2000118` usado nos testes antigos estava CERTO.** A anotação de
2026-07-21 que dizia que `0xc2000118` era "do Southbridge 1 (Gladius/Aeolia)" e que o
correto seria `0xc900c118` **está errada** — e os testes feitos com base nela leram um
endereço que não é o chip_id da GBE. Reavaliar qualquer conclusão daquela rodada.
