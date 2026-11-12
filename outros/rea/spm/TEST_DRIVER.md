# Teste do Driver Baikal Memory (00:14.6)

**Dispositivo:** Sony Baikal Memory (SPM/DDR3), PCI 00:14.6  
**Módulo:** baikal-memory.ko  
**Data:** 2026-11-12  
**Status:** Compilado e pronto para teste

---

## 1. Arquivos

| Arquivo | Local | Descrição |
|---------|-------|-----------|
| `baikal-memory.ko` | `outros/rea/spm/dumps/` | Módulo do kernel compilado |
| `baikal-memory.c` | `kernel/kernel_build_7.0/drivers/misc/` | Fonte do driver |
| `HANDOFF.md` | `outros/rea/spm/` | Documentação de handoff |

---

## 2. Como Carregar o Módulo no PS4

```bash
# Carregar o módulo
sudo insmod /mnt/hdauxiliar/ps4-linux-baikal/outros/rea/spm/dumps/baikal-memory.ko

# Verificar se carregou
dmesg | tail -20
lsmod | grep baikal

# Verificar dispositivo de caractere
ls -l /dev/baikal-memory
```

**Saída esperada no dmesg:**
```
baikal-memory: Baikal Memory (SPM/DDR3, 00:14.6) driver
baikal-memory 0000:00:14.6: BAR0: ... (4 KiB), BAR2: ... (1 GiB), BAR4: ... (1 MiB), BAR5: ... (256 KiB)
baikal-memory 0000:00:14.6: BAR5 mapeado em ...
Driver Baikal Memory carregado. Dispositivo /dev/baikal-memory disponível.
```

---

## 3. Como Testar Leitura da SPM

### Teste 1: Leitura via dispositivo de caractere

```bash
# Ler primeiros 256 bytes do BAR5
sudo dd if=/dev/baikal-memory bs=1 count=256 | xxd

# Ler primeiros 4 KiB do BAR0
sudo dd if=/dev/baikal-memory bs=4096 count=1 skip=0 | xxd
```

**Resultado esperado:** Dados não-zero no BAR5 (tabela estruturada), 0xFF no BAR0.

### Teste 2: Leitura via sysfs

```bash
# Ler registradores conhecidos do BAR5
cat /sys/class/baikal-memory/bar5_0x00
cat /sys/class/baikal-memory/bar5_0x04
cat /sys/class/baikal-memory/bar5_0x08
cat /sys/class/baikal-memory/bar5_0x0c
cat /sys/class/baikal-memory/bar5_0x10
cat /sys/class/baikal-memory/bar5_0x14
cat /sys/class/baikal-memory/bar5_0x18
cat /sys/class/baikal-memory/bar5_0x1c
```

**Resultado esperado:** Valores hexadecimais (ex: 0x21090002, 0x88050108, etc.)

---

## 4. Como Descarregar o Módulo

```bash
sudo rmmod baikal-memory
```

---

## 5. Problemas Conhecidos

| Problema | Solução |
|----------|---------|
| `insmod: ERROR: could not insert module` | Verificar se o kernel versão corresponde (7.0.8-Strawberry-ThinLTO-Baikal-+) |
| `/dev/baikal-memory` não aparece | Verificar dmesg para erros de probe PCI |
| Leitura retorna zeros | Verificar se BAR5 foi mapeado corretamente (verificar dmesg) |
| SSH não conecta | Verificar se o serviço SSH está rodando no PS4 |

---

## 6. Comandos de Diagnóstico

```bash
# Verificar se o dispositivo PCI está presente
lspci -s 00:14.6 -vv

# Verificar logs do kernel
dmesg | grep -i baikal

# Verificar módulo carregado
lsmod | grep baikal

# Verificar dispositivo de caractere
ls -l /dev/baikal-memory

# Verificar sysfs
ls -l /sys/class/baikal-memory/
```

---

## 7. Arquivos Relacionados

| Arquivo | Descrição |
|---------|-----------|
| `baikal-memory.c` | Fonte do driver |
| `Kconfig` | Opção de compilação CONFIG_BAALAK_MEMORY |
| `Makefile` | Regra de compilação |
| `baikal-memory.ko` | Módulo compilado |
| `HANDOFF.md` | Este documento |
