# HANDOFF — Driver de Memória Baikal (SPM/DDR3, 00:14.6)

**Subsistema:** SPM (Scratch Pad Memory) — Baikal Memory  
**Dispositivo PCI:** 00:14.6, Vendor 0x104d, Device 0x90dd  
**Hardware:** PS4 Slim (CUH-2xxx, Baikal B1), 256 MB SPM DDR3  
**Kernel alvo:** 7.0.8-Strawberry-ThinLTO-Baikal-+ (x86_64)  
**Status:** Fases 1–5 VALIDADAS AO VIVO (2026-11-12) — driver carrega via udev, leitura/sysfs da SPM validados, build oficial Fase 1–3 OK (tag `20261112-baikal-memory-fase3`), RTC via ICC convive com o `baikal-memory` e reporta tempo real (Fase 4: `hwclock -r` exige kernel com UIE emulation) e Fase 5 (escrita controlada restrita à janela BAR2 com proteção `allow_write=0`) testada e aprovada ao vivo no PS4 Slim. Próximo passo: Fase 6 (stress test e cold boot) e deploy de kernel com UIE emulation para fechar `hwclock -r`.  
**Acesso ao PS4:** SSH WiFi `root@192.168.6.128`, senha `ps4`. Porta `eth0` (cabeada) não tem link (PHY mudo, bug conhecido).

---

## 1. O que foi descoberto (BARs confirmados ao vivo)

### BARs no hardware real (este console, boot de 2026-11-12):

| BAR | Endereço Físico | Tamanho | Conteúdo ao vivo | Status |
|-----|-----------------|---------|------------------|--------|
| BAR0 | 0xcc000000–0xcc000fff | 4 KiB | **Todos zeros** (era 0xFF em boot anterior) | MMIO controle — mudou entre boots |
| BAR2 | 0x80000000–0xbfffffff | 1 GiB | Zeros até 256 MB, depois 0xFF | DDR3 real (limpo neste boot) |
| BAR4 | 0xcd000000–0xcd0fffff | 1 MiB | Todo 0x00 | Vazio |
| BAR5 | 0xcd400000–0xcd43ffff | 256 KiB | Offset 0 = zeros; dados em offsets altos (0x20000+) | Tabela estruturada |

### Janelas-chave no BAR5 (leitura direta via /dev/mem, 2026-11-12):

| Offset | Conteúdo | Significado |
|--------|----------|-------------|
| BAR5+0x2f000 (0xcd42f000) | `2c cc 44 3f 69 5f ...` = **MAC `2c:cc:44:3f:69:5f`** | Bootparams/MAC (confirmado por `00-build-kernel-7.0.sh` linha 354) |
| BAR5+0x2c000 (0xcd42c000) | Dados ativos (ex: `42 04 38 00 00 00 0c 00 ...`) | Região `spm.icc` — já reservada pelo driver `ps4-bpcie-icc` |
| BAR5+0x00000 | Todos zeros | **Não há dados aqui neste boot** |
| BAR5+0x20000–0x40000 | 0xFF nesta leitura; dados no dump salvo | Conteúdo varia entre boots/consoles |

### ⚠️ Descoberta crítica — o dump salvo não corresponde ao hardware atual

O arquivo `outros/rea/spm/dumps/baikal_bar5.bin` (commit `29aa02f`, 2026-11-12 16:33) **não bate** com a leitura ao vivo deste console:
- Salvos tem dados em `0x00000`; atual é zero lá
- Salvos tem dados em `0x20000–0x40000`; atual é 0xFF lá
- Salvos NÃO tem o MAC em `0x2f000`; atual tem `2c:cc:44:3f:69:5f`
- Conclusão: o dump foi capturado em outro estado/outro console. **Não confiar no dump salvo como fonte da verdade.**

### Registro ICC ocupado pelo driver Linux

`/proc/iomem` mostra `cd42c000-cd42cfff : spm.icc` — o driver `ps4-bpcie-icc` (built-in) já reserva e mapeia `BAR5+0x2c000` (tamanho `BPCIE_SPM_ICC_SIZE`, definido em `drivers/ps4/baikal.h` linha 123 como `0x2c000`). Não há conflito com nosso driver porque nosso `devm_request_mem_region` para BAR5 falhou com EBUSY e caiu na tentativa 2 (`devm_ioremap` direto), que funcionou.

