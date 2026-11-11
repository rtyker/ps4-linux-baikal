# Plano de Viabilidade e Roadmap Técnico — KVM-AMD no PS4 Baikal (Kernel 7.0.8)

> **Data:** 2026-07-24 | **Status:** Fase 1 concluída (build estático OK) | **Arquivo:** `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md`

---

## 1. Resumo Executivo

Este documento consolida o estudo de viabilidade e o roadmap técnico para habilitar **KVM (Kernel-based Virtual Machine) com suporte a AMD-V (SVM)** no kernel Linux 7.0.8 rodando no PlayStation 4 (modelos Slim/Pro com southbridge **Baikal**, SoC Jaguar/Puma "DG1501SML87LB", AMD family 0x16 model 0x67).

**Veredito:** ✅ **Tecnicamente viável.** Toda a extensão SVM/NPT necessária está presente no silício; o código KVM integral está na árvore `kernels/ps4-baikal-7.0.8-kernel/`; basta ligar as Kconfigs e reconstruir o bzImage.

---

## 2. Contexto Hardware (Validação ao Vivo — 2026-07-24)

| Item | Valor | Fonte |
|------|-------|-------|
| **CPU** | DG1501SML87LB (AMD family 0x16, model 0x67, stepping 0) | `/proc/cpuinfo` |
| **Cores** | 8 físicos (sem SMT) | `lscpu` |
| **Virtualização** | `svm`, `npt`, `lbrv`, `svm_lock`, `nrip_save`, `tsc_scale`, `flushbyasid`, `decodeassists`, `pausefilter`, `pfthreshold`, `vmmcall` | `flags` em `/proc/cpuinfo` |
| **Flag lscpu** | `Virtualization: AMD-V` | `lscpu` |
| **Memória total** | ~7 GB (unified RAM+VRAM, ~5.1 GB disponível) | `free -h` |
| **Kernel atual** | 7.0.8-Strawberry-ThinLTO-Baikal-+ | `uname -r` |
| **KVM atual** | `# CONFIG_KVM is not set` — **não existe** `/dev/kvm` | `.config` + `ls /dev/kvm` |
| **Módulos KVM** | Ausentes em `/lib/modules/.../kernel/arch/x86/kvm/` | `ls` |

**Conclusão hardware:** O SoC Jaguar expõe **todo o conjunto SVM/NPT** requerido pelo KVM-AMD upstream. Não há barreira de silício.

---

## 3. Análise da Fonte do Kernel (`kernels/ps4-baikal-7.0.8-kernel/`)

### 3.1 Estado Atual do `.config`
```bash
CONFIG_VIRTUALIZATION=y
# CONFIG_KVM is not set          ← ÚNICA BARREIRA REAL
CONFIG_AMD_IOMMU=y
CONFIG_X86_X2APIC=y
CONFIG_SMP=y
CONFIG_NR_CPUS=8
```

### 3.2 Código KVM Disponível (Upstream Integral)
```
arch/x86/kvm/
  ├── kvm.c, x86.o, emulate.o, irq.o, lapic.o, cpuid.o, pmu.o, mtrr.o
  ├── mmu/ (tdp_iter.o, tdp_mmu.o, mmu.o, page_track.o, spte.o)
  ├── ioapic.c, i8254.c, i8259.c
  ├── kvm-asm-offsets.c
  ├── svm/ (svm.o, vmenter.o, pmu.o, nested.o, avic.o, sev.o, hyperv.o)
  ├── vmx/ (Intel — não usado)
virt/kvm/
  ├── kvm_main.o, eventfd.o, coalesced_mmio.o, dirty_ring.o, async_pf.o...
```

### 3.3 Check de Compatibilidade (`arch/x86/kvm/svm/svm.c`)
```c
static bool __kvm_is_svm_supported(void) {
    if (c->x86_vendor != X86_VENDOR_AMD && c->x86_vendor != X86_VENDOR_HYGON)
        return false;                    // PS4 = AMD ✅
    if (!cpu_has(c, X86_FEATURE_SVM))
        return false;                    // PS4 tem SVM ✅
    if (cc_platform_has(CC_ATTR_GUEST_MEM_ENCRYPT))
        return false;                    // Sem SEV/PSP no Jaguar ✅ (não é SEV guest)
    return true;                         // ← PASSARÁ
}
```
**Nenhuma restrição para family 0x16.**

### 3.4 Patches PS4-Baikal que Podem Interagir
| Arquivo | Efeito | Impacto no KVM |
|---------|--------|----------------|
| `arch/x86/platform/ps4/ps4.c` | Platform init, APcie/Bpcie | Neutro |
| `arch/x86/platform/ps4/calibrate.c` | TSC calibration | Neutro (TSC scaling presente) |
| `drivers/iommu/amd/init.c` | `#ifdef CONFIG_X86_PS4_BAIKAL` preserva IOMMU/IR tables | KVM puro não requer IOMMU; VFIO passthrough futuro precisará atenção |
| `arch/x86/include/asm/ps4.h` | Definições de registradores/IRQs | Neutro |

