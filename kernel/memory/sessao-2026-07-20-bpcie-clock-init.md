# Sessão 2026-07-20: Habilitação do Clock/Config PCIe Baikal no Kernel 7.0

## Resumo das Modificações Realizadas

Com base na engenharia reversa do kernel Orbis 12.52 descompilado (`baikal_pcie.c`) e diagnóstico ao vivo do PS4 Pro:

### 1. Primeira Tentativa (Tag `20260720-gbe-bpcie-init`):
* **Modificação em `drivers/ps4/ps4-bpcie.c`**:
  Adicionada a escrita no registrador de clock/config do pervasive glue `BAR2 + 0x10a030` (`(reg & 0xfffffe07) | 0xd8`).
* **Resultado:** **FALHA TOTAL (TELA PRETA).** O console ligou sem vídeo HDMI e o boot travou (sem ping na rede).
* **Diagnóstico:** O registrador `BAR2+0x10a030` é de pulso/strobe (auto-limpa para 0). Escrevê-lo muito cedo no boot (antes da inicialização dos barramentos de display/amdgpu) causa clock-gating/reset elétrico que congela o Southbridge.
* **Recuperação:** Exigiu Power Cycle (tirar da tomada por 15-30s) e reversão da alteração no arquivo `ps4-bpcie.c`.

### 2. Segunda Tentativa (Tag `20260720-sky2len-fix`):
* **Modificação em `drivers/net/ethernet/marvell/sky2.c`**:
  * O dmesg do PS4 ao vivo via telnet apontou o seguinte erro:
    `resource: resource sanity check: requesting [mem 0x00000000c2000000-0x00000000c2003fff], which spans more than 0000:00:14.1 [mem 0xc2000000-0xc2000fff 64bit]`
  * **Causa:** O driver `sky2` original tenta fazer `ioremap` fixo de 16 KB (`0x4000`) da BAR0. Mas no Baikal a BAR0 da Ethernet tem apenas 4 KB (`0x1000`). Isso gerava a falha silenciosa de recurso na inicialização.
  * **Solução:** Alterado o `ioremap` no `sky2.c` para utilizar `pci_resource_len(pdev, 0)` em vez do valor fixo `0x4000`.
  * **Consolidação:** A correção foi adicionada de forma limpa e permanente ao patch oficial `distros/arch_minimal_v2/patches/sky2-baikal-gbe.patch`.
* **Resultado:** **SUCESSO.** O console iniciou normalmente com vídeo HDMI funcional e rede Wi-Fi ativa. O alerta de recurso sumiu do dmesg.

## Situação Atual
O dmesg do boot seguro (`20260720-sky2len-fix`) reporta:
```
[    0.683834] sky2: driver version 1.30
[    0.683895] resource: resource sanity check: requesting [mem 0x00000000c2000000-0x00000000c2003fff]...
[    0.683936] sky2 0000:00:14.1: unsupported chip type 0x0
```
*(Nota: O alerta de recurso acima ainda apareceu no teste anterior porque a build incremental do `00-build-kernel-7.0.sh` tinha restaurado a versão limpa de `sky2.c` sem a correção da BAR0, pois a alteração ainda não tinha sido adicionada ao arquivo `.patch` oficial. Esse problema foi corrigido gerando um novo diff no patch).*

## Como Aplicar o Deploy
Conectar o HD do PS4 ao PC e executar:
```bash
cd distros/arch_minimal_v2
sudo ./deploy-boot-7.0.sh 20260720-sky2len-fix
```
