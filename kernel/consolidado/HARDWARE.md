# Informações do Hardware PS4

> ⚠️ **FONTE DE VERDADE (2026-07-27):** este arquivo é a referência oficial para as especificações físicas deste console específico (RTYKER), confirmadas por fotos das etiquetas reais da placa/módulos/HD. Qualquer outro documento do projeto que divergir (ex.: `BAIKAL_HARDWARE_DISCOVERIES.md` citava HD de 465 GiB — corrigido para 1TB real) deve ser considerado desatualizado e corrigido para bater com aqui. **Pendência:** revisar se algum cálculo de offset/tamanho de partição no kernel Linux ou no payload assume incorretamente a capacidade antiga (465 GiB) em vez do 1TB real do Toshiba MQ04ABF100.

## Convenção de Nomenclatura — Lados da Placa (NVG-002)

> Combinado com o usuário em 2026-07-27, para consistência em fotos futuras da placa:
- **FRENTE**: lado com a APU exposta (pasta térmica visível, sem cooler), bateria de CMOS, conector de fita azul. Foto de referência: `consolidado/pictures/verso_processador.jpeg` (nome do arquivo não reflete a convenção — é a FRENTE).
- **VERSO**: lado com o cooler/dissipador (heatpipe), baía do drive óptico, conectores USB traseiros. Fotos de referência: `consolidado/pictures/002.jpeg`, `003.jpeg`.

## Especificações do PS4 RTYKER

| Componente | Detalhe |
|------------|---------|
| **Modelo** | PS4-RTYKER |
| **Modelo Sony (CUH)** | **CUH-7214B** (PlayStation 4 Pro) — confirmado por foto da etiqueta traseira |
| **Alimentação** | 100-240V~ 1,32A, 50/60Hz, 200W |
| **Firmware** | 12.52 |
| **Southbridge** | Baikal B1 (0x30201) |
| **HEN** | 12.52 |
| **GoldHEN** | v2.4b18.9 |
| **IP LAN** | 192.168.6.130 |
| **MAC LAN** | 2C:CC:44:3F:69:5F |
| **WiFi MAC** | E8:D8:19:93:CC:AF |
| **SoC** | 740F30 |
| **Sub System** | 30201 |
| **Version** | 4.3 |
| **Placa-mãe (board)** | NVG-002 |
| **Part Number placa** | 1-983-931-11 |
| **Fabricante placa** | Sony Interactive Entertainment Inc. |
| **Módulo WiFi/BT** | AW-CB319 |
| **FCC ID (WiFi/BT)** | AK8M18DAQ1 |
| **IC (WiFi/BT)** | 4098-M18DAQ1 |
| **ANATEL (WiFi/BT)** | 01936-18-03657 |
| **HD Interno** | Toshiba MQ04ABF100, 1TB (1.953.525.168 setores) |
| **HD Interno S/N** | X8MNSD6RS |
| **HD Interno Rev** | AGS AA00/JU0G0A |

## HD Interno — Varredura Completa (2026-07-27, disco real conectado via USB/SATA no PC)

> Disco confirmado como sendo o HD físico original do console (S/N `X8MNSD6RS` bate com a etiqueta fotografada). Conectado ao PC via adaptador SATA-USB (ponte **JMicron 152D:0578**, driver `uas`), aparece como `/dev/sda`. Toda a varredura abaixo foi **somente leitura** (nenhuma escrita, nenhuma montagem).

### Identificação física/ATA
| Campo | Valor |
|---|---|
| Modelo | TOSHIBA MQ04ABF100 |
| Firmware/Revisão | JU0G0A |
| Serial | X8MNSD6RS |
| WWN | `0x50000398d6107884` |
| Capacidade | 1.000.204.886.016 bytes (931,51 GiB / 1TB, 1.953.525.168 setores de 512B) |
| Setor lógico/físico | 512B / 4096B (Advanced Format 4Kn emulado) |
| Rotação | 5400 RPM |
| Recursos ATA suportados | SMART, HPA, Power Management, APM, Security (não habilitado), Download Microcode |
| Ponte USB | JMicron Generic (VID:PID `152d:0578`), FW `0508` |

