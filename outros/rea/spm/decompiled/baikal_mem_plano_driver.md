# Plano de Implementação — Driver de Memória Baikal (00:14.6 / SPM DDR3)

**Versão:** 1.0  
**Data:** 2026-11-12  
**Kernel alvo:** 7.0.8-Strawberry-ThinLTO-Baikal-+ (x86_64)  
**Dispositivo:** Sony Baikal Memory (DDR3/SPM), PCI 00:14.6, Vendor 0x104d, Device 0x90dd  
**Hardware:** PS4 Slim (CUH-2xxx, Baikal B1), 256 MB SPM DDR3  
**Status:** Planejamento — pronto para iniciar desenvolvimento

---

## 1. Visão Geral

O dispositivo 00:14.6 do SoC Baikal expõe memória dedicada (SPM/DDR3) usada pelo Syscon/EMC para comunicação de baixo nível, power management, RTC, e potencialmente armazenamento de contexto do sistema. O kernel Orbis (FreeBSD-based) já possui drivers `spm_pci` e `SceDdr3Swap` para essa memória, mas o Linux 7.0 Baikal não tem nenhum driver para esse dispositivo.

**Objetivo:** Desenvolver `baikal-memory.ko` — módulo de kernel Linux que expõe de forma segura e estruturada a memória SPM/DDR3 do Baikal, permitindo leitura (e eventualmente escrita controlada) via interface de caractere + mmap, com suporte a sysfs para registradores conhecidos.

---

## 2. Dados Coletados (Fases 1 e 2)

### 2.1 BARs Confirmados ao Vivo (PS4 Slim)

| BAR | Endereço Físico | Tamanho | Conteúdo | Status |
|-----|-----------------|---------|----------|--------|
| BAR0 | 0xcc000000–0xcc000fff | 4 KiB | Todo 0xFF | Não mapeado/inicializado |
| BAR2 | 0x80000000–0xbfffffff | 1 GiB | Zeros até 256 MB, depois 0xFF | 256 MB DDR3 real |
| BAR4 | 0xcd000000–0xcd0fffff | 1 MiB | Todo 0x00 | Vazio |
| BAR5 | 0xcd400000–0xcd43ffff | 256 KiB | Tabela estruturada (não zero) | Dados ativos |

### 2.2 Strings do Kernel Orbis (FreeBSD-based)

| String | Significado |
|--------|-------------|
| `Baikal Scratch Pad Memory` | Nome oficial da SPM |
| `spm_pci` / `pci/spm` | Driver PCI da SPM no Orbis |
| `SceDdr3Swap` | Módulo de swap DDR3 criptografado |
| `Baikal DDR3 memory` | Referência à memória DDR3 |
| `baikal_dmac_pci` | Driver DMA do Baikal |
| `bootparam_get_ddr3_capacity()` | Função para obter capacidade DDR3 |
| `icc_query`, `icc_device_power`, `icc_power_shutdown` | Protocolo ICC para comunicação com Syscon |

### 2.3 Arquivos Salvos

| Arquivo | Conteúdo | Local |
|---------|----------|-------|
| BAR5 completo (256 KiB) | Tabela estruturada | `outros/rea/dumps/baikal_bar5.bin` |
| BAR0 completo (4 KiB) | Todo 0xFF | `outros/rea/dumps/baikal_bar0.bin` |
| Fase 1 — BAR map | Documentação | `outros/rea/decompiled/baikal_mem_fase1_bar_map.md` |
| Fase 2 — Strings Orbis | Documentação | `outros/rea/decompiled/baikal_mem_fase2_orbis_strings.md` |

---

## 3. Plano de Implementação (6 Fases)

### Fase 1 — Estrutura do Módulo e Probe PCI (Semana 1)

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

### Fase 2 — Leitura Segura da SPM (Semana 2)

**Objetivo:** Permitir leitura da memória SPM via `/dev/baikal-memory` com `mmap` ou `read()`.

**Tarefas:**
- [x] Implementar `baikal_memory_read()`: leitura de offsets específicos da SPM
- [x] Implementar `baikal_memory_mmap()`: mapeamento direto da SPM para userspace
- [x] Adicionar validação de offset/tamanho (não permitir leitura fora dos limites)
- [x] Adicionar mutex para proteção de acesso concorrente (não spinlock: `copy_to_user`/`memcpy_fromio` podem dormir)
- [x] Testar leitura de offsets conhecidos (MAC em BAR5+0x2f000, região ICC em BAR5+0x2c000)
- [x] Verificar que leituras são estáveis (mesmo valor em leituras repetidas)

**Critério de aceite (revisado em 2026-11-12):** o offset 0 (BAR0/BAR2) está **zerado neste console**, então "não-zero no offset 0" não é um critério válido. O critério real passou a ser: `dd if=/dev/baikal-memory bs=1 skip=$((0x52f000)) count=6` retorna `2c cc 44 3f 69 5f` (MAC real) de forma repetível, e `skip=$((0x52c000))` retorna os dados da região `spm.icc`. Implementação validada ao vivo; patch em `kernel/patches/baikal-memory-fase2.patch`.

---

### Fase 3 — Sysfs e Registradores Conhecidos (Semana 2-3)

