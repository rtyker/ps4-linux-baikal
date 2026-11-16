# Achados Fase 2 — Análise de Strings no Kernel Orbis (kmem_dump_1252.bin)

**Data:** 2026-11-12  
**Método:** `strings` + `grep` no dump do kernel Orbis 12.52  
**Arquivo analisado:** `others/rea/dumps/kmem_dump_1252.bin`

---

## 1. Dispositivo de Memória Baikal (00:14.6) — Strings Encontradas

| String | Contexto |
|--------|----------|
| `Baikal Scratch Pad Memory` | Nome oficial da SPM no kernel Orbis |
| `spm_pci` | Nome do driver PCI da SPM |
| `pci/spm` | Caminho PCI do dispositivo SPM |
| `Baikal DDR3 memory` | Referência à memória DDR3 do Baikal |
| `Baikal DMA1 controller` / `Baikal DMA2 controller` | Controladores DMA do Baikal |
| `baikal_dmac_pci` | Driver PCI do controlador DMA |
| `pci/baikal_dmac` | Caminho PCI DMAC |
| `invalid ddr3_size %#x` | Validação de tamanho DDR3 |
| `bootparam_get_ddr3_capacity(): %d` | Função para obter capacidade DDR3 |
| `Aeolia DDR3 memory` / `Belize DDR3 memory` | Comparativo com others southbridges |

---

## 2. Subsistema ICC (Inter-Chip Communication) — Strings Encontradas

| String | Contexto |
|--------|----------|
| `Baikal ICC` | ICC do Baikal |
| `icc_query` | Query ICC (major<=4, len<=0x401) |
| `icc_query_nowait` | Query ICC não-bloqueante |
| `icc_device_power` | Controle de poder de dispositivo ICC |
| `icc_device_power_control(%d->%d)` | Controle de estado de poder |
| `icc_power_shutdown` / `icc_power_shutdown_pre_sync` / `icc_power_shutdown_post_sync` / `icc_power_shutdown_final` | Sequência de shutdown S5 |
| `icc_power_suspend (%s eap) (keep 0x%X)` | Suspend de poder |
| `icc_nvs` / `icc_nvs_read` / `icc_nvs_write` | NVS (Non-Volatile Storage) do ICC |
| `icc_fan` / `icc_fan_get_fan_manual_duty` | Controle de ventoinha |
| `icc_thermal` / `icc_thermal td` | Controle térmico |
| `SceIccNotification` | Notificações ICC |
| `SceIccnvs` | NVS do ICC |
| `SceIccThermal` | Térmico do ICC |
| `pci/icc` | Caminho PCI ICC |

---

## 3. Subsistema DDR3Swap — Strings Encontradas

| String | Contexto |
|--------|----------|
| `SceDdr3Swap` | Módulo de swap DDR3 do Orbis |
| `ddr3swap_state` | Estado do ddr3swap |
| `ddr3swap:mtx` | Mutex do ddr3swap |
| `ddr3swap:cv` | Cond var do ddr3swap |
| `ddr3swap_crypt:mtx` | Mutex de criptografia |
| `ddr3swap_hdd.lock_hdd` | Lock do HDD |
| `invalid ddr3swap size : size=%lu MB` | Validação de tamanho |
| `[DDR3SWAP DEBUG] ...` | Logs de debug (enc, dec, hddread, hddwrite, etc.) |
| `failed to create thread for ddr3swap: ret=%#x` | Erro de criação de thread |

---

## 4. Registradores de Scratch — Strings Encontradas

| String | Contexto |
|--------|----------|
| `mmACP_AXI2DAGB_SCRATCH_%02i` | Registradores de scratch ACP |
| `mmRLC_GPM_SCRATCH_DATA` | Registradores de scratch RLC/GPM |
| `DC_DMCU_SCRATCH=%08X` | Scratch DMCU |
| `DOUT_SCRATCH[0-7]` | Scratch de saída |
| `Dumping scratch registers:` | Dump de registradores de scratch |
| `SPM LOG 0x%x` | Log da SPM |

---

## 5. Caminhos de Fonte do Kernel Orbis (referências)

| Caminho | Descrição |
|---------|-----------|
| `W:\Build\J02690760\sys\freebsd\sys\dev\pci\baikal_pcie.c` | Driver PCIe Baikal |
| `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\icc.c` | Driver ICC principal |
| `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\icc_power.c` | Power management ICC |
| `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\icc_device_power.c` | Device power ICC |
| `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\icc_nvs.c` | NVS ICC |
| `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\icc_thermal.c` | Thermal ICC |
| `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\icc_notification.c` | Notificações ICC |
| `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\icc_snvs.c` | SNVS ICC |

---

## 6. Funções de Memória (dmem) Encontradas

