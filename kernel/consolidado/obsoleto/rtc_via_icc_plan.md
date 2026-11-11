# Plano: RTC via ICC no PS4 Linux

**Data:** 2026-07-24
**Status:** Plano aprovado para implementação
**Autor:** Análise via RE do dump Orbis 12.52 + verificação no PS4 real
**Revisão:** 2026-07-25 — RE confirmatória do driver `rtc.c` no kernel x86 (`dc57f...`, `dc3f5bd0`, etc.) totalmente validando as descobertas abaixo; detalhes na seção "Validação da RE (2026-07-25)".

---

## ⭐ Dois drivers RTC no Orbis (descoberta 2026-07-25)

A RE desta semana revelou que o kernel Orbis tem **DOIS drivers RTC distintos em camadas**:

| Driver | Arquivo fonte | Camada | Hardware | Funções RE |
|---|---|---|---|---|
| **`rtc_mvl.c`** | `sys/dev/scesb/rtc/rtc_mvl.c` | baixo nível (acesso direto PIO/MMIO ao SoC) | Marvell Yukon (MediaTek/Marvell family — `_mvl`) | `dc5d63f0` probe, `dc5d6450` attach, `dc5d6600` read_aeolia_rtc, `dc5d6870` gettime |
| **`rtc.c`** | `sys/dev/scesb/rtc/rtc.c` | alto nível (via ICC + MMIO 0x5180000/0x5140000) | genérico (suporta Aeolia / Belize / Baikal) | `dc57e9d0` init_exclock, `dc57f340` load_ctx, `dc57f6f0` save_ctx, `dc3f5bd0` icc_query wrapper |

> **Importância para o plano**: o driver Linux `rtc-ps4-icc.c` deve seguir omodelo de **`rtc.c`** (camada via ICC), não `rtc_mvl.c`. Razão:
> - `rtc.c` é o "driver do console" — usa ICC (que já temos no Linux via `bpcie_icc_cmd`) + MMIO padrão de 8 bytes.
> - `rtc_mvl.c` é o driver de baixo nível do IP core Marvell — os offsets `0x130..0x13c`/`0x160..0x164` provavelmente correspondem ao barramento ICC "através do southbridge", acesso pelo qual o SC expõe via ICC. Em Linux teríamos que expor o ICC indirect já que o PHY/barramento Aeolia não está diretamente acessível pelo kernel x86.
> - `rtc_mvl.c` é **read-only** (sem settime/Write) e serve para o "ciclo de leitura estável" — o Orbis nunca nele escreveu; em vez disso, **quando precisa settime, ele usa `rtc.c`** via MMIO `0x5140000`.

Análise consolidada do driver `rtc_mvl.c` em `consolidado/decompiled/baikal_rtc_mvl.txt`.

---

## Objetivo

Implementar suporte RTC via ICC no PS4 Linux para corrigir o clock do sistema (atualmente travado na build epoch, bloqueando `pacman` por validação SSL).

---

## Causa Raiz

- `CONFIG_RTC_CLASS` **não habilitado** no kernel do PS4 → sem `/dev/rtc`, sem `/sys/class/rtc`
- Não existe driver Linux para o RTC Marvell do PS4 (que é baseado em ICC)
- PS4 não tem bateria RTC → após cold boot, clock volta para a epoch do kernel build (atualmente 2026-06-26)
- Orbis FreeBSD implementa RTC via dois serviços ICC distintos:
  - Strings `RTC: icc save context fail %d` e `RTC: icc load context fail %d` no módulo `icc_power.c`

---

## Descobertas da RE (dump Orbis 12.52)

### Serviço ICC 2 — Context Load/Save

| Operação   | ICC Major | ICC Minor | Sub-op (major/minor) | Payload      |
| ---------- | --------- | --------- | -------------------- | ------------ |
| Save ctx   | 2         | 0x0b      | 0x81 / 0x1           | 1 byte (valid flag) |
| Load ctx   | 2         | 0x0c      | 0x81 / 0x1           | 1 byte (valid flag) |