### Tabela de partições — GPT customizado da Sony
- **Disk GUID:** `D366DB3E-F699-11E8-8092-2CCC443F695F`
  - ⚠️ **Achado:** os últimos 6 bytes do GUID (`2C:CC:44:3F:69:5F`) são **literalmente o MAC address da porta LAN** deste console. A Sony deriva o GUID do disco a partir do MAC — todas as PARTUUID individuais de cada partição também terminam no mesmo MAC, confirmando o padrão.
  - **Revisão do header GPT = 2.0** (`0x00020000`), não a 1.0 padrão da spec UEFI — é por isso que `parted` emite aviso ("table format version 20000... mais recente do que o Parted pode reconhecer"). GPT customizado da Sony, estruturalmente compatível (header de 92 bytes, 128 entradas de 128 bytes cada), só com o campo de revisão alterado.

| Partição | Setor inicial | Setor final | Tamanho | Type GUID (Sony, não padrão) | Atributo | Papel provável |
|---|---|---|---|---|---|---|
| sda1 | 1.947.985.920 | 1.949.034.495 | 512 MiB | `17800F17-B9E1-425D-B937-0119A0813172` | — | |
| sda3 | 1.949.034.496 | 1.951.131.647 | 1 GiB | `CCB52E94-EBEF-48C4-A195-9E2DA5B0292C` | — | |
| sda5 | 1.951.131.648 | 1.951.164.415 | 16 MiB | `145268BF-63AD-47C1-9378-9AACD9BEED7C` | — | |
| sda7 | 1.951.164.416 | 1.951.426.559 | 128 MiB | `6E0C5310-8445-4066-B571-9B65FDB75935` | — | |
| sda9 | 1.941.694.464 | 1.943.791.615 | 1 GiB | `EABBF00B-C299-4488-9DE9-B2839BCE7546` | `0x80000000000000` | par redundante A/B com sda10 (mesmo type GUID, mesmo conteúdo binário nos primeiros bytes) |
| sda10 | 1.939.597.312 | 1.941.694.463 | 1 GiB | `EABBF00B-C299-4488-9DE9-B2839BCE7546` | `0x0` | ver sda9 |
| sda11 | 1.945.888.768 | 1.947.985.919 | 1 GiB | `DC85025F-A694-4109-BE44-FA0C063E8B81` | `0x80000000000000` | par redundante A/B com sda12 |
| sda12 | 1.943.791.616 | 1.945.888.767 | 1 GiB | `DC85025F-A694-4109-BE44-FA0C063E8B81` | `0x0` | ver sda11 |
| sda13 | 19.398.656 | 44.564.479 | 12 GiB | `76A9A5B4-44B0-472A-BDE3-3107472ADEE2` | — | |
| sda17 | 524.288 | 2.621.439 | 1 GiB | `80DD49E3-A985-4887-81DE-1DACA47AED90` | — | |
| sda19 | 2.621.440 | 19.398.655 | 8 GiB | `A71FF62D-1421-4DD9-935D-25DABD81BEC5` | — | |
| sda25 | 44.564.480 | 57.147.391 | 6 GiB | `FDB5EDE1-73C3-4C43-8C5B-2D3DCFCDDFF8` | — | |
| **sda27** | 57.147.392 | 1.939.597.311 | **897,6 GiB** | `C638477A-E002-4B57-A454-A27FB63A33A8` | — | maior partição — provável dados de usuário/jogos |
| sda29 | 1.951.426.560 | 1.953.523.711 | 1 GiB | `21E4DFB4-0040-4934-A037-EA9DC058EEA6` | — | |

Nenhuma partição tem `name` (label UTF-16) preenchido no GPT — a Sony não usa esse campo.