### 3.5 SEV (Secure Encrypted Virtualization)
- `CONFIG_KVM_AMD_SEV` default `y` no upstream
- PS4 Jaguar **não tem PSP/CCP-DD** (`# CONFIG_CRYPTO_DEV_CCP_DD is not set`)
- `sev_hardware_setup()` abortaria graceful, mas **precisa ser desligado** (`CONFIG_KVM_AMD_SEV=n`) para evitar warnings/build issues
- AVIC (`X86_FEATURE_AVIC`) **ausente no silício** → KVM cai para legacy IRQ routing (funcional, sem impacto prático)

---

## 4. Pipeline de Build/Deploy Existente

| Etapa | Ferramenta/Comando | Status |
|-------|-------------------|--------|
| Toolchain | Docker `ps4-kernel-builder:latest` (Ubuntu 24.04 + clang-14 + gcc-11) | ✅ Validado |
| Config base | `.config` em `kernels/ps4-baikal-7.0.8-kernel/` | ✅ |
| Build command | `make O=out -j$(nproc) bzImage modules` | ✅ Funciona |
| Output | `out/bzImage` (13.4 MB, ZSTD-compressed) | ✅ |
| Deploy | kexec via payload em `/data/linux/boot/` ou USB | ✅ Testado (GBE driver) |
| Rollback | Power cycle → volta ao Orbis OS | ✅ Trivial |
| SSH admin | `192.168.6.128` (WiFi, `wlan0`) — independente de `eth0` | ✅ |

---

## 5. Roadmap por Fases (com Gates de Aceitação)

### Fase 0 — Investigação de Viabilidade ✅ **CONCLUÍDA (2026-07-24)**
- [x] Confirmar CPU expõe SVM/NPT completo (`/proc/cpuinfo`, `lscpu`)
- [x] Verificar código KVM integral na árvore
- [x] Auditar `.config` — só `CONFIG_KVM` desligado
- [x] Confirmar `__kvm_is_svm_supported()` passa para family 0x16
- [x] Documentar interações IOMMU/SEV/AVIC
- [x] Registrar no `BACKLOG.md` (ID: **KVM-PS4**)

**Gate de saída:** Veredito "VIÁVEL" documentado. ✅

---

### Fase 1 — Build Estático Sem Deploy ✅ **CONCLUÍDA (2026-07-24)**
**Objetivo:** Compilar KVM + KVM_AMD no toolchain do repo, zero risco (não toca PS4).

**Ações executadas:**
1. Backup do `.config` original → `.config.orig-baseline`
2. Aplicar Kconfigs via `scripts/config`:
   - `CONFIG_KVM=m`, `CONFIG_KVM_AMD=m` (módulos carregáveis)
   - `CONFIG_KVM_AMD_SEV=n`, `CONFIG_KVM_INTEL=n`, `CONFIG_X86_SGX_KVM=n`, `CONFIG_KVM_INTEL_TDX=n`
3. `make olddefconfig` → resolveu selects: `KVM_COMMON=y`, `HAVE_KVM_IRQCHIP=y`, `KVM_MMIO=y`, `KVM_ASYNC_PF=y`, `KVM_GENERIC_HARDWARE_ENABLING=y`, etc.
4. **Problema:** Source tree não limpa para `O=out` build → criou cópia isolada em `/mnt/hdauxiliar/temp/kernel_build_7.0/`, fez `mrproper` + `git stash pop` (preserva patches mts/apcie), build out-of-tree
5. **Falha zstd:** Container sem binário `zstd` → criou `ps4-kernel-builder:zstd` com `apt install zstd`
6. **Sucesso:** bzImage + módulos linkados

**Artefatos gerados (em `kernels/kvm-build-workdir/artifacts-fase1/`):**
| Arquivo | Tamanho | Nota |
|---------|---------|------|
| `bzImage.kvm` | 14.28 MB | +860 KB vs original (KVM selects built-in) |
| `kvm.ko` | 21.75 MB | Módulo KVM core |
| `kvm-amd.ko` | 4.34 MB | Módulo SVM |
| `config.kvm` | 136 KB | `.config` com KVM ligado |
| `kvm_build.log` | 11 KB | Log completo do build |
| `kvm_bzimage.log` | 1 KB | Log do relink final |

**Gate de saída:** `kvm.ko` e `kvm-amd.ko` existem, `extract-ikconfig bzImage.kvm` confirma `CONFIG_KVM=m`, `CONFIG_KVM_AMD=m`. ✅

---

