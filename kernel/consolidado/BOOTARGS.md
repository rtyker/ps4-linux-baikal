# Guia Completo de Parâmetros de Boot (bootargs.txt) para PS4 Linux

O arquivo `bootargs.txt` (localizado na partição FAT32 de boot, `/dev/sda1`) serve para passar parâmetros de configuração diretamente para a linha de comando do Kernel Linux durante a inicialização (kexec). Ele permite personalizar o comportamento de drivers de vídeo, áudio, energia e rede para se adaptarem perfeitamente ao hardware customizado do PS4.

> [!NOTE]
> Todos os testes descritos e validados neste documento foram realizados utilizando uma **TV** como monitor primário. Sinais de TV são geralmente mais tolerantes a handshakes e resoluções do que monitores de computador comuns.

> [!TIP]
> Para testes com **monitor**, veja a pasta `../monitor_edid/` — contém EDID binário, log de tentativas (TENTATIVAS_LOG.md), análise completa do monitor (MONITOR_INFO.md) e bootargs específicos para forçar 1080p via sufixo `@60e`.

---

## 1. Configurações Prontas

### Linha Padrão de Alta Estabilidade (Fallback)
Se você busca a máxima compatibilidade ou está tendo problemas de tela preta, deixe o arquivo **`bootargs.txt` vazio (0 bytes)** ou use esta linha simplificada:
```text
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0 console=ttyS0,115200n8 console=tty0 video=HDMI-A-1:1920x1080@60
```

### Linha Otimizada com Recursos Extras (Recomendada)
Para habilitar áudio HDMI, evitar lags em periféricos USB, limpar o console de logs de boot, desativar mitigações de CPU (performance de IA/jogos), ativar compressão zswap e habilitar auto-recuperação da GPU:
```text
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0 console=ttyS0,115200n8 console=tty0 video=HDMI-A-1:1920x1080@60 quiet amdgpu.audio=1 usbcore.autosuspend=-1 amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1
```

---

## 2. Detalhamento de Parâmetros e Opções

### Vídeo e Exibição (Handshake HDMI)

| Parâmetro | Opções | Descrição |
| :--- | :--- | :--- |
| `video=HDMI-A-1:1920x1080@60` | Opcional | Força a saída HDMI em 1080p a 60Hz. É o padrão mais seguro para a maioria das TVs e monitores. |
| `video=HDMI-A-1:1920x1080@60e` | Experimental | O sufixo `e` força o estado de "sempre ativo". **Cuidado:** Pode causar tela preta com HD piscando em monitores modernos se o handshake de EDID falhar. |
| `drm.edid_firmware=edid/1920x1080.bin` | Opcional | Injeta informações de EDID falsas do diretório de firmware. **Apenas utilize** se a sua imagem tiver o arquivo compilado e se for estritamente necessário para forçar a tela. |

### Drivers Gráficos AMD (amdgpu / radeon)

| Parâmetro | Valor | Descrição |
| :--- | :--- | :--- |
| `amdgpu.dpm` / `radeon.dpm` | `0` (Estável) | Desativa o Dynamic Power Management. Previne congelamentos de tela e kernel panics causados por flutuação de clock/tensão no PS4. |
| | `1` (Desempenho) | Ativa o gerenciamento dinâmico de energia. Libera melhor performance para jogos, mas pode exigir kernels com patches de voltagem para não crashar. |
| `amdgpu.gpu_recovery` | `1` (Ativo) | Permite que o driver tente reiniciar a GPU silenciosamente em caso de travamento gráfico no meio do jogo, em vez de derrubar o sistema inteiro. |
| `amdgpu.audio` | `1` (Ativo) | Força a inicialização da controladora de áudio digital HDMI embutida na APU. |
| `amdgpu.ppfeaturemask` | `0xffffffff` | Libera via software o controle total de overclock, curvas de ventoinha e p-states da placa de vídeo (para usuários avançados). |
| `amdgpu.si_support` / `cik_support` | `1` (Ativo) | Habilita suporte para GPUs de arquiteturas antigas (Southern Islands e Sea Islands). Útil para forçar o driver `amdgpu` em vez do `radeon`. |

