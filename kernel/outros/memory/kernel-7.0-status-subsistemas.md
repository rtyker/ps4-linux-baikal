---
name: kernel-7-0-status-subsistemas
description: "Onde consultar o histórico de tentativas de boot do kernel 7.0 Baikal, para não repetir testes"
metadata: 
  node_type: memory
  type: reference
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

Todo teste de boot do kernel 7.0 (tags, firmware usado, initramfs, resultado do dmesg) é registrado em:

`distros/arch_minimal_v2/TENTATIVAS_7.0.md`

Antes de sugerir um novo teste ou repetir uma hipótese, ler esse arquivo primeiro — ele tem a lista "O que já sabemos que NÃO funciona" e "Próximos passos pendentes" sempre atualizada. Ver também [[kernel-7.0-gladius-firmware-ausente]] para o detalhe técnico do problema de firmware GPU.

Resumo rápido do estado (ver arquivo para detalhes/datas):
- Kernel 7.0 (rmuxnet/linux, baikal/7.0.8-Stable) boota (USB/AHCI/initramfs OK confirmado via dmesg)
- Vídeo: GFX/CP trava (-110 timeout) mesmo com firmware liverpool-as-gladius; só dump real do console resolve
- Ethernet (sky2): nunca vira `eth0` mesmo builtin — investigar se é o mesmo bug Baikal GBE de `PESQUISA_ETHERNET_BAIKAL.md`
- WiFi (SDIO MT7668): driver inicializa mas falha em "load manufacture data" / regdomain — não conecta ainda
- **CRÍTICO** (ver [[kernel-7.0-sata-desconexao-boot]]): o próprio HD (sda) perde a conexão SATA ~31s após boot real no PS4 e é desabilitado ~62s — pode ser a causa real de vários boots "mortos" anteriores, não (só) travamento de kernel/GPU