### Fase 2 — Auditoria Pós-Build 🔄 **PRÓXIMA (não toca PS4)**
**Objetivo:** Validar compatibilidade dos módulos com kernel em execução no PS4 antes de deploy.

| Check | Comando | Critério de Aceite |
|-------|---------|-------------------|
| **modinfo vermagic** | `modinfo artifacts-fase1/kvm.ko \| grep vermagic` | Deve casar com `uname -r` do PS4 (`7.0.8-Strawberry-ThinLTO-Baikal-+`) |
| **modversions (CRC)** | `modinfo artifacts-fase1/kvm.ko \| grep -E 'vermagic|depends|intree'` | Sem `vermagic mismatch` |
| **Dependências** | `modinfo artifacts-fase1/kvm-amd.ko` | `depends: kvm,irqbypass,crct10dif_pclmul...` — todos built-in ou módulos existentes |
| **Símbolos KVM** | `nm artifacts-fase1/kvm.ko \| grep -E 'kvm_arch_init|kvm_arch_exit|kvm_vcpu_ioctl'` | Símbolos exportados presentes |
| **Diff de config** | `diff -u .config.orig-baseline artifacts-fase1/config.kvm \| grep -E '^[+-]CONFIG_KVM\|^[+-]CONFIG_VIRTUALIZATION'` | Apenas KVM/AMD/SEV alterados |
| **Tamanho bzImage** | `ls -lh artifacts-fase1/bzImage.kvm` | < 20 MB (cabe no payload kexec) |
| **Compressão** | `file artifacts-fase1/bzImage.kvm` | "ZST compressed" (compatível com kexec atual) |

**Gate de saída:** Todos os checks passam → liberado para Fase 3.

---

### Fase 3 — Deploy Controlado via kexec ⏳ **REQUER CONFIRMAÇÃO DO USUÁRIO**
**Objetivo:** Carregar o novo bzImage no PS4 via kexec, testar boot, rollback trivial.

**Pré-requisitos:** PS4 ligado, acessível via SSH (`192.168.6.128`), Fase 2 aprovada.

**Procedimento:**
```bash
# 1. Copiar bzImage.kvm para PS4 (via SCP/USB)
scp artifacts-fase1/bzImage.kvm root@192.168.6.128:/data/linux/boot/bzImage.kvm.test

# 2. Backup do bzImage atual (opcional, rollback = power cycle)
ssh root@192.168.6.128 "cp /data/linux/boot/bzImage /data/linux/boot/bzImage.bak.$(date +%s)"

# 3. Trocar bzImage ativo
ssh root@192.168.6.128 "mv /data/linux/boot/bzImage.kvm.test /data/linux/boot/bzImage && sync"

# 4. kexec reboot (ou reboot normal se payload carrega do disco)
ssh root@192.168.6.128 "reboot"

# 5. Aguardar boot (monitorar via netconsole/UART se disponível)
#    SSH WiFi (192.168.6.128) deve subir independentemente do eth0
```

**Critérios de aceite:**
- [ ] PS4 boota no novo kernel (SSH WiFi sobe, `uname -r` mostra `7.0.8-Strawberry-ThinLTO-Baikal-+`)
- [ ] `dmesg | grep -i kvm` não mostra erros de init
- [ ] `lsmod` não mostra `kvm`/`kvm_amd` (ainda não carregados — módulos `=m`)
- [ ] Rollback funcionando: power cycle → Orbis OS → kexec payload antigo sobe

**Risco:** Baixo. kexec é não-destrutivo; power cycle restaura Orbis. Drivers mts/apcie/BAIKAL patches idênticos (source tree mesma).

---

### Fase 4 — Smoke Test Módulos KVM ⏳
**Objetivo:** Carregar módulos, confirmar `/dev/kvm`, funcionalidade básica.

```bash
# No PS4 via SSH:
modprobe kvm
modprobe kvm_amd
ls -la /dev/kvm              # deve existir, crw-rw---- root:kvm
dmesg -T | grep -i kvm       # "kvm: NPT enabled", "kvm: SVM enabled"
kvm-ok                       # se instalado (userspace check)
```

**Critérios de aceite:**
- [ ] `modprobe` sem erros (sem `vermagic mismatch`, sem `Unknown symbol`)
- [ ] `/dev/kvm` criado com major 10, minor 232
- [ ] `kvm_amd` reporta `NPT enabled`, `SVM enabled`, `nested enabled`
- [ ] `cpuid | grep -i kvm` no guest mostra capabilities

---

### Fase 5 — Smoke Test VM Mínima (QEMU-system) ⏳
**Objetivo:** Subir um guest Linux mínimo (kernel + initramfs) via QEMU-system-x86_64 usando `/dev/kvm`.