### Gerenciamento de Dispositivos e Periféricos USB

| Parâmetro | Valor | Descrição |
| :--- | :--- | :--- |
| `usbcore.autosuspend` | `-1` (Desativado) | Impede que o Linux suspenda a energia das portas USB por inatividade. **Altamente recomendado** para prevenir lag em mouses/teclados e desconexão de HDs externos. |

### Logs e Limpeza Visual de Tela

| Parâmetro | Valor | Descrição |
| :--- | :--- | :--- |
| `quiet` | - | Oculta a maioria das mensagens de depuração do kernel durante a inicialização, exibindo apenas mensagens críticas e a tela de login. |
| `loglevel` | `3` (Apenas Erros) | Define o nível de logs gravados no console tty0 para exibir apenas erros críticos. |

### Ajustes do Sistema e Hardware

| Parâmetro | Valor | Descrição |
| :--- | :--- | :--- |
| `clocksource` | `tsc` | Define o Time Stamp Counter do processador como fonte primária de relógio do sistema. Garante alta precisão e evita desvios temporais. |
| `panic` | `0` | Impede o reinício imediato do console em caso de erro fatal (Kernel Panic), permitindo fotografar a tela de erro para diagnóstico. |
| `consoleblank` | `0` | Desativa a suspensão da tela por inatividade. Evita que o PS4 apague o display e não consiga recuperá-lo depois. |
| `net.ifnames` | `0` | Desativa os nomes de rede previsíveis do systemd, mantendo o formato clássico `eth0` (cabo) e `wlan0` (sem fio). |
| `mitigations` | `off` | Desativa mitigações de segurança de CPU contra falhas como Spectre/Meltdown. **Garante ganho de 5% a 15% de performance de CPU** no processador Jaguar do PS4. |
| `zswap.enabled` | `1` | Ativa o cache de swap comprimido na memória RAM, reduzindo drasticamente acessos lentos de escrita no HD externo USB. |

---

## 3. Relação Indireta com a VRAM (vram.txt)

O payload (AIO v24+) lê um arquivo separado chamado `vram.txt` localizado na partição boot. O valor inserido nele (em megabytes) altera a alocação de memória que o kexec passará para o kernel:
* **4096** (4GB VRAM): Melhora estabilidade gráfica e permite rodar jogos e interfaces pesadas, porém limita a CPU a usar apenas os 4GB de RAM restantes do console.
* **1024** ou **2048** (1GB ou 2GB VRAM): Ideal para tarefas de processamento de CPU como compilações, servidores e **IA local (Ollama)**, pois deixa de 6GB a 7GB de RAM livres para o sistema.

---

## 4. Diagnóstico de Problemas (Troubleshooting)

### Caso 1: Tela Preta, mas com o HD Piscando (Atividade)
O sistema deu boot e o Linux está rodando, mas a tela está sem sinal (HDMI Handshake Failure).
* **Solução 1:** Remova o arquivo `bootargs.txt` ou deixe-o com **0 bytes**. O payload usará a linha padrão de fallback sem injeção de EDID.
* **Solução 2:** Se o problema persistir, remova o sufixo `e` do parâmetro de vídeo (mude de `video=HDMI-A-1:1920x1080@60e` para `video=HDMI-A-1:1920x1080@60`).
* **Solução 3:** Certifique-se de que a resolução no menu de configurações originais do PS4 esteja travada em **1080p** e o **HDR/HDCP estejam desligados**.

### Caso 2: Console Desliga Imediatamente no Boot (Sem cooler, luz apagada)
Houve uma falha crítica de carregamento (Kernel Panic) ou falha na descompressão do kernel antes mesmo de o sistema de vídeo iniciar.
* **Solução 1:** O kernel (`bzImage`) utilizado pode ser incompatível com a placa-mãe do seu PS4 (ex: kernel experimental de outra revisão de hardware). Volte para uma versão de kernel LTS consagrada (como o **5.4.247-neocine** para Baikal).
* **Solução 2:** Verifique se o formato de compressão do kernel (ZST, XZ ou Gzip) é suportado pelo exploit do payload.