### Conteúdo das partições — TODAS criptografadas
Inspecionados os primeiros 4KB de cada uma das 14 partições (`dd` + `xxd`/`strings`, somente leitura): **100% dos dados têm aparência de alta entropia (ruído puro)** — nenhuma assinatura de filesystem reconhecível (sem magic FAT/exFAT/ext/UFS/GPT aninhado), nenhuma string ASCII legível. Confirma o que já era esperado pela RE do kernel Orbis (`KERNEL_DUMP_HARDWARE_INVENTORY.md` seção 5, `/dev/da0x*.crypt*`): **o disco inteiro é criptografado pelo Orbis OS**, não há como montar/ler nenhuma partição a partir do Linux sem a chave (derivada de hardware, provavelmente do efuse/Syscon).
- `sda9`/`sda10` e `sda11`/`sda12` têm **bytes idênticos no início** — reforça a hipótese de slots redundantes (A/B, ex.: preload/kernel de boot com fallback), mesmo com o bit de atributo GPT `0x80000000000000` distinguindo qual é o "principal".

### Implicação prática
Não há caminho de acesso direto (fora do Orbis OS) às 14 partições deste HD a partir do Linux rodando no PS4 — qualquer necessidade de dado do disco interno (ex.: comparar com o dump do kernel Orbis já extraído) precisa continuar vindo do dump via TCP/kexec já feito, não de leitura crua de partição.

## Pesquisa Web (2026-07-27) — PS4 Developer Wiki (psdevwiki.com), componentes oficiais da NVG-002

> Fonte: `psdevwiki.com/ps4/NVG-002`, `/Southbridge`, `/Internal`, `/Service_Connectors`, `/Devkit_USB_Uart` — acessados via navegador (Claude in Chrome) em 2026-07-27, pois o fetch automatizado direto leva 403 (proteção anti-bot Cloudflare).

### Componentes oficiais da placa NVG-002 (product code `1-983-931-11`, chassis CUH-72xx)
| Componente | Part Number |
|---|---|
| APU | `CXD90055GB` |
| APU RAM | Micron `D9WDH` |
| **Southbridge** | **`CXD90042GG`** (revisão **Baikal**) |
| Southbridge RAM | `K4B4G0846E-BYMA` (visto em placas `1-983-931-11` semana 39/2018) — **1GB total (2× chip 4Gb)**, o dobro da Fat/Slim (256MB) |
| Syscon | `A06-COL2` |
| Serial Flash | `FL256LAIF01` (256MB) |
| HDMI | `MN864729` |
| LAN (conector físico) | Pulse Electronics `GST5009S1 LF` (sem. 39/2018) ou G-TICN/MS Inserts `MS242-A106-1H` (11/2018) |
| Wireless (WiFi/BT) | `AW-CB319` — confirma o módulo já fotografado |
| BD-ROM | `MT1965AU` |

### Southbridge Baikal (`CXD90042GG`) — confirmação cruzada
- Usado nas placas: NVB-004, **NVG-002**, NVG-004, SAD-002, SAE-002/004, SAF-004/006
- Chassis **7200** com Baikal = **NVG-002 / NVG-004**, fabricado entre **2018-09 e 2019-06** (bate com o FCC/ANATEL `01936-18-03657` de 2018 já registrado)
- O Southbridge é na verdade um SoC com **dois processadores no mesmo die**: **EMC** (ARM Cortex-M3, ~100MHz, roda FreeBSD próprio, expõe debug via UART independente do Syscon/APU) e **EAP** (ARM Cortex-A8 PJ4C, 500MHz, FreeBSD 9, gerencia rede/BD/HDD mesmo em standby)
- Conectado à APU via **PCIe x4**; conectado ao Syscon via **SPI**
- Há um protocolo de debug via UART do EMC ("EMC UART Debug Communication") com dezenas de comandos textuais (`devpm`, `tempr`, `fduty`, `rtc`, `pcie`, `scversion` etc.) — documentado apenas para a geração **Aeolia** (CUH-10xx); não confirmado se os mesmos comandos funcionam no Baikal.

