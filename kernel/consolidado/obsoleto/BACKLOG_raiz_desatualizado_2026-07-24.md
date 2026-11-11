# Backlog — PS4 Linux Baikal

Índice de planos/projetos em andamento e pendentes de execução.

## Planos ativos

| ID | Plano | Estado | Data | Arquivo |
|----|-------|--------|------|---------|
| GBE-MTS | Driver GBE Baikal (mts.ko) — RX/TX/PHY MDIO | em andamento (Fase 0 pendente) | 2026-07-25 | `PLANO_FASES_GBE_2026-07-25.md` |
| BAR4-EFUSE | BAR4 / eFuse / calibração | pendente | 2026-07-23 | `PLANO_BAR4_EFUSE_CALIBRACAO_2026-07-23.md` |
| DUPLEX-PHY | Duplex / PHY MDIO | pendente | 2026-07-23 | `PLANO_DUPLEX_PHY_MDIO_2026-07-23.md` |
| IRQ-FULLDUPLEX | IRQ real / full-duplex | pendente | 2026-07-23 | `PLANO_IRQ_REAL_FULLDUPLEX_2026-07-23.md` |
| MAC-EN2 | Investigação MAC enable 2 | pendente | 2026-07-23 | `PLANO_MAC_EN2_INVESTIGACAO_2026-07-23.md` |
| RX-MTS | RX do mts.ko | pendente | 2026-07-23 | `PLANO_RX_MTS_2026-07-23.md` |
| RX-INVESTIGACAO | Investigação RX/TX | pendente | 2026-07-23 | `PLANO_INVESTIGACAO_RX_TX_2026-07-23.md` |

## Planos macro (estudo de viabilidade + roadmap)

| ID | Projeto | Estado | Data | Arquivo |
|----|---------|--------|------|---------|
| **KVM-PS4** | **Habilitar KVM-AMD no kernel Baikal (SVM/NPT do SoC Jaguar)** | **Fase 1 ✅ / Fase 2 ✅ — Fase 3 pronta p/ deploy** | **2026-07-24** | `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md` |

---

### KVM-PS4 — Resumo do macro-plano

**Objetivo:** Avaliar viabilidade técnica de habilitar KVM (kvm + kvm_amd) no kernel Linux 7.0.8 rodando no PS4 Baikal, permitindo virtualização por hardware utilizando SVM/NPT nativos do SoC Jaguar (DG1501SML87LB, AMD family 0x16).

**Veredito preliminar (Fase 0 — investigação concluída):** ✅ **VIÁVEL.**
- CPU expõe `svm`, `npt`, `nrip_save`, `tsc_scale`, `flushbyasid`, `decodeassists`, `pausefilter`, `pfthreshold`, `vmmcall` — `Virtualization: AMD-V` ativa
- Código KVM integral presente na árvore `kernels/ps4-baikal-7.0.8-kernel/arch/x86/kvm/` e `virt/kvm/`
- `.config` atual só tem `# CONFIG_KVM is not set` (todo o resto da base já está pronto: `CONFIG_VIRTUALIZATION=y`, `AMD_IOMMU=y`, `X86_X2APIC=y`, `SMP=y`, `NR_CPUS=8`)
- Check `__kvm_is_svm_supported()` só valida `X86_VENDOR_AMD` + `X86_FEATURE_SVM` + "não é SEV guest" — nenhuma barreira para family 0x16
- Sem AVIC no silício (sem `X86_FEATURE_AVIC`) → KVM cai para legacy IRQ, sem impacto funcional
- Sem SEV (sem PSP/CCP-DD ativos) → `KVM_AMD_SEV` **deve** ser desligado

**Roadmap de fases (ver plano detalhado):**

| Fase | Descrição | Estado | Artefatos / Gate |
|------|-----------|--------|------------------|
| **Fase 0** | Investigação de viabilidade (hardware, source tree, Kconfig, toolchain) | ✅ **CONCLUÍDA** 2026-07-24 | `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md` (seção 4) |
| **Fase 1** | Build estático sem deploy (compila KVM no toolchain do repo) | ✅ **CONCLUÍDA** 2026-07-24 | `kernels/kvm-build-workdir/artifacts-fase1/`<br>`bzImage.kvm` (14.28 MB, +860 KB vs original)<br>`kvm.ko` (21.75 MB)<br>`kvm-amd.ko` (4.34 MB)<br>`config.kvm` (136 KB)<br>Logs: `kvm_build.log`, `kvm_bzimage.log` |
| **Fase 2** | Auditoria pós-build: diff config, modinfo, check modversions | ✅ **CONCLUÍDA** 2026-07-24 | **Gates passados:**<br>• `vermagic` exato: `7.0.8-Strawberry-ThinLTO-Baikal- SMP preempt mod_unload`<br>• `CONFIG_MODVERSIONS=n` (sem CRC check)<br>• `CONFIG_MODULE_SIG=n`, `CONFIG_MODULE_COMPRESS=n`<br>• `depends`: `kvm` (nenhum), `kvm-amd` → `kvm`<br>• `bzImage.kvm` 14.28 MB (cabe no payload kexec) |
| **Fase 3** | Deploy controlado via kexec (rollback = power cycle) | ⏳ **PRONTA — aguarda confirmação usuário** | Requer PS4 ligado, SSH `192.168.6.128` ativo |
| **Fase 4** | Smoke test `modprobe kvm` / `/dev/kvm` / `kvm-amd` | ⏳ pendente | `/dev/kvm` criado, `dmesg`: "NPT enabled", "SVM enabled" |
| **Fase 5** | Smoke test VM minimal (QEMU-system + guest kernel/initramfs) | ⏳ pendente | QEMU user-mode networking (não precisa `eth0`) |
| **Fase 6** | (opcional) investigação IOMMU/VFIO passthrough | ⏳ pendente | `CONFIG_VFIO_PCI=y`, IOMMU preservado pelo patch Baikal |

**Estado atual:** **Fases 1 e 2 concluídas com sucesso**. Artefatos validados. **Fase 3 pronta para execução** (requer confirmação do usuário — toca no PS4 via kexec).

**Notas de risco:**
- Fase 1-2: **zero risco** (apenas compilação no host, sem tocar PS4)
- Fase 3+: kexec é não-destrutivo (desligar = volta ao Orbis); todos os testes ao vivo regidos pela Regra de Ouro do `AGENTS.md`
- IOMMU do PS4 é preservado (não reinicializado) em `drivers/iommu/amd/init.c` sob `#ifdef CONFIG_X86_PS4_BAIKAL` — KVM puro não demanda IOMMU; VFIO exigiria investigação adicional (Fase 6)

**Artefatos da Fase 1 (em `kernels/kvm-build-workdir/artifacts-fase1/`):**
```
bzImage.kvm        14,283,776 bytes  (novo kernel com KVM)
config.kvm           136,690 bytes  (.config com KVM=m, KVM_AMD=m, KVM_AMD_SEV=n)
kvm.ko              21,751,000 bytes  (módulo KVM core)
kvm-amd.ko           4,338,136 bytes  (módulo SVM/AMD-V)
kvm_build.log           11,675 bytes  (log completo do build)
kvm_bzimage.log           1,320 bytes  (log do relink bzImage com zstd)
```