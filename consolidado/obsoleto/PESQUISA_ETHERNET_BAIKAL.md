# Pesquisa e Investigação — Ethernet Baikal (PS4 Pro)

Resumo das descobertas e estado atual da investigação sobre o suporte a Ethernet no PS4 Pro Baikal (**2026-07-13**).

---

## 1. O Sintoma Atual
Após descomentar o ID da placa de rede Baikal no driver `sky2.c` (`PCI_DEVICE_ID_SONY_BAIKAL_GBE`), o boot do kernel falhou ao inicializar a placa cabeada com os seguintes logs no `dmesg`:
```
[    0.865893] sky2: driver version 1.30
[    0.865964] caller sky2_probe+0x14e/0x6b0 mapping multiple BARs
[    0.865971] sky2 0000:00:14.1: unsupported chip type 0x0
[    0.866097] sky2: probe of 0000:00:14.1 failed with error -95
```
*   O driver falha no método de probe porque a leitura do registrador `B2_CHIP_ID` retorna `0x0`.

---

## 2. Diagnósticos Detalhados Coletados via SSH

### A. Registros Físicos (BAR0) inacessíveis
Ao tentar ler diretamente a memória de registradores do dispositivo PCI através do arquivo sysfs (`resource0` mapeado em `c2000000`), o kernel retorna um erro de entrada/saída físico:
```bash
hexdump -C -n 128 /sys/bus/pci/devices/0000:00:14.1/resource0
# Retorno: Input/output error (EIO)
```
*   **Significado:** Embora o barramento PCI enxergue o dispositivo `00:14.1` com `Mem+` ativado, a comunicação física com os registradores do chip de rede resulta em barramento bloqueado / timeout (gerando o erro `EIO` e a leitura de `0x0`).

### B. Diferença de BAR com Aeolia/Belize
*   O BAR0 da Ethernet no PS4 Baikal tem tamanho de apenas **4K** (`size=4K`), diferente de outros modelos que usam **16K** (razão pela qual o kernel emite o alerta `mapping multiple BARs` ao tentar mapear `0x4000` bytes).

---

## 3. Descoberta Importante no Repositório Remoto
Analisamos as filiais (branches) remotas de desenvolvimento de kernel PS4 da comunidade (`ps4-linux-12xx`), e descobrimos que:
*   Na branch `x_exp__6.15.4-BaikalLove`, o desenvolvedor principal explicitou em um comentário no `sky2.c`:
    ```c
    //{ PCI_DEVICE(PCI_VENDOR_ID_SONY, PCI_DEVICE_ID_SONY_BAIKAL_GBE) }, //TODO: Figure out lack of ethernet support on Baikal eventually
    ```
*   Na branch `x_exp__6.15.4-baikal-crashniels`, outro comentário confirma a mesma dúvida:
    ```c
    // is this broken maybe?
    // { PCI_DEVICE(PCI_VENDOR_ID_SONY, PCI_DEVICE_ID_SONY_BAIKAL_GBE) },
    ```
*   **Conclusão:** O suporte nativo à Ethernet no PS4 Pro Baikal é um **problema conhecido e não resolvido** na comunidade. A placa cabeada está em estado "adormecido" ou desligado eletricamente (clock-gated/power-gated).

---

## 4. Próxima Etapa (Para Amanhã)
Precisamos investigar como ativar/despertar eletricamente a placa de rede cabeada no chipset Baikal. As principais hipóteses são:
1.  **Syscon/ICC Command**: Verificar se o controlador Syscon (gerenciado pelo driver `ps4-bpcie-icc.c`) possui algum comando de inicialização necessário para habilitar o clock do GBE.
2.  **PCI Command/Power State**: Investigar se o driver de barramento Baikal (`ps4-bpcie.c`) ou o gerenciador de energia do ACPI precisa de algum patch específico de clock-gating para liberar o tráfego da Ethernet.
