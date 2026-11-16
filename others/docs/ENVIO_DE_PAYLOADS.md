# Envio de payloads para o PS4 (loader Orbis / GoldHEN)

> Projeto: PS4 Linux Baikal — procedimento **canônico** de injeção de payload.
> Script oficial: [`../scripts/ps4_send_payload.sh`](../scripts/ps4_send_payload.sh)
> Regra resumida: [`../../AGENTS.md`](../../AGENTS.md) → "Envio de payload para o PS4".
>
> **Escopo:** enviar um ELF para o PS4 rodando **Orbis** (antes do `kexec` para Linux) e
> recuperar arquivos que o payload escreveu no console.

---

## 1. Onde o payload roda (e onde NÃO roda)

| Ambiente | Tem loader? | IP / MAC no WiFi `192.168.6.0/24` | Observação |
|----------|-------------|----------------------------------|------------|
| **Orbis + GoldHEN** | ✅ BinLoader `:9090`, FTP `:2121`, klog `:3232` | **`192.168.6.130`** · MAC `6A:FA:C4:EA:34:9C` | único ambiente em que um payload pode ser injetado |
| **Linux (pós-`kexec`)** | ❌ | **`192.168.6.128`** · MAC do `wlan0` (diferente) | as portas 9090/2121 não existem; o exploit do Orbis morreu no `kexec` |

Consequência prática: **todo payload é descartável e morre no reboot/kexec**. Se o PS4 já está
no Linux, é preciso reiniciar no Orbis, ativar o GoldHEN, injetar, e só então voltar ao Linux.

### 1.1 Como saber em qual ambiente o console está (sem tocar na porta do loader)

**O IP muda quando o Linux sobe.** Orbis e Linux usam DHCP e MACs diferentes no mesmo WiFi:

| Quem responde | Ambiente | O que fazer |
|---------------|----------|-------------|
| `192.168.6.130` | **Orbis + GoldHEN** | pode injetar payload (`:9090`) e puxar arquivos (`:2121`) |
| `192.168.6.128` | **Linux rodando** | SSH `root@192.168.6.128` (senha `ps4`); **não** existe loader |
| nenhum dos dois | desligado, fora da rede ou outro IP (DHCP mudou) | conferir o console/roteador antes de tentar |

```bash
ping -c 1 -W 1 192.168.6.130   # responde → Orbis (loader disponível)
ping -c 1 -W 1 192.168.6.128   # responde → Linux (sem loader; use SSH)
```

> ⚠️ **Não conclua "PS4 desligado" só porque `192.168.6.128` não responde** — se o console está
> no Orbis ele está em `.130`. E não conclua "payload enviado com sucesso" só porque houve ping:
> ping só responde à pergunta *qual sistema está rodando*.
>
> Se o IP mudar (reserva DHCP expirada), passe `--ip <novo-ip>` para o script.

Consequência para diagnóstico: a diferença de IP/MAC é o **teste mais barato** de "o console está
no Orbis ou no Linux" — dois pings, sem consumir o `accept()` único do BinLoader.

---

## 2. Portas do GoldHEN (não confundir)

| Porta | Serviço | Uso |
|-------|---------|-----|
| **9090** | **BinLoader** (payload ELF) | o loader em si — usada por `ps4_send_payload.sh` |
| **2121** | FTP (anônimo) | recuperar arquivos do console (`/data/...`, `/mnt/usb0/...`) |
| **3232** | klog | leitura de log do kernel Orbis (opcional, para debug) |

> Fonte: README oficial do GoldHEN (`FTP Server on 2121 port`, `BinLoader Server on 9090 port`,
> `Klog Server on 3232 port`).

⚠️ **`9020`/`9021` NÃO são do GoldHEN.** Essas portas pertencem ao `elfldr` do
[`ps4-payload-dev`](https://github.com/ps4-payload-dev/sdk) (o `orbis-deploy` do SDK usa 9021 por
padrão). Se algum dia for usado **esse** loader, aí sim a porta é 9020/9021 — mas nunca as duas
coisas ao mesmo tempo.

⚠️ **O BinLoader é experimental** (aviso do próprio GoldHEN): payload mal-formado pode travar o
console. Só envie binário conferido por hash e de fonte conhecida.

---

## 3. Procedimento padrão (rede)