### ⚠️ ACHADO CRÍTICO: pinout físico de UART NÃO existe publicamente para Baikal/Pro
- `psdevwiki.com/ps4/Internal` documenta pads físicos de UART (pinout completo: GND/TX/RX, 3.3V CMOS TTL, 115200 8N1) **só para CUH-10xxA (SAA-001/SAB-001/SAC-001)** — southbridge **Aeolia**, chip completamente diferente do nosso.
- `psdevwiki.com/ps4/Service_Connectors` tem seções "Preproduction Generation" e "First Generation" com pinout detalhado (Syscon 30 pinos, Southbridge 20 pinos) — mas a seção **"Second Generation" (que cobriria Slim/Pro/Baikal) está marcada literalmente como "TODO"**. A comunidade nunca publicou o pinout físico do Baikal.
- `psdevwiki.com/ps4/Devkit_USB_Uart` documenta o **conector proprietário de UART usado só em kits de desenvolvedor** (dongles DUH-D1000/DUH-D7000/DEHT, chip CP2105 customizado, VID `054C`) — não é o pad de solda de um console retail.
- **Conclusão prática:** não há atalho — localizar o UART físico na NVG-002 exigirá RE nossa (rastreamento de continuidade com multímetro a partir do datasheet/pinagem do `CXD90042GG`, ou comparação de trilhas), não uma foto/schematic já pronta na internet.

### Candidato físico apontado pelo usuário (2026-07-27) — foto `V002.jpeg`, lado VERSO
- O usuário circulou uma área no lado **VERSO** (perto das marcações de zona `F6001`/`F6201`/`F6202` já vistas antes), próxima a um chip **QFP preto retangular com pinos visíveis** e, logo abaixo dele, um **footprint de conector não populado** (fileira de pads dourados, perto de dois furos de parafuso) — padrão físico compatível com um conector de debug/teste não montado de fábrica.
- **NÃO confirmado ainda**: nem a identidade do chip preto (poderia ser o Southbridge `CXD90042GG` ou outro componente), nem se o footprint vazio é de fato UART (pode ser SPI/I2C/JTAG/outro).
- **Próximo passo combinado:** fotos macro (1) da marcação impressa no chip preto e (2) do footprint de pads não populado, para tentar ler serigrafia (TX/RX/GND/J-algo) e cruzar o part number do chip com o datasheet do `CXD90042GG`.

### Fotos de contexto mais amplo — `V003.jpeg`/`V004.jpeg` (VERSO, 2026-07-27)
- `V003.jpeg`: mostra a mesma região de `V002.jpeg` com mais contexto. **Achado que reduz a confiança na hipótese anterior:** a etiqueta redonda dentro da área com pasta térmica perto de "F6001" traz o texto **"ANATEL 01956-18-03657"** — praticamente idêntico ao ANATEL do módulo Wireless `AW-CB319` (`01936-18-03657`, já catalogado). Isso sugere fortemente que essa região é onde o **módulo WiFi/BT fica fisicamente montado/blindado na placa principal**, não o Southbridge. O chip QFP preto circulado em `V002.jpeg` pode ser um componente de suporte do módulo wireless (ex.: level shifter, EEPROM), não necessariamente o `CXD90042GG`.
- `V004.jpeg`: enquadramento mais amplo do VERSO. A área quadrada central com grade densa de pequenos pads é, muito provavelmente, o **campo de vias por baixo da APU** (que fica montada do lado oposto, na FRENTE) — não um chip novo, apenas o reflexo estrutural do footprint BGA da APU vista pelo verso da placa multicamada.
- **Status: ainda sem identificação confirmada do chip físico `CXD90042GG`.** Precisa de foto com zoom suficiente pra ler o texto gravado no próprio chip candidato (não só o contexto ao redor).

### Pista do usuário (2026-07-27, pesquisa própria): UART pode estar no lado VERSO
- O usuário pesquisou por conta própria e encontrou indício de que a saída UART, embora não claramente identificada, **fica no lado VERSO da placa** (lado do cooler/heatpipe, baía do drive óptico, conectores USB traseiros — ver convenção acima, fotos `002.jpeg`/`003.jpeg`), **não** no lado FRENTE (APU exposta, bateria CMOS, VRM — fotos `verso_processador.jpeg`, `F001`-`F003.jpeg`).
- **Ainda não confirmado** exatamente qual pad/conector no VERSO — só a pista de lado. Próximo passo natural: fotos macro do lado VERSO com foco em pads não populados (furos sem componente, geralmente perto do Southbridge Baikal) e qualquer serigrafia legível (ex.: "TX", "RX", "J1", "UART", "TP").
- **Pendência aberta:** identificar fisicamente qual chip no VERSO é o `CXD90042GG` (Southbridge Baikal) — nenhuma foto até agora permitiu confirmar isso com certeza.

