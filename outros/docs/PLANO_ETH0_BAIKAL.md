# Plano Estratégico — suporte completo do eth0 (Baikal GBE) no PS4

## Status e evidências do hardware

O driver `mts.ko` existe, compila e registra `eth0` com endereço MAC `2c:cc:44:3f:69:5f` (lido da SPM). O MAC/DMA funciona parcial: TX completa e RX não.
O problema agora é que o PHY nunca acorda — o link não sobe, IRQ não chega, RX nunca entrega pacotes.
A causa raiz deve ser um domínio de energia separado controlado pelo firmware Sony antes do kernel, fora do alcance direto de MDIO, ICC, SAMU ou RMU.

## O que já foi investigado e descartado

- ICC Major=5 não tem minor para a GBE (major=5 só controla wlan/bt/usb/hdd/bd).
- ICC Major=4, minor=0x38 é válido mas só consulta status, não liga o PHY.
- Varredura de minors de Major=4 com GET entrega sempre a mesma resposta genérica — inútil.
- Phys address scan 0–31 não discrimina (funções Orbis não têm parâmetro de endereço).
- MDIO Clause 22/45: protocolo corrigido, mas sem resposta real (PHY sem energia/clock).
- MSI e IMR desmascarados: IRQ_count=0, o PHY não gera evento algum.
- Bruteforce de registradores/bar2 em fase de boot trava o console — risco alto.

## Hipótese mais forte

O PHY da GBE vive em domínio de energia independente, ligado pelo firmware/bootloader Sony durante o init do southbridge, antes do kernel assumir.
Isso explica por que a GBE funciona nativamente sob Orbis (firmware liga e mantém) e falha assim que o Linux boot (o init do Linux não replica o mesmo fluxo).
A RE de `gbe_phy_ctrl` (dc5a44c0) e vizinhança não mostrou chamadas ICC/SAMU — o controle é apenas leitura via MDIO, sem ação de power-on.
Conclusão: é provável que o Linux precise replicar, em `ps4-bpcie` ou num driver de glue, o conjunto de writes/pulsos que o firmware Sony aplica durante a inicialização do southbridge.
Endossos externo: o linux-psx reporta Ethernet nativo `psx0` funcionando em Baikal B1 (teste limitado, mas evidência de que é possível).
Outras fontes independentes (linux-ps4, ps4-baikal-5.4, tutoriais) convergem para “eth0 não funciona em Baikal” — o bloco é reconhecido como um dos hard blocks do port.

## Lacunas de informação reconhecidas

- É desconhecido o sequence exato de clock / reset / hold / efuse / escrita secret que liga o PHY no init Sony.
- O driver Atual não mapeia/usa BAR4 do glue para efuse de calibração PHY — nem todos os registradores físicos já escrito.
- A resposta do PHY em Clause 45 devolve zero sempre — mas não se confirmou se o barramento MMIO dela (glue BAR2/BAR4) está no estado correto para responder.

## Plano de ação passo-a-passo

1. **Coletar baseline ao vivo agora com o PS4 no estado funcional (SSH por WiFi):**
   - Varrer BAR0 inteiro de 00:14.1 e anotar valores; cruzar com mapa conhecido em `bar0_register_map`.
   - Ler glue BAR2 (0xc8800000) e BAR4 (se mapeado) em regiões já documentadas (hold/pulse, clock), comparar sessão com leituras de boot.
   - Confirmar estado do MAC enable (0x34/0x38) e da IMR (0x54) e dos contadores (0x100/0x104/0x128/0x12c).
   - Recolher o log da UART (UART TTL) dos últimos segundos do boot e do handoff do kexec para ver quando a rail cai (timestamp).
   - Guardar tudo em `outros/rea/scans/` com data e tag do build.

2. **Mapear o que o linux-psx faz diferente no bring-up de eth0:**
   - Estudar o diff entre `mts` deste projeto e o driver `psx_mts_net` (linux-psx) de Bring-up: sequência de writes no BAR0, uso de BAR4, holds, calibração, parametros mdio e tratamento de umclock.
   - Focar no que o seu driver não faz que o deles faz (ou vice-versa); anotar em uma tabela comparativa.

3. **Análise estática do glue do Orbis para o PHY:**
   - Decompilar as funções `gbe_phy_ctrl` e qualquer rotina do glue que toque no BAR2/BAR4 no init, especialmente a que não foi extraída ainda (`dc5a5ec0` e caminho `dc5ba8d0`/`dc5baa30`).
   - Procurar no mesmo dump Orbis a sequência completa que o firmware/EMC/Managment executa na inicialização do southbridge para ativar a GBE (possível caminho em EMC, Syscon, ou ACPI).
   - Priorizar por endereço MMIO já conhecido e por writes no BAR2/4 com bit pattern semelhante ao do clock/hold já validado.

4. **Experimentar, com máximo de cuidado e leitura antes de escrita:**
   - Com o console funcionando, testar leitura apenas de cada candidato de glue (SEM escrever) para confirmar safe-to-read.
   - Só após uma via de RE apontar um sequence de escrita com lastro, planejar uma tentativa controlada de trafego no PHY via driver ou via glconcat.
   - Nunca repetir escrita cega em BAR2/BAR4 no caminho de boot sem última confirmação de leitura segura.

5. **Validar via rede (somente quando PHY levantar):**
   - eth0 com IP fixo na subnet 192.168.0.0/24, ping de/para o host, RX/TX por DMA, verificação de IRQ real via /proc/interrupts.
   - Registrar no `test_history` com id único, target_component=GTE/phy, status e complementary_info.

## Riscos e restrições

- Risco de travamento ou perda de vídeo com writes no BAR2/BAR4 no boot (já observado em testes M4/M7).
- Já está documentado que “nunca montar em /mnt” e que toda build/deploy passa pelos scripts do projeto — manter.
- Esta fase é levantamento e plano; código do driver não deve ser alterado agora, apenas analisado/discutido.
- Salvar cada descoberta ao vivo e cada tentativa no banco SQLite e nos documentos do projeto antes de avançar.

## Entregáveis desta planificação

- Este arquivo como plano vivo.
- Tabela comparativa do bring-up MTS (projeto vs linux-psx).
- Snapshot de leitura ao vivo do BAR0/glue no PS4 com timestamp.
- Atualização do BACKLOG.md e/ou AGENTS.md com a causa raiz mais provável e o próximo experimento candidato mais seguro.