---

## 2. Estado do driver (Fase 1 — CONCLUÍDA)

### Arquivos no kernel (commit `9c260fc53`):

| Arquivo | Local | Conteúdo |
|---------|-------|----------|
| `baikal-memory.c` | `kernel/kernel_build_7.0/drivers/misc/` | Fonte do driver (150 linhas modificadas vs commit original) |
| `Kconfig` | `kernel/kernel_build_7.0/drivers/misc/` | `config BAIKAL_MEMORY` (linha 664) — depends PCI |
| `Makefile` | `kernel/kernel_build_7.0/drivers/misc/` | `obj-$(CONFIG_BAIKAL_MEMORY) += baikal-memory.o` (linha 78) |
| `.ko` compilado | `outros/rea/spm/dumps/baikal-memory.ko` | 304 KB, com debug_info, não stripped |

### Nota sobre o símbolo Kconfig
O símbolo é `BAIKAL_MEMORY`. Os typos `BAALAK`/`BAILAK` foram corrigidos em 2026-11-12: Kconfig e Makefile agora vêm dentro do `baikal-memory-fase2.patch` (aplicado após o `git reset --hard`), e o `00-build-kernel-7.0.sh` habilita `CONFIG_BAIKAL_MEMORY` via `scripts/config` **antes** do `olddefconfig` — o `config` rastreado não traz esse símbolo.

### Como o driver sobe no PS4
Carrega automaticamente via udev (não precisa de `insmod` manual). No boot de teste, apareceu no dmesg aos ~12,9 s:

```
baikal_memory: loading out-of-tree module taints kernel.
baikal-memory 0000:00:14.6: [BAIKAL] Vendor: 0x104d, Device: 0x90dd
baikal-memory 0000:00:14.6: [BAIKAL] BAR0 OK / BAR2 OK / BAR4 OK / BAR5 OK (tentativa 2)
baikal-memory 0000:00:14.6: [BAIKAL] misc device OK: /dev/baikal-memory
baikal-memory 0000:00:14.6: [BAIKAL] sysfs group OK
baikal-memory 0000:00:14.6: [BAIKAL] === PROBE CONCLUIDO COM SUCESSO ===
```

### Device e sysfs criados
- `/dev/baikal-memory` → `cr--r--r-- 1 root root 10, 261` (somente leitura, modo 0444)
- `/sys/devices/pci0000:00/0000:00:14.6/bar5_0x00` … `bar5_0x1c` → retornam `0x00000000` (offset 0 está zerado neste boot)
- Não existe `/sys/class/baikal-memory/` (o driver cria sysfs no `kobj` do device PCI, não na classe misc)

---

## 3. Fase 2 — Leitura Segura da SPM (CONCLUÍDA em 2026-11-12)

### Problema original
O driver lia apenas **BAR5 offset 0**, que está **zerado** neste boot; o critério de aceite (`dd ... count=256` não-zero) não era atingível.

### Implementação entregue
`baikal_memory_read()` foi reescrito em torno de `baikal_mem_resolve()`, que traduz offset do dispositivo → BAR + deslocamento, copy via `memcpy_fromio()` para um bounce de 64 bytes e `copy_to_user()`:

| Faixa de `/dev/baikal-memory` | Origem |
|-------------------------------|--------|
| `0x000000–0x000fff` | BAR0 (4 KiB, MMIO de controle) |
| `0x001000–0x003fff` | BAR2 (primeiros 4 MiB da SPM DDR3) |
| `0x500000–0x53ffff` | BAR5 (256 KiB, tabela estruturada) |

`llseek`/`SEEK_END` passaram a usar `BAIKAL_DEV_SIZE` (`0x540000`); leitura além do fim retorna 0 bytes (EOF), não lixo. BAR4 segue fora (todo zero ao vivo, sem dados úteis). O sysfs `bar5_0x00…0x1c` foi mantido.

