# Cabo UART para PS4 (Southbridge Baikal)

> **✅ STATUS (2026-07-27): FUNCIONAL** — Solda validada eletricamente. PS4 transmite stream contínuo de `0x20` (espaços) @ 115200 8N1 (firmware retail censura debug). Com `earlycon=uart8250,mmio32,0xC890E000 console=ttyS0,115200n8` no bootargs, o **kernel Linux boot aparece na UART** (validado 2026-07-27: `kernel_init()`, `kexec_init() successful`, firmware amdgpu extraído, trap 9 posterior em driver gráfico — UART OK).

## Conector na Motherboard
- **Local**: J1 ou J2 (perto do Southbridge / APU)
- **Tipo**: JST-SH 4 pinos (1.0mm pitch) ou pads para solda direta
- **Pinout Baikal** (base `0xC890E000`):

| Pino | Função | Conexão |
|------|--------|---------|
| 1 | VCC (3.3V) | **NÃO CONECTAR** (apenas referência) |
| 2 | TX (PS4 → PC) | → RX do adaptador |
| 3 | RX (PC → PS4) | → TX do adaptador |
| 4 | GND | → GND do adaptador |

## Adaptador USB-Serial Necessário
- **Chipset**: CP2102, CH340G, FT232RL, ou PL2303HX
- **Voltagem**: **3.3V logic level** (NÃO 5V - queima o southbridge)
- **Baudrate**: 115200 8N1

### Conexão Cruzada (Null Modem)
```
PS4 TX ──────→ Adaptador RX
PS4 RX ──────→ Adaptador TX
PS4 GND ─────→ Adaptador GND
PS4 VCC ─────→ NÃO LIGAR
```

## Onde Comprar

| Item | Onde | Preço aprox |
|------|------|-------------|
| USB-TTL 3.3V (CP2102/CH340) | AliExpress, Shopee, Mercado Livre | R$ 15-30 |
| Cabo JST-SH 4p fêmea 1.0mm | AliExpress ("JST SH 1.0mm 4pin") | R$ 10-20 |
| Kit pronto "PS4 UART" | GitHub sellers, lojas modchip | R$ 50-80 |

### Links de Busca
- AliExpress: `"USB TTL 3.3V CP2102"` + `"JST SH 1.0mm 4pin female"`
- Mercado Livre: `"conversor usb serial ttl 3.3v"` + `"conector jst sh 4 pinos"`

## Opções DIY (Sem Conector JST)
1. **Fios 30AWG + Kapton**: Contate direto nos pads J1/J2
2. **Header 4x1 2.54mm**: Solde na placa, use jumpers fêmea
3. **Arduino/ESP32**: Use como USB-serial 3.3V (TX/RX/GND)

## Kernel Command Line (Baikal)
```bash
console=uart8250,mmio32,0xC890E000
```
Adicionado em `bootargs.txt` - habilita output kernel desde early boot.

## Teste no PC (Linux)
```bash
# Identifica porta
dmesg | grep ttyUSB
# ou
ls /dev/ttyUSB*

# Conecta
screen /dev/ttyUSB0 115200
# ou
picocom -b 115200 /dev/ttyUSB0
# ou
minicom -D /dev/ttyUSB0 -b 115200
```

## Saída Esperada
```
[    0.000000] Linux version 5.4.x...
[    0.000000] Command line: ... console=uart8250,mmio32,0xC890E000 ...
[    0.123456] console [uart8250] enabled
...
Welcome to Arch Linux on PS4!
ps4-arch login:
```

## ⚠️ Cuidados
- **NÃO ligue VCC (pino 1)** - southbridge Baikal não tolera 3.3V injetado
- **GND primeiro** - conecte GND antes de TX/RX
- **3.3V apenas** - adaptadores 5V queimam a UART do southbridge
- **Curto-circuito** - isole bem os fios, a placa é densa

## Referências Visuais
Buscar: `"PS4 Baikal UART J1 J2 pinout"` ou `"PS4 slim/pro uart console"`

Motherboard Baikal (CUH-2xxx / CUH-7xxx):
- J1/J2 perto do chip Southbridge (marcado "BAIKAL" ou "Sony CXD90050")
- 4 pads em linha, 1.0mm pitch
- Silk screen costuma ter "TX RX GND VCC" ou "J1/J2"

## Alternativa: Netconsole
Se não quiser hardware, use `netconsole` (já configurado no projeto):
```bash
# No PC receptor:
nc -u -l -p 6666

# No kernel cmdline (já presente):
netconsole=6665@192.168.0.2/eth0,6666@192.168.0.1/b4:45:06:6c:f6:4f
```
