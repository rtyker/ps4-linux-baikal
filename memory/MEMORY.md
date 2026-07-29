# Memória do Projeto — PS4 Linux Baikal (kernel 7.0)

> ⚠️ **NUNCA diagnosticar/reagir a "PS4 não responde" sem perguntar primeiro o que está na tela** — captura vazia ou timeout de rede não é sinal de falha; pode ser só o usuário ainda não ter iniciado o boot. Esperar confirmação explícita, não montar teorias de falha. Ver [feedback_aguardar_confirmacao_antes_de_agir](feedback_aguardar_confirmacao_antes_de_agir.md).
> 🗄️ **BANCO DE DADOS SQLITE OFICIAL:** `/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db` armazena **671 registradores validados** com `safe_to_read = 1` (BAR0 GbE, BAR0 xHCI, BAR2 Glue, BAR4 Efuse, BAR5 AHCI, ECAM) e tabelas estruturadas.
> 🛠️ **SCRIPT OFICIAL DE TESTES:** `harness_gbe.py` (raiz do projeto) — único script para diagnósticos via Telnet. Marca `safe_to_read = 1` no SQLite para registradores validados.
> ⚠️ **CORRIGIDO 2026-07-23 noite — NÃO CONFUNDIR:** `192.168.6.128` (WiFi, `wlan0`) é **só para telnet/administração**. A Ethernet cabeada sob teste (`eth0`, driver `mts.ko`) tem **IP FIXO `192.168.0.2`**, host de teste em `192.168.0.1` via `enp60s0`. Ver `AGENTS.md` na raiz do projeto (regra de topologia, prioridade alta) — testar `eth0` na subnet do WiFi não prova nada sobre ele.
> ⚠️ **NUNCA fazer probe TCP manual nas portas 9090/9020 do PS4** (ping é OK, connect não) — consome o `accept()` único e trava a injeção.
> 🔴 **RX Ethernet: causa raiz e correções 2026-07-23 noite:** BAR4 EFUSE (`0xc9000000`) corrigida (liberou tuning MDIO), decodificador de endereços packed MDIO corrigido (`devad = packed_addr & 0xff`), e tabela LUT de 64 bytes da Sony extraída do dump Orbis 12.52. Módulo 100% estável. Ver [sessao-2026-07-23-bar4-efuse-e-mdio-packed-fix](sessao-2026-07-23-bar4-efuse-e-mdio-packed-fix.md).
> ⚠️ **CORRIGIDO 2026-07-24: `01-build-image-7.0.sh` sobrescrevia o initramfs recém-gerado pelo DEBUG loop de ontem** (rotulado incorretamente como "oficial") — todo rootfs/mts.ko novo gravado nunca era montado no boot. Corrigido para usar o initramfs do próprio `mkinitcpio`. Ver [bug-01-build-sobrescrevia-initramfs-com-debug-loop](bug-01-build-sobrescrevia-initramfs-com-debug-loop.md).
> ⚠️ **CORRIGIDO 2026-07-24: `mkinitcpio.conf` usava `COMPRESSION="zstd"`, kernel 7.0 não tem `CONFIG_RD_ZSTD`** — boot falhava com "Cannot open root device" pois o kernel só processava o segmento `early_cpio` e não conseguia descomprimir o payload principal. Corrigido para `COMPRESSION="gzip"` (igual aos artefatos RELEASE/DEBUG que sempre funcionaram). Ver [bug-initramfs-zstd-incompativel-com-kernel-2026-07-24](bug-initramfs-zstd-incompativel-com-kernel-2026-07-24.md).
> ⚡ **OTIMIZAÇÃO 2026-07-24: `libata.force=1.00:3.0Gbps,noncq` adicionado ao cmdline** para reduzir os ~45s que o HD interno (`sda`/`ata1`) gasta em tempestade de resets SATA antes do `switch_root` — sem rebuild de kernel, ainda não validado ao vivo. Ver [otimizacao-boot-libata-force-hd-interno-2026-07-24](otimizacao-boot-libata-force-hd-interno-2026-07-24.md).
> ✅ **UART TTL 2026-07-27: FUNCIONAL — pinagem estava invertida, CORRIGIDA** — `stty -F /dev/ttyUSB0 115200 raw -echo -icanon; dd if=/dev/ttyUSB0 bs=1 | xxd` mostra: (1) Orbis/CEX = `2020 2020...` (espaços, censurado, esperado); (2) Payload Server = logs reais `[GoldHEN]`, `[SceShellUI]`, `[avc]`, sem filtro. Esquema: **AMARELO→GND, VERMELHO→RX (recebe TX do PS4), LARANJA→TX** (opcional). Ver [uart-ttl-pinagem-corrigida-2026-07-27](uart-ttl-pinagem-corrigida-2026-07-27.md).
> 🔴 **KEXEC NATIVO 2026-07-27/28 — TRAVA REAL CONFIRMADA E LOCALIZADA COM PRECISÃO (kernel time ~127.7s, logo após `mts_driver_init` retornar, ANTES de qualquer próximo initcall):** `kexec -e` funciona e troca de kernel de verdade. **4 testes de diagnóstico realizados:** (1) `unbind` do xHCI ao vivo — quebrou o disco (erro real de journal EXT4 `Journal has aborted` em `/dev/sdb2`, confirmado por foto); (2) `setpci` isolado no bit MSI-enable, sem unbind — quebrou o disco do MESMO jeito (qualquer manipulação ao vivo de MSI/xHCI é destrutiva, não só o unbind); (3) `pci=nomsi` no kernel-alvo — travou AINDA MAIS CEDO (13.8s), com 3 dispositivos PCI (incl. xHCI `0000:00:14.7`) em `deferred probe pending` — refuta "só faltava desabilitar MSI" (hardware provavelmente não tem INTx roteado, precisa de MSI); (4) `initcall_debug` no kernel-alvo — **achado mais preciso até agora**: `mts_driver_init` retorna com sucesso (`returned 0`) e regista `eth0`, mas NENHUM `calling X+0x0/...` posterior aparece — o travamento não é um initcall síncrono, é algo fora do `do_one_initcall()`, quase certamente o worker do `systemd-udevd` (mts roda com `@ 294`, PID de worker udev) travando ao processar o uevent do PRÓXIMO dispositivo (muito provavelmente xHCI). Bônus: capturado log verboso do `mts.ko` com comando ICC `major=4,minor=0x38` "GBE power-on" já confirmado pelo driver — diferente do `major=5,minor=0x41` já descartado, pista nova pro bug de RX. Ver [kexec-nativo-mecanismo-funciona-mas-v5-trava-pos-console-handoff-2026-07-27](kexec-nativo-mecanismo-funciona-mas-v5-trava-pos-console-handoff-2026-07-27.md).
> ⚠️ **UART TTL 2026-07-27: `console=ttyS0,115200n8` no bootargs causou tela preta/boot travado** (não isolado ainda do erro de R/W recorrente no boot via disco `HEN.AIO`) — revertido com sucesso (backup `bootargs.txt.bak`), boot voltou ao normal. Próxima tentativa deve usar `earlycon=uart8250,mmio32,0xC890E000` (caminho MMIO real da UART Baikal) em vez de `ttyS0` (porta 8250 legada x86, sem hardware real detectado). Ver [console-ttys0-bootargs-causa-tela-preta-2026-07-27](console-ttys0-bootargs-causa-tela-preta-2026-07-27.md).
> 🆕 **BOOT ORBIS→LINUX CAPTURADO AO VIVO PELA 1ª VEZ (2026-07-28):** sequência completa via UART do payload original (`linux-1024mb.bin`): arm+firmware Gladius → shutdown do SceSysCore → handshake ICC (`icc 08-4001`, `icc:disabled thermal notification`, **`eth0: link state changed to DOWN`** intercalado no meio, `ICC 05-00 polling`) → `fix_acpi_tables()` → quiesce (`sb_id=3`=Baikal, disable IOMMU, VRAM, reset GPU) → jump. Pista nova (não conclusiva) pro bug de RX Ethernet: o `eth0` desce junto com comandos ICC `major=8` e `major=5,minor=0` — **diferentes** do `major=5,minor=0x41` já testado e descartado como controle de power da GBE. Também relevante pro bug de S5: handshake ICC do Orbis é bem mais rico que o único comando que o driver Linux `icc_shutdown()` envia. Ver [orbis-payload-sequencia-boot-capturada-live-2026-07-28](orbis-payload-sequencia-boot-capturada-live-2026-07-28.md).
> 🔴 **SATA INTERNO & VÍDEO HDMI (SESSÃO 2026-07-29):** Log UART `sata_teste_20260729_145146.bin` (tag `20260729-sata-globallock`) confirmou: (1) **Vídeo HDMI 1080p SOLUCIONADO**: sinal 1080p@60Hz estável sem erros no DRM; (2) **SATA Interno PENDENTE**: A hipótese do spinlock global no `ps4-bpcie.c` foi **refutada**. O spinlock funcionou sem travar o sistema, mas o Glue cessa a sinalização da subfunção 1 aos 4.89s. No estouro de exceção em `t = 36.80s` (`READ DMA EXT`), a porta AHCI mantém `PxIS=0x2` e `IS=0x1` (interrupção ativa no controlador), porém o Glue `BAR2+0x110088` lê `0x001e0103` (subfunção 1 zerada). Prova física de que a interrupção da porta do AHCI deixa de ser propagada para o Glue após a inicialização.
> ⚠️ **ATENÇÃO 2026-07-24: cabo/conexão de rede estava frouxo, usuário reconectou** — todo o diagnóstico de RX ("PHY nunca acorda", MDIO sempre zero, ping 100% perda) foi feito antes dessa correção física. Re-testar o básico (ping) antes de aprofundar mais hipóteses de software. MDIO Clause 45 retornando zero provavelmente não é explicado por cabo (é comunicação local ao chip), mas o ping/link pode ter sido mascarado. Ver [cabo-rede-frouxo-reconectado-2026-07-24](cabo-rede-frouxo-reconectado-2026-07-24.md).