### Evidências ao vivo (PS4, kernel 7.0.8-Strawberry-ThinLTO-Baikal-+)

```
# dd if=/dev/baikal-memory bs=1 skip=$((0x52f000)) count=16 | od -An -tx1
 2c cc 44 3f 69 5f 0d c5 a5 04 d8 55 2d 30 82 42     <- MAC real + bootparams
# dd if=/dev/baikal-memory bs=1 skip=$((0x52c000)) count=16 | od -An -tx1
 42 04 38 00 00 00 0c 00 20 00 ab 00 01 00 00 00     <- região spm.icc (BAR5+0x2c000)
```

- MAC idêntico em 3 leituras consecutivas (estável).
- Offset 0 (BAR0) e janela BAR2 (`0x1000`) retornam zeros **neste boot** — é o estado do hardware, não do driver.
- `dd skip=$((0x540000))` retorna `0 bytes copied` (EOF correto).
- `.ko` instalado em `/usr/lib/modules/7.0.8-Strawberry-ThinLTO-Baikal-+/kernel/drivers/misc/baikal-memory.ko` + `depmod` (sobe via udev).

> Consequência prática: o "critério de aceite não-zero no offset 0" **não vale** para este console (BAR0/BAR2 zerados). A verificação correta é a leitura do MAC em `0x52f000` descrita acima.

### 3.1 Fase 3 — Sysfs dos registradores com dados reais (CONCLUÍDA em 2026-11-12)

Atributos só-leitura (`0444`) no `kobj` do device PCI (`/sys/devices/pci0000:00/0000:00:14.6/`):

| Atributo | Offset no BAR5 | Saída |
|----------|----------------|-------|
| `bar5_0x00` … `bar5_0x1c` | `0x00`–`0x1c` | `0x%08x` (u32) |
| `bar5_0x2c000` | `0x2c000` | dump de 16 bytes em hex (região `spm.icc`) |
| `bar5_0x2f000` | `0x2f000` | MAC formatado `%pM` (bootparams) |

```
# cat /sys/devices/pci0000:00/0000:00:14.6/bar5_0x2f000
2c:cc:44:3f:69:5f
# cat /sys/devices/pci0000:00/0000:00:14.6/bar5_0x2c000
42 04 38 00 00 00 0c 00 20 00 ab 00 01 00 00 00
```

**Bug corrigido de passagem:** os atributos `bar5_0x00…0x1c` extraíam o offset do próprio nome com `simple_strtoul(attr->attr.name, NULL, 16)` — que para em `'r'` e devolve **0xba** para `"bar5_0x00"`. Ou seja, todos os oito liam o registrador errado (região zerada, então passava despercebido). Agora cada atributo carrega `offset`/`len`/`mac` numa `struct baikal_sysfs_reg` e o `container_of()` resolve o registrador.

### Regras do projeto para modificar o driver
- O build kernel (`00-build-kernel-7.0.sh`) faz `git reset --hard HEAD` → **qualquer edição direta no driver será apagada no próximo build**
- Fluxo obrigatório:
  1. Editar `drivers/misc/baikal-memory.c` na árvore `kernel/kernel_build_7.0/`
  2. Compilar isolado: `make CC="ccache clang" LLVM=1 ARCH=x86_64 drivers/misc/baikal-memory.o`
  3. Gerar patch: `git diff HEAD -- drivers/misc/baikal-memory.c > patches/baikal-memory-fase2.patch`
  4. Resetar árvore: `git reset --hard HEAD`
  5. Validar: `git apply --check patches/baikal-memory-fase2.patch`
  6. Adicionar aplicação do patch ao `00-build-kernel-7.0.sh` (padrão `git apply --check` + `exit 1` em falha)
  7. Build completo → novo `.ko` → instalar no PS4

### Nunca usar
- Heredocs (`cat << 'EOF'`), `sed` ou `echo >>` inline no script de build para injetar código
- `|| echo AVISO` ou engolir erro de `git apply`

---

## 4. Como testar no PS4 (via SSH)