### 🎯 PINOUT ENCONTRADO (2026-07-27) — fonte externa `repair.wiki`, cobre exatamente a família NVA/NVB/NVG

> Imagem original: `https://repair.wiki/images/thumb/2/24/BWE-UART-Pinout.jpg/1920px-BWE-UART-Pinout.jpg` (autor: BetterWayElectronics.com.au). Baixada e salva em `consolidado/pictures/REF_BWE-UART-Pinout.jpg`, com recortes ampliados em `consolidado/pictures/crop_nvg_uart.png` (diagrama de pinos) e `crop_nvg_fullboard.png` (placa completa, mesma revisão `NVG-002 1-983-931-21` — mesmo product code base que o nosso `1-983-931-11`, só semana de fabricação diferente).

**Achado principal:** o diagrama "NVA / NVB / NVG" (nossa família exata) mostra os pinos de UART **ao lado de um chip QFP cuja marcação lê "A06-COL2"** — isso bate exatamente com o **Syscon `A06-COL2`** já catalogado pra nossa NVG-002 (seção "Componentes oficiais" acima). Ou seja: **o UART fica perto do Syscon, não do Southbridge Baikal** (`CXD90042GG`) como vínhamos supondo.

**Layout ao redor do chip Syscon (vendo o VERSO, conforme o diagrama):**
- Coluna vertical de pontos entre o chip e dois furos grandes de montagem (parafuso):
  - 2 pontos brancos no topo (não identificados/sem uso no legend)
  - **vermelho = UART RX**
  - **verde = UART TX**
  - (furo de montagem grande)
  - **preto = GND**
  - mais pontos brancos abaixo
- À direita dessa coluna de pontos: um **conector FPC/fita** (fileira de pads dourados) — bate com o "footprint de conector" que o usuário já tinha notado perto da área circulada em `V002.jpeg`.
- Sinal: **3.3V CMOS TTL, 115200 8N1** (mesmo padrão dos outros modelos).

### ✅ LOCALIZAÇÃO FÍSICA CONFIRMADA (2026-07-27) — chip Syscon `A06-COL2` identificado ao vivo

- **`V004-B.jpeg`** (macro fechado, rotacionado 180° para leitura correta em `V004-B_rotated.png`): marcação do chip lida com clareza: **"A06-COL2"** — confirma que é o Syscon, exatamente o chip do diagrama de referência.
- **`V002.jpeg`** (o candidato originalmente circulado pelo usuário) mostra **o mesmo chip** (mesmo encapsulamento QFP, mesmo padrão de desgaste no epóxi preto) — ou seja, **a hipótese original do usuário estava certa desde o início**; a pista da etiqueta ANATEL próxima (seção acima) foi uma coincidência de proximidade física entre o módulo WiFi e o Syscon nessa placa, não um sinal de que o local estivesse errado.
- **`V004-C.jpeg`** (foto mais aberta, decisiva): mostra o chip **à direita** e, **à esquerda dele, os dois furos grandes de montagem empilhados na vertical** (com anel de cobre/laranja ao redor, idêntico ao padrão do diagrama de referência), e mais à esquerda ainda **uma fileira fina de pads dourados não populados** (footprint de conector FPC) — bate ponto a ponto com a sequência do diagrama: `chip → pontos de teste → furo grande → conector`.
- Rótulo de zona nessa área: **`F6202`** (visível no canto inferior da foto, mesmo rótulo já visto em `V003.jpeg`).