> ⚡ **RMU HANDSHAKE & DMA TX 2026-07-25:** Com `eth0` UP, o controlador DMA da GBE processou pela primeira vez os quadros RMU in-band de 34 bytes (magic `0xfa42`), tanto Fase 1 (`cmd=0x0000`) quanto Fase 2 (`cmd=0x800b`, descoberto em `dc5a6290`), devolvendo o bit `OWN` do descritor de TX ao driver em ambas as transmissões. Prova que o motor DMA TX físico funciona 100%. Criado o atributo sysfs `/sys/class/net/eth0/device/trigger_rmu` (opções 1, 2 e 3) para acionamento e diagnóstico sob demanda.
> 🔍 **PERVASIVE GLUE 0x142020 2026-07-25:** Engenharia reversa em `fcn.ffffffffdc6df850` revelou o registrador de controle do bloco GBE (`0x2000`) em `BAR2 + 0x140000 + 0x2000 + 0x20 = 0x142020`. Testado no PS4 real: registrador lê `0x06040400` de forma estável.
> ⚡ **PCI CONFIG SPACE & BUS RESET 2026-07-25:** Dump do espaço de configuração PCI via `trigger_pci` confirmou: `00:14.1` (GBE) e `00:14.0` (Bridge) estão ambos com `CMD=0x0546` (Memory Space e Bus Master ativos). Bridge Control (`0x3e`) = `0x0000` (`bit 6 Bus Reset = 0`, desassinalado). Descarte definitivo da hipótese de que a enumeração PCI ou o `kexec` colocou o barramento em reset ou D3.
> 🐞 **CORRIGIDO 2026-07-25: `drivers_mts/mts.c` não compilava** (string truncada fundida com `mts_mac_enable`, provável resíduo de edição anterior nunca testada) + `device_remove_file` faltando p/ `trigger_rx_clean`. Rodar sempre `sudo bash scripts/build_mts_module.sh` após editar `mts.c`. Ver [mts-c-corrupcao-de-edicao-sempre-compilar-antes](mts-c-corrupcao-de-edicao-sempre-compilar-antes.md).
> ⚡ **TESTE MAC LOOPBACK 2026-07-25:** Testado envio de frame ARP de 64 bytes via DMA TX no modo padrão e com comutação de `bit 1` em `BAR0+0x50`, `0x5c` e `0x70` via `trigger_loopback`. Transmissão DMA completou com sucesso em todas as variantes, mas o contador de hardware `MTS_CNT_PKTS` (`0x100`) e `rx_packets` permaneceram em zero (confirmando que esses bits não são os seletores de loopback interno isolados do MAC).
> ⚡ **REGISTRADOR DE TRIGGER BAR0+0x1c CONFIRMADO 2026-07-25:** Engenharia reversa em `fcn.ffffffffdc5a4950` revelou que o Orbis aciona a sinalização PHY/MAC escrevendo `0x80000000` em `BAR0+0x1c` e fazendo poll no `bit 17` (`0x20000`). Testado no PS4 real via `trigger_phy_trigger`: a escrita alterou o registrador instantaneamente de `0x00000000` para `0x80030000` (bit 17 set na 1ª iteração), confirmando o registrador de trigger de hardware do MAC/PHY!
> ⚡ **QUADRO RMU SUB-HEADER 0x9807 VALIDADO 2026-07-25:** Decompilação de `fcn.ffffffffdc5a5200` revelou o construtor de comandos RMU contendo o sub-cabeçalho `0x9807` nos bytes 26/27. Testado via `trigger_rmu` (opção 4) no PS4 real: o controlador DMA aceitou e devolveu o descritor (`OWN`) com sucesso.
> ❌ **REFUTADO 2026-07-25 (reteste): "PHY HARDWARE AUTÊNTICO CONFIRMADO (PHY ID = 0x888103a2)" era falso positivo.** O dump de 16 registradores Clause 22 via `trigger_phy_trigger` (opção 4) NÃO é reprodutível nem coerente: repetido no mesmo dia, `Reg[02]` mudou de `0x8881` para `0x0000` (registrador de PHY ID é hardwired, não pode mudar), e os valores aparecem em blocos de 3 registradores consecutivos idênticos (Reg3=Reg4=Reg5, Reg6=Reg7=Reg8, Reg10=Reg11=Reg12, Reg13=Reg14=Reg15) — mesma assinatura de dado residual do barramento MDIO já descartada em [devmem-nao-existe-usar-dd-octal](devmem-nao-existe-usar-dd-octal.md) (transação não completa, bus devolve o último valor latched repetido). **Não tratar mais este resultado como prova de PHY vivo.** PHY continua mudo/sem resposta real; ver [mac-en2-descartado-phy-nunca-acorda-2026-07-23](mac-en2-descartado-phy-nunca-acorda-2026-07-23.md).
> ⭐ **RE RTC 2026-07-25:** Decompilação completa do driver RTC do Orbis 12.52 validou 100% o plano `consolidado/plans/rtc_via_icc_plan.md`. Descobertos **DOIS drivers RTC em camadas no kernel**: `rtc_mvl.c` (baixo nível, MMIO direto, **read-only**) e `rtc.c` (alto nível via ICC + MMIO `0x5180000`/`0x5140000` — **este é o que o driver Linux `rtc-ps4-icc.c` deve seguir**). Confirmados via RE direta: ICC major=2 minor=0x0b/0x0c sub=0x81/1 (save/load context), ICC major=4 minor=0x50 (bitmask alarmes), MMIO read `0x5180000` + MMIO write `0x5140000`. Constante Sony `0x4effa200` = offset de epoch Sony (NÃO usar no Linux, escrever epoch unix puro). 8 funções registradas no `ps4_hardware_memory.db` (`decompiled_functions`, categorias "RTC (rtc_mvl.c)" e "RTC (rtc.c)"); lacunas restantes: `dc839e40`/`dc839d90` (MMIO read/write wrappers), `dc6b1a20`/`dc6b1b80` (dispatchers save/load), `dc797090` (transport ICC subjacente). Ver [rtc-via-icc-re-validada-2026-07-25](rtc-via-icc-re-validada-2026-07-25.md), `consolidado/decompiled/baikal_rtc_mvl.txt` e `consolidado/decompiled/INDEX.md` §6.B.
> 🔊 **ÁUDIO HDMI CONFIRMADO 2026-07-24:** usuário confirmou áudio via HDMI funcionando perfeitamente durante a sessão de desktop (Xorg+Cinnamon) — validação em uso real, complementa o status de driver já registrado em `consolidado/STATUS_ATUAL.md`. Ver [audio-hdmi-confirmado-desktop-2026-07-24](audio-hdmi-confirmado-desktop-2026-07-24.md).
> ✅ **DESKTOP (Xorg+Cinnamon) 2026-07-24 — CORRUPÇÃO VISUAL RESOLVIDA, VALIDADA AO VIVO E INTEGRADA AO PIPELINE:** causa raiz era o Mesa não reconhecer `CHIP_GLADIUS`/`CHIP_LIVERPOOL` (o kernel já suportava, com `external_rev_id` pronto pra integração). Patch pra Mesa 26.1.5 (`mesa/01-build-mesa.sh`) confirmado ao vivo (`glxinfo` → `gladius`, corrupção sumiu). Agora **persistente por padrão**: `01-build-image-7.0.sh` extrai o Mesa patchado pra `/opt/mesa-ps4-patched` e persiste `LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH` via `/etc/environment` automaticamente em toda imagem nova, sem passo manual. Pendente apenas: testar o build de imagem completo + power cycle real do zero (só o deploy manual equivalente foi validado ao vivo até agora). Ver [mesa-gladius-liverpool-patch-2026-07-24](mesa-gladius-liverpool-patch-2026-07-24.md) e `consolidado/MESA_GLADIUS_LIVERPOOL_FIX.md`.

