---
name: audio-hdmi-confirmado-desktop-2026-07-24
description: Áudio via HDMI confirmado funcionando perfeitamente pelo usuário durante a sessão de desktop Xorg+Cinnamon (teste pessoal), não só como driver carregado mas em uso real.
metadata:
  type: project
---

Durante a sessão de teste do ambiente desktop (Xorg + Cinnamon) no PS4 em 2026-07-24, o usuário confirmou diretamente que o **áudio via HDMI está funcionando perfeitamente**.

Isso complementa (não substitui) o que já estava registrado em `consolidado/STATUS_ATUAL.md` — lá o áudio HDMI já aparecia marcado como funcional a nível de driver (`snd_hda_intel` ✅). Essa confirmação é a validação em uso real, com o desktop completo rodando (útil para separar "driver carrega sem erro" de "som realmente sai pela TV").

**Como aplicar:** não há ação pendente — só registro do fato. Se algum áudio parar de funcionar numa sessão futura, isso é uma regressão (não um "nunca funcionou"), então vale investigar o que mudou desde 2026-07-24.