**Objetivo:** Expor registradores de interesse via sysfs para fácil leitura/monitoramento.

**Tarefas:**
- [ ] Criar `/sys/class/baikal-memory/` com atributos só-leitura
- [ ] Mapear offsets conhecidos do BAR5 (tabela de descritores ICC/comandos)
- [ ] Exibir valores em formato hexadecimal via sysfs
- [ ] Documentar cada offset conhecido no `Documentation/abi/sysfs-class-baal-memory`
- [ ] Testar leitura via `cat /sys/class/baikal-memory/...`

**Critério de ace
ite:** Sysfs acessível e retorna valores corretos para offsets conhecidos.

---

### Fase 4 — Integração com RTC e ICC (Semana 3-4)

**Objetivo:** Integrar com o driver RTC `rtc-ps4-icc` (já existente no kernel 7.0) e expor interface ICC via memória Baikal.

**Tarefas:**
- [ ] Revisar `drivers/rtc/rtc-ps4-icc.c` para entender como usa MMIO/ICC
- [ ] Adicionar suporte a leitura de contexto ICC via memória Baikal
- [ ] Implementar interface para `icc_query` via memória compartilhada (se aplicável)
- [ ] Testar `modprobe rtc-ps4-icc` com `baikal-memory` carregado
- [ ] Validar `/dev/rtc0` aparece e `hwclock -r` funciona

**Critério de aceite:** RTC via ICC funciona com o driver de memória carregado.

---

### Fase 5 — Escrita Controlada (Opcional, Semana 4-5)

**Objetivo:** Permitir escrita em registros específicos da SPM (APENAS após validação extensa de leitura).

**Tarefas:**
- [ ] Identificar quais registros são seguros para escrita (via RE do kernel Orbis)
- [ ] Implementar `baikal_memory_write()` com validação rígida
- [ ] Adicionar parâmetro de módulo `allow_write=0` (desligado por padrão)
- [ ] Testar escrita em registros não críticos primeiro
- [ ] Documentar riscos de escrita na SPM

**Critério de aceite:** Escrita funciona apenas em registros identificados como seguros; não causa panic.

---

### Fase 6 — Validação e Documentação (Semana 5)

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

## 4. Riscos e Mitigações

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Escrita na SPM corrompe estado do Syscon | Crítica | **Somente leitura nas fases 1-4. Escrita apenas na fase 5 com `allow_write=0` padrão.** |
| Ler offsets críticos travar o console | Alta | Começar com leituras pequenas (64 bytes) e aumentar gradualmente |
| 1 GiB não cabe no ioremap de kernel | Média | Mapear em janelas menores (ex: 4 MiB por vez) ou mapear apenas BAR0/BAR4 inicialmente |
| Conflito com `ps4-bpcie-icc` | Média | Coordenar acessos via spinlock; driver de memória é somente-leitura inicialmente |
| BAR0 todo 0xFF (não inicializado) | Baixa | Documentar como comportamento esperado; focar em BAR5 e BAR2 |

---

## 5. Critério de Aceite Geral

- [ ] BARs do 00:14.6 confirmados ao vivo no PS4 Slim ✅ (Fase 1 concluída)
- [ ] Driver compila no kernel 7.0 Baikal
- [ ] Módulo carrega sem panic no PS4
- [ ] Leitura da SPM via driver retorna dados consistentes
- [ ] Sysfs expõe registradores conhecidos
- [ ] RTC via ICC funciona com o driver carregado (se aplicável)
- [ ] Reboot do console bem-sucedido após carregar/descarregar o módulo
- [ ] Documentação completa em `Documentation/driver-api/baikal-memory.rst`
- [ ] Entradas no banco `ps4_hardware_memory.db` atualizadas
- [ ] Commit no repositório

---

## 6. Referências

| Arquivo | Conteúdo | Local |
|---------|----------|-------|
| BAR5 completo (256 KiB) | Tabela estruturada | `outros/rea/dumps/baikal_bar5.bin` |
| BAR0 completo (4 KiB) | Todo 0xFF | `outros/rea/dumps/baikal_bar0.bin` |
| Fase 1 — BAR map | Documentação | `outros/rea/decompiled/baikal_mem_fase1_bar_map.md` |
| Fase 2 — Strings Orbis | Documentação | `outros/rea/decompiled/baikal_mem_fase2_orbis_strings.md` |
| Plano de implementação | Este documento | `outros/rea/decompiled/baikal_mem_plano_driver.md` |
| Banco SQLite | Registro de BARs/registers | `outros/rea/ps4_hardware_memory.db` |
| Levantamento hardware | Inventário completo | `outros/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md` |
| Status drivers | Lista de componentes | `outros/docs/STATUS_DRIVERS_PS4_BAIKAL.md` |
| BACKLOG | Tarefas pendentes | `outros/docs/BACKLOG.md` (item Baikal Memory) |

---

## 7. Próximo Passo Imediato

Iniciar a **Fase 1**: criar o esqueleto do driver em `drivers/misc/baikal-memory.c`, adicionar ao Kconfig/Makefile, e testar `modprobe baikal-memory` no PS4 sem panic.