Despacho: `icc_send(0x81, 0x1, &flag)` → tradução interna para ICC major=2 (0x0b/0x0c).

Funções Orbis localizadas:
- Dispatch save: `0xffffffff80361a20` (valida soma ≤ 0x100, jmp `0x361a50`)
- Dispatch load: `0xffffffff80361b80` (valida soma ≤ 0x100, jmp `0x361bb0`)
- Implementação: `0xffffffff80361a50` (save), `0xffffffff80361bb0` (load)

### Serviço ICC 4 — Alarm Control

| Operação | ICC Major | ICC Minor | Sub-op | Data        |
| -------- | --------- | --------- | ------ | ----------- |
| Read     | 4         | 0x50      | 1 byte | retorna 0xff = sem alarmes, ou bitmask |
| Write    | 4         | 0x50      | 1 byte | escreve bitmask |

**Bitmask:**
- bit 0 = alarm0 (offset 0xc0 no device struct)
- bit 1 = alarm1 (offset 0xc4)
- bit 2 = alarm2 (offset 0xc8)

### MMIO (usado pelo driver Orbis RTC)

- `0x5180000`: read 8 bytes → registros de tempo RTC
- `0x5140000`: write 8 bytes → setar tempo RTC
- Ajustes: `0xffffffffb1005e00 - valor_RTC` (frames de epoch arbitrária)

### Estado Global (Orbis)

- `0x821d6a88`: ponteiro para RTC device struct
  - `+0xcc`: flag "context loaded"
  - `+0xc0`, `+0xc4`, `+0xc8`: 3 alarmes, bit 1 = habilitado
- `0x821d6ab0`: flag "RTC iniciaisado"
- `0x821d6ac0`: buffer de 96KB para contexto

### Referências adicionais

- `0x80266b00`: função RTC chamada por load/save (mutex/dev init?)
- `0x80447090`: ICC transport (`icc_send` real)
- `0x800a5bd0`: ICC RTC read alarm (`icc_rtc_read_alarm(major=4, minor=0x50, len=1, &byte)`)
- `0x800a5a10`: ICC RTC write alarm (`icc_rtc_write_alarm(...)`)

---

## ⭐ Validação da RE (2026-07-25)

Decompilação direta das funções `rtc.c` do kernel x86_64 (`kmem_dump_1252.bin`,
base ELF `0xffffffffdc350000`) **confirma 100% das descobertas acima**, e adiciona
precisão sobre os endereços_reais.

### Funções confirmadas

| Nome estimado | vaddr (kernel x86) | tamanho | confirma |
|---|---|---|---|
| `icc_query` (wrapper ICC, sig len≤1024) | `0xffffffffdc3f5bd0` | 233 B | contrato ICC (major≤4, len≤0x401) |
| `icc_query_write` (variante de escrita) | `0xffffffff dc3f5a10` | — | usado em write_alarm |
| `icc_send_internal` (transport subjacente) | `0xffffffff dc797090` | — | packet ICC de 2032 B |
| `ssb_rtc_init_exclock` (boot init) | `0xffffffff dc57e9d0` | 465 B | chama `icc_query(4,0x50,1,...)` + vtable + MMIO `0x5180000` |
| `rtc_save_context` | `0xffffffff dc57f6f0` | 308 B | chama `dc6b1a20(0x81,1,&flag)` (save=minor 0x0b) |
| `rtc_load_context` | `0xffffffff dc57f340` | 601 B | chama `dc6b1b80(0x81,1,&flag)` (load=minor 0x0c) + MMIO read `0x5180000` + write `0x5140000` em cold start |
| `dc6b1a20` — Dispatch save (sub-op 0x81) | `0xffffffff dc6b1a20` | — | equivalente kernel x86 de `0x80361a20` |
| `dc6b1b80` — Dispatch load (sub-op 0x81) | `0xffffffff dc6b1b80` | — | equivalente kernel x86 de `0x80361b80` |
| `dc839e40` — MMIO READ 8 bytes | `0xffffffff dc839e40` | — | wrappee legível (`(end_addr, &buf, 8)`) |
| `dc839d90` — MMIO WRITE 8 bytes | `0xffffffff dc839d90` | — | wrappee legível (`(end_addr, &buf, 8)`) |
| `dc5b6b00` — lock dev RTC e retorna softc | `0xffffffff dc5b6b00` | — | referenciado em save/load/init |

