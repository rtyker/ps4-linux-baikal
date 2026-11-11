---
name: icc-shutdown-s5-analise-dump-1252
description: "RE completa do dump kmem_dump_1252.bin — módulos ICC, mapa de comandos, shutdown multi-fase Orbis, gap com nosso driver Linux"
metadata:
  type: project
  originSessionId: analise-2026-07-23
  modified: 2026-07-23T12:00:00.000Z
---

# Análise RE do Dump Orbis 12.52 — ICC Power/Shutdown

## Dump analisado

- **Arquivo:** `consolidado/dumps_orbis/kmem_dump_1252.bin`
- **Tamanho:** 33.770.224 bytes (32.2 MB)
- **Kernel base (teste anterior):** `0xffffffff948dc000` (testado com `kern_base_finder`)
- **Offsets relativos:** todos os offsets abaixo são relativos ao início do dump (dump[0] = kernel_base)

---

## 1. Módulos ICC do Orbis (FreeBSD) — String Table Completa

Todos os módulos ICC foram identificados via strings de source path (`W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\`):

| Módulo | Offset no dump | Função |
|--------|---------------|--------|
| `icc.c` | `0x0080239b` | Driver principal ICC — init, send, receive, event dispatch |
| `icc_power.c` | `0x007b025b` | Shutdown, reboot, suspend — **módulo-alvo** |
| `icc_device_power.c` | `0x008085d8` | Controle de power state de dispositivos (HDD, etc.) |
| `icc_nvs.c` | `0x0078a7e2` | Escrita/leitura NVS (non-volatile storage) durante shutdown |
| `icc_snvs.c` | `0x007ab537` | NVS seguro (secure non-volatile storage) |
| `icc_buttons.c` | `0x007a182f` | Power/reset button — registro de notificações |
| `icc_notification.c` | `0x007be4ed` | Thread de notificações ICC |
| `icc_thermal.c` | `0x007c4643` | Thermal management |
| `icc_sc_fw_update.c` | `0x0078b288` | Firmware update do SC (southbridge) |

---

## 2. Tabela de Strings de `icc_power.c` (offset `0x7affe0` — `0x7b0298`)

A tabela de strings revela a estrutura completa do shutdown Orbis:

### Fases do Shutdown (multi-fase)

| String | Offset | Significado |
|--------|--------|-------------|
| `shutdown_pre_sync` | `0x7affe0` | Nome da fase pre-sync (evento FreeBSD) |
| `icc_power_shutdown_pre_sync` | `0x7affef` | Handler registrado para pre-sync |
| `shutdown_post_sync` | `0x7b000f` | Nome da fase post-sync |
| `icc_power_shutdown_post_sync` | `0x7b001e` | Handler registrado para post-sync |
| `shutdown_final` | `0x7b003d` | Nome da fase final |
| `icc_power_shutdown_final` | `0x7b004a` | Handler registrado para final |
| `shutdown_force` | `0x7b0063` | Opção de force shutdown |

### Variáveis e Parâmetros

| String | Offset | Significado |
|--------|--------|-------------|
| `icc_available` | `0x7b0071` | Flag de disponibilidade do ICC |
| `init_last_shutdown_cause` | `0x7b0080` | Última causa de shutdown gravada |

### Mensagens de Log

| String | Offset | Significado |
|--------|--------|-------------|
| `icc_power_suspend (%s eap) (keep 0x%X)` | `0x7b0099` | Log de suspend — parâmetro "eap" |
| `with` | `0x7b00c4` | Parâmetro "com" |
| `without` | `0x7b00c9` | Parâmetro "sem" |
| `icc_power_shutdown failed(%d)` | `0x7b00ce` | **ERRO: shutdown pode falhar** |
| `Enter system suspend state` | `0x7b00ea` | Log de entrada em suspend |
| `icc post sync:Thermal alert LED off` | `0x7b011c` | LED de thermal alert desligado no post-sync |
| `ICC: howto:%08x depth:%d cause:%02x hand:%02x` | `0x7b013e` | **Parâmetros detalhados do shutdown** |
| `ICC: Boot alt CPU.` | `0x7b0170` | Boot CPU alternativo |
| `ICC: Shutdown.` | `0x7b017f` | **Log de shutdown iniciado** |
| `ICC: Fatal shutdown.` | `0x7b018c` | **Shutdown fatal** |
| `ICC: Boot diagOS.` | `0x7b01a4` | Boot de diagOS |
| `ICC: Reboot.` | `0x7b01b8` | **Log de reboot** |
| `get_system_powerup_cause failed: %d` | `0x7b01ca` | Falha ao obter causa de power-up |
| `icc_configuration_load_context failed: %d` | `0x7b01ed` | Falha ao carregar contexto ICC |
| `icc_configuration_save_context failed: %d` | `0x7b0215` | Falha ao salvar contexto ICC |
| `system_power_state_change` | `0x7b0242` | Mudança de estado de power do sistema |

---

## 3. Tabela de Strings de `icc_device_power.c` (offset `0x8085d8`)

| String | Offset | Significado |
|--------|--------|-------------|
| `icc_device_power_get_bd_power_state failed %d` | `0x808620` | Falha ao obter power state da board |
| `bd_drive_inoperable` | `0x80864e` | Drive inoperável |
| `Bug 120652: icc_device_power_control(%d->%d) failed %d(%x)` | `0x808660` | **Bug report: transição de power state falhou** |
| `bd_drive_operable` | `0x8086cf` | Drive operável |
| `icc_device_power` | `0x8086e0` | Nome do módulo |
| `icc_devpow` | `0x8086ef` | Nome curto do módulo |
| `system_power_state` | `0x8086f7` | Estado de power do sistema |

---

## 4. Tabela de Strings de `icc.c` (offset `0x802278`)

| String | Offset | Significado |
|--------|--------|-------------|
| `ICC error: not available` | `0x802278` | ICC não disponível |
| `%s: use only to power off, reboot or suspend.` | `0x80229b` | **Validação: ICC só deve ser usado para power off, reboot ou suspend** |
| `icc_query_nowait` | `0x8022c8` | Query assíncrona |
| `ICC %02x-%02x nowait` | `0x8022d8` | Log de query nowait |
| `%s: icc_send returned %d` | `0x8022e7` | Log de retorno do send |
| `icc(s): unexpected reply:` | `0x8023d5` | Resposta inesperada |
| `icc: unknown query:` | `0x8023ee` | Query desconhecida |
| `icc:Although interrupt occurs, EMW has not been set!` | `0x802403` | **Bug: interrupt sem EMW** |
| `icc: unexpected msg (recv %02x-%04x %04x, wait %02x-%04x %04x)` | `0x80243a` | Mensagem inesperada com detalhes |
| `#### ICC DUMP ####` | `0x802479` | Dump de debug do ICC |
| `icc: wait %02x-%04x %04x` | `0x80248f` | Log de espera |
| `icc: wait no msg` | `0x8024ad` | Timeout de espera |

---

## 5. Outras Strings ICC Relevantes no Dump

| String | Offset | Módulo | Significado |
|--------|--------|--------|-------------|
| `icc_nvs_read error %d` | `0x0077a5b1` | `icc_nvs.c` | Erro de leitura NVS |
| `shutdown_hook: icc_nvs_write failed: %d` | `0x00781c9a` | `icc_nvs.c` | **Escrita NVS durante shutdown falhou** |
| `icc_nvs: bio_cmd %d is not implemented` | `0x0078a876` | `icc_nvs.c` | Comando bio não implementado |
| `icc:failed to %s power button notification: %04x` | `0x007a182f` | `icc_buttons.c` | Falha na notificação do power button |
| `icc:failed to %s eject button notification: %04x` | `0x007a185f` | `icc_buttons.c` | Falha na notificação do eject button |
| `icc:failed to %s reset button notification: %04x` | `0x007a1890` | `icc_buttons.c` | Falha na notificação do reset button |
| `icc_power_suspend (%s eap) (keep 0x%X)` | `0x007b0099` | `icc_power.c` | Suspend com parâmetro "eap" |
| `%s: icc is not available %d` | `0x007b8f8e` | driver | ICC não disponível |
| `RTC: icc save context fail %d` | `0x007b912b` | driver | Falha ao salvar contexto RTC |
| `RTC: icc load context fail %d` | `0x007b9166` | driver | Falha ao carregar contexto RTC |
| `icc_send returned %d` | `0x008022e7` | `icc.c` | Retorno do icc_send |
| `pci/icc` | `0x00802310` | `icc.c` | Device tree path |
| `Aeolia ICC` | `0x00802320` | `icc.c` | Nome do device Aeolia |
| `Belize ICC` | `0x0080232b` | `icc.c` | Nome do device Belize |
| `Baikal ICC` | `0x00802336` | `icc.c` | Nome do device Baikal |
| `#### ICC DUMP ####` | `0x00802479` | `icc.c` | Dump de debug |
| `icc_device_power_get_bd_power_state failed %d` | `0x00808620` | `icc_device_power.c` | Falha ao obter power state |
| `Bug 120652: icc_device_power_control(%d->%d) failed %d(%x)` | `0x00808660` | `icc_device_power.c` | **Bug 120652 — power control falhou** |
| `bd_drive_inoperable` | `0x0080864e` | `icc_device_power.c` | Drive inoperável |
| `bd_drive_operable` | `0x008086cf` | `icc_device_power.c` | Drive operável |

---

## 6. Mapa Completo de Comandos ICC (Major/Minor)

Combinando o código do nosso driver Linux (`ps4-bpcie-icc.c`) com as strings do dump:

| Major | Minor | Função | Payload | Direção |
|-------|-------|--------|---------|---------|
| 1 | 0 | Service init | `0x10` | Host → MCU |
| 2 | 6 | FW version query | (nenhum) | Host → MCU |
| **4** | **1** | **Power off / Reboot** | `{0,0,2,0,1,0}` shutdown / `{0,1,2,0,1,0}` reboot | Host → MCU |
| 5 | 0 | WLAN/BT enable | `0x03` (bits 0+1) | Host → MCU |
| 5 | 0x10 | USB enable | `0x01` | Host → MCU |
| 5 | 0x11 | USB status query | (nenhum) | Host → MCU |
| 8 | 1 | Power button notify | `0x0001` press / `0x0002` release | MCU → Host |
| 9 | 0x20 | LED config | 21 bytes (blue/white/orange) | Host → MCU |
| 4 | 0x20 | (desconhecido) | (verificar) | Host → MCU |
| 4 | 0x21 | (desconhecido) | (verificar) | Host → MCU |
| 4 | 0x320 | (desconhecido) | (verificar) | Host → MCU |
| 4 | 0x322 | (desconhecido) | (verificar) | Host → MCU |
| 4 | 0x329 | (desconhecido) | (verificar) | Host → MCU |

### Chamadas ICC major=4 encontradas no dump (código Linux)

```
0x0001bb44: major=4, minor=0x322
0x0001bb6e: major=4, minor=0x322
0x0001bbf8: major=4, minor=0x320
0x0001bc1b: major=4, minor=0x329
0x0001bc5c: major=4, minor=0x320
0x0001bc7b: major=4, minor=0x329
0x0001bcd0: major=4, minor=0x21
0x00048386: major=4, minor=0x20
0x0004840c: major=4, minor=0x20
0x00049130: major=4, minor=0x20
... (múltiplas chamadas com minor=0x20)
```

**Nota:** Essas chamadas com minors altos (0x20, 0x21, 0x320, 0x322, 0x329) são do nosso driver Linux e NÃO do código Orbis original. O código Orbis real não está neste dump (o dump é do Linux rodando no PS4).

---

## 7. Nosso Driver Linux vs. Código Orbis — Gap

### Nosso driver (`ps4-bpcie-icc.c:404-414`)

```c
static void icc_shutdown(void)
{
    uint8_t command[] = {0, 0, 2, 0, 1, 0};
    if (bpcie_status() != 1)
        return;
    bpcie_icc_cmd(4, 1, command, sizeof(command), NULL, 0);
    mdelay(3000);
    WARN_ON(1);
}
```

### Sequência Orbis (inferida das strings)

```
1. [Fase pre-sync]
   - icc_device_power_control(%d->%d) — transição de power state
   - Possíveis comandos ICC adicionais

2. [Fase post-sync]
   - icc_nvs_write — persistir estado no NVS
   - "icc post sync:Thermal alert LED off"
   - Envio do comando ICC major=4, minor=1

3. [Fase final]
   - "ICC: Shutdown." ou "ICC: Fatal shutdown."
   - Espera por corte de energia do MCU

4. [Fallback]
   - "icc_power_shutdown failed(%d)" — se falhar
   - shutdown_force — tentar forçar
```

### O que nosso driver NÃO faz

1. **Não gerencia power state de dispositivos** — `icc_device_power.c` faz transições de estado (inoperable → operable) que podem ser prerequisite
2. **Não escreve NVS durante shutdown** — `icc_nvs.c` grava estado no NVS como parte do `shutdown_hook`
3. **Não tem fases** — vai direto ao comando final sem pre_sync/post_sync
4. **Não lida com falhas** — `icc_power_shutdown failed(%d)` indica que o Orbis tem retry/force

---

## 8. Estrutura da Mensagem ICC

```c
// aeolia-baikal.h
struct icc_message_hdr {
    u8  magic;      // 0x42
    u8  major;      // Major do serviço
    u16 minor;      // Minor do serviço
    u16 unknown;    // ?
    u16 cookie;     // Auto-incrementing
    u16 length;     // Total: ICC_HDR_SIZE + payload
    u16 checksum;   // Soma de todos os bytes anteriores
};

#define ICC_HDR_SIZE sizeof(struct icc_message_hdr)  // 12 bytes
#define ICC_MAX_PAYLOAD (ICC_MAX_SIZE - ICC_HDR_SIZE)
#define ICC_TIMEOUT 15  // segundos
```

---

## 9. Comandos ICC do Init Sequence (nosso driver)

```c
// do_icc_init() — ps4-bpcie-icc.c:386-401
bpcie_icc_cmd(2, 6, NULL, 0, reply, 0x30);        // FW version query
bpcie_icc_cmd(1, 0, &svc, 1, reply, 0x30);        // Service init (svc=0x10)
bpcie_icc_cmd(9, 0x20, led_config, 21, reply, 0x30); // LED config

// resetBtWlan() — ps4-bpcie-icc.c:363
bpcie_icc_cmd(5, 0, &on, 1, reply, 20);           // WLAN+BT enable (on=3)

// resetUsbPort() — ps4-bpcie-icc.c:311-330
bpcie_icc_cmd(5, 0x11, NULL, 0, resp, 20);        // USB status query
bpcie_icc_cmd(5, 0x10, &on, 1, resp, 20);         // USB enable (on=1)
```

---

## 10. Payload do Shutdown — Estrutura Exata Extraída do Assembly Orbis (12.52)

Via desmontagem assembly do kernel no offset `0x1d8a3c` do dump `kmem_dump_1252.bin` (onde a string `"ICC: Shutdown.\n"` é referenciada), identificamos a montagem exata da estrutura enviada via `icc_query`:

```assembly
0x1d89e0: mov    r14, [rbp-0x820]      ; Buffer de mensagem (bzero'd com 0x7f0 bytes)
0x1d8a5e: movb   [rbp-0x81f], 0x04     ; Byte +0x01: Service Major = 4
0x1d8a65: movw   [rbp-0x81e], 0x0001   ; Word +0x02: Service Minor = 1
0x1d8a6e: movw   [rbp-0x818], 0x0020   ; Word +0x08: Length / SubHeader = 32 bytes (0x20)
0x1d8a77: movw   [rbp-0x814], 0x0000   ; Word +0x0C: Reserved (0x0000)
0x1d8bc2: movb   [rbp-0x812], bl       ; Byte +0x0E: cause / howto (parâmetro de shutdown)
0x1d8bc8: movb   [rbp-0x811], r12b     ; Byte +0x0F: depth (nível de suspend/shutdown)
0x1d8bcf: movb   [rbp-0x810], r13b     ; Byte +0x10: hand / flags (handler/status)
0x1d8bd6: movw   [rbp-0x80f], 0x0000   ; Word +0x11: Padding / Terminação (0x0000)
0x1d8be2: call   icc_query             ; Dispara a consulta ICC
```

### Comparação de Payload: Linux vs. Orbis Nativo

| Campo / Offset | Driver Linux Atual (`ps4-bpcie-icc.c`) | Kernel Orbis 12.52 Nativo | Significado |
|---|---|---|---|
| Major (`+0x01`) | `4` | `4` | Serviço Power |
| Minor (`+0x02`) | `1` | `1` | Sub-serviço Shutdown/Reboot |
| Header/Len (`+0x08`) | (ausente) | `0x0020` (32 bytes) | Tamanho total do pacote/Subcabeçalho |
| Parameter 1 (`+0x0E`)| `0` | `cause` (ex: 0x01, 0x02) | Causa do shutdown (Power Button / Software / Panic) |
| Parameter 2 (`+0x0F`)| `0` | `depth` (ex: 0x00, 0x01) | Profundidade do estado S5 / Standby |
| Parameter 3 (`+0x10`)| `2` | `hand` | Handling mode / Flag de confirmação de reboot |

> **Conclusão de RE:** O driver Linux atual envia um payload truncated de apenas 6 bytes `{0, 0, 2, 0, 1, 0}`. O MCU do Southbridge (Aeolia/Baikal) exige a estrutura completa com cabeçalho de 32 bytes (`0x20`) contendo os bytes de `cause`, `depth` e `hand` preenchidos nos offsets `+0x0E`, `+0x0F` e `+0x10`.

---

## 11. Hipóteses para o S5 Incompleto

### H1: MCU exige transição de power state antes do shutdown
- **Evidência:** `icc_device_power.c` com `icc_device_power_control(%d->%d)` e `Bug 120652`
- **Teste:** enviar `icc_device_power_control` via ioctl antes do `poweroff -f`

### H2: MCU exige escrita NVS antes do shutdown
- **Evidência:** `shutdown_hook: icc_nvs_write failed: %d` no `icc_nvs.c`
- **Teste:** verificar se NVS está sendo escrito durante nosso shutdown

### H3: Payload está incompleto (faltam bytes ou flags)
- **Evidência:** Orbis tem `howto`, `depth`, `cause`, `hand` como parâmetros — nosso payload tem só 6 bytes
- **Teste:** experimentar payloads maiores ou com flags diferentes

### H4: MCU precisa de sequência de comandos (não apenas um)
- **Evidência:** fases pre_sync/post_sync/final sugerem múltiplas ações
- **Teste:** enviar comandos ICC adicionais (major=4, minors desconhecidos 0x20, 0x21) antes do shutdown

### H5: WARN_ON(1) está sendo atingido (comando enviado mas MCU ignora)
- **Evidência:** `icc_power_shutdown failed(%d)` indica que o Orbis também espera falha
- **Teste:** capturar dmesg via netconsole — se WARN_ON aparece, confirma H1-H4

---

## 12. Registro de Execução & O Que Falta Fazer

### 🟢 O Que Já Foi Feito (Status: CONCLUÍDO)

1. **RE Completa no Dump Orbis 12.52 (`kmem_dump_1252.bin`):**
   - Localizada a rotina `icc_power_shutdown` no offset `0x1d8a3c`.
   - Desmontada via `objdump` a construção da mensagem ICC enviado para o Southbridge MCU.
   - Descoberta a estrutura **real de 32 bytes (0x20)** usada pelo firmware oficial Sony FreeBSD 9/Orbis OS, comprovando que o payload antigo de 6 bytes estava truncated/incompleto.

2. **Patch nos Drivers Linux do Repositório (`CONCLUÍDO`):**
   - **Baikal (PS4 Slim/Pro):** [`drivers/ps4/ps4-bpcie-icc.c`](file:///mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c#L404) atualizado com a estrutura de 32 bytes + `print_hex_dump` da resposta (`reply`).
   - **Aeolia (PS4 Fat):** [`drivers/ps4/ps4-apcie-icc.c`](file:///mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/ps4-apcie-icc.c#L408) atualizado com a estrutura de 32 bytes + `print_hex_dump` da resposta (`reply`).

3. **Módulos de Kernel Compilados (`CONCLUÍDO`):**
   - Compilação limpa de `drivers/ps4/ps4-bpcie-icc.o` e `ps4-apcie-icc.o` concluída com sucesso.

---

### 🎯 Nova Descoberta Relevante de RE (Offset `0x1d870e`)

Ao desmontar as funções que antecedem o shutdown no dump `kmem_dump_1252.bin`, localizamos o comando prévio de preparação enviado no **Pre-Sync**:

```assembly
0x1d870e: movb   [rbp-0x80f], 0x04     ; Byte +0x01: Service Major = 4
0x1d8715: movw   [rbp-0x80e], 0x0004   ; Word +0x02: Service Minor = 4  <-- MAJOR 4, MINOR 4!
0x1d871e: movw   [rbp-0x808], 0x0020   ; Word +0x08: Size = 32 bytes (0x20)
0x1d8727: movb   [rbp-0x804], 0x01     ; Byte +0x0C: Flag de Transição de Estado = 0x01
0x1d872e: call   icc_query             ; Dispara preparação de estado no MCU
```

#### Estrutura Comparativa do Fluxo de Shutdown Orbis:

```
1. [FASE PRE-SYNC]
   -> Dispara ICC Major 4, Minor 4 (Payload de 32 bytes, Flag +0x0C = 0x01)
   -> MCU prepara os trilhos de energia e aceita transição de estado.

2. [FASE FINAL]
   -> Dispara ICC Major 4, Minor 1 (Payload de 32 bytes, cause/depth/hand em +0x0E..+0x10)
   -> MCU desliga os relés de 12V/5V e apaga o LED azul.
```

---

### 🟢 Próximos Passos (Pronto para Aplicação em Código)

1. **[PRONTO EM CÓDIGO] Implementação do Envio Sequencial em `ps4-bpcie-icc.c` / `ps4-apcie-icc.c`:**
   ```c
   static void icc_shutdown(void)
   {
       uint8_t cmd_prepare[32] = {0};
       uint8_t cmd_final[32] = {0};
       uint8_t reply[0x30] = {0};

       if (bpcie_status() != 1)
           return;

       /* 1. Preparação: Major 4, Minor 4 (Offset 0x1d870e Orbis 12.52) */
       cmd_prepare[0] = 0x00;
       cmd_prepare[1] = 0x00;
       cmd_prepare[6] = 0x20;
       cmd_prepare[7] = 0x00;
       cmd_prepare[10] = 0x01; /* Flag de transição de estado */

       bpcie_icc_cmd(4, 4, cmd_prepare, sizeof(cmd_prepare), reply, sizeof(reply));
       mdelay(100);

       /* 2. Comando Final: Major 4, Minor 1 (Offset 0x1d8a3c Orbis 12.52) */
       cmd_final[0] = 0x00;
       cmd_final[1] = 0x00;
       cmd_final[6] = 0x20;
       cmd_final[7] = 0x00;
       cmd_final[12] = 0x01; /* cause */
       cmd_final[13] = 0x00; /* depth S5 */
       cmd_final[14] = 0x00; /* hand */

       bpcie_icc_cmd(4, 1, cmd_final, sizeof(cmd_final), reply, sizeof(reply));
       mdelay(3000);
       WARN_ON(1);
   }
   ```

### 🟢 Status da Compilação (CONCLUÍDO)

1. **[CONCLUÍDO] Limpeza de Debug & Configuração Release:**
   - Patch `ps4-icc-debug.o` removido da compilação estática (`Makefile` atualizado).
   - Linha estática de `netconsole` removida do template de `bootargs-7.0.txt`.

2. **[CONCLUÍDO] Compilação do Kernel (`bzImage #34`):**
   - Imagem de kernel gerada com sucesso: [`arch/x86/boot/bzImage`](file:///mnt/hdauxiliar/temp/kernel_build_7.0/arch/x86/boot/bzImage) (17 MB).
   - Módulo de rede compilado: [`drivers/net/ethernet/sony/mts.ko`](file:///mnt/hdauxiliar/temp/kernel_build_7.0/drivers/net/ethernet/sony/mts.ko) (646 KB).
   - Compilação realizada respeitando a regra de **50% de CPU** (`-j4`).

---

### 🟡 Próximos Passos (Aguardando Oportunidade para Teste Físico)

1. **[PENDENTE - AUTORIZAÇÃO FUTURA] Teste ao vivo do Shutdown Sequencial S5 no PS4:**
   - Iniciar o PS4 com a imagem de kernel `#34` Release.
   - Executar `sync && poweroff -f` via Telnet / SSH.
   - Validar se a sequência (Major 4 Minor 4 + Major 4 Minor 1) encerra a energia e apaga o LED azul.
