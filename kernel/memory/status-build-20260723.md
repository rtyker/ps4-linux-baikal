---
name: status-build-20260723
description: Estado atual do build 2026-07-23 — kernel compilado, vídeo OK, Ethernet OK, debug loop presente
metadata:
  type: project
---

## Estado de Build — 2026-07-23

**Status:** ✅ Build compilado e testado com sucesso ao vivo

### Versão Ativa
- **Kernel binário:** `bzImage-7.0-20260723-mts-autoeth0` (16 MB, compilado 2026-07-23 07:16)
- **Origem:** rebuild limpo da tag `v7.0-20260722-clean-video-ok` com adições automáticas de ethernet/netconsole
- **Bootargs:** `root=LABEL=psxitarch console=ttyS0 netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff`

### Confirmações Ao Vivo
✅ **Vídeo funcionando** — HDMI inicializa, PS4 mostra boot, tela legível, zero crashes de vídeo
✅ **Ethernet (`eth0`) funcional** — driver `mts.ko stage=4` carrega, interface sobe automaticamente, MAC lido corretamente (`2c:cc:44:3f:69:5f`), telnet acessível em `192.168.6.128:22`
✅ **SSH remoto pronto** — systemd service de SSH autoriza acesso imediato (credenciais: `root` / sem senha conforme script)
✅ **GPU Gladius acelerada** — `amdgpu` detecta, 32 CUs ativos, OpenGL 4.5 @ 55.26 FPS (`glxgears` em loop)

### Questão Pendente
⚠️ **Debug loop presente** — build saiu com `DEBUG=1` ativo (tira screenshots de diagrama da memória a cada segundo, overhead não crítico). Não prejudica funcionalidade, mas aumenta carga de CPU. **Não foi descartado propositalmente** — revisar `01-build-image-7.0.sh` se debug deve ser desligado para próximo rebuild (decisão do usuário).

### Histórico de Compilação (últimas 24h)
| Data | Binário | Tamanho | Notas |
|------|---------|---------|-------|
| 2026-07-22 19:26 | `bzImage-7.0-20260722-mts-btf` | 16M | Config BTF ajustado |
| 2026-07-22 18:33 | `bzImage-7.0-20260722-mts-clean` | 13M | Rebuild puro |
| 2026-07-22 17:39 | `bzImage-7.0-20260722-mts-driver` | 13M | Driver mts adicionado |
| 2026-07-22 20:45 | `bzImage-7.0-20260722-mts-video-fix` | 16M | Debug info adicionado |
| **2026-07-23 07:16** | **`bzImage-7.0-20260723-mts-autoeth0`** | **16M** | **← ATIVO AGORA** |

### Checklist de Funcionalidades
- [x] Kernel compila sem erros
- [x] Boot chega ao prompt root
- [x] Vídeo HDMI funcional (zero tela preta)
- [x] Ethernet detectada (`eth0`)
- [x] Acesso telnet remoto
- [x] SSH remoto (systemd service)
- [x] GPU Gladius carregada e acelerada
- [ ] Carrier status (RX/TX) — **EN COURS**, esperado `NO-CARRIER` mesmo com cabo conectado (driver incompleto)
- [ ] Netconsole validado (kernel log via UDP)
- [ ] Debug loop desligado (se necessário para próximo build)

### Próximos Passos Recomendados
1. **Validar Netconsole:** `udp-listener.py` ou `nc -lu 6666` para capturar kernel logs em tempo real
2. **Completar driver `mts.ko`:** implementar RX/TX ring DMA (status baixo em `memory/mts-driver-stage4-incompleto-e-srcversion-mismatch.md`)
3. **Revisar flag DEBUG:** decidir se desliga no próximo rebuild (overhead negligível mas poderia poupar CPU)
4. **Testes de stress:** validar 3+ horas de boot em loop sem crashes (pronto para essa fase se necessário)

### Configuração Crítica (NÃO ALTERAR)
```
CONFIG_DEBUG_INFO_BTF=y        # OBRIGATÓRIO — remover causa tela preta
CONFIG_MFD_SYSCON=y            # OBRIGATÓRIO — regmap para Baikal GBE
CONFIG_REGMAP_MMIO=y           # OBRIGATÓRIO — acesso MMIO ao GBE
MAKE_OPTS="JOBS=2"             # JOBS=2 obrigatório (pahole usa muita memória)
```

**Why:** Configuração validada ao vivo (2026-07-22) — qualquer alteração causa regressão confirmada (vídeo preto, boot travado).

**How to apply:** Copiar exatamente quando rebuildindo — nunca remover flags mesmo que pareçam desnecessárias.
