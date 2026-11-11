# Plano: Investigação e Correção do RX no driver `mts.ko` (GBE Baikal)

## Contexto

TX já está funcional e commitado (`20dd14b fix(mts): corrige lógica de reclamação TX`):
descobrimos ao vivo que o bit `MTS_DESC_OWN` tinha semântica invertida em relação
ao que o comentário original alegava — o hardware sinaliza conclusão de TX
**limpando** OWN para 0, não setando para 1. Corrigimos `mts_tx_reclaim()` e agora
`TX packets`/`TX bytes` incrementam corretamente e o ping funciona.

Falta RX. O teste ao vivo mostrou uma contradição que precisa ser resolvida antes
de qualquer mudança de código: **o ping teve 100% de sucesso (5/5 pacotes), mas
`ifconfig eth0` reporta `RX packets: 0`**. Isso só é possível se:

- (a) outra interface está respondendo no lugar do eth0 — o CLAUDE.md confirma que
  o boot padrão sobe **WiFi automático + Ethernet** simultaneamente, então é
  plausível que a resposta do ping esteja chegando via `wlan0` na mesma sub-rede
  (192.168.6.0/24), não via `eth0` de verdade; ou
- (b) o RX real está funcionando (frames chegam, `napi_gro_receive` é chamado) mas
  o contador `dev->stats.rx_packets` está com o mesmo tipo de bug cosmético que já
  corrigimos no TX; ou
- (c) há um bug real de lógica (possivelmente o mesmo tipo de inversão do bit OWN)
  no caminho de RX, e nenhum frame está sendo processado pelo driver de fato.

Hoje não há como diferenciar essas três hipóteses porque **não existe nenhuma forma
de inspecionar o hardware em tempo real após o boot**: `ethtool` não está instalado
no rootfs do PS4, e a única leitura dos contadores clear-on-read de hardware
(`MTS_CNT_PKTS`/`BYTES`/`PKTS2`/`BYTES2`, offsets `0x100/0x104/0x128/0x12c`) acontece
uma única vez em `mts_probe()` (`mts.c` ~linha 1500), **antes de qualquer tráfego**.
Confirmado por exploração: nenhum arquivo em `memory/` documenta esse achado
específico — é informação nova desta sessão.

Decisões de escopo já confirmadas com o usuário:
- **Adicionar um mecanismo de diagnóstico permanente** no driver (não é
  gambiarra temporária a remover depois).
- **IRQ real fica para depois** — RX/TX continuam via NAPI + timer de polling de
  10ms (`mts_poll_timer`), que já está funcionando para TX. O handler de IRQ
  (`mts_interrupt`, `mts.c` ~linha 1355) permanece como placeholder por ora.

Refinamento de implementação em relação à pergunta original: em vez de **debugfs**
(que depende de `CONFIG_DEBUG_FS` e de `/sys/kernel/debug` estar montado — incerto
neste initramfs), vou expor o diagnóstico como um **atributo sysfs read-only** no
próprio dispositivo PCI (`/sys/bus/pci/devices/0000:00:14.1/mts_regs`, também
acessível via `/sys/class/net/eth0/device/mts_regs`). Sysfs está sempre disponível
em qualquer kernel Linux moderno, sem dependência de montagem extra, e o resultado
para o usuário é o mesmo: `cat` puro, sem precisar de ferramentas adicionais.

---

## Fase 0 — Isolar a causa raiz por via telnet (sem mudar código)

Objetivo: decidir entre as hipóteses (a)/(b)/(c) acima com o mínimo de esforço,
antes de tocar em uma linha de C.

1. `ip addr show` (ou `ifconfig -a`) e `ip route show` — conferir se `wlan0`
   também está `UP` com IP na faixa `192.168.6.0/24` ou com rota para
   `192.168.6.100`.
