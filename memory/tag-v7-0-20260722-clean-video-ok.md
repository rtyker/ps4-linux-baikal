---
name: tag-v7-0-20260722-clean-video-ok
description: Baseline funcional oficial — vídeo OK, boot completo, telnet OK, rebuild limpo (tag de referência)
metadata:
  type: project
---

## Tag de Referência — `v7.0-20260722-clean-video-ok`

**Status:** ✅ BASELINE OFICIALMENTE FUNCIONAL — Usar como ponto de partida para todos os rebuilds

### O Que É Esta Tag
Snapshot do kernel Linux 7.0 Baikal compilado com sucesso e validado ao vivo em 2026-07-22. É o **ponto de referência IMUTÁVEL** a partir do qual todas as melhorias subsequentes foram aplicadas (ethernet, GPU Gladius, SSH automático).

### Origem e Motivação
- Removido patch `sky2-baikal-gbe.patch` que travava o vídeo (confirmado: GBE não é Yukon e patch forçava probe indevida)
- Rebuild totalmente limpo do zero com `CONFIG_DEBUG_INFO_BTF=y` + `CONFIG_REGMAP_MMIO=y`
- Validação ao vivo: vídeo HDMI OK, boot até prompt, acesso telnet via WiFi com sucesso

### Características Comprovadas
✅ Kernel 7.0 Baikal compila sem erros (toolchain gcc 15.2.0)
✅ Boot HDMI funciona (tela legível, zero crashes de vídeo)
✅ Acesso root via telnet (WiFi automática, credenciais padrão)
✅ Telnet estável (múltiplas sessões, zero timeouts relatados)
✅ Mensagens kernel legíveis em dmesg (zero corrupção de memória)

### Configuração Crítica da Tag
```bash
# Arquivo: linux_build_7.0/.config (SNAPSHOT)
CONFIG_DEBUG_INFO_BTF=y         # OBRIGATÓRIO — remover causa tela preta
CONFIG_MFD_SYSCON=y              # OBRIGATÓRIO — suporte a regmap Baikal
CONFIG_REGMAP_MMIO=y             # OBRIGATÓRIO — acesso MMIO ao GBE Baikal
CONFIG_SKY2=y                    # Suporte Marvell Yukon (para Aeolia/Belize futuros)
CONFIG_NETDEV_10000=y            # Rede via Ethernet
CONFIG_DEBUG_KERNEL=y            # Debug info
CONFIG_DEBUG_INFO=y              # Symbols

# Compilação
MAKE_OPTS="JOBS=2"               # ← CRÍTICO: pahole usa muita RAM, JOBS>2 causa swap/OOM
```

### Não Alterar Nunca
- ✋ Remover `CONFIG_DEBUG_INFO_BTF=y` → tela preta garantida
- ✋ Remover `CONFIG_MFD_SYSCON` ou `CONFIG_REGMAP_MMIO` → boot com hang no GBE
- ✋ Usar `JOBS > 2` no pahole → OOM/swap killing processos
- ✋ Adicionar patches que forçam probe em IDs não-Yukon → travamento de vídeo/vídeo preto

### Como Usar Como Referência
```bash
# Checkout exato (se em git, exemplo):
# git checkout v7.0-20260722-clean-video-ok

# Copiar .config exato:
cp linux_build_7.0/.config linux_build_7.0/.config.bak
# [ revisar e aplicar exatamente ]

# Rebuild validado:
cd linux_build_7.0
make clean
make -j2 bzImage ARCH=x86_64
```

### Progresso Após Esta Tag
Adições aplicadas com sucesso após esta baseline (sem quebrar vídeo):
1. ✅ **Ethernet automática (2026-07-23):** netconsole + `mts.ko stage=4` autoload
2. ✅ **GPU Gladius acelerada (2026-07-23):** amdgpu com firmwares, OpenGL 4.5 @ 55 FPS
3. ✅ **SSH systemd service (2026-07-22):** acesso remoto automático
4. 🔄 **Debug loop (2026-07-23):** em progresso — decisão de desligar pendente

### Checklist de Reproducibilidade
Se precisar rebuildar exatamente a partir desta tag:
- [ ] Docker ps4sdk ativo (`docker build -t ps4sdk .` em `ps4-payload-sdk/`)
- [ ] `.config` copiado exato da snapshot
- [ ] `MAKE_OPTS=JOBS=2` configurado
- [ ] `make clean` rodado
- [ ] `make -j2 bzImage` rodado (NÃO `make -j8` ou paralelo)
- [ ] Resultado esperado: `bzImage-7.0-20260722-*` sem erros, vídeo HDMI OK ao boot

### Referências Relacionadas
- [[status-build-20260723]] — estado atual (derivado desta tag)
- [[baseline-oficial-sky2len-fix]] — histórico de como chegamos aqui
- `consolidado/BAIKAL_HARDWARE_DISCOVERIES.md` — Hardware discoveries que levaram a esta baseline