**Requisitos no PS4:**
- `qemu-system-x86_64` (static binary ou instalado no rootfs)
- Guest kernel/initramfs minimal (ex: Alpine linux, ~30 MB)
- Rede: user-mode networking (`-netdev user`) — não requer `eth0` funcional

```bash
# Exemplo comando (ajustar paths):
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 512M -smp 2 \
  -kernel /path/guest-vmlinuz \
  -initrd /path/guest-initramfs.cpio.gz \
  -append "console=ttyS0 root=/dev/ram0 rdinit=/sbin/init" \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -nographic -serial stdio
```

**Critérios de aceite:**
- [ ] Guest boota até prompt de shell (login ou init)
- [ ] `lscpu` no guest mostra CPU virtualizada (QEMU CPU)
- [ ] Rede guest → host funciona (ping para 10.0.2.2)
- [ ] `dmesg` no host não mostra OOPS/KVM faults

---

### Fase 6 (Opcional) — IOMMU/VFIO Passthrough 📋
**Objetivo:** Avaliar se IOMMU preservado pelo patch Baikal permite VFIO passthrough de dispositivos (GPU, NIC) para guests.

**Investigações necessárias:**
- `CONFIG_VFIO_PCI=y`, `CONFIG_VFIO_IOMMU_TYPE1=y`
- `iommu=pt` no cmdline vs patch `amd_iommu_disabled` no Baikal
- `dmesg | grep -i iommu` após boot com KVM
- Testar `vfio-pci` bind de GPU (Radeon) ou NIC (mts/GBE) — **cuidado: pode quebrar host display/rede**

**Gate:** Só após Fases 3-5 estáveis. Documentar em issue separado.

---

## 6. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| `vermagic mismatch` ao carregar `.ko` | Baixa (mesmo toolchain, mesmo kernel source) | Médio | Fase 2 audita; se falhar, rebuild in-tree com `make modules_install` |
| KVM init crash (SVM bug family 0x16) | Muito baixa (upstream suporta Jaguar) | Alto | `dmesg` captura; rollback = power cycle |
| IOMMU conflict (preservado vs KVM) | Baixa (KVM não usa IOMMU por default) | Médio | Desligar `CONFIG_AMD_IOMMU` se necessário (rebuild) |
| SEV/PSP warnings no boot | Média (SEV default y) | Baixo | `CONFIG_KVM_AMD_SEV=n` já aplicado |
| AVIC missing → performance | N/A (ausente no silício) | Baixo | Legacy IRQ funciona; sem impacto funcional |
| bzImage kexec failure | Baixa (mesmo formato ZSTD) | Alto | Manter backup bzImage original; USB fallback |
| Memória insuficiente para guest | Média (5.1 GB livre) | Médio | Guest minimal 256-512 MB; zswap ativo |

---

## 7. Decisões de Design (ADR Log)

| ADR | Decisão | Justificativa |
|-----|---------|---------------|
| **ADR-001** | Módulos `=m` (não `=y`) | Isola falhas; permite `rmmod` se travar; built-in aumenta bzImage desnecessariamente |
| **ADR-002** | `CONFIG_KVM_AMD_SEV=n` | Sem PSP/CCP-DD no Jaguar; evita warnings/build deps |
| **ADR-003** | Build em cópia isolada + `mrproper` | Preserva source tree original com patches não-commitados |
| **ADR-004** | Container `ps4-kernel-builder:zstd` estendido | Adiciona `zstd` CLI sem alterar toolchain base |
| **ADR-005** | Deploy via kexec substituindo `/data/linux/boot/bzImage` | Método já validado no repo; rollback = power cycle |
| **ADR-006** | Smoke test VM com QEMU user-mode networking | Não depende de `eth0`/driver mts (ainda instável) |

---

## 8. Referências Cruzadas

- `AGENTS.md` — Regras de hardware, rede, deploy, RE
- `PLANO_FASES_GBE_2026-07-25.md` — Estilo de roadmap, faseamento, gates
- `BAIKAL_DEVLOG.md` — Contexto patches Baikal/IOMMU/MSI
- `kernels/ps4-baikal-7.0.8-kernel/.config.orig-baseline` — Config baseline
- `kernels/kvm-build-workdir/artifacts-fase1/` — Artefatos Fase 1
- `consolidado/ps4_hardware_memory.db` — SQLite de varreduras (não usado neste plano)

---

## 9. Próximos Passos Imediatos

1. [ ] **Executar Fase 2** (auditoria módulos — comandos na seção 5)
2. [ ] **Aguardar confirmação do usuário** para Fase 3 (deploy no PS4)
3. [ ] Preparar `qemu-system-x86_64` static binary + guest kernel/initramfs minimal para Fase 5

---

## 10. Changelog do Documento

| Data | Versão | Autor | Mudança |
|------|--------|-------|---------|
| 2026-07-24 | 1.0 | Assistant | Criação inicial; Fase 1 concluída registrada |