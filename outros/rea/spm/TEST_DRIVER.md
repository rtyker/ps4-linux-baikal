# Teste do Driver Baikal Memory (00:14.6)

**Dispositivo:** Sony Baikal Memory (SPM/DDR3), PCI 00:14.6  
**Módulo:** baikal-memory.ko  
**Data:** 2026-11-12  
**Status:** Fase 2 validada ao vivo em 2026-11-12 — leitura via driver retorna o MAC real (BAR5+0x2f000) e a região `spm.icc`, estáveis

---

## 1. Arquivos

| Arquivo | Local | Descrição |
|---------|-------|-----------|
| `baikal-memory.ko` | `outros/rea/spm/dumps/` | Módulo do kernel compilado |
| `baikal-memory-fase2.ko` | `outros/rea/spm/dumps/` | Módulo testado ao vivo (Fase 2, 303.752 bytes) |
| `baikal-memory-fase2.patch` | `kernel/patches/` | Patch do driver (aplicado pelo `00-build-kernel-7.0.sh`) |
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

### Layout de `/dev/baikal-memory` (Fase 2)

| Faixa | Origem |
|-------|--------|
| `0x000000–0x000fff` | BAR0 (4 KiB) |
| `0x001000–0x003fff` | BAR2 (primeiros 4 MiB da SPM DDR3) |
| `0x500000–0x53ffff` | BAR5 (256 KiB) |

### Teste 1: Leitura via dispositivo de caractere

```bash
# MAC real da SPM (BAR5+0x2f000 -> offset 0x52f000 no device)
dd if=/dev/baikal-memory bs=1 skip=$((0x52f000)) count=6 | od -An -tx1
# => 2c cc 44 3f 69 5f

# Região spm.icc (BAR5+0x2c000)
dd if=/dev/baikal-memory bs=1 skip=$((0x52c000)) count=16 | od -An -tx1
# => 42 04 38 00 00 00 0c 00 20 00 ab 00 01 00 00 00

# BAR0 (zerado neste boot) e janela BAR2
dd if=/dev/baikal-memory bs=16 count=1 2>/dev/null | od -An -tx1
dd if=/dev/baikal-memory bs=1 skip=$((0x1000)) count=16 2>/dev/null | od -An -tx1

# EOF correto além de 0x540000
dd if=/dev/baikal-memory bs=1 skip=$((0x540000)) count=4
# => 0 bytes copied
```

**Resultado obtido (2026-11-12):** MAC estável em 3 leituras consecutivas; ICC com dados; BAR0/BAR2 zerados (estado do hardware, não do driver).

### Teste 2: Leitura via sysfs

Os atributos ficam no `kobj` do device PCI (não em `/sys/class/baikal-memory/`):

```bash
D=/sys/devices/pci0000:00/0000:00:14.6

# MAC real da SPM (formatado)
cat $D/bar5_0x2f000          # => 2c:cc:44:3f:69:5f

# Região spm.icc (dump de 16 bytes)
cat $D/bar5_0x2c000          # => 42 04 38 00 00 00 0c 00 20 00 ab 00 01 00 00 00

# Registradores baixos (u32; zerados neste boot)
for a in 0x00 0x04 0x08 0x0c 0x10 0x14 0x18 0x1c; do printf '%s=' $a; cat $D/bar5_$a; done
```

**Resultado obtido (2026-11-12):** MAC correto e ICC com dados; baixos em `0x00000000` (estado do hardware). Todos os atributos são `0444`.

> Validado que o `/dev/baikal-memory` continua lendo o mesmo MAC após a mudança de sysfs.

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
| Leitura retorna zeros no offset 0 | Esperado neste console (BAR0/BAR2 zerados); testar `skip=$((0x52f000))` para ler o MAC |
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
| `Kconfig` | Opção de compilação CONFIG_BAIKAL_MEMORY |
| `Makefile` | Regra de compilação |
| `baikal-memory.ko` | Módulo compilado |
| `HANDOFF.md` | Este documento |