## Estado Atual Confirmado (2026-07-23)

- **Kernel baseline:** tag `v7.0-20260722-clean-video-ok` (vídeo OK, boot completo, telnet OK, rebuild limpo)
  - Patch `sky2-baikal-gbe.patch` removido (travava vídeo)
  - `CONFIG_DEBUG_INFO_BTF=y` obrigatório (desabilitar quebra boot — tela preta)
  - `JOBS=2` em `MAKE_OPTS` (pahole usa muita memória)
- **Ethernet:** `eth0` via `mts.ko stage=4` — registrada com MAC real `2c:cc:44:3f:69:5f`, DMA funcional, **zero Kernel Panics**. Confirmada comunicação **MDIO Clause 45** (`ret=0`), refutada Clause 22 (timeout). Registradores do Glue lidos via 2 MB ioremap (`0x140000=0x10206333`). Tabela de calibração segura (128 elementos) executou todas as **66 iterações com sucesso** e ativou **`Link UP: 1000 Mbps Full duplex`**. Ver [teste-3-resultado-2026-07-23](teste-3-resultado-2026-07-23.md), [plano-teste-4-phy-power-up-2026-07-23](plano-teste-4-phy-power-up-2026-07-23.md), [teste-4-resultado-glue-2026-07-23](teste-4-resultado-glue-2026-07-23.md), [teste-5-resultado-calibracao-tabela-2026-07-23](teste-5-resultado-calibracao-tabela-2026-07-23.md) e [teste-6-habilitar-rx-tx-padrao](teste-6-habilitar-rx-tx-padrao.md).