### Globais confirmadas (kernel x86)

| Endereço | conteúdo |
|---|---|
| `0xffffffffde526a88` | ponteiro para `ssb_rtc` softc (RTC device) — plano original diz `0x821d6a88` (cópia SC); devido a relocação do kernel, espaço x86 correspondente é `0xffffffffde526a88` |
| `0xffffffffdeaacea0` | mutex/recursiva mtx (`mtx_init`, checada em `__FILE__:0x...` em todo retorno crítico) |

> ⚠️ **Importante**: o plano original cita como endereços globais os valores `0x80xxxxxx` (de
> análise de dumps do SC ARM), porém o kernel x86 do PS4 referencia as estruturas
> em endereços `0xffffffffde...`. Para implementação do driver Linux o importante
> é que o protocolo ICC e os offsets (`+0xc0/+0xc4/+0xc8/+0xcc` no softc) estão corretos;
> os endereços absolutos só importam para hooks via kprobe etc. — que **não** serão
> necessários no driver.

### Descrição do MMIO read/write (`0x5180000` / `0x5140000`)

A leitura completa observada no Orbis (`rtc_load_context` linhas 24-66):

```c
// Passo 1: ICC load context (recuperar flag de "contexto válido"):
rc = icc_dispatch_load(0x81, 1, &flag);              // → major=2, minor=0x0c
if (rc) device_printf("RTC: icc load context fail %d", rc);

// Passo 2: obter offset de época salvado em registry (vtable em softc+0x30):
(*vtable.get_registry_offset)(softc, &reg_offset);

// Passo 3: MMIO read: 8 bytes em 0x5180000 (com buffer transitório):
rc = mmio_read_8(0x5180000, &mmio_buf, 8);            // dc839e40

// Passo 4: combinar (mmio_time + reg_offset) → tempo local
local_time = mmio_time + reg_offset;

// Passo 5 (somente em cold start, flag==0): escrever de volta para iniciar o RTC
if (rc != 0 && flag == '\0') {
    epoch_adj = -0x4effa200 - local_time;              // converte para epoch "arbitrária"
    global_epoch_offset = epoch_adj;
    rc = mmio_write_8(0x5140000, &epoch_adj_buf, 8);    // dc839d90
    if (rc) device_printf("[RTC] ERR: %s sceRegMgrSetBin() Fail:%d", ...);
    device_printf("RTC device error: Set Usertime 1970/01/01");
}

// Passo 6: ler de volta do 0x5140000 (completa o tempo com ajuste fino)
rc = mmio_read_8(0x5140000, &readback, 8);
final_time = local_time + 0x4effa200 + readback;       // ainda ajusta com 0x4effa200
*out_time = final_time;
```

**Constante mágica `0x4effa200`** do Orbis é o deslocamento de "epoch arbitrária Sony"
(usado como offset entre o epoch unix 1970 e a epoch do RTC do SC). No driver Linux
**NÃO** precisamos usar isto — o Linux trabalha com epoch unix diretamente, e o
context save/load do SC guarda apenas o offset para zerar no boot do hardware.

### Descrição do `rtc_save_context` (salva contexto no shutdown)