2. Testar isolando a interface, sem precisar derrubar o WiFi:
   `ping -I eth0 -c 5 192.168.6.100` (busybox `ping -I` faz bind ao device,
   restringindo envio E recebimento àquela interface).
   - Se falhar/timeout com `-I eth0` mas funcionar sem `-I`: confirma hipótese
     (a) — a resposta estava mesmo chegando por `wlan0`. RX do `eth0` está
     genuinamente quebrado → segue para Fase 1/2/3 tratando como bug real.
   - Se continuar funcionando 100% com `-I eth0`: RX já está entregando frames
     de verdade ao stack — o problema é só contabilização (hipótese b) → escopo
     da correção fica bem menor (só stats, sem mexer na lógica OWN).
3. Complementar com `arping -I eth0 -c 3 192.168.6.100` se `arping` existir no
   busybox (`which arping`) — teste puramente L2, sem ambiguidade de rota.
4. Registrar o resultado no arquivo de memória (Fase 6) antes de prosseguir,
   já que essa é a descoberta mais importante do dia.

---

## Fase 1 — Adicionar diagnóstico permanente em sysfs

**Arquivo:** `drivers_mts/mts.c` (principal), `drivers_mts/mts.h` (se precisar de
campo extra em `struct mts_priv`, provavelmente não).

Adicionar um atributo `DEVICE_ATTR_RO(mts_regs)` cujo `show()`:
- Lê ao vivo (não só no probe) os registradores-chave: `0x00, 0x04, 0x34, 0x38,
  0x50, 0x54, 0x5c, 0x70, 0x7c` e os 4 contadores clear-on-read
  (`MTS_CNT_PKTS/BYTES/PKTS2/BYTES2`).
- Imprime `mp->tx_idx`, `mp->tx_clean`, `mp->rx_idx`.
- Dump dos primeiros ~4 descritores TX e RX (`ctl`, `d1`, `d2` de cada).
- Hexdump dos primeiros ~64 bytes de 2-3 buffers RX (ex: os slots ao redor do
  `rx_idx` atual) — isso prova diretamente se o hardware escreveu dados reais no
  buffer de DMA, **independente** da interpretação do bit OWN.

Registrar via `device_create_file(&pdev->dev, &dev_attr_mts_regs)` em
`mts_probe()` (depois que `mp->regs`/anéis já estão mapeados, stage ≥ 2) e
remover com `device_remove_file()` em `mts_remove()`. Reaproveitar a lógica já
existente em `mts_dump_regs()` (`mts.c` ~linha 1286) como base, só trocando o
destino de `dev_info()` para `seq`/buffer do atributo sysfs.

Compilar com `scripts/build_mts_module.sh` (já validado no fluxo anterior) e
testar `insmod` + `cat /sys/bus/pci/devices/0000:00:14.1/mts_regs` antes de
seguir para o teste de tráfego.

---

## Fase 2 — Reproduzir teste isolado com cross-check de hardware

1. `insmod mts.ko stage=4`, `ifconfig eth0 up`.
2. `cat mts_regs` → snapshot "antes" (contadores devem estar zerados/baixos).
3. Rodar o teste decidido na Fase 0 (`ping -I eth0` ou `arping -I eth0`).
4. `cat mts_regs` → snapshot "depois". Comparar:
   - Contador de hardware `MTS_CNT_PKTS`/`PKTS2` incrementou? (prova que o MAC
     recebeu algo fisicamente, independente do driver)
   - Buffers RX (hexdump) têm bytes não-zero condizentes com um frame Ethernet
     real (destino = MAC do PS4 `2c:cc:44:3f:69:5f`, EtherType 0x0800/0x0806)?
   - Bit OWN dos descritores RX próximos ao `rx_idx` mudou de estado depois do
     tráfego?
   - `dev->stats.rx_packets` (via `ifconfig eth0`) bateu com o contador de
     hardware?

---

## Fase 3 — Diagnosticar causa raiz (decisão por cenário)

Com os dados da Fase 2, cai em um dos três cenários já mapeados no Contexto:

- **(a) Wifi respondendo**: já resolvido só isolando a interface na Fase 0 —
  não é bug de driver, é artefato de teste. Documentar e não mexer no código de
  RX além de eventualmente ajustar o método de teste padrão do projeto (sempre
  usar `-I eth0` daqui pra frente, ou desativar wlan0 durante testes de eth0).
