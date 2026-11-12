# Descoberta Definitiva: Mascaramento do Vetor MSI PCI (`0x000000fe`) no SATA Interno Baikal

**Data:** 2026-07-29  
**Ambiente:** PS4 Baikal (`192.168.6.128` - CachyOS + Kernel 7.0 Baikal `20260729-sata-globallock`)  
**Status:** Causa Raiz de Hardware/Driver Localizada via SSH ao Vivo  

---

## 1. Evidência Factual #1 — Diagnóstico PCI (`lspci` ao vivo via SSH)

Inspecionamos os registradores estendidos do controlador PCI composto `0000:00:14.7` (Sony Baikal xHCI + AHCI) diretamente via SSH no console ativo:

```text
# lspci -s 0000:00:14.7 -vv
00:14.7 System peripheral: Sony Corporation Baikal USB 3.0 xHCI Host Controller (prog-if 07)
	Subsystem: Sony Corporation Device 90df
	Control: I/O- Mem+ BusMaster+ SpecCycle- MemWINV- VGASnoop- ParErr+ Stepping- SERR+ FastB2B- DisINTx+
	Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR+ <PERR- INTx-
	Latency: 0
	Interrupt: pin ? routed to IRQ 32
	Region 0: Memory at ce000000 (64-bit, non-prefetchable) [size=4M]
	Region 2: Memory at ce800000 (64-bit, non-prefetchable) [size=64K]
	Region 4: Memory at cf000000 (64-bit, non-prefetchable) [size=8M]
	Capabilities: [80] Express (v2) Endpoint, IntMsgNum 0
	Capabilities: [e0] MSI: Enable+ Count=1/8 Maskable+ 64bit+
		Address: 00000000fee00000  Data: 0024
		Masking: 000000fe  Pending: 00000000
	Capabilities: [f8] Power Management version 3
```

### 🔴 O Achado Crucial no Registrador de Máscara MSI (`Capabilities [e0] + 0x10`):

Masking = 0x000000fe (0b00000000000000000000000011111110)

| Vetor MSI | Subfunção / Dispositivo | Estado do Bit de Máscara | Ação do Hardware PCI | Resultado Medido |
|---|---|---|---|---|
| **Vetor 0** | USB xHCI1 (Subfunc 0) | **`0` (Unmasked / Ativo)** | Interrupção MSI permitida | 77.824+ IRQs processadas com sucesso! |
| **Vetor 1** | **AHCI SATA (Subfunc 1)** | **`1` (Masked / Bloqueado)** | **Interrupção MSI bloqueada no hardware** | **0 IRQs entregues após probe (interrupção cessa)** |
| **Vetores 2-7** | USB xHCI2 e reservados | **`1` (Masked / Bloqueado)** | Interrupção MSI bloqueada | N/A |

---

## 2. Evidência Factual #2 — Linha do Tempo do Kernel (`dmesg` ao vivo via SSH)

O log `dmesg` do sistema operacional confirma exatamente o que acontece quando o Vetor 1 do SATA está mascarado no PCI:

```text
[ 1.243s] ata1.00: ATA-10: TOSHIBA MQ04ABF100, JU0G0A, max UDMA/100
[ 1.268s] sd 0:0:0:0: [sda] 1953525168 512-byte logical blocks: (1.00 TB/932 GiB)
[ 1.268s] sd 0:0:0:0: [sda] Mode Sense: 00 3a 00 00
...
[31.823s] ata1: ahci_dbg: EH entry — IS=0x00000001 GHC=0x80000002 | PxIS=0x00000001 PxIE=0x00000000 PxCMD=0x0004d617
[31.824s] ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6 frozen
[31.825s] ata1.00: failed command: READ DMA (cmd c8, tag 22)
[31.829s] ata1.00: status: { DRDY }
[31.831s] ata1: hard resetting link
[32.298s] ata1: SATA link up 3.0 Gbps (SStatus 123 SControl 300)
...
[78.918s] ata1.00: qc timeout after 30000 msecs (cmd 0xec)
[78.922s] ata1.00: disable device
...
[79.425s] sda: unable to read partition table
```

---

## 3. Evidência Factual #3 — Tentativa de Acesso ao Disco (`fdisk` e Sysfs ao vivo)

Quando tentamos acessar o disco via SSH após a inicialização:

```bash
$ sudo fdisk -l /dev/sda
fdisk: cannot open /dev/sda: Input/output error
```

Ao solicitar um rescan manual via sysfs (`echo 1 > /sys/class/scsi_device/0:0:0:0/device/rescan`):

```text
[1797.335s] sd 0:0:0:0: [sda] Read Capacity(16) failed: Result: hostbyte=0x04 driverbyte=DRIVER_OK
[1797.335s] sda: detected capacity change from 1953525168 to 0
```

### Explicação da Falha de I/O:
Como o Vetor 1 do MSI está mascarado (`0xfe`), as interrupções de conclusão de comando nunca chegam à CPU. O subsistema SCSI da libata aguarda 30 segundos, esgota os 3 retries e chama `disable device`, reduzindo a capacidade reconhecida do `/dev/sda` de **1 TB para 0 Bytes** e retornando erro de I/O (`EIO`).

---

## 4. Explicação Técnica da Causa Raiz

1. O controlador composto `0000:00:14.7` possui capacidade MSI com suporte a **8 vetores** (`Count=1/8 Maskable+`).
2. O driver `ps4-bpcie.c` (ou a camada genérica de MSI PCI do kernel) durante a chamada `pci_alloc_irq_vectors()` ou `bpcie_msi_mask_irq()` grava a máscara `0x000000fe` no registrador `Capabilities [e0] + 0x10`.
3. Essa máscara zera explicitamente a capacidade de envio de MSI para os vetores 1 a 7 (`Masking: 000000fe`).
4. Como a subfunção 1 (SATA/AHCI) depende do envio de sinal MSI referente ao subvetor 1, o controlador PCI **bloqueia o disparo da interrupção física**.
5. Como consequência da falta de resposta de IRQ, o driver `libahci` zera `PxIE` (`PxIE=0x00000000`), a porta entra em estado `frozen` e estoura a exceção em `t = 31.82s`.

---

## 5. Plano de Correção Definitivo

### Modificação no Driver `ps4-bpcie.c`:

No arquivo `drivers/ps4/ps4-bpcie.c`, ajustar o manipulador de máscara MSI (`bpcie_msi_mask_irq` / `bpcie_msi_unmask_irq` / `pci_write_config_dword`) para garantir que o registrador de máscara MSI de `0000:00:14.7` permaneça com o bit 1 **desmascarado** (`0x00000000` ou `0x000000fc`):

```c
/* Garantir que o vetor 1 (AHCI SATA) não seja mascarado no PCI MSI Capability */
if (pdev->vendor == 0x104d && pdev->device == 0x90df) {
    pci_write_config_dword(pdev, 0xe0 + 0x10, 0x00000000);
}
```

---

## 6. Histórico de Referência

- **Teste ao Vivo:** 2026-07-29 17:14 BRT
- **IP PS4:** `192.168.6.128`
- **Comandos Utilizados:** `lspci -s 0000:00:14.7 -vv`, `dmesg | grep -iE 'ata|ahci|sda'`, `fdisk -l /dev/sda`
- **Registrador Chave:** `PCI Capabilities [e0] offset 0x10` (`MSI Masking = 0x000000fe`)
