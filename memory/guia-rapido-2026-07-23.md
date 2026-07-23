---
name: guia-rapido-2026-07-23
description: Guia rápido — estado atual do projeto e como começar (2026-07-23)
metadata:
  type: reference
---

## 🚀 Guia Rápido — Comece Aqui (2026-07-23)

**Status:** ✅ Kernel Linux 7.0 Baikal **FUNCIONAL** — vídeo, Ethernet, GPU, SSH tudo rodando.

---

## 📋 Checklist de 30 Segundos

- ✅ Vídeo HDMI funciona?  **SIM** (tela legível ao boot)
- ✅ Ethernet funciona?  **SIM** (eth0 UP, MAC correto, DMA OK)
- ✅ SSH remoto funciona?  **SIM** (systemd service automático)
- ✅ GPU acelerada?  **SIM** (55 FPS OpenGL 4.5, Vulkan 1.3)
- ✅ Build atual OK?  **SIM** — `bzImage-7.0-20260723-mts-autoeth0`

---

## 📚 O Que Ler Primeiro (Na Ordem)

### 1️⃣ **Regras do Projeto** (2 min)
👉 `CLAUDE.md` (raiz) — Regras imperativas, nunca quebrar essas.

### 2️⃣ **Estado Atual** (5 min)
👉 `memory/resumo-executivo-2026-07-23.md` — Tabelas de status, pendências, próximos passos.

### 3️⃣ **Detalhes Técnicos** (10 min, conforme necessário)
- `memory/status-build-20260723.md` — Build detalhado
- `memory/gpu-gladius-amdgpu-validado.md` — GPU validada
- `memory/mts-driver-stage4-incompleto-e-srcversion-mismatch.md` — Ethernet em progresso

### 4️⃣ **Índice de Tudo** (30 seg)
👉 `memory/MEMORY.md` — Índice completo, busque por palavra-chave.

---

## 🎯 Próximas Ações (Recomendadas)

### Rápido (~15 min)
- [ ] Testar netconsole UDP: `nc -lu 6666` no host → ver kernel logs ao vivo
- [ ] Verificar carrier Ethernet: telnet PS4 → `ip link show eth0` (deve estar `NO-CARRIER`, é esperado)

### Médio (~1-2h)
- [ ] Testar RX manual: `ip addr add 192.168.6.130/24 dev eth0` + `ping` (confirmará se RX não funciona)
- [ ] Desligar debug loop se overhead incomoda: mudar `DEBUG=1 → DEBUG=0` em `01-build-image-7.0.sh`

### Longo (~4-6h, opcional)
- [ ] Completar driver Ethernet: implementar RX/TX rings (ver `mts-driver-stage4-incompleto-e-srcversion-mismatch.md`)
- [ ] Reverse-engineering GBE: usar dump kernel 12.52 para comparar Sony's driver

---

## 🗂️ Arquivos Importantes vs. Descartados

### ✅ **USE ESTES ARQUIVOS**

#### Configuração & Status (2026-07-23)
| Arquivo | Propósito | Leia se... |
|---------|-----------|-----------|
| `CLAUDE.md` | Regras gerais | Quer entender regras de não fazer |
| `memory/MEMORY.md` | Índice de tudo | Procura por palavra-chave |
| `memory/resumo-executivo-2026-07-23.md` | Estado global | Quer visão 30s de tudo |
| `memory/status-build-20260723.md` | Build checklist | Quer rebuild ou entender config |
| `memory/tag-v7-0-20260722-clean-video-ok.md` | Baseline imutável | Quer saber ponto de referência |

#### Técnica & Hardware
| Arquivo | Propósito |
|---------|-----------|
| `consolidado/LICOES_APRENDIDAS.md` | Lições comprovadas (LEIA ANTES DE AGIR) |
| `consolidado/BAIKAL_HARDWARE_DISCOVERIES.md` | Mapa de hardware (BAR0/BAR2/etc) |
| `consolidado/MARCO_HISTORICO_ETH0_MTS_BAIKAL.md` | Histórico eth0 bring-up |
| `consolidado/INTEGRACAO_IMAGEM_7.0_GLADIUS_E_WIFI.md` | Integração GPU |
| `consolidado/RE_KERNEL_GBE_ATTACH.md` | Reverse-engineering GBE (Sony) |
| `consolidado/ps4_hardware_memory.db` | SQLite com 671 registradores validados |

### ❌ **IGNORE/DESCARTADOS**

Estes arquivos são histórico obsoleto — **não use:**

```
old_project/                        ← Projeto antigo descontinuado
old_project/distros/...             ← Builds antigos (stmmac, wifissh, etc)
old_project/LICOES_APRENDIDAS.md    ← Versão antiga (use consolidado/LICOES_APRENDIDAS.md)
distros/arch_minimal_v2/TENTATIVAS_7.0.md  ← Log de testes (referência apenas)
```

### 📦 **NÃO ALTERAR**

Estes são baselines imutáveis — **NUNCA modifique:**

```
distros/arch_minimal_v2/boot_referencia/bzImage-7.0-20260722-*
distros/arch_minimal_v2/boot_referencia/config-7.0-20260720-*
scene-kmem-dumper/source/diag.c (9356 bytes, 2026-07-20)
scene-kmem-dumper/diag.bin
```

---

## 💡 Dica Importante

**Antes de fazer QUALQUER coisa neste projeto:**

1. Ler `CLAUDE.md` (regras de não fazer)
2. Ler `consolidado/LICOES_APRENDIDAS.md` (erros já cometidos)
3. Ler contexto relevante (status/hardware/driver)
4. **DEPOIS agir**

**Porquê?** Erros aqui podem travar console por horas (power cycle necessário). Prevenção via documentação é mais rápido que recovery.

---

## 🆘 Procurando Por...

| Procuro... | Leia aqui |
|---|---|
| **Como compilar kernel?** | `CLAUDE.md` + `distros/arch_minimal_v2/00-build-kernel-7.0.sh` |
| **Config exato do kernel?** | `distros/arch_minimal_v2/linux_build_7.0/.config` (git tag `v7.0-20260722-clean-video-ok`) |
| **Driver Ethernet incompleto?** | `memory/mts-driver-stage4-incompleto-e-srcversion-mismatch.md` |
| **GPU funcionando?** | `memory/gpu-gladius-amdgpu-validado.md` |
| **Registradores de hardware?** | `consolidado/ps4_hardware_memory.db` (SQLite) + `consolidado/BAIKAL_HARDWARE_DISCOVERIES.md` |
| **Histórico de tudo?** | `consolidado/LICOES_APRENDIDAS.md` (lições) + `consolidado/MARCO_*` (marcos) |
| **Erros já feitos?** | `consolidado/LICOES_APRENDIDAS.md` (seção "Erros a Evitar") |
| **Payload/dumping kernel?** | `CLAUDE.md` seção "Estado do Dumper TCP" (referência — não é objetivo atual) |

---

## ✉️ Próxima Sessão?

Volte aqui, leia este arquivo (~2 min), depois `resumo-executivo-2026-07-23.md` (~3 min), e você terá contexto completo para agir.

**Última atualização:** 2026-07-23
**Status:** ✅ Estável e funcional