- **(b) Stats desatualizadas, dados chegando certo**: bug isolado e pequeno —
  só falta somar `dev->stats.rx_packets`/`rx_bytes` no ponto certo dentro de
  `mts_rx_clean()` (`mts.c` ~linha 1120-1166), sem mexer na condição do OWN.
- **(c) Driver não processa nenhum descritor**: reexaminar a condição
  `if (!(ctl & MTS_DESC_OWN)) break;` em `mts_rx_clean()`. **Atenção**: ao
  contrário do TX, inverter cegamente essa condição é arriscado — o anel RX é
  inicializado hoje com `OWN=0` em todos os descritores (`mts_setup_rings()`,
  `mts.c` ~linha 414-427, comentário "buffer vazio, aguardando pacote"). Se o
  hardware realmente sinaliza "pacote pronto" limpando OWN (em vez de setando),
  então o estado inicial (`OWN=0` em todos) pareceria falsamente "cheio" desde o
  instante zero — o que não bate com "zero pacotes processados desde sempre".
  Por isso a correção aqui (se for o caso) provavelmente exige **também**
  inverter a inicialização do anel RX (`OWN=1` = vazio/aguardando, análogo ao TX),
  não só a condição de leitura — mudança em par, testada com o hexdump da Fase 2
  como oráculo de verdade (só aceitar a mudança se o hexdump mostrar dados reais
  E o driver passar a processá-los).

---

## Fase 4 — Aplicar a correção indicada

Implementar exatamente a mudança apontada pela Fase 3 (uma das três, não todas).
Recompilar com `sudo scripts/build_mts_module.sh`, subir via o servidor HTTP já
usado nesta sessão (`python3 -m http.server 8000` em
`drivers_mts/build/`), `wget` + `rmmod`/`insmod` no PS4 via telnet
(`192.168.6.128`, porta 23).

---

## Fase 5 — Validação end-to-end

1. `ping -I eth0 -c 10 192.168.6.100` → confirmar `RX packets` > 0 e igual (ou
   muito próximo) ao número de respostas recebidas.
2. `ping -I eth0 -s 1400 -c 5 192.168.6.100` → payload maior, valida
   fragmentação/tamanho de buffer RX (`MTS_RX_BUF_SIZE = 0x600`).
3. Rajada rápida `ping -I eth0 -c 100 -i 0.05 192.168.6.100` → stress leve,
   confirmar que a fila TX não trava (`netif_stop_queue` não fica preso) e que
   RX não perde pacotes/não estoura o anel (256 descritores).
4. Se tudo acima passar: tentar `udhcpc -i eth0` (objetivo original do
   `progress_report.md`) para validar o caso de uso real (DHCP), já que é o
   critério de sucesso mencionado desde o relatório inicial desta sessão.

---

## Fase 6 — Persistir e documentar

1. Remover qualquer `dev_info`/log temporário de debug que sobrar no código
   (manter só o necessário, no padrão do resto do driver).
2. `git commit` da correção de RX + do atributo sysfs `mts_regs`, seguindo o
   mesmo padrão de mensagem usado no commit `20dd14b`.
3. Atualizar `CLAUDE.md` (seção "Estado Atual do Projeto") e criar um arquivo
   novo em `memory/` documentando: a causa raiz real do RX (qual dos 3
   cenários), a semântica final e verificada do bit OWN para TX **e** RX lado a
   lado, e a existência do novo atributo `mts_regs` como ferramenta de
   diagnóstico permanente para investigações futuras (link, IRQ, etc.).

---

## Observações de risco / reversibilidade

- Todos os comandos da Fase 0/2/5 são não-destrutivos (leitura, ping, ifconfig).
- `rmmod`/`insmod` repetido já é o fluxo padrão usado nesta sessão, sem risco
  adicional.
- Se a Fase 0 indicar necessidade de derrubar `wlan0` temporariamente
  (`ifconfig wlan0 down`), isso é reversível (`ifconfig wlan0 up` depois) — vou
  avisar antes de executar, já que mexe em conectividade ativa do console.
- Nenhuma mudança aqui toca em payload de injeção (`send_payload_loop.py`) nem
  na Regra de Ouro da Injeção — é tudo debug de um kernel Linux já
  inicializado e acessível via telnet.