```bash
# Carregar módulo (sobe via udev automaticamente; insmod só se precisar forçar recarga)
sshpass -p ps4 scp outros/rea/spm/dumps/baikal-memory.ko root@192.168.6.128:/tmp/
sshpass -p ps4 ssh root@192.168.6.128 "insmod /tmp/baikal-memory.ko 2>/dev/null; true"

# Verificar device e sysfs
sshpass -p ps4 ssh root@192.168.6.128 "ls -l /dev/baikal-memory; ls /sys/devices/pci0000:00/0000:00:14.6/bar5_*"

# Critério de aceite Fase 2 (vai retornar zeros com o driver atual — esperar correção)
sshpass -p ps4 ssh root@192.168.6.128 "dd if=/dev/baikal-memory bs=1 count=256 | xxd"

# Leitura direta de hardware para comparar (via /dev/mem)
sshpass -p ps4 ssh root@192.168.6.128 "dd if=/dev/mem bs=1 count=16 skip=\$((0xcd400000+0x2f000)) 2>/dev/null | od -An -tx1"  # deve mostrar 2c cc 44 3f 69 5f

# dmesg do driver
sshpass -p ps4 ssh root@192.168.6.128 "dmesg -T | grep -i baikal | tail -20"

# Descarga (se necessário)
sshpass -p ps4 ssh root@192.168.6.128 "rmmod baikal-memory"
```

---

## 5. UART (captura de console serial)

Scripts em `outros/scripts/uart_{start,stop,capture}.sh`. Porta `/dev/ttyUSB0` no host, 115200 baud, raw.

```bash
# Iniciar captura (duracao em segundos, nome opcional)
./outros/scripts/uart_start.sh 600 baikal-memory-fase2

# Acompanhar ao vivo
tail -f outros/tests/uart_logs/baikal-memory-fase2_*.log

# Parar
./outros/scripts/uart_stop.sh
```

**Nota:** O log UART pode parar de receber mensagens do kernel após o initramfs montar o rootfs (as mensagens vão para tty0/HDMI). Isso é normal.

---

## 6. Riscos e Mitigações

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Escrita na SPM corrompe estado do Syscon | Crítica | **Somente leitura nas Fases 1-4. Escrita apenas na Fase 5 com `allow_write=0` padrão.** |
| Ler offsets críticos travar o console | Alta | Começar com leituras pequenas (64 bytes) e aumentar gradualmente |
| Conflito com `ps4-bpcie-icc` (reserva BAR5+0x2c000) | Média | Driver memória não escreve; leitura via `devm_ioremap` direto funciona (tentativa 2) |
| Dados do BAR5 variam entre boots/consoles | Média | Não confiar em dump salvo; validar sempre via `/dev/mem` ao vivo |
| `CONFIG_DETECT_HUNG_TASK` desligado | Baixa | Sem aviso de task bloqueada em I/O travado |
| Sem `/dev/rtc` (CONFIG_RTC_CLASS=n) | Média | Fase 4 (RTC via ICC) bloqueada até habilitar RTC_CLASS |

---

## 7. Próximo Passo Imediato

**Build oficial validado em 2026-11-12** — `sudo ./kernel/00-build-kernel-7.0.sh 20261112-baikal-memory-fase3` terminou com **exit 0**: o patch aplicou logo após o `git reset --hard` ("✓ Patch baikal-memory aplicado com sucesso"), o `olddefconfig` resolveu `CONFIG_BAIKAL_MEMORY=m`, e o `.ko` saiu em `kernel/kernel_build_7.0/drivers/misc/baikal-memory.ko` (502.144 bytes) com vermagic `7.0.8-Strawberry-ThinLTO-Baikal-+`. Artefatos da tag em `distro/boot_referencia/bzImage-7.0-20261112-baikal-memory-fase3` + `config-7.0-20261112-baikal-memory-fase3` (o `deploy-boot` ainda exige bootargs e initramfs dessa tag). Snapshot pós-build gerado em `kernel/snapshots/`.

### 3.2 Fase 4 — RTC via ICC (CONCLUÍDA COM RESSALVA, 2026-11-12)

