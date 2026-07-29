# Plano: Migração do Jailbreak PS4 12.52 — Disco Blu-ray AIO → Web-Host local

## Contexto

**Problema atual** (`consolidado/BACKLOG.md:215`): o boot via disco Blu-ray AIO
(UFC "X=Poops") falha **antes do payload**, na fase de exploit chain do próprio
disco, com:

```
Pre-configuration
Initial triple free
Twins failed
Triple free failed
Fatal fail(-1), please REBOOT PS4
```

`Twins/Triple free` = heap spray do exploit WebKit/Kempaku do jogo. `-1` = falha
de aquisição da primitiva Ring 0. O usuário confirmou que o problema **ocorre
mesmo com boot frio** (power cycle completo), então não é estado transitório de
heap — é falha sistemática do exploit do disco.

**Solução**: eliminar o disco/ jogo explorado inteiro da cadeia. Subir um
Web-Host local (nanoDNS + servidor HTTP) no PC do projeto, apontar o DNS do PS4
pra lá, e disparar o exploit PSFree + GoldHEN.bin pela página do "User Guide"
do navegador Orbis. Método standard atual, citado em issues oficiais GoldHEN
(#366).

**Topologia de rede confirmada** (não confundir com a subnet do `eth0`/GBE
test):

| Elemento | IP | Interface | Papel |
|----------|----|-----------|-------|
| PS4 (Orbis/GoldHEN) | `192.168.6.128` | `wlan0` (WiFi MT7668) | Alvo da injeção |
| PC host (este Linux) | `192.168.6.100` | `wlp0s20f3` (WiFi) | Web-Host: DNS + HTTP |
| Roteador | gateway da `192.168.6.0/24` | — | DHCP pro PS4 |

**NÃO usar `enp60s0`** (192.168.0.1) — essa interface é dedicada ao teste de RX
do driver `mts.ko` (AGENTS.md:88). O PS4 precisa alcançar o Web-Host durante o
Orbis, antes do Linux bootar — só a WiFi serve.

## Pré-requisitos (validados)

- [x] PC Linux com `wlp0s20f3` ativa em `192.168.6.100/24`
- [x] PS4 alcançável por SSH em `192.168.6.128` (root/ps4) — mas **só após**
  GoldHEN injetado, não ajuda aqui no cold-boot
- [x] UART TTL funcional (`scripts/uart_start.sh`) — para capturar logs do exploit
- [x] Firmware confirmado: 12.52, GoldHEN v2.4b18.9 (idêntico ao do disco AIO)

## Arquitetura

```
   ┌─────────────────────────────────────────────────────┐
   │  PC host (192.168.6.100) — wlp0s20f3                 │
   │  ┌────────────────────┐      ┌────────────────────┐  │
   │  │ nanoDNS (port 53)  │      │ HTTP server :80     │  │
   │  │ *.playstation.net  │      │  /index.html        │  │
   │  │  →127.0.0.1        │      │  /goldhen_1252.bin  │  │
   │  │  guides.elpes4.net │      │  /psfree.js         │  │
   │  │  →127.0.0.1        │      │  /payloads/*.bin   │  │
   │  └─────────▲──────────┘      └──────────▲─────────┘  │
   └─────────────┼────────────────────────────┼──────────┘
                 │  DNS query                   │  HTTP GET
                 ▼                              ▼
   ┌─────────────────────────────────────────────────────┐
   │  PS4 Orbis 12.52 (192.168.6.128)                    │
   │                                                      │
   │  Configurações > Rede > WiFi > Custom:              │
   │    DNS primário: 192.168.6.100                       │
   │                                                      │
   │  User Guide / Manual do Usuário (✚ ícone no menu): │
   │    → resolve manuals.playstation.net → 192.168.6.100 │
   │    → baixa /index.html → executa psfree JS          │
   │    → injeta goldhen_1252.bin via kexec               │
   └──────────────────────────────────────────────────────┘
```

## Por que `manuals.playstation.net` e `guides.elpes4.net`

Sony tensa faz o `User Guide` do Orbis abrir uma URL hard-coded
(`https://manuals.playstation.net/document/...`). O DNS hijack local aponta
esse domínio para o nosso servidor HTTP. Algumas versões de firmware também
procuram `guides.elpes4.net` (legacy PS4 redirect). Ambos apontados para
127.0.0.1 — sem colisão com DNS real.

## Alternativas para 12.50/12.52 (consolidado, por estabilidade)

| # | Método | Estabilidade | Recursos | Status p/ projeto |
|---|--------|-------------|----------|-------------------|
| 1 | **Web-Host local** (nanoDNS+HTTP) | ★★★★★ | PC WiFi + DNS | ✅ Escolhido |
| 2 | Web-Host Internet (azif/Karo) | ★★★★ | Só internet | Backup (se Fase 1 falhar) |
| 3 | USB auto-host (PiSugar) | ★★★★ | Pendrive exFAT | Alternativa offline |
| 4 | Injeção manual Payload Server | ★★★ | Requer bootstrap prévio | Só pós-trigger |
| 5 | BD-R regravado em 2x | ★★ | Mídia nova | Workaround paliativo |
| 6 | Trocar de jogo explorado | ★★ | Outro jogo | Restrito ao AIO suportado |
| 7 | Atualizar FW p/ 13.00+ | ⛔ | — | **Inviável** (sem exploit público, issue GoldHEN #295) |

## Plano de execução

### Fase 1 — Bootstrap do Web-Host local (1-2h)

**1.1. Instalar dependências no PC host:**

```bash
# Arch/minimal_v2 já usa Arch ou derivado. Confirmar com:
which dnsmasq python3 socat
# Se faltar:
sudo pacman -S --needed dnsmasq python3
```

**1.2. Criar diretório do host:**

```bash
mkdir -p /opt/ps4-webhost/{html,payloads}
# Em /opt porque é padrão FHS para servir conteúdo estático
# (não usar /mnt/t — é NTFS montado, lento pra I/O e com permissões
# capengas, conforme memory/filesystem-ntfs-mnt-t-restricao.md)
```

**1.3. Obter os arquivos do host:**

Existem 3 caminhos (em ordem de preferência):

(a) **Baixar dos repositórios oficiais PSFree + GoldHEN.bin 12.52** (recomendado):
   - PSFree HTML+JS: source pública da scene (procurar `PSFree host PS4 12.52`
     no psx-place / GitHub). Ver `REFERENCIAS.md` (criar quando baixar).
   - `goldhen_1252.bin`: própria versão já usada no disco AIO (MD5 conferir com
     `consolidado/MASTER_CONSOLIDADO.md` se documentado lá).

(b) **Reaproveitar o payload do disco AIO**: se o disco montar como UDF no PC
   (`mount -t udf /dev/sr0 /mnt/aio`), copiar `*.bin`, `*.html`, `*.js` dele.
   Mantém a mesma versão já testada do GoldHEN.

(c) **Host alternativo público (azif65/Karo)** como referência: baixar uma cópia
   do host online para estudo/uso offline.

**1.4. Subir o Web-Host (script `scripts/webhost_start.sh`):**

```bash
sudo ./scripts/webhost_start.sh
# Faz:
#  - inicia dnsmasq em :53 com `address=/manuals.playstation.net/192.168.6.100`
#                      e `address=/guides.elpes4.net/192.168.6.100`
#  - inicia python http.server na :80 servindo /opt/ps4-webhost/html
#  - abre firewall (iptables nft) p/ :53 udp e :80 tcp da subnet 192.168.6.0/24
#  - logs em /tmp/ps4-webhost-{dns,http}.log
```

**1.5. Configurar DNS no PS4 (usuario opera joystick):**

```
PS4 > Configurações > Rede > Configurar conexão à Internet > WiFi > Personalizada
  > Especificar configuração de IP: Automático
  > DHCP: Não especificar
  > DNS primário:   192.168.6.100
  > DNS secundário: (vazio)
  > Proxy: Não usar
  > MTU: Automático
```

**1.6. Testar a injeção:**

```
PS4 > Menu inicial > User Guide / Manual do Usuário
  → abre webview → resolve manuals.playstation.net → 192.168.6.100
  → carrega /index.html → PSFree executa → injeta GoldHEN.bin
  → notificação "GoldHEN Loaded"
```

**1.7. Smoke test:**

```bash
# PC host:
ping -c 3 192.168.6.128              # PS4 deve responder pós-GoldHEN
sshpass -p ps4 ssh root@192.168.6.128 "uname -a; ps aux | head; ls /data/GoldHEN/"
# (no Orbis, ps/aux podem ser limitados — usar `kldstat` ou checar /data/GoldHEN/)
```

**1.8. CapturarUART para diagnóstico de falhas:**

```bash
scripts/uart_start.sh 300 webhost-tentativa1
# Em outra aba:
tail -f tests/uart_logs/webhost-tentativa1_*.log
# Procure por tokens PSFree/GoldHEN/SceKernel/kexec no log Orbis
```

### Fase 2 — Robustez e automação pós-trigger (2-3h, paralelo)

**2.1. AutoPayload do GoldHEN** (auto-boot do kexec-loader):

Logo que GoldHEN injeta, ele auto-carrega payloads de `/data/GoldHEN/auto/`.
Colocar aí o `kexec-loader.bin` (o mesmo já usado pelo disco AIO hoje) → boot
do Linux vira **1 clique no User Guide**, sem payload extra manual.

```bash
sshpass -p ps4 scp ps4-linux-payloads/build/kexec-loader.bin \
    root@192.168.6.128:/data/GoldHEN/auto/linux_loader.bin
# (Renomear p/ auto vazio — GoldHEN vai disparar tudo nesta pasta uma vez)
```

**2.2. Hook de "re-trigger por SSH"** (script `scripts/retrigger_jb.sh`):

NESTE MOMENTO o PS4 já tem GoldHEN ativo (boot Linux carregado usb-host), mas
se o GoldHEN "cair" durante uma sessão de teste (módulo `mts.ko` bugado
desliga Orbis), o usuário precisa re-cli­car no joystick no User Guide. Para
evitar isso durante sessões longas de depuração GBE/UART, criar um script que:

- mata o GoldHEN atual no PS4 via SSH (se processo GoldHEN exposing `/data/GoldHEN/`)
- reabre `User Guide` por `sceAppLaunch` interno (algumas versões do GoldHEN
  expõem um IPC, ou um simples kill do processo webkit força re-abertura)
- como fallback: usar `ps4-payload-sdk` para lançar um pequeno payload que
  chama `sceSystemServiceLaunchWebBrowser` com URL `manuals.playstation.net`

Estado: **investigação** — o Orbis bloqueia `sceSystemServiceLaunchWebBrowser`
para apps não-ShellUI, mas existem payloads da scene que contornam. Marcar
como "opcional" — só vale se a Fase 1 funcionar.

**2.3. Documentar:**

- Atualizar `consolidado/BACKLOG.md:215` ("Jailbreak via Blu-ray instável") →
  marcar como **CLOSED — workaround = Web-Host**.
- Atualizar `consolidado/BACKLOG.md:205` ("Boot via disco AIO — erros R/W") →
  marcar como **OBSOLETO** (disco não mais usado).
- Criar `memory/migracao-webhost-12.52-sucesso.md` (ou `*-falha.md`) com:
  - Versão do PSFree usada (MD5)
  - Versão do GoldHEN.bin (MD5 — comparar com o do disco AIO)
  - Latência média de injeção (cold-boot → "GoldHEN Loaded" notification)
  - Taxa de falha em N tentativas (se >5%, regressar pra Fase 1.3-b pois
    pode ser versão PSFree incompatível com 12.52)

### Fase 3 — Manter disco Blu-ray como fallback só em emergência (opcional)

Se a Fase 1 funcionar, a decorrência natural é parar de usar o drive óptico
para jailbreak. O disco AIO só é útil como:
- Boot Linux offline sem rede WiFi disponível (muito raro)
- Fallback se o PC host cair

Se ainda quiser manter o disco funcional como fallback:
- Regravar BD-R em **2x** (não 8x/16x) — pior throughput, melhor compatibilidade
  de leitura em drives desgastados (`BACKLOG.md:211`)
- Validar com disco virgem (não o velho) para isolar mídia vs scanner/leitor

## Critérios de sucesso (gate de cierre)

- [ ] Web-Host sobe em <10s com `scripts/webhost_start.sh` e derruba com
      `scripts/webhost_stop.sh` (sem resíduo de portas/processos)
- [ ] 5 boots frios consecutivos usando só o User Guide, sem nenhum `-1`
- [ ] Latência médio cold-boot → "GoldHEN Loaded" < 8s
- [ ] Após GoldHEN.active, SSH em `192.168.6.128` responde em <3s
- [ ] AutoPayload boot do `kexec-loader.bin` funcional — Linux boota sem
      nenhuma ação manual adicional

## Riscos e mitigacões

| Risco | Chance | Impacto | Mitigação |
|-------|--------|---------|-----------|
| `manuals.playstation.net` URL mudou em FW 12.52 | Médio | Alto | Captura UART do User Guide mostrará o nome do host acessado; ajustar dnsmasq |
| PSFree 12.52 não existe publicamente ainda | Baixo | Alto | Confirmar antes na psx-place; se não, fallback p/ trigger via jogo mas com payload atualizado (sem disco AIO) |
| PC host WiFi perde DHCP quando roteador muda | Baixo | Médio | Fixar IP estático em `wlp0s20f3` (192.168.6.100) |
| Mudar DNS do PS4 invalida gateway | Baixo | Médio | Manter DHCP e gateway automáticos, só substituir DNS |
| Firewall do PC bloquear :80 da subnet 192.168.6.0/24 | Médio | Médio | `webhost_start.sh` já abre via iptables/nft |
| `eth0` PS4 (192.168.0.x) confunde a topologia | Baixo | Baixo | AGENTS.md:88: WiFi é admin, eth0 é teste; Web-Host usa só WiFi |

## Referências (preencher quando baixar arquivos em 1.3)

- [ ] PSFree commit/version usado (MD5)
- [ ] GoldHEN.bin 12.52 MD5 (igual ao disco AIO? conferir com
      `consolidado/MASTER_CONSOLIDADO.md` se registrado)
- [ ] Issue oficial GoldHEN #366 (nanoDNS + PSFree)
- [ ] Issue oficial GoldHEN #295 ("no kernel exploit in 13.00+"→ 12.52 ACEITA)
- [ ] Discos AIO UFC "X=Poops" técnica = splat heap / dual/triple free classic
- [ ] psx-place threads relevantes

## Próximos passos imediatos

1. Confirmar o usuário vai rodar `1.1` (pacman install dnsmasq) no PC host
2. Definir path de 1.3: (a) baixar scene, (b) reaproveitar do disco AIO,
   (c) baixar host azif/Karo. Recomendação: **(b) primeiro para garantir
   compatibilidade** com o GoldHEN.bin já testado.
3. Rodar `1.4` (subir host), configurar DNS no PS4 em `1.5`, testar em `1.6`.