| String | Contexto |
|--------|----------|
| `dmem_alloc` | Alocação de memória |
| `dmem_query` | Query de memória |
| `dmem_set_pid_and_prot` | Set PID e proteção |
| `dmem_handle_process_exec_begin/end` | Handler de execução de processo |
| `dmem_handle_process_exit` | Handler de saída de processo |
| `dmem_handle_system_resume/suspend` | Handler de suspend/resume do sistema |
| `dmem_handle_vmspace_exit_done` | Handler de saída de vmspace |
| `dmem_process_relocated` | Relocação de processo |
| `dmem_query` | Query de memória dinâmica |
| `dmem_start_app_process` | Início de processo de app |

---

## 7. Interpretação e Próximos Passos

**⚠️ IMPORTANTE:** O kernel Orbis é baseado em **FreeBSD**, não Linux. Isso impacta diretamente o desenvolvimento do driver `baikal-memory.ko` para Linux 7.0:

| Aspecto | Orbis (FreeBSD) | Linux 7.0 (nosso alvo) |
|---------|----------------|------------------------|
| Base | FreeBSD 12.x | Linux 7.0.x |
| Driver de memória | `spm_pci` (FreeBSD) | `baikal-memory` (Linux, a desenvolver) |
| Subsistema swap | `SceDdr3Swap` (Orbis) | zram/zswap (Linux) |
| ICC | `icc_query` (FreeBSD) | Precisa de equivalente Linux |
| Registradores de scratch | `mmACP_AXI2DAGB_SCRATCH` (Orbis) | Mapear para Linux devmem/sysfs |

**Conclusões:**
1. O kernel Orbis tem suporte nativo à memória SPM/DDR3 do Baikal via driver `spm_pci` (FreeBSD)
2. Existe um subsistema `SceDdr3Swap` que usa a DDR3 como swap criptografado (Orbis-specific)
3. O ICC é usado para comunicação com o Syscon/EMC, incluindo power management (FreeBSD)
4. Os caminhos de fonte do kernel Orbis estão disponíveis para referência (RE)
5. Funções `dmem_*` gerenciam memória dinâmica no Orbis (FreeBSD)
6. **O driver Linux precisará ser desenvolvido do zero**, adaptando as interfaces FreeBSD para as APIs do Linux (devm_*, ioremap, misc_register, etc.)

**Próximos passos:**
1. Usar o Ghidra 12.1.2 (instalado em /opt/ghidra/ghidra_12.1.2_PUBLIC) para analisar funções específicas
2. Desenvolver driver `baikal-memory.ko` baseado nas descobertas
3. Registrar achados no banco SQLite (`others/rea/ps4_hardware_memory.db`)

---

## 8. Referências

- `others/rea/dumps/kmem_dump_1252.bin` — dump do kernel Orbis 12.52
- `others/rea/ps4_hardware_memory.db` — banco SQLite
- `others/rea/decompiled/` — saídas do Ghidra
- `others/docs/PLANO_DRIVER_MEMORIA_BAIKAL.md` — plano de desenvolvimento
- `others/docs/ACHADOS_MEMORIA_BAIKAL_FASE1.md` — achados da Fase 1 (BARs)

## 9. Resultado: DMA para a SPM (2026-11-16)

O DMAC do Baikal (`00:14.5`, `104d:90dc`, DMAC1 no BAR0) enxerga a SPM (`00:14.6`) em **`0xC0000000 + off`** (= BAR2 PCI `0x80000000` + `0x40000000`). O endereço PCI `0x80000000` dá erro imediato do DMAC (`INT_FLAG=0x2`). Provado com padrão aleatório gravado e relido (`test_history` 87–90) e depois pelo `/dev/baikal-memory` (94–97).

| | Leitura da SPM | Escrita na SPM |
|---|---|---|
| CPU (`memcpy_fromio`/`memcpy_toio`) | ~4,1 MB/s | ~81 MB/s |
| DMAC1 puro (harness, polling) | ~1,5 GB/s | ~0,9 GB/s |
| `/dev/baikal-memory` com DMA (inclui `dd` e `copy_to_user`) | 547 a 624 MB/s (1 MiB), 887 a 924 MB/s (4 MiB) | 146 MB/s medidos em 64 KiB (1 medida) |

Integração: `kernel/patches/baikal-memory-dma.patch` (usa o `dmaengine` do `baikal-dmac`). Plano e resultados completos em `others/rea/spm/plans/PLANO_BAIKAL_MEMORY_DMA_2026-11-16.md` (§5.1). A janela da SPM lida pelo driver tem 4 MiB; a BAR5 (`/dev/baikal-memory` em `0x500000`) tem dados vivos que mudam sozinhos.