O kernel em execução já tem `RTC_CLASS=y` e `rtc-ps4-icc` como módulo, então a fase foi validada ao vivo sem reflash, com o `baikal-memory` carregado.

**O que foi descoberto:**

1. **Os registradores do RTC Marvell não estão no BAR5** — a RE de `rtc_mvl.c` (`outros/rea/spm/decompiled/baikal_rtc_mvl.txt`) descreve STATUS em `+0x100` e TIME em `0x130/0x134/0x138/0x13c`; lidos via `/dev/baikal-memory` (offset do device `0x500000+`), todos voltam **zero**, inclusive `0x160`/`0x164`. Ou seja, este RTC não está na janela mapeada do 00:14.6.
2. **O ICC save/load context não devolve tempo** — `echo "2 0x0c 00" > /proc/ps4_icc` e `2 0x0b` retornam `ret=20` com reply `02 02 00 …`; o BAR5+0x2c000 só mostra o tráfego do mailbox (ex.: `42 02 0b 00 00 00 19 00 20 00 88 …`, byte do minor + contador). Nada de BCD/epoch.
3. Por isso `rtc-ps4-icc` **semeia** `base_time` com `ktime_get_real_seconds()` no probe e mantém os comandos ICC de save/load context (integração preservada, sem inventar escrita no hardware).

**Resultado ao vivo (ambos os drivers carregados):**

```
lsmod: rtc_ps4_icc + baikal_memory
/sys/class/rtc/rtc0/time   -> 00:03:07
/sys/class/rtc/rtc0/date   -> 2026-11-13
/sys/class/rtc/rtc0/since_epoch -> 1794528187   (hctosys=1)
/proc/driver/rtc      -> rtc_time 00:03:07 / rtc_date 2026-11-13
bar5_0x2f000          -> 2c:cc:44:3f:69:5f      (baikal-memory intacto)
```

Antes do fix o kernel registrava `setting system clock to 1970-01-01` (zerava o relógio no boot); agora registra o tempo real.

**Ressalva — `hwclock -r`:** no kernel **em execução** ainda sai com `hwclock: select() to /dev/rtc to wait for clock tick timed out` (exit 1), porque `CONFIG_RTC_INTF_DEV_UIE_EMUL` está desligado (`# ... is not set`) e o driver não tem IRQ de update. O `00-build-kernel-7.0.sh` agora habilita `CONFIG_RTC_INTF_DEV_UIE_EMUL=y`; **a validação final do `hwclock -r` exige subir um kernel novo** (deploy + power cycle).

**Artefatos:** patch `kernel/patches/ps4-icc-rtc-wrapper.patch` regenerado com o seed (validado com `git apply --cached --check`); módulo testado em `outros/rea/spm/dumps/rtc-ps4-icc-fase4.ko`.

### 3.3 Fase 5 — Escrita controlada (VALIDADA AO VIVO NO PS4, 2026-11-12)

**Implementação:** parâmetro de módulo `allow_write` (`bool`, `0444`, **padrão `0`/desligado**), operação `.write` em `/dev/baikal-memory` e `MODULE_VERSION("0.2")`. O nó do dispositivo passa a `0600` (root), mas toda escrita retorna `-EPERM` enquanto `allow_write=0`.

**Whitelist/regra de segurança (conservadora):** mesmo com `allow_write=1`, `baikal_mem_resolve(..., writable_only=true)` só aceita a **janela BAR2** exposta no layout do dispositivo (`0x001000–0x003fff`, primeiros 4 MiB da DDR3/SPM). Escritas em **BAR0** (MMIO de controle), **BAR5** (tabela estruturada; `spm.icc` em `0x2c000` é reservada pelo `ps4-bpcie-icc`) e fora dos limites são rejeitadas (`-EPERM`). BAR4 não é exposta.