- **Acesso remoto:** SSH automático no boot (systemd service) validado em ambiente **RELEASE** (sem `DEBUG LOOP`). Ver [sessao-2026-07-23-ssh-sem-debug-loop-sucesso](sessao-2026-07-23-ssh-sem-debug-loop-sucesso.md). WiFi + Ethernet cabeada funcionando.

- **GPU Gladius (RESOLVIDO & TESTADO):** `amdgpu` detecta Gladius (`0x1002:0x9924`), 32 CUs ativados (`active_cu_number 32`), `/dev/dri/card0` e `/dev/dri/renderD128` funcionais. Aceleração 3D OpenGL 4.5 (55.26 FPS cravados no `glxgears`) e Vulkan 1.3 (`radv`) validadas ao vivo. Firmwares genuínos e pacotes gráficos integrados no script oficial `01-build-image-7.0.sh`. Ver [marco-2026-07-23-gpu-gladius-firmware-real](marco-2026-07-23-gpu-gladius-firmware-real.md) e `consolidado/INTEGRACAO_IMAGEM_7.0_GLADIUS_E_WIFI.md`.

## Regras Críticas (NUNCA quebrar)

1. **`CONFIG_DEBUG_INFO_BTF=y`** obrigatório — remover causa tela preta (provado 2 builds)
2. **`diag.c` + `diag.bin` (9356 bytes, 2026-07-20) imutáveis** — referência comprovada de teste básico
3. **`app.bin` UM teste por power cycle** — reinjetar sem reboot do PS4 não progride
4. **Nenhuma alteração em `linux_boot.c` ou quiesce do kexec** — regra absoluta
5. **Testes ao vivo sempre com autorização explícita do usuário** antes de injetar
6. **PROIBIDO rodar `make`, `make bzImage`, ou qualquer comando de compilação/build sem autorização/confirmação prévia e explícita do usuário** — alteração de código ou plano NÃO autoriza a execução automática de build.
7. **Linha de energia (S5) exige ICC dedicado ou toque manual** — `poweroff -f` encerra SO mas deixa luz azul. Causa raiz confirmada em código 2026-07-23: `pm_power_off` já chama `icc_shutdown()` (major=4/minor=1, `ps4-bpcie-icc.c:404-414`), mas o próprio driver tem `WARN_ON(1)` após 3s esperando o corte de energia — sinal de que esse comando sozinho não é suficiente nesse hardware. Ver [icc-shutdown-s5-incompleto](icc-shutdown-s5-incompleto.md).
8. **`mkinitcpio.conf` do initramfs 7.0 SEMPRE `COMPRESSION="gzip"`, NUNCA `"zstd"`** — o kernel 7.0 Baikal (`config-7.0`) não tem `CONFIG_RD_ZSTD` habilitado (só `GZIP/BZIP2/LZMA/XZ/LZO/LZ4`). Usar zstd faz o kernel processar só o segmento `early_cpio` e falhar em descomprimir o payload principal, resultando em "Cannot open root device" / "RAMDISK: Couldn't find valid RAM disk image" no boot — sem crash, sem log de erro óbvio do initramfs, só root nunca monta. Antes de gravar, conferir `xxd boot_referencia/initramfs-7.0.cpio.gz | head -1` → tem que começar com `1f8b 0800` (gzip) já no primeiro byte. Ver [bug-initramfs-zstd-incompativel-com-kernel-2026-07-24](bug-initramfs-zstd-incompativel-com-kernel-2026-07-24.md).

