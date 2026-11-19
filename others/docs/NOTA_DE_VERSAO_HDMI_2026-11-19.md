# Nota de versão — a tela preta do HDMI foi vencida

**Tag:** `20261119-hdmi-events-clean` · **Data:** 19/11/2026 · **Console testado:** PS4 Pro (Baikal)

## Em uma frase

Tirar o cabo HDMI e colocá-lo de volta agora **traz a imagem de volta sozinha**, sem comando, sem
reiniciar e sem ninguém digitar nada.

## O problema

Quem usa Linux no PS4 conhece: você desliga a TV ou troca o cabo de entrada, volta, e a tela fica
**preta para sempre**. O Linux continua vivo (a rede responde, o SSH funciona), só a imagem não volta.
O único jeito era reiniciar o console, ou entrar por SSH e mandar o servidor gráfico trocar a resolução
(720p e de volta para 1080p) — um quebra-galho que nem sempre funcionava.

O pior: o Linux dizia que o monitor **continuava conectado**, mesmo com o cabo no chão.

## O que parecia o problema (e não era)

Gastamos muito tempo atrás de pistas que se mostraram becos sem saída:

- **O HDCP (proteção de conteúdo)?** Não. A imagem não depende dele.
- **Reescrever os registradores do chip da ponte HDMI?** Não adiantou: o chip desfaz a escrita sozinho.
- **Olhar um bit do chip que "avisa" quando há monitor?** Parecia ótimo, mas ele se comportava de jeito
  diferente a cada teste. Uma versão do kernel que vigiava esse bit **não chegou a iniciar o Linux**
  (a causa exata nunca foi isolada) e foi descartada.
- **Um programa que fica vigiando o cabo por fora do kernel?** Conseguia ler os registradores, mas nunca
  via de verdade o momento em que o cabo era ligado.

## A virada

Dois testes simples mudaram tudo. Primeiro, colocamos pequenas mensagens de diagnóstico dentro do kernel
nos pontos onde ele poderia perceber o cabo. Resultado ao desligar e religar o monitor: **silêncio total**.
O kernel não era avisado de nada. Ele estava **cego** ao cabo.

Segundo, quando a imagem voltava com a troca de resolução, o kernel executava uma "reconfiguração
completa" da saída de vídeo. Era isso que o chip da ponte precisava, e não uma chamada de "detectar
monitor". Depois que o cabo é religado, o monitor é o mesmo, o EDID (a "identidade" dele) é o mesmo e a
resolução é a mesma, então o kernel achava que não havia nada a refazer.

Faltava saber **como o kernel poderia ser avisado**. Foi aí que a pesquisa em projetos de outras pessoas
ajudou muito: outros desenvolvedores do PS4 Linux já tinham descoberto que o **firmware do chip da ponte
HDMI manda um aviso toda vez que o cabo é ligado ou desligado** — mas só **depois que o sistema pede
para receber esses avisos** com um comando especial. O nosso kernel nunca tinha pedido. Era como ter um
interfone que toca, mas deixar o aparelho desligado.

Mandamos o comando ao vivo e testamos: ao desligar e religar o monitor, os avisos chegaram, um para cada
vez, e com o EDID do monitor junto.

## O que mudou

O kernel agora:

1. **Liga os avisos** do chip da ponte HDMI quando o sistema inicia.
2. **Percebe quando o cabo sai**: o conector passa a constar como desconectado, como deveria.
3. **Percebe quando o cabo volta**, espera meio segundo para o contato se firmar e então
4. **refaz a configuração completa da saída de vídeo**, o que traz a imagem de volta.

Tudo isso acontece dentro do kernel, sem programa extra e sem nada para configurar.

## Quanto já testamos

- **9 ciclos de desligar e religar o cabo** em sequência, sem nenhum comando manual: a imagem voltou
  **todas as vezes**.
- **2 inicializações a frio** com a correção: sem problemas.
- Nenhuma falha no sistema, nenhum erro de kernel (`BUG`, `Oops`) e nenhum serviço que tenha deixado de iniciar.

## O que ainda estamos verificando

Somos honestos sobre os limites:

- Mais inicializações a frio seguidas (fizemos 2, queremos pelo menos 3).
- Casos de borda: cabo fora por muito tempo, monitor desligado pelo botão, cabo ligado enquanto o console
  ainda está no sistema original.
- O **console serial (UART)** de diagnóstico para de gravar cedo na inicialização. Isso não afeta o uso
  normal, mas atrapalha a investigação quando algo dá errado, e é uma tarefa em aberto.
- Só testamos em **um console** (PS4 Pro). Em outros modelos, o comportamento pode variar.

## Como voltar atrás

Esta versão não apaga nada da anterior. Se algo der errado, a versão `20261117-mtsx` (Ethernet com fio
funcionando, sem esta correção) continua disponível e pode ser reinstalada:

```bash
sudo ./distro/deploy-boot-ftp-7.0.sh 20261117-mtsx --internal-root <pasta> --vram 1024
```

(Os detalhes completos estão no `AGENTS.md`, no `BACKLOG.md` e nos registros de teste do banco
`others/rea/ps4_hardware_memory.db`, testes 162 a 171.)

## Os bastidores, para quem curte detalhe técnico

- O chip é um conversor DisplayPort → HDMI da Panasonic (MN864729). Ele conversa com o processador pelo
  ICC, o canal interno de mensagens do console.
- Os avisos de cabo chegam como mensagens ICC (`major 0x10`, `minor 0x8001`). O primeiro byte de dados é
  o serviço (`0x10`) e o segundo é o código (`1` = cabo saiu, `2` = cabo entrou, este com o EDID de 256
  bytes anexado). Eles só são enviados depois do comando de fila `5/4` com `enable=1`.
- O patch é o `kernel/patches/ps4-bridge-hdmi-events.patch`: um ponto de registro de handlers no driver
  ICC (`ps4-bpcie-icc.c`), o tratamento do evento em `ps4_bridge.c` e `drm_helper_resume_force_mode()`
  para a reconfiguração.
- Registrador `0x7008` (bit 3): monitor presente. Medimos `04` com o cabo fora e `1c` com o cabo ligado.
  Serve como checagem de apoio, mas não é o sinal usado pelo patch.

## Agradecimentos

Esta correção só saiu porque outras pessoas abriram seu trabalho:

- **HackSucks / caramel** — descobriu os avisos ICC de HDMI e o comando que os ativa.
- **striker91n / ps4-linux-7.3** — apontou que, depois do replug, o que resolve é a reconfiguração
  completa da saída de vídeo, e explicou por quê.

Se você usa o PS4 Linux e tem um desafio parecido, **documente o que não funcionou**. Metade desta vitória
veio de saber exatamente quais caminhos já estavam fechados.
