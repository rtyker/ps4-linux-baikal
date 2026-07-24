# Instruções para Agentes — PS4 Linux Baikal

## 🔴 PRIORIDADE ALTA — Topologia de Rede (NUNCA confundir)

- **WiFi (`wlan0`, subnet `192.168.6.0/24`) é SÓ PARA TELNET/acesso administrativo ao console.** IP típico do PS4: `192.168.6.128`.
- **Rede cabeada (`eth0`, driver `mts.ko`) é a rede sob teste — IP FIXO `192.168.0.2`.** Host do PC no Ethernet: `192.168.0.1` (interface `enp60s0`).
- **NUNCA testar o `eth0` usando a subnet do WiFi (`192.168.6.x`).** Um ping "funcionando" para `192.168.6.100`/`192.168.6.128` passa pelo `wlan0`, não prova nada sobre o `eth0`.
- **Todo teste de RX/TX do driver `mts.ko` deve usar a subnet `192.168.0.0/24`**: `ping -c N 192.168.0.2` do lado do host, ou `ping -I eth0 -c N 192.168.0.1` do lado do PS4.
- Telnet continua sendo feito via WiFi (`192.168.6.128:23`) mesmo durante testes de `eth0` — são canais independentes, não há conflito em usar os dois ao mesmo tempo.

## Conexão via Telnet

**Preferência do usuário:** Use o script `./scripts/telnet_ps4.sh` para conectar via telnet ao console PS4.

Em vez de criar scripts Python ad-hoc (`test_*.py`, `send_telnet_commands()`, etc.), sempre invoque:

```bash
./scripts/telnet_ps4.sh
```

Este script encapsula:
- Endereço do PS4: `192.168.6.128`
- Porta: `23`
- Tratamento de conexão, timeouts e limpeza
- Histórico de comandos (se configurado)

**Exceção:** Se o script não existir ou estiver quebrado, avisar o usuário explicitamente antes de criar alternativas.

---

## Compilação de Módulos

Use `sudo scripts/build_mts_module.sh` (já validado) para compilar o driver `mts.ko`.

Não criar `Makefile` ad-hoc nem comandos `gcc` diretos — o script já encapsula opções de cross-compile e flags corretas.

---

## Servidor HTTP para Download

O padrão é `python3 -m http.server 8000` na pasta `drivers_mts/build/` para servir o `.ko` compilado ao PS4.

Endereço: `http://192.168.6.100:8000/mts.ko`

---

## Evitar Repetição de Scripts

Se um procedimento está em `scripts/` (telnet, build, deploy), **sempre reutilizar** em vez de duplicar como `.py` temporário em `/tmp`.

Documentar novas utilidades em `scripts/` se forem reutilizáveis em múltiplas sessões.

---

## Deploy do mts.ko

Script: `./scripts/deploy_mts.sh [push|test]`

- **push**: Compila (se necessário), sobe HTTP server, envia mts.ko via wget, insmod stage=4
- **test**: Configura eth0 (192.168.0.2), ping -I eth0 192.168.0.1, captura mts_regs + dmesg RX_CLEAN

Uso:
```bash
./scripts/deploy_mts.sh push
./scripts/deploy_mts.sh test
```

Requer: expect, python3, netcat (nc) no host. PS4 precisa ter wget, base64, insmod.
