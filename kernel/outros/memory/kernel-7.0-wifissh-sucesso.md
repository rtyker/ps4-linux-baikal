---
name: kernel-7-0-wifissh-sucesso
description: "Tag 20260716-wifissh: initramfs de debug com WiFi+telnet dá acesso root remoto ao PS4 real (kernel 7.0), independente do SATA/rootfs — usado para coletar hardware real"
metadata:
  node_type: memory
  type: project
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

Na sessão de 2026-07-16, a tag `20260716-wifissh` (kernel 7.0 build #6 + initramfs de debug com pilha WiFi completa em RAM) conseguiu **acesso root remoto ao PS4 real via WiFi + telnet**, independente de o rootfs em disco montar ou não. Isso deu visibilidade total pela primeira vez nesta fase do projeto.

**Como funciona:** o initramfs de debug sobe `wpa_supplicant` + `udhcpc` + `telnetd` (porta 23, root sem senha) direto na RAM, antes de qualquer tentativa de montar o rootfs real. WiFi conecta na rede `prfelicidade_5G`, pega IP conhecido `192.168.6.128` via DHCP. Conectar com `telnet 192.168.6.128 23`.

**Achado crítico feito via esse shell:** `root=/dev/sda2` no `bootargs-7.0.txt` de produção apontava pro HD **interno** do PS4 (errado — ver [[kernel-7.0-sata-desconexao-boot]]), não pro nosso disco de boot (`sdb`). Corrigido para `root=LABEL=psxitarch` em todos os bootargs do projeto — já virou regra permanente em `LICOES_APRENDIDAS.md` #24 ([[root-sempre-label-psxitarch]]).

**Coleta de hardware feita nessa sessão via telnet** (salva em `distros/arch_minimal_v2/hardware_ps4_real/` e documentada em `BAIKAL_HARDWARE_DISCOVERIES.md` seção 5): eFuse real do WiFi MT7668 (`/proc/net/wlan/efuse_dump`, 960 bytes), MAC WiFi real `00:0c:43:26:60:48`, confirmação de que `sdb` é um SSD Kingston SV300S37A120G (não HD mecânico), topologia USB/PCI completa, dmesg completo do boot.

**Status dos subsistemas nesse teste:**
- ✅ WiFi conecta e telnet root funciona
- ❌ GPU/GFX-CP: `ring gfx test failed (-110)` — mesmo bloqueio de sempre, precisa do firmware gladius real (dump do console, método fail0verflow) — ver [[kernel-7.0-gladius-firmware-ausente]]
- ⚠️ WiFi: driver reporta "load manufacture data fail" / regdomain não encontrado (não fatal, usa defaults do eFuse)
- ❌ Ethernet: sky2 nunca cria `eth0`

**Como aplicar:** essa tag (`wifissh`) é o initramfs de DEBUG padrão atual do projeto — usar como base para todos os próximos testes no HD real, mantendo a regra de nunca trocar para produção sem aprovação explícita ([[ler-licoes-aprendidas-primeiro]], lição #25). Para debugar algo nesse hardware, sempre preferir telnet ao vivo em vez de só ler dmesg gravado, já que dá shell interativo completo.
