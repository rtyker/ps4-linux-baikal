---
name: producao-so-apos-aprovacao
description: "REGRA IMPERATIVA: só usar rootfs/initramfs de PRODUÇÃO quando tudo estiver concluído, funcionando e aprovado pelo usuário — durante troubleshooting/diagnóstico, usar SEMPRE o initramfs de debug"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

**Regra imperativa:** enquanto o boot do kernel 7.0 (ou qualquer subsistema) ainda está em fase de diagnóstico/troubleshooting, usar SEMPRE o initramfs de debug (o que grava dmesg em FAT/pendrive, com ou sem WiFi+telnet). NUNCA trocar para o initramfs/rootfs de produção (mkinitcpio, systemd completo) por conta própria só porque "parece que vai funcionar" ou para testar uma correção pontual (ex: `root=LABEL=...`).

**Por quê:** em 2026-07-16, durante uma sessão de telnet no initramfs de debug (que já estava funcionando e dando visibilidade), copiei por conta própria o initramfs de produção do rootfs para a partição de boot, substituindo o debug — antes de o usuário ter validado que o boot completo (SATA, systemd, sshd) funcionava de ponta a ponta. Resultado: o teste seguinte não deu nenhum sinal (produção não tem log em FAT, não pisca LED), então perdemos toda a visibilidade que tínhamos conquistado, e não sabemos se o boot travou, se travou onde, ou se só demorou. O usuário reagiu com razão: "só use produção quando tudo estiver concluído e funcionando e aprovado".

**Como aplicar (regra reforçada em 2026-07-16, dita duas vezes pelo usuário):**
- **TUDO que fizermos é DEBUG por padrão. TUDO precisa gerar log.** Isso só muda se o usuário disser explicitamente o contrário — nunca por iniciativa própria, nunca por achar que "já deve estar funcionando".
- Todo boot, todo teste, todo deploy no HD do PS4 usa o initramfs de DEBUG (grava dmesg/netstat em FAT/pendrive, com WiFi+telnet quando aplicável) até o usuário aprovar explicitamente a mudança para produção.
- Trocar para produção é uma decisão do usuário, não uma iniciativa minha — perguntar/confirmar antes, mesmo que pareça "só um teste rápido".
- Enquanto qualquer bloqueador conhecido não estiver resolvido (vídeo GFX/CP, tamanho do bzImage >10MB, etc. — ver `TENTATIVAS_7.0.md`), manter o debug initramfs ativo no HD entre testes.
- Se uma correção precisar ser validada (ex: `root=LABEL=psxitarch`), testar primeiro com o initramfs de DEBUG (que dá visibilidade via FAT/telnet) antes de sequer cogitar produção.
- Ver [[ler-licoes-aprendidas-primeiro]] e [[root-sempre-label-psxitarch]].