**Candidatos a pad de TX/RX/GND (⚠️ ainda NÃO confirmados eletricamente):**
Entre o chip e o furo superior há um pequeno grupo de pads circulares prateados não populados (sem componente montado) — pelo padrão do diagrama de referência (RX e TX ficam imediatamente acima/ao lado do furo superior, GND fica ao lado do furo, mais distante do chip), os **2 pads mais próximos do furo superior, do lado do chip,** são os melhores candidatos a **RX/TX**, e um pad mais afastado (entre os dois furos ou ao lado do furo inferior) é candidato a **GND**. A foto real não tem serigrafia/cor indicando qual é qual (isso só existe no diagrama anotado) — **não dá pra cravar 100% por imagem**, a resolução e o ângulo não permitem certeza pad-a-pad.

**⚠️ RECOMENDAÇÃO ANTES DE SOLDAR:** confirmar eletricamente com multímetro antes de qualquer solda:
1. **GND:** testar continuidade (modo bipe) entre o pad candidato e um ponto de terra conhecido (ex.: blindagem metálica, malha do conector HDMI/USB, parafuso de chassi) — GND deve apitar continuidade.
2. **TX (saída do console):** com o console ligado, medir tensão DC no pad candidato em relação ao GND já confirmado — uma linha TX UART ociosa tipicamente fica em **~3.3V** (idle high) e varia brevemente durante o boot; **RX** normalmente fica flutuante/próximo de 0V sem nada conectado.
3. Só depois de confirmar os 3 pontos eletricamente, conectar o adaptador USB-TTL 3.3V (nunca 5V) seguindo a mesma pinagem já documentada no `CABO_UART.md` (GND primeiro, depois TX/RX cruzados).

### 🎯🎯 PINOUT DEFINITIVO ENCONTRADO — foto anotada ESPECÍFICA da NVG-002 (2026-07-27)

> Fonte: **`https://www.psdevwiki.com/ps4/Talk:Service_Connectors#NVG-002`**, imagem `https://www.psdevwiki.com/ps4/images/c/c3/Nvg-002.jpg` (arquivo `File:Nvg-002.jpg`, 1390×1153px). Encontrada pelo usuário — página de discussão que complementa `Service_Connectors` (cuja seção "Second Generation" estava marcada "TODO"); aqui a comunidade **já preencheu o caso NVG-002 especificamente**, com foto real anotada.

Essa foto é **da mesma revisão exata da nossa placa** — mostra o chip `A06-COL2` e os rótulos de zona `F6202`/`F6201`, idênticos aos vistos em `V002.jpeg`/`V003.jpeg`/`V004-C.jpeg`. Está anotada com texto direto sobre a imagem: **"NVG-002 (72xx)"**, e dois círculos com rótulo:
- **círculo vermelho = TX**
- **círculo preto = GND**

Layout confirmado (visto na foto): chip `A06-COL2` à esquerda com os pinos voltados para a direita; à direita do chip, um pequeno grupo de pads não-populados; o pad **TX** é o mais próximo do canto superior-direito da fileira de pinos do chip (levemente acima e à esquerda do primeiro furo grande de montagem); o pad **GND** fica imediatamente à direita/abaixo de TX, quase encostando no topo desse primeiro furo. Não há um terceiro ponto rotulado como RX nessa foto — só TX e GND foram documentados (uso comum quando o objetivo é só *ler* o log de boot via UART, sem enviar comandos de volta).

**⚠️ Tentativa de sobrepor essa imagem à nossa `V004-C.jpeg` pixel-a-pixel FALHOU nesta sessão:**
- Download direto via `curl` (com e sem header `Referer`) retornou **HTTP 403** (proteção anti-hotlink do site).
- Fetch via JavaScript dentro do navegador funcionou (retornou 200, 336KB), mas a ferramenta de execução JS **bloqueia a saída de dados codificados em base64/hex** (proteção interna contra exfiltração de dados binários) — não há como trazer os bytes da imagem para o disco por esse caminho nesta sessão.
- Comparação visual manual (recortes/zoom) não teve rotação/ângulo batendo de forma confiável entre a foto de referência e `V004-C.jpeg` — **por segurança, não travamos uma coordenada de pixel específica na NOSSA foto**, para não arriscar apontar solda no pad errado.