### 3.1 Preparar o console

1. PS4 ligado no **Orbis** (não no Linux) — confirmado por `ping 192.168.6.130` (§1.1).
2. GoldHEN ativo (v2.4b18.8 ou mais novo).
3. PC e PS4 na mesma rede. No WiFi do projeto o PS4 **no Orbis** é `192.168.6.130`
   (MAC `6A:FA:C4:EA:34:9C`); depois do `kexec` ele passa a `192.168.6.128`.

### 3.2 Validar (sem enviar nada)

```bash
cd /mnt/hdauxiliar/ps4-linux-baikal
./others/scripts/ps4_send_payload.sh --check others/tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin
```

O script confere: `socat`/`readelf` instalados, ELF64 x86-64 válido, tamanho plausível e
presença do console por **ICMP**.

> **ICMP OK não prova que o loader está no ar** — o Linux também responde ping. A prova real é o
> envio dar certo + notificação na TV.

### 3.3 Enviar

```bash
./others/scripts/ps4_send_payload.sh others/tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin
# equivalência manual (se o script não existir):
#   socat -t 10 - TCP:192.168.6.130:9090 < payload.bin        # Orbis, não o Linux
```

### 3.4 Confirmar

- **TV do PS4:** notificação no canto superior esquerdo com a mensagem do payload.
- **klog (opcional):** `nc 192.168.6.130 3232` (ler apenas; é outro serviço, não o loader).

### 3.5 ⚠️ Após rodar um dumper de memória (EAPDumper ou similar): **reboot obrigatório**

Dumperes de memória (como o EAPDumper) **travam a memória do Orbis após a execução**. Consequências:

| O que acontece | Por quê | O que fazer |
|----------------|---------|-------------|
| Segundo envio de payload falha (`accept()` não aceita mais) | o loader/estado de memória ficou inconsistente | **reboot do console** |
| Tentativa de novo `--ftp-get` ou novo envio sem reboot | memória travada, serviço do GoldHEN prejudicado | reiniciar no Orbis, reativar GoldHEN |
| Quer voltar ao Linux | o kernel Orbis já está "usado" pelo dumper | reboot → exploit → GoldHEN → `kexec` para Linux 7.0 |

**Regra de ouro:** depois de rodar qualquer dumper de memória no Orbis, **não tente enviar outro payload nem fazer FTP antes de reiniciar o console**. O próximo ciclo é: reboot → Orbis → GoldHEN → (opcional novo payload) → kexec → Linux.

### 3.6 Recuperar os arquivos gerados (FTP)

```bash
./others/scripts/ps4_send_payload.sh --ftp-get /data/hddeap/eap_hdd_key.bin
# ou: curl -s ftp://192.168.6.130:2121/data/hddeap/eap_hdd_key.bin -o eap_hdd_key.bin
```

### 3.7 Voltar para o Linux

Reboot/exploit → `kexec` para o Linux 7.0 → provisionar o que o payload produziu
(ex.: `/etc/ps4_keys.bin` com `chmod 600`).

---

## 4. Procedimento alternativo (USB, sem rede)

1. Copiar o `.bin` para a raiz de um pendrive **FAT32/exFAT** montado pelo Orbis como `/mnt/usb0`.
2. No GoldHEN, abrir o menu de **Payloads** e carregar o arquivo do USB.
3. O payload escreve o resultado no próprio USB (quando implementa) e/ou em `/data/...`.

Útil quando o WiFi do console não está configurado — mas exige pendrive e navegação no menu.

---

## 5. Regras e armadilhas (todas já nos custaram tempo)

| Regra | Por quê |
|-------|---------|
| **Nunca** testar a porta do loader com `nc -z`, `telnet` ou `curl -v` | o BinLoader tem `accept()` **único**; o teste consome a conexão e o envio real falha até reiniciar o GoldHEN |
| Um envio por sessão do GoldHEN | idem: depois do primeiro payload o servidor pode não aceitar outra conexão |
| Não usar `ssh`/`scp` para trocar payload | no Orbis **não há SSH** (o `sshpass -p ps4 ssh root@192.168.6.128` é só para o Linux) |
| **Não usar o IP do Linux (`.128`) para payload** | no Orbis o console está em **`.130`**; mirar `.128` acerta o Linux (sem loader) ou nada |
| Enviar somente binário conferido (`sha256sum`) | BinLoader executa código em ring 0 do Orbis |
| Payload > 8 MiB | loaders do PS4 costumam rejeitar; o script avisa |
| Payload que escreve em disco | só grava em partições do Orbis (`/data`, `/mnt/usb0`); nada persiste no rootfs Linux |
| **Dumper de memória (EAPDumper etc.) exige reboot após rodar** | a memória do Orbis fica travada; segundo envio/FTP falha até reiniciar o console |