```c
flag_loaded = softc->flag_loaded;            // offset +0xcc
if (flag_loaded != 0) {
    rc = icc_dispatch_save(0x81, 1, &flag_loaded);
    if (rc) device_printf("RTC: icc save context fail %d", rc);
}

// Em qualquer caso: reler bitmask de alarmes e atualizar se necessário
rc = icc_query(4, 0x50, 1, &current_alarms);
if (rc == 0 && current_alarms != 0xff) {
    uchar new = current_alarms;
    if (softc->alarm0 [+0xc0] & 2) new |= 1;
    if (softc->alarm1 [+0xc4] & 2) new |= 2;
    if (softc->alarm2 [+0xc8] & 2) new |= 4;
    if (current_alarms != new)
        rc = icc_query_write(4, 0x50, 1, &new);   // dc3f5a10
}
```

### Strings do driver `rtc.c` (+nomes de arquivo fonte)

```
0xffffffffdcb08ef4  W:\...\scesb\rtc\rtc.c              (path do modulo)
0xffffffffdcb0908b  Aeolia RTC                           (device desc PS4 fat)
0xffffffffdcb09096  Belize RTC                           (device desc PS4 Pro)
0xffffffffdcb090a1  Baikal RTC                           (device desc PS4 Slim) ← é o nosso!
0xffffffffdcb09077  pci/ssb_rtc                          (driver PCI bus)
0xffffffffdcb0906b  ssb_rtc_pci                          (probe)
0xffffffffdcb0907b  ssb_rtc                              (device name)
0xffffffffdcb090e8  rtc_rw                               (sx-lock para leitura/escrita)
0xffffffffdcb090db  rtc_mtx_lock                         (mutex do modulo)
0xffffffffdcb09102  rtc_shutdown_event                   (shutdown hook)
0xffffffffdcb09185  RTC device error: Set Usertime 1970/01/01  (warning cold start)
0xffffffffdcb09050  get_registry_offset                  (vtable method)
0xffffffffdcb09012  set_registry_offset                  (vtable method)
0xffffffffdcb09026  [RTC] ERR: %s sceRegMgrGetBin() Fail :%d
0xffffffffdcb08fe8  [RTC] ERR: %s sceRegMgrSetBin() Fail :%d
```

### Diff vs `rtc_mvl.c` (driver de baixo nível)

| mecânica | `rtc.c` (camada alta, ICC) | `rtc_mvl.c` (camada baixa, MMIO direto) |
|---|---|---|
| Acesso ao hardware | ICC + MMIO `0x5180000`/`0x5140000` | PIO ou MMIO direto via `bus_space` em offsets `0x100/0x130..0x13c/0x160/0x164` |
| Settime | ✅ sim (via `0x5140000` MMIO write) | ❌ **read-only** |
| Source dos offsets | descoberta SC ("Aeolia RTC") | descoberta direta no SoC |
| Retry da leitura | não (ICC garante atomicidade) | ✅ retry de 21 tentativas × 100us (Bug 55086) |
| Status de saúde | via ICC `4,0x50` (bitmask alarm) | le direto `0x100` (bit 2=OK, bit 8=battery fail) |
| Uso em Linux | ✅ **recomendado** (tem `settime`) | ⚠️ útil para `read_alarm` etc., mas só-leitura |

---

## Opções de Design

### A: Driver RTC completo via ICC
- **Prós:** `/dev/rtc` real, `hwclock`, sincronização kernel time, suporte a alarmes
- **Contras:** Requer mudanças no config + novo driver + plumbing ICC

### B: fake-hwclock + NTP no boot
- **Prós:** Sem mudanças no kernel, funciona imediato, simples
- **Contras:** Não é RTC real; depende de rede; sem alarme

### C: Híbrido (escolhido)
- **Prós:** RTC real + fallback network sync
- **Contras:** Mais trabalho
- **Detalhes:** Habilitar `CONFIG_RTC_CLASS` + criar `rtc-ps4-icc` + adicionar NTP fallback

---

## Plano de Implementação