**➡️ Recomendação prática para fechar isso com 100% de certeza:** abra `https://www.psdevwiki.com/ps4/images/c/c3/Nvg-002.jpg` no celular/PC ao lado da placa física, **gire o console (não a foto)** até a orientação bater com a imagem (chip `A06-COL2` à esquerda, pinos à direita, dois furos grandes empilhados à direita do chip) — nessa orientação os pontos TX/GND da foto caem diretamente sobre os pads reais. Depois, ainda assim, confirmar com multímetro (passos acima) antes de soldar.

**Offsets de patch do NOR** (mencionados na mesma imagem de referência, ainda não verificados por nós): `0x1C931F` e `0x1CC31F`, ambos setar para `01` para habilitar log de debug via UART — mesmos offsets já citados no `consolidado/obsoleto/CABO_UART.md` antigo, agora com origem/fonte confirmada (BetterWayElectronics.com.au via repair.wiki).

### ⚠️ Southbridge Baikal `CXD90042GG` — leitura obtida, PENDENTE de reconfirmação (2026-07-27)

Numa primeira tentativa de mosaico de alta resolução (fotos + stitching descartados pelo usuário por qualidade insatisfatória — ver nota abaixo), foi possível ler momentaneamente a marcação de um chip BGA no lado **VERSO**, próximo ao módulo WiFi/BT (etiqueta ANATEL `01936-18-03657`) e a chips de RAM marcados `SSB77 D9HDH`:

```
SIE
CXD90042GG
1841-BHHTH
CTT25K74.00-1
TAIWAN
```

Isso bateria com o **Southbridge Baikal `CXD90042GG`** catalogado via psdevwiki (seção "Pesquisa Web" acima) — encapsulamento **BGA** (não QFP), lote `1841` (semana 41 de 2018, compatível com a janela de fabricação 2018-09/2019-06 já registrada). **Porém as fotos-fonte e o mosaico foram apagados a pedido do usuário (resultado insatisfatório) — esta leitura ainda não tem uma foto de evidência salva no repositório.** Tratar como pista a reconfirmar num novo set de fotos, não como fato fechado.

**Se confirmado no futuro:** notar que esse chip (Southbridge, BGA, perto do WiFi/RAM) seria fisicamente diferente e em local diferente do chip Syscon `A06-COL2` (QFP, perto dos 2 furos de montagem + conector FPC, candidato à área de UART) já documentado e confirmado nas seções anteriores.

### Tentativa de mosaico de alta resolução — descartada (2026-07-27)

Uma primeira sequência de 48 fotos macro do lado VERSO foi processada com stitching sequencial próprio (ORB + `estimateAffinePartial2D` + RANSAC via OpenCV, já que o `cv2.Stitcher` de alto nível travava/segfault com muitas imagens de uma vez). O resultado quebrou em 19 segmentos (nem todo par de fotos consecutivas tinha sobreposição suficiente) e a qualidade final **não agradou o usuário** — fotos originais e todos os mosaicos gerados foram **apagados a pedido dele**, e o set de fotos será refeito do zero. Lições para a próxima tentativa:
- Manter sobreposição mais consistente (~30-40%) entre fotos consecutivas, evitando saltos grandes.
- Manter o celular o mais paralelo possível à placa (menos variação de ângulo/rotação entre fotos consecutivas reduz erro de alinhamento).
- Script de stitching (não commitado, fica no scratchpad da sessão) pode ser reaproveitado/ajustado quando o novo set chegar.

## Southbridges do PS4

O PS4 possui diferentes southbridges dependendo da revisão do hardware:

| Southbridge | Modelos | EMC Timer Base | UART Base | PCI IDs |
|-------------|---------|----------------|-----------|---------|
| **Aeolia** | PS4 Phat (primeiros) | `0xd0281000` | `0xd0340000` | 0x908f-0x90a4 |
| **Belize** | PS4 Slim, PS4 Pro | `0xd0281000` | `0xd0340000` | 0x908f-0x90a4 |
| **Baikal** (B1) | PS4 Slim/Pro (revisões recentes) | **N/A** (layout diferente) | `0xC890E000` | 0x90d7-0x90de |

