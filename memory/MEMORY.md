# Memória do Projeto — PS4 Linux Baikal (kernel 7.0)

> 🗄️ **BANCO DE DADOS SQLITE OFICIAL:** `/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db` armazena **671 registradores validados** com `safe_to_read = 1` (BAR0 GbE, BAR0 xHCI, BAR2 Glue, BAR4 Efuse, BAR5 AHCI, ECAM) e tabelas estruturadas.
> 🛠️ **SCRIPT OFICIAL DE TESTES:** `harness_gbe.py` (raiz do projeto) — único script para diagnósticos via Telnet. Marca `safe_to_read = 1` no SQLite para registradores validados.
> ⚠️ **IP PS4 ATUAL:** `192.168.6.128` (Ethernet cabeada, via `mts.ko`).
> ⚠️ **NUNCA fazer probe TCP manual nas portas 9090/9020 do PS4** (ping é OK, connect não) — consome o `accept()` único e trava a injeção.

## Estado Atual Confirmado (2026-07-23)

- **Kernel baseline:** tag `v7.0-20260722-clean-video-ok` (vídeo OK, boot completo, telnet OK, rebuild limpo)
  - Patch `sky2-baikal-gbe.patch` removido (travava vídeo)
  - `CONFIG_DEBUG_INFO_BTF=y` obrigatório (desabilitar quebra boot — tela preta)
  - `JOBS=2` em `MAKE_OPTS` (pahole usa muita memória)
- **Ethernet:** `eth0` via `mts.ko stage=4` — registrada com MAC real `2c:cc:44:3f:69:5f`, DMA funcional, **zero Kernel Panics**. **RX/TX e detecção de carrier NÃO implementados ainda** — `NO-CARRIER` é esperado mesmo com cabo conectado, não é bug de rede. Ver [mts-driver-stage4-incompleto-e-srcversion-mismatch](mts-driver-stage4-incompleto-e-srcversion-mismatch.md).
- **Acesso remoto:** SSH automático no boot (systemd service), WiFi + Ethernet cabeada funcionando
- **GPU Gladius (RESOLVIDO & TESTADO):** `amdgpu` detecta Gladius (`0x1002:0x9924`), 32 CUs ativados (`active_cu_number 32`), `/dev/dri/card0` e `/dev/dri/renderD128` funcionais. Aceleração 3D OpenGL 4.5 (55.26 FPS cravados no `glxgears`) e Vulkan 1.3 (`radv`) validadas ao vivo. Firmwares genuínos e pacotes gráficos integrados no script oficial `01-build-image-7.0.sh`. Ver [marco-2026-07-23-gpu-gladius-firmware-real](marco-2026-07-23-gpu-gladius-firmware-real.md) e `consolidado/INTEGRACAO_IMAGEM_7.0_GLADIUS_E_WIFI.md`.

## Regras Críticas (NUNCA quebrar)

1. **`CONFIG_DEBUG_INFO_BTF=y`** obrigatório — remover causa tela preta (provado 2 builds)
2. **`diag.c` + `diag.bin` (9356 bytes, 2026-07-20) imutáveis** — referência comprovada de teste básico
3. **`app.bin` UM teste por power cycle** — reinjetar sem reboot do PS4 não progride
4. **Nenhuma alteração em `linux_boot.c` ou quiesce do kexec** — regra absoluta
5. **Testes ao vivo sempre com autorização explícita do usuário** antes de injetar
6. **PROIBIDO rodar `make`, `make bzImage`, ou qualquer comando de compilação/build sem autorização/confirmação prévia e explícita do usuário** — alteração de código ou plano NÃO autoriza a execução automática de build.
7. **Linha de energia (S5) exige ICC dedicado ou toque manual** — `poweroff -f` encerra SO mas deixa luz azul. Causa raiz confirmada em código 2026-07-23: `pm_power_off` já chama `icc_shutdown()` (major=4/minor=1, `ps4-bpcie-icc.c:404-414`), mas o próprio driver tem `WARN_ON(1)` após 3s esperando o corte de energia — sinal de que esse comando sozinho não é suficiente nesse hardware. Ver [icc-shutdown-s5-incompleto](icc-shutdown-s5-incompleto.md).

## Informações Técnicas Ativas

- **offsets GPU (FW 12.52):** `kern_off_gpu_devid_is_9924=0x4AC580`, `kern_off_gc_get_fw_info=0x4BAF30` (validados contra `K1252_COPYOUT=0x2BD5C0` já testado em scene-kmem-dumper)
- **Firmware Gladius vs Liverpool:** tamanhos diferentes em `ps4-linux-payloads/linux/ps4-kexec-common/firmware.h` — `GL_FW_RLC_SIZE=8192` vs `LVP_FW_RLC_SIZE=6144`; demais idênticos
- **NOP handler em `firmware.c` linhas 271-320:** CONFIRMADO 2026-07-23 — aplicado incondicionalmente para ambas variantes (não é bug específico de Gladius; hipótese descartada). Tamanho do RLC (8192/6144) também não é hardcoded no driver `gfx_v7_0.c`, é lido do header do firmware — hipótese descartada também.

## Observações Técnicas (ainda válidas)

- **`devmem` NÃO existe neste sistema** — usar `printf octal + dd of=/dev/mem`, sempre conferir exit code
- **Registradores hold/pulse do BPCIE glue são WRITE-ONLY** — readback sempre 0 (provado: xHCI seta hold=1, lê 0)
- **Sequência correta hold/pulse:** `pulse=1, hold=1, pulse=0`, deixar `hold=1` (não adicionar `hold=0` depois)

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

### Hardware & Drivers
- [mts.ko: srcversion mismatch e driver stage=4 incompleto](mts-driver-stage4-incompleto-e-srcversion-mismatch.md) — recompilar sempre na árvore exata do kernel rodando (vermagic não basta); TX/carrier/IRQ status ainda não implementados no driver
- [GPU Gladius amdgpu validado](gpu-gladius-amdgpu-validado.md) — **✅ TOTALMENTE FUNCIONAL** — 32 CUs ativos, OpenGL 4.5 @ 55 FPS, Vulkan 1.3, vídeo acelerado
- [Marco Histórico: Bring-up da interface eth0 com mts.ko](../consolidado/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md) — sucesso de registro eth0, MAC, DMA
- [SSH Automático Implementado (2026-07-22)](ssh-automatico-implementado.md) — systemd service, pronto em uso

### Sistema & Configuração
- [Filesystem NTFS em /mnt/t](filesystem-ntfs-mnt-t-restricao.md) — builds devem usar `/mnt/hdauxiliar/temp` (ext4)
- [SATA "desconecta" durante boot — CORRIGIDO](kernel-7.0-sata-desconexao-boot.md) — era HD interno (sda), não bloqueador
- [Desligamento S5 incompleto via ICC](icc-shutdown-s5-incompleto.md) — `poweroff -f` encerra SO mas luz azul permanece

## Arquivos Descartados

- Documentação de testes antigos de GBE/stmmac/sky2 (resolvido com mts.ko correto)
- Testes de Fases 8/9/10/14 do harness_gbe.py (invalidados por devmem não existir)
- Hipóteses sobre firmware GBE power-on via SAMU/ICC (causa raiz era driver errado, não energia)
- Sessões de debug kern_base_finder (supersedidas por dump TCP bem-sucedido do kernel)
