# HANDOFF — Driver de Memória Baikal (SPM/DDR3, 00:14.6)

**Subsistema:** SPM (Scratch Pad Memory) — Baikal Memory  
**Dispositivo PCI:** 00:14.6, Vendor 0x104d, Device 0x90dd  
**Hardware:** PS4 Slim (CUH-2xxx, Baikal B1), 256 MB SPM DDR3  
**Kernel alvo:** 7.0.8-Strawberry-ThinLTO-Baikal-+ (x86_64)  
**Status:** Fase 1 em andamento — mapeamento concluído, desenvolvimento do driver iniciando

---

## 1. O que foi descoberto (Fases 1 e 2 concluídas)

### BARs confirmados ao vivo no PS4:

| BAR | Endereço Físico | Tamanho | Conteúdo | Status |
|-----|-----------------|---------|----------|--------|
| BAR0 | 0xcc000000–0xcc000fff | 4 KiB | Todo 0xFF | Não mapeado/inicializado |
| BAR2 | 0x80000000–0xbfffffff | 1 GiB | Zeros até 256 MB, depois 0xFF | 256 MB DDR3 real |
| BAR4 | 0xcd000000–0xcd0fffff | 1 MiB | Todo 0x00 | Vazio |
| BAR5 | 0xcd400000–0xcd43ffff | 256 KiB | Tabela estruturada (não zero) | Dados ativos |

### Strings encontradas no kernel Orbis (FreeBSD-based):

- `Baikal Scratch Pad Memory` — nome oficial da SPM
- `spm_pci` / `pci/spm` — driver PCI da SPM no Orbis
- `SceDdr3Swap` — módulo de swap DDR3 criptografado (Orbis-specific)
- `Baikal DDR3 memory` — referência à memória DDR3
- `baikal_dmac_pci` — driver DMA do Baikal
- `bootparam_get_ddr3_capacity()` — função para obter capacidade DDR3
- `icc_query`, `icc_device_power`, `icc_power_shutdown`, `icc_nvs` — protocolo ICC

**⚠️ Importante:** O kernel Orbis é FreeBSD-based. O driver Linux deve ser desenvolvido do zero, adaptando interfaces FreeBSD para APIs Linux (devm_*, ioremap, misc_register, etc.).

### Arquivos salvos:

| Arquivo | Conteúdo | Local |
|---------|----------|-------|
| `baikal_bar5.bin` | BAR5 completo (256 KiB) | `outros/rea/spm/dumps/` |
| `baikal_bar0.bin` | BAR0 completo (4 KiB) | `outros/rea/spm/dumps/` |
| `baikal_mem_fase1_bar_map.md` | Mapeamento de BARs | `outros/rea/spm/decompiled/` |
| `baikal_mem_fase2_orbis_strings.md` | Strings do kernel Orbis | `outros/rea/spm/decompiled/` |
| `baikal_mem_plano_driver.md` | Plano de implementação 6 fases | `outros/rea/spm/decompiled/` |

### Banco SQLite (`outros/rea/ps4_hardware_memory.db`):

| BAR | Endereço | Tamanho | Status |
|-----|----------|---------|--------|
| BAR0 | 0xcc000000 | 4 KiB | MAPPED_READ_0xFF |
| BAR2 | 0x80000000 | 1 GiB | MAPPED_ZEROS_THEN_0xFF |
| BAR4 | 0xcd000000 | 1 MiB | MAPPED_ALL_ZERO |
| BAR5 | 0xcd400000 | 256 KiB | MAPPED_STRUCTURED_DATA |

---

## 2. Plano de Implementação (6 Fases)

### Fase 1 — Estrutura do Módulo e Probe PCI ⬅️ ATUAL

**Objetivo:** Criar o esqueleto do driver que faz probe do dispositivo 00:14.6 e mapeia os BARs.

**Tarefas:**
- [ ] Criar `drivers/misc/baikal-memory.c` no kernel 7.0
- [ ] Adicionar entrada em `drivers/misc/Kconfig` (`CONFIG_BAIKAL_MEMORY`)
- [ ] Adicionar entrada em `drivers/misc/Makefile`
- [ ] Implementar `baikal_memory_probe()`: detectar vendor 0x104d, device 0x90dd
- [ ] Implementar `baikal_memory_remove()`: cleanup adequado
- [ ] `ioremap` BAR0 (4 KiB), BAR2 (256 MB window), BAR4 (1 MiB), BAR5 (256 KiB)
- [ ] Registrar dispositivo de caractere `/dev/baikal-memory` (major dinâmico)
- [ ] Compilar e testar `modprobe baikal-memory` sem panic

**Critério de aceite:** Módulo carrega/descarrega sem panic; `/dev/baikal-memory` existe.

---

### Fase 2 — Leitura Segura da SPM

**Objetivo:** Permitir leitura da memória SPM via `/dev/baikal-memory` com `mmap` ou `read()`.

**Tarefas:**
- [ ] Implementar `baikal_memory_read()`: leitura de offsets específicos da SPM
- [ ] Implementar `baikal_memory_mmap()`: mapeamento direto da SPM para userspace
- [ ] Adicionar validação de offset/tamanho (não permitir leitura fora dos limites)
- [ ] Adicionar spinlock para proteção de acesso concorrente
- [ ] Testar leitura de offsets conhecidos (ex: 0x0000–0x0100 do BAR5)
- [ ] Verificar que leituras são estáveis (mesmo valor em leituras repetidas)