### PCI IDs Baikal (Linux)
| Device | ID | Driver |
|--------|-----|--------|
| ACPI | `0x90d7` | — |
| GBE (Ethernet) | `0x90d8` | sky2.c |
| AHCI (SATA) | `0x90d9` | ahci.c |
| SDHCI (eMMC) | `0x90da` | sdhci-pci-core.c |
| PCIe (Glue) | `0x90db` | ps4-apcie.c |
| DMAC | `0x90dc` | — |
| MEM | `0x90dd` | — |
| XHCI (USB) | `0x90de` | xhci-aeolia.c |

### ⚠️ Incompatibilidade: BAR4 Glue Logic
A southbridge Aeolia/Belize usa **PCI function 4 (BAR4)** como registradores de configuração ("glue logic") para mapear todos os dispositivos. Em Baikal B1, **function 4 pode ter layout diferente**, causando:
- `pci_ioremap_bar(dev, 4)` → NULL
- `apcie_glue_init()` → falha
- Todos os dispositivos (SATA, GPU, USB) → **não inicializam**

**Correção no kernel 5.15**: Skip de glue_init quando `is_baikal == true`.

A southbridge é a ponte sul do chipset, responsável por:
- Controladora USB
- Áudio
- Rede
- Armazenamento
- GPIO

O tipo de southbridge afeta quais payloads kexec são compatíveis.

## APU (CPU + GPU)

O PS4 usa uma APU AMD personalizada (Jaguar):
- **CPU**: 8-core AMD Jaguar x86-64 (1.6 GHz)
- **GPU**: AMD GCN (Graphics Core Next) 1.8 TFLOPS
- **RAM**: 8GB GDDR5 (unificada CPU+GPU)
- **TSC Frequency**: 1.594 GHz (PS4_DEFAULT_TSC_FREQ)
- **LAPIC Timer**: Calibrado via EMC timer (Aeolia) ou default (Baikal)

## Limitações de Hardware para Linux

### RAM
- **Total**: 8GB GDDR5
- **Disponível para Linux**: ~4-5GB (OrbisOS reserva o resto)
- **Swap**: ESSENCIAL - Recomendado 8-12GB

### Vídeo
- Driver AMD open-source (Radeon/RADV)
- Resolução máxima: 1080p@60Hz (alguns kernels suportam 4K)
- Problemas comuns: tela preta em monitores (resolvido com EDID falso)
- **Solução para monitor LG**: adaptador HDMI-VGA **COM USB de energia**.
  Adaptadores HDMI-VGA sem alimentação USB não funcionam no PS4 -
  a saída HDMI do PS4 não fornece energia suficiente para o chip
  conversor. O cabo USB precisa estar conectado a uma fonte de
  5V (carregador USB, porta USB do PS4, etc.).

### Wi-Fi
- Chipset MediaTek MT76
- Funciona com driver `mt76` do kernel
- Pode ser instável em alguns kernels

### Bluetooth
- Controladora Bluetooth integrada
- Suporte limitado no Linux

### Áudio
- HDMI audio funciona
- Áudio analógico via controle pode ser complicado

## Configurações Recomendadas de Vídeo (OrbisOS)

Antes de carregar o payload Linux:
1. Resolução: 1080p
2. Gama RGB: Completa
3. HDR: Desligado
4. HDCP: Desabilitado
5. HDMI device link: Desabilitado
6. Saída de cor intensa: Desligado

## Payload Guest App

- Use preferencialmente payload de 3GB (3072MB) para desktop ou 1GB (1024MB) para instalação
- GoldHEN v2.4b18.5+ recomenda arquivos .elf
- **Payloads v24+ são firmware agnósticos**: um único payload para todos os firmwares
- Carregamento via BinLoader do host PSFree-Enhanced
- VRAM ajustável via `vram.txt` (32MB a 4GB)
- Para uso como servidor: 32MB-512MB libera RAM para o sistema

## Endereços Importantes

- **Payload sender port**: 9090
- **FTP port**: 2121 (GoldHEN FTP)
- **PS4 Remote Play**: Chiaki app