## Análise Atual — PHY Carrier Detection (2026-07-23 — STATUS: TESTE #3 EM PROGRESSO)

**📊 Estado:** Bloqueador primário (crash) ✅ ELIMINADO. Teste #2 identificou **PHY não responde em Clause 45**. Implementando **Clause 22 (MII) fallback** (compilado com sucesso, aguardando transferência ao PS4).

**👉 HISTÓRICO DE CORREÇÃO:**
1. [PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md](PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md) — Identificação da causa raiz (stack overflow em `calib_tbl[32]`, índices até 65) + plano de isolamento + teste incremental
2. **TESTE #1 (2026-07-23 14:30 UTC) — ✅ PASSOU:**
   - ✅ Módulo carregado sem crash
   - ✅ BAR2/glue mapeado corretamente (valores reais lidos: 0x6c=0x331250b5, etc.)
   - ✅ Stack overflow eliminado (bloco de tabela desabilitado via `enable_phy_calib_table=0`)
   - ✅ Instrumentação pre/post funciona (todas as 7 escritas registradas)
   - ❌ Link ainda DOWN (próxima investigação)
   - **Ver:** [tentativas-frustradas-mts-carrier.md#teste-ao-vivo-1](tentativas-frustradas-mts-carrier.md#teste-ao-vivo-1) para dados detalhados
3. **TESTE #2 (2026-07-23 15:00-15:15 UTC) — ✅ ACHADO CRÍTICO:**
   - ✅ Fase 1 CONCLUÍDA: **MDIO Clause 45 sempre retorna 0x0000**
   - ⚠️ Fase 2 INTERROMPIDA: Enable `enable_phy_calib_table=1` causa crash (PS4 inacessível)
   - **Conclusão:** PHY não responde em Clause 45. Próximo: implementar Clause 22 (MII)
   - **Ver:** [teste-2-resultado-completo-2026-07-23.md](teste-2-resultado-completo-2026-07-23.md) para análise detalhada
4. **TESTE #3 (2026-07-23 16:45-17:00 UTC) — ✅ CONCLUÍDO:**
   - ✅ **Implementação Clause 22 compilada e testada ao vivo:**
     - Funções `mts_mdio_c22_read()` e `mts_mdio_c22_write()` testadas
     - Diagnóstico automático executado no PS4 real
   - **🔴 ACHADO CRÍTICO:** PHY **NÃO está powered-down, mas**:
     - Clause 45: ret=0 (sucesso) val=0x0000 (ZEROS perpetuados)
     - Clause 22: ret=-110 (ETIMEDOUT - não responde)
     - **Conclusão:** Protocolo Clause 45 está CORRETO, mas PHY **retorna zeros** (power-down confirmado)
   - **Próximo Bloqueador:** PHY precisa ser despertado via sequência power-up/wake-up (Teste #4)

**⚠️ NÃO reativar `enable_phy_calib_table=1`** sem RE completa da tabela (DC5a0ba0 linhas 382-506)

Documentos de suporte:
- [Análise Profunda: bloqueador PHY carrier](analise-profunda-phy-carrier-2026-07-23.md) — **Root cause identificada:** falta PHY calibration (dc5a0ba0 do Orbis não implementada no mts.c)
- [Plano de Implementação: PHY Calibration](plano-implementacao-phy-calib-2026-07-23.md) — Estratégia de tradução de Orbis para Linux, offsets BAR2, MDIO writes necessárias
- [Tentativas Frustradas: Validação mts.ko eth0](tentativas-frustradas-mts-carrier.md) — Histórico de testes (BTF, link detection, bug fix `link_up=true`, **TESTE #1 ✅ PASSOU**)
- [Teste #1 Resumo Executivo](teste-1-resumo-executivo-2026-07-23.md) — Crash eliminado, BAR2 funcional, link ainda investigar
- [Plano Teste #2](plano-teste-2-link-investigation-2026-07-23.md) — Próximo: investigar MDIO responses e por que link detection falha
- [Teste #2 Resultado Completo](teste-2-resultado-completo-2026-07-23.md) — **🔴 ACHADO CRÍTICO:** PHY não responde em Clause 45 MDIO (sempre lê 0x0000). Próximo: implementar Clause 22 fallback.
- [Teste #2 Fase 1 Resultado](teste-2-fase1-resultado-2026-07-23.md) — Coleta detalhada de dados MDIO confirmando zero response em Clause 45
- [Teste #3 Implementação Clause 22](teste-3-clause22-implementacao-2026-07-23.md) — ✅ Compilado com sucesso. Funções `mts_mdio_c22_read()` e `mts_mdio_c22_write()` + diagnóstico automático implementados. Aguardando teste ao vivo.

## Informações Técnicas Ativas

- **offsets GPU (FW 12.52):** `kern_off_gpu_devid_is_9924=0x4AC580`, `kern_off_gc_get_fw_info=0x4BAF30` (validados contra `K1252_COPYOUT=0x2BD5C0` já testado em scene-kmem-dumper)
- **Firmware Gladius vs Liverpool:** tamanhos diferentes em `ps4-linux-payloads/linux/ps4-kexec-common/firmware.h` — `GL_FW_RLC_SIZE=8192` vs `LVP_FW_RLC_SIZE=6144`; demais idênticos
- **NOP handler em `firmware.c` linhas 271-320:** CONFIRMADO 2026-07-23 — aplicado incondicionalmente para ambas variantes (não é bug específico de Gladius; hipótese descartada). Tamanho do RLC (8192/6144) também não é hardcoded no driver `gfx_v7_0.c`, é lido do header do firmware — hipótese descartada também.

## Observações Técnicas (ainda válidas)

- **`devmem` NÃO existe neste sistema** — usar `printf octal + dd of=/dev/mem`, sempre conferir exit code
- **Registradores hold/pulse do BPCIE glue são WRITE-ONLY** — readback sempre 0 (provado: xHCI seta hold=1, lê 0)
- **Sequência correta hold/pulse:** `pulse=1, hold=1, pulse=0`, deixar `hold=1` (não adicionar `hold=0` depois)
- **⚠️ ESCRITA EM BAR0+0x200 = 0 TRAVA O MAC ENABLE (2026-07-24 descoberta)** — o Orbis `dc5a0ba0` escreve 0 em 0x200 no attach, mas o Orbis faz MAC enable APÓS a calibração (no `ifconfig up` via `dc5a31f0`). No nosso driver, a calibração roda DENTRO do `mts_mac_enable()` (stage 3) e a escrita em 0x200=0 impedia permanentemente o re-enable do MAC (0x34/0x38 ficavam 0 para sempre, readback `/dev/mem` também 0). **Removida a escrita em 0x200 no `mts_phy_calibration()`** — sem ela, MAC enable funciona, 0x34 lê 1, TX enfileira pacotes, Link UP detectado. Ver `PHY_DEBUG_SESSION_20260724.md` e commit 2026-07-24.
- **⚠️ CORREÇÃO CRÍTICA: `mts_mac_stop()` NUNCA deve escrever 0 em 0x34/0x38 (2026-07-24/25)** — o Orbis `dc5a3060` escreve **2** (bit 1 = soft-reset) e aguarda ACK (bit 1 → 0). Escrever 0 (clear bit 0) corrompe o estado do hardware após ~3 ciclos rmmod/insmod, impedindo permanentemente o re-enable do MAC até power cycle. A sequência correta é:
  1. `0x54 = 0x7ffffa` (IMR, mascara IRQs)
  2. `0x34 = 2`, poll bit 1 até zerar (soft-reset MAC1)
  3. `0x38 = 2`, poll bit 1 até zerar (soft-reset MAC2)
  4. Liberar buffers TX/RX (`mts_tx_drain_force()`)
  5. `0x1c8 &= ~0x440`

### Como Reativar o Debug Loop / Debug Mode (se necessário)
1. **Netconsole Dinâmico (Userland em tempo real):**
   ```bash
   modprobe netconsole netconsole=@192.168.6.128/eth0,6666@192.168.6.X/ff:ff:ff:ff:ff:ff
   ```
2. **Netconsole Estático no Boot:** Adicionar `netconsole=@<IP_PS4>/eth0,6666@<IP_PC>/ff:ff:ff:ff:ff:ff` no `bootargs-7.0.txt` (`distros/arch_minimal_v2/01-build-image-7.0.sh`).
3. **Interface `/proc/ps4_icc`:** Reativar alterando a linha 17 em `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/Makefile` para `obj-y += ps4-icc-debug.o`.

## Referências Atuais (não obsoletas)

### Status & Build (2026-07-23)
- **`bzImage #35` (Implantado em `/dev/sdb1`):** Kernel compilado a 50% CPU com a árvore baseline restaurada (`ps4-icc-debug.o` incluído, `bootargs` com `earlyprintk=efi,keep`), garantindo vídeo OK + sequência ICC de S5 Shutdown (Major 4 Minor 4 + Major 4 Minor 1).
- [Tag v7.0-20260722-clean-video-ok](tag-v7-0-20260722-clean-video-ok.md) — **BASELINE OFICIALMENTE FUNCIONAL** — ponto de partida para todos os rebuilds
- [Sucesso SSH sem Debug Loop em RELEASE](sessao-2026-07-23-ssh-sem-debug-loop-sucesso.md) — **✅ CONQUISTADO** — SSH automático rodando no ambiente de produção sem loop BusyBox


### Hardware & Drivers
- [mts.ko: srcversion mismatch e driver stage=4 incompleto](mts-driver-stage4-incompleto-e-srcversion-mismatch.md) — recompilar sempre na árvore exata do kernel rodando (vermagic não basta); TX/carrier/IRQ status ainda não implementados no driver
- [GPU Gladius amdgpu validado](gpu-gladius-amdgpu-validado.md) — **✅ TOTALMENTE FUNCIONAL** — 32 CUs ativos, OpenGL 4.5 @ 55 FPS, Vulkan 1.3, vídeo acelerado
- [Marco Histórico: Bring-up da interface eth0 com mts.ko](../consolidado/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md) — sucesso de registro eth0, MAC, DMA
- [SSH Automático Implementado (2026-07-22)](ssh-automatico-implementado.md) — systemd service, pronto em uso

### Sistema & Configuração
- [Filesystem NTFS em /mnt/t](filesystem-ntfs-mnt-t-restricao.md) — builds devem usar `/mnt/hdauxiliar/temp` (ext4)
- [SATA "desconecta" durante boot — CORRIGIDO](kernel-7.0-sata-desconexao-boot.md) — era HD interno (sda), não bloqueador
- [HD interno falha por NCQ/IRQ compartilhada, não por PHY](sata-interno-falha-e-ncq-irq-compartilhada-2026-07-28.md) — `SErr 0x0` em 100% das falhas; plano de PHY/EFUSE era beco sem saída (contém erratas — ler até o fim)
- [✅ rootwait economiza 10,5s de boot](rootwait-substitui-rootdelay-ganho-10s-2026-07-28.md) — validado ao vivo; nunca mais usar `rootdelay=N`
- [Função 7 do Baikal usa UM só vetor MSI](baikal-func7-um-unico-vetor-msi-2026-07-28.md) — o vetor "dedicado" do AHCI nunca dispara; alocar 3 vetores é inútil
- [ACK do glue precisa de lock GLOBAL (divergência do Orbis)](glue-ack-lock-global-divergencia-orbis-2026-07-28.md) — `0x110084` é seletor compartilhado; usamos lock por descritor, Orbis usa mutex global
- [Desligamento S5 incompleto via ICC](icc-shutdown-s5-incompleto.md) — `poweroff -f` encerra SO mas luz azul permanece

## Arquivos Descartados

- Documentação de testes antigos de GBE/stmmac/sky2 (resolvido com mts.ko correto)
- Testes de Fases 8/9/10/14 do harness_gbe.py (invalidados por devmem não existir)
- Hipóteses sobre firmware GBE power-on via SAMU/ICC (causa raiz era driver errado, não energia)
- Sessões de debug kern_base_finder (supersedidas por dump TCP bem-sucedido do kernel)