---

## 6. Caso concreto do projeto: chave EAP (`EAPDumper`)

Obtém a chave EAP/ERK do HD interno (necessária para montar `sda27`/`sda29`/`sda25` no Linux — `sda13` não é montável).
Ver [`../tools/ps4_hdd_tools/README.md`](../tools/ps4_hdd_tools/README.md) e
[`BACKLOG_MOUNT.md`](BACKLOG_MOUNT.md) (MOUNT-09).

```bash
# 1) compilar (uma vez)
./others/tools/ps4_hdd_tools/build_eapdumper.sh
#    → EAPDumper/EAPDumper.bin, sha256 52e6617ee5ceff727a807c8a3ba925cc5d5fffeff3fd770dad1d76fb5975eb0f

# 2) PS4 no Orbis + GoldHEN, e enviar
./others/scripts/ps4_send_payload.sh others/tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin

# 3) puxar a chave (32 bytes) e provisionar no Linux
./others/scripts/ps4_send_payload.sh --ftp-get /data/hddeap/eap_hdd_key.bin
#    (o script normaliza, valida por sha256 e instala em /etc/ps4-keys/eap_hdd_key.bin)
PS4_SSH_PASS=ps4 ./distro/scripts/provisiona-chave.sh /tmp/opencode/eap_hdd_key.bin --ssh root@192.168.6.128
```

O payload também grava `/data/hddeap/eap_hdd_key.hex` (texto) e `eap_offset_scan.txt`
(relatório do *sniper scan*). Em FW 12.52 — fora da tabela `EAP_OFFSETS` — o scan cobre
`0x2600000`–`0x2900000`, que inclui o offset real `0x26C4CF0`.

🔑 **Chave obtida ao vivo (2026-11-13):** 32 bytes, sha256 `990c1aa3…c8bf`. Cópias: `.env.keys`
na raiz do repo (gitignored, `EAP_HDD_KEY`) e **`~/ps4-keys/`** no host (pasta 700, `eap_hdd_key.bin`
+ `.hex` + `LEIA-ME.txt`). No console fica em `/etc/ps4-keys/eap_hdd_key.bin` (modo 600); o payload
original fica em `/data/hddeap/eap_hdd_key.bin` no Orbis. **A chave em si não é registrada em
documento nenhum do repo.**

---

## 7. Diagnóstico de falhas

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| `Connection refused` no envio | PS4 no Linux, GoldHEN inativo ou BinLoader desligado | reiniciar no Orbis, ativar GoldHEN/BinLoader |
| Envio "OK", mas nenhuma notificação na TV | payload incompatível com o FW, ou morreu antes de notificar | conferir hash/binário, testar payload mínimo |
| Segundo envio falha sempre | `accept()` único já consumido | reiniciar o GoldHEN (ou o payload que escutava) |
| `ping` falha | IP errado, console desligado, ICMP bloqueado | `--ip`, ligar console, `--no-ping` |
| FTP `530`/timeout | FTP desligado no GoldHEN | ativar FTP (porta 2121) |
| Arquivo baixado com 0 byte | payload não escreveu (erro interno) | ver klog `:3232` e a notificação na TV |

---

## 8. Histórico (scripts antigos — perdidos, não usar)

Os antigos `send_payload_loop.py` (porta 9090), `inject.sh`, `inject_diag.sh` e
`receive_kmem_dump.py` do diretório `scene-kmem-dumper/` **não existem mais** no repositório
(removidos em 2026-11-11 junto com a limpeza de `others/memory/`). O que sobrou deles é a
narrativa em [`ESTADO_E_HISTORICO.md`](ESTADO_E_HISTORICO.md) (§ "Contexto de Payloads").
Este documento + `ps4_send_payload.sh` substituem todos eles.