**Validação ao vivo no PS4 (2026-11-12):**
1. Com `allow_write=0` (padrão): `/dev/baikal-memory` em modo `0600`. Tentativa de escrita em qualquer região devolve `dd: error writing '/dev/baikal-memory': Operation not permitted` (EPERM). Leitura de MAC e ICC 100% preservada.
2. Com `allow_write=1`:
   - Escrita em BAR0 (`seek=0`): Rejeitada com `Operation not permitted`.
   - Escrita em BAR5 (`seek=0x52f000`): Rejeitada com `Operation not permitted`.
   - Escrita em BAR2 (`seek=0x2000`, 4 bytes): Escrito padrão `\xde\xad\xbe\xef`. Leitura imediata confirmou `de ad be ef`. Escrita de `\x00\x00\x00\x00` restaurou para zeros. Zero erros ou alertas no dmesg do kernel.
3. Módulo v0.2 instalado em `/usr/lib/modules/...` e recarregado em modo seguro padrão (`allow_write=0`).

**Frentes Pendentes da SPM:**
1. **Deploy de kernel no PS4:** Tag oficial `20261113-baikal-memory-fase5` gerada com sucesso com `CONFIG_RTC_INTF_DEV_UIE_EMUL=y` e `baikal-memory` v0.2. Falta gravar no HD de boot para validar `hwclock -r`.
2. **Fase 6 — Estresse & Catalogação:** Teste de estresse contínuo por 30+ minutos via script no PS4 e inserção dos registros no banco SQLite `ps4_hardware_memory.db`.
3. **Controle de Energia S5 / Desligamento da Luz Azul:** Investigar envio de comando `icc_power_shutdown` via `spm.icc` (BAR5 `0x2c000`) para corte total da fonte de alimentação.

### Estado do patch (obrigatório para idempotência)

| Item | Valor |
|------|-------|
| Patch | `kernel/patches/baikal-memory-fase2.patch` (Fases 1–5 + Kconfig/Makefile) |
| Aplicação | `00-build-kernel-7.0.sh` — preflight + bloco próprio com `git apply --check` e `exit 1` |
| Validação (2026-11-12) | `git diff HEAD` regenerado, árvore resetada e `git apply --check` OK |
| Compilação isolada (2026-11-12) | `make ... CC="ccache clang" LLVM=1 ARCH=x86_64 drivers/misc/baikal-memory.o`: OK |
| Binário testado Fase 1–5 | `outros/rea/spm/dumps/baikal-memory-fase5.ko` (build oficial tag `20261113-baikal-memory-fase5`, 514.344 bytes) |
| Build oficial | tag `20261113-baikal-memory-fase5`, exit 0 (patch aplicado pós-`git reset`, UIE emulado e Fase 5 integrada) |

> O patch cobre `drivers/misc/baikal-memory.c` **e** `drivers/misc/Kconfig` + `drivers/misc/Makefile` (símbolo `CONFIG_BAIKAL_MEMORY`). O `config` rastreado não tem o símbolo do driver: o build o habilita com `scripts/config --module CONFIG_BAIKAL_MEMORY` antes do `olddefconfig`.

---

## 8. Referências no Repositório

| Documento | Local |
|-----------|-------|
| Levantamento de hardware completo | `outros/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md` |
| Status de drivers | `outros/docs/STATUS_DRIVERS_PS4_BAIKAL.md` |
| BACKLOG (item Baikal Memory) | `outros/docs/BACKLOG.md` (item [~]) |
| Plano de driver (6 fases) | `outros/rea/spm/decompiled/baikal_mem_plano_driver.md` |
| Achados Fase 1 (BARs) | `outros/docs/ACHADOS_MEMORIA_BAIKAL_FASE1.md` |
| Achados Fase 2 (strings Orbis) | `outros/docs/ACHADOS_MEMORIA_BAIKAL_FASE2.md` |
| Banco SQLite | `outros/rea/ps4_hardware_memory.db` (tabela `bar_regions` id 9-12) |
| Ghidra 12.1.2 | `/opt/ghidra/ghidra_12.1.2_PUBLIC` |
| Kernel dump Orbis | `outros/rea/dumps/kmem_dump_1252.bin` |
| Build script kernel | `kernel/00-build-kernel-7.0.sh` |
| Patch do driver (Fases 1+2) | `kernel/patches/baikal-memory-fase2.patch` |
| `.ko` testado | `outros/rea/spm/dumps/baikal-memory-fase2.ko` |
| Patches | `kernel/patches/` |