**Critério de aceite:** `dd if=/dev/baikal-memory bs=1 count=256` retorna dados consistentes e não-zero.

---

### Fase 3 — Sysfs e Registradores Conhecidos

**Objetivo:** Expor registradores de interesse via sysfs para fácil leitura/monitoramento.

**Tarefas:**
- [ ] Criar `/sys/class/baikal-memory/` com atributos só-leitura
- [ ] Mapear offsets conhecidos do BAR5 (tabela de descritores ICC/comandos)
- [ ] Exibir valores em formato hexadecimal via sysfs
- [ ] Documentar cada offset conhecido em `Documentation/abi/sysfs-class-baal-memory`
- [ ] Testar leitura via `cat /sys/class/baikal-memory/...`

**Critério de aceite:** Sysfs acessível e retorna valores corretos para offsets conhecidos.

---

### Fase 4 — Integração com RTC e ICC

**Objetivo:** Integrar com o driver RTC `rtc-ps4-icc` (já existente no kernel 7.0) e expor interface ICC via memória Baikal.

**Tarefas:**
- [ ] Revisar `drivers/rtc/rtc-ps4-icc.c` para entender como usa MMIO/ICC
- [ ] Adicionar suporte a leitura de contexto ICC via memória Baikal
- [ ] Implementar interface para `icc_query` via memória compartilhada (se aplicável)
- [ ] Testar `modprobe rtc-ps4-icc` com `baikal-memory` carregado
- [ ] Validar `/dev/rtc0` aparece e `hwclock -r` funciona

**Critério de aceite:** RTC via ICC funciona com o driver de memória carregado.

---

### Fase 5 — Escrita Controlada (Opcional)

**Objetivo:** Permitir escrita em registros específicos da SPM (APENAS após validação extensa de leitura).

**Tarefas:**
- [ ] Identificar quais registros são seguros para escrita (via RE do kernel Orbis)
- [ ] Implementar `baikal_memory_write()` com validação rígida
- [ ] Adicionar parâmetro de módulo `allow_write=0` (desligado por padrão)
- [ ] Testar escrita em registros não críticos primeiro
- [ ] Documentar riscos de escrita na SPM

**Critério de aceite:** Escrita funciona apenas em registros identificados como seguros; não causa panic.

---

### Fase 6 — Validação e Documentação

**Objetivo:** Validar o driver em cenários reais e documentar completamente.

**Tarefas:**
- [ ] Teste de stress: leituras repetidas por 30+ minutos sem degradação
- [ ] Teste de reboot: módulo carrega/descarrega em múltiplos boots
- [ ] Testar com CIFS montado (para garantir não há conflito de memória)
- [ ] Escrever `Documentation/driver-api/baikal-memory.rst`
- [ ] Atualizar `outros/docs/STATUS_DRIVERS_PS4_BAIKAL.md`
- [ ] Adicionar entradas ao banco `ps4_hardware_memory.db`
- [ ] Commit no repositório com mensagem detalhada

**Critério de aceite:** Driver estável, documentado, e integrado ao repositório.

---

## 3. Riscos e Mitigações

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Escrita na SPM corrompe estado do Syscon | Crítica | **Somente leitura nas Fases 1-4. Escrita apenas na Fase 5 com `allow_write=0` padrão.** |
| Ler offsets críticos travar o console | Alta | Começar com leituras pequenas (64 bytes) e aumentar gradualmente |
| 1 GiB não cabe no ioremap de kernel | Média | Mapear em janelas menores (ex: 4 MiB por vez) ou mapear apenas BAR0/BAR4 inicialmente |
| Conflito com `ps4-bpcie-icc` | Média | Coordenar acessos via spinlock; driver de memória é somente-leitura inicialmente |
| BAR0 todo 0xFF (não inicializado) | Baixa | Documentar como comportamento esperado; focar em BAR5 e BAR2 inicialmente |

---

## 4. Próximo Passo Imediato

**Iniciar a Fase 1:** Criar o esqueleto do driver em `drivers/misc/baikal-memory.c`, adicionar ao Kconfig/Makefile, e testar `modprobe baikal-memory` no PS4 sem panic.

---

## 5. Referências no Repositório

| Documento | Local |
|-----------|-------|
| Levantamento de hardware completo | `outros/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md` |
| Status de drivers | `outros/docs/STATUS_DRIVERS_PS4_BAIKAL.md` |
| BACKLOG (item Baikal Memory) | `outros/docs/BACKLOG.md` (item [~]) |
| Plano de driver | `outros/rea/spm/decompiled/baikal_mem_plano_driver.md` |
| Banco SQLite | `outros/rea/ps4_hardware_memory.db` |
| Ghidra 12.1.2 | `/opt/ghidra/ghidra_12.1.2_PUBLIC` |
| Venv PyGhidra | `/opt/ghidra/venv` |
| Kernel dump Orbis | `outros/rea/spm/dumps/` (kmem_dump_1252.bin está em rea/dumps/) |

---

## 6. Como Testar no PS4

```bash
# Compilar o módulo (no host adsv2, cross-compilado)
# Copiar para o PS4
scp baikal-memory.ko anderson@ps4:/tmp/

# No PS4
sudo insmod /tmp/baikal-memory.ko
ls -l /dev/baikal-memory
sudo dmesg | tail -20

# Testar leitura
sudo dd if=/dev/baikal-memory bs=1 count=256 | xxd

# Descarregar
sudo rmmod baikal-memory
```