### Fase 1: Configuração do Kernel
1. Habilitar `CONFIG_RTC_CLASS=y`
2. Habilitar `CONFIG_RTC_INTF_DEV=y` (para `/dev/rtc`)
3. Habilitar `CONFIG_RTC_DRV_PS4_ICC=m`
4. Rebuild do kernel (`bzImage` #33 já tem patch S5)

### Fase 2: Exportação ICC
Em `drivers/ps4/ps4-bpcie-icc.c` e `ps4-apcie-icc.c`:
- Adicionar `EXPORT_SYMBOL_GPL(bpcie_icc_cmd)` / `EXPORT_SYMBOL_GPL(apcie_icc_cmd)`
- Adicionar wrapper `int ps4_icc_rtc_cmd(u8 major, u8 minor, void *data, size_t len)` com loop de retry (até 100× 50ms) — mesmo padrão do power-on da GBE

### Fase 3: Driver RTC (`drivers/rtc/rtc-ps4-icc.c`)

Driver platform minimalista baseado na semântica real observada em `rtc.c` (RE 2026-07-25):

```c
struct ps4_rtc_softc {
    void __iomem *mmio_read;     // ioremap(0x5180000, 8)
    void __iomem *mmio_write;    // ioremap(0x5140000, 8)
    // alarmes
    u8 alarm0_en, alarm1_en, alarm2_en;
};

static const struct rtc_class_ops ps4_rtc_ops = {
    .read_time   = ps4_rtc_read_time,
    .set_time    = ps4_rtc_set_time,
    .read_alarm  = ps4_rtc_read_alarm,
    .set_alarm   = ps4_rtc_set_alarm,
    .alarm_irq_enable = ps4_rtc_alarm_irq_enable,
};

// ----- read_time (seguindo rtc_load_context dc57f340) -----
static int ps4_rtc_read_time(struct device *dev, struct rtc_time *tm)
{
    u8  ctx_loaded;
    u64 mmio_time;
    int rc;

    // 1) ICC load context: recupera flag "contexto salvo"
    rc = ps4_icc_rtc_cmd(2, 0x0c, &ctx_loaded, 1);   // major=2 minor=0x0c len=1
    if (rc)
        dev_warn(dev, "RTC: icc load context fail %d\n", rc);
    else
        dev_dbg(dev, "context loaded flag = %u\n", ctx_loaded);

    // 2) MMIO read 0x5180000 (8 bytes) — le direto (NAO usar 0x4effa200 — Linux trabalha com epoch unix)
    if (ps4_rtc_read_mmio64(sc->mmio_read, &mmio_time)) {
        dev_err(dev, "MMIO read 0x5180000 falhou\n");
        mmio_time = 0;
    }

    // 3) Em cold start (flag=0), o Orbis reescreve 0x5140000 com epoch corrigido.
    //    Linux NÃO replica isto — mantém o MMIO como está; date/hwclock faz set_time quando preciso.
    rtc_time64_to_tm(mmio_time, tm);
    return 0;
}

// ----- set_time (seguindo rtc_load_context Passo 5) -----
static int ps4_rtc_set_time(struct device *dev, struct rtc_time *tm)
{
    u64 t = rtc_tm_to_time64(tm);
    int rc;

    // Escreve epoch unix direto (o Orbis subtract 0x4effa200 para sua epoch arbitrária;
    // Linux não precisa)
    rc = ps4_rtc_write_mmio64(sc->mmio_write, t);
    if (rc) return rc;

    // Salva contexto para persistir entre power cycles (preserva "context loaded")
    u8 flag = 1;
    ps4_icc_rtc_cmd(2, 0x0b, &flag, 1);   // ignore falha — apenas log
    return 0;
}

// ----- read_alarm (seguindo ssb_rtc_init_exclock dc57e9d0) -----
static int ps4_rtc_read_alarm(struct device *dev, struct rtc_wkalrm *alrm)
{
    u8 bitmask;
    int rc = ps4_icc_rtc_cmd(4, 0x50, &bitmask, 1);
    if (rc) return rc;
    if (bitmask == 0xff) {
        alrm->enabled = 0;
    } else {
        alrm->enabled = !!(bitmask & 0x7);   // qualquer bit 0/1/2 = enabled
        // alarm0/alarm1/alarm2 em offsets softc +0xc0/+0xc4/+0xc8 (~específico)
    }
    return 0;
}

// ----- set_alarm (variação write da mesma minor) -----
static int ps4_rtc_set_alarm(struct device *dev, struct rtc_wkalrm *alrm)
{
    u8 new = alrm->enabled ? 0x7 : 0x00;  // 3 alarmes em bit 0/1/2 do bitmask
    return ps4_icc_rtc_cmd_write(4, 0x50, &new, 1);  // observed: dc3f5a10
}
```

#### Notas de implementação vindas da RE

1. **Não usar `0x4effa200`**: é o offset de "epoch Sony" adotado pelo Orbis para a
   aritmética interna dele. No Linux, escrever/ler epoch unix diretamente em `0x5180000`/`0x5140000`.
   Validável em teste: comparar `cat /sys/class/rtc/rtc0/since_epoch` com `date +%s`.

2. **Endereço `0x5180000` é físico do SoC** — deve ser ioremap'd no driver, NÃO é PCI BAR.
   Confirmar em `/proc/iomem` no PS4 real antes de implementar; se já estiver mapeado por outro
   driver (e.g. `ps4-apcie`), reusar via `devm_ioremap`.

3. **Cold start**: quando o SC perdeu contexto (bateria ausente), o Orbis escreve
   epoch 1970 em `0x5140000` para "inicializar". No Linux devemos imitar: no probe,
   se `icc_query_load_context` retornar `flag==0`, fazer um `set_time(0)` implícito
   (ou deixar `hwclock --systohc` fazer isto).

4. **Retry no transporte ICC**: o wrapper `ps4_icc_rtc_cmd` deve tentar até 100× com
   `msleep(50)` entre tentativas (mesmo padrão usado em `bpcie_icc_cmd(4, 0x38, ...)`
   para GBE power-on — ver `AGENTS.md`).

5. **Comprimento máximo do payload ICC**: confirmado por `icc_query` (`dc3f5bd0`):
   `len < 0x401` (1024 bytes). RTC usa len=1 apenas, então nunca esbarra no limite.

6. **Maior complexidade**: a função `ssb_rtc_init_exclock` (dc57e9d0) ainda chama
   `func_0xffffffffdc5b6b00` (obter softc) e uma vtable em `softc+0x30` para
   `get_registry_offset`/`set_registry_offset`. Linux não precisa replicar — pode
   manter `__tab_offset` zero (ou seja, treat MMIO read/write como tempo absoluto).

7. **Tolerância a frio `read-only`**: o baixo nível `rtc_mvl.c` (decompilei em
   `baikal_rtc_mvl.txt`) faz leituras estáveis com retry (Bug 55086) para os 4 bytes
   do RTC Aeolia em offsets `0x130..0x13c`. Se observarmos leitura "salta" em
   `0x5180000` 8 bytes, podemos aplicar a mesma técnica de retry (le duas vezes e
   comparar) — o Orbis não faz porque ICC garante atomicidade, mas diretamente no
   MMIO exposto é uma defesa.

### Fase 4: Integração & Teste
1. Adicionar `rtc-ps4-icc` ao kernel config
2. Rebuild kernel + módulos
3. Deploy no PS4: `scp bzImage + módulos`, `depmod`, `modprobe rtc-ps4-icc`
4. Validar: `hwclock -r`, `date`, `pacman -Sy`

### Fase 5 (opcional): Fallback NTP
- Adicionar `systemd-timesyncd` ou `ntpd -q -g` no boot para sync inicial
- Considerar `fake-hwclock` como safety net

---

## Mudanças de Arquivos

| Arquivo | Mudança |
| ------- | ------- |
| `arch/x86/configs/ps4_defconfig` | `CONFIG_RTC_CLASS=y`, `CONFIG_RTC_INTF_DEV=y`, `CONFIG_RTC_DRV_PS4_ICC=m` |
| `drivers/ps4/ps4-bpcie-icc.c` | `EXPORT_SYMBOL_GPL(bpcie_icc_cmd)` + `ps4_icc_rtc_cmd()` |
| `drivers/ps4/ps4-apcie-icc.c` | Idem para Aeolia |
| `drivers/rtc/rtc-ps4-icc.c` | **NOVO** driver |
| `drivers/rtc/Kconfig` | Adicionar `config RTC_DRV_PS4_ICC` |
| `drivers/rtc/Makefile` | `obj-$(CONFIG_RTC_DRV_PS4_ICC) += rtc-ps4-icc.o` |

---

## Riscos & Mitigações

| Risco | Mitigação |
| ----- | --------- |
| Protocolo ICC RTC difere no hardware vs. dump | Testar incremental; usar retry loop no `ps4_icc_rtc_cmd` |
| Endereços MMIO (0x5180000/0x5140000) podem precisar de mapping | Usar `ioremap()` no driver; verificar com `/proc/iomem` |
| Sem bateria = clock ainda reseta em power loss | NTP no boot é mandatório; RTC mantém hora enquanto energizado |
| Rebuild do kernel necessário | `bzImage` #33 existe; só adicionar config + driver |
| **`0x4effa200` — const mágica do Orbis** (RE 2026-07-25) | NÃO replicar em Linux — escrever epoch unix puro em `0x5140000`. Validar com `date` |
| **MMIO `0x5180000` já mapeado por outro driver** | Verificar em `/proc/iomem` no PS4 real; se ocupado, usar `devm_ioremap` compartilhado ou `ioremap` una vez só no probe |
| **`read_alarm` pode demorar (ICC slow path)** | Wrapping `read_alarm` com timeout curto + fallback (00:00 se falha) |
| **Bitmask 0x50 ≠ 0xff em boot pode invalidar alarms do Orbis** | No `set_alarm` Linux, mascarar apenas bits 0/1/2 — mantém o restante (escalabilidade futura) |
| **`rtc.c` vs `rtc_mvl.c` — escolha errada** | Driver Linux seguirá `rtc.c` (camada ICC). `rtc_mvl.c` é read-only e de baixo nível, não adequado |

---

## Critérios de Sucesso

- `/dev/rtc0` aparece após `modprobe rtc-ps4-icc`
- `hwclock -r` retorna tempo válido
- `date` permanece estável entre boots (com NTP sync)
- `pacman -Sy` não falha por erro de clock

---

## Histórico de Decisões

- **2026-07-24**: Plano criado com base em RE do dump Orbis 12.52 + verificação ao vivo (`CONFIG_RTC_CLASS=n`, data do PS4 = Jun 26 2026)
- **2026-07-24**: Opção C escolhida (driver completo + NTP fallback vs. somente fake-hwclock)
- **2026-07-25**: RE confirmatória completa das funções `rtc.c` no kernel x86 (`dc57e...`, `dc3f5bd0` icc_query, `dc839e40`/`dc839d90` MMIO). Tudo validado: ICC major=2/4 + minor=0x0b/0x0c/0x50 + MMIO 0x5180000/0x5140000. Descobertos dois drivers RTC distintos (`rtc_mvl.c` read-only e `rtc.c` via ICC) — driver Linux seguirá `rtc.c`. Constante mágica `0x4effa200` documentada como não usada no Linux. Strings de descrição "Aeolia/Belize/Baikal RTC" confirmadas. Ver detalhes na seção "Validação da RE (2026-07-25)".
