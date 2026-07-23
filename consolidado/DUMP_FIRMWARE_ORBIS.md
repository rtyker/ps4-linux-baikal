# DUMP FIRMWARE ORBIS (sd8797_uapsta.bin) DO PS4 REAL

---

## ✅ RESOLVIDO — Firmware Orbis custom obtido

| Item | Valor |
|------|-------|
| **Arquivo** | `extra_firmware/mrvl/sd8797_uapsta.bin` |
| **Tamanho** | 443 KB (453.648 bytes) |
| **SHA256** | `c5b84ce8f70072f9f11173f448d574655ff2506595cb8dc113f6d8110272ad66` |
| **Fonte** | [feeRnt/ps4-linux-initramfs](https://github.com/feeRnt/ps4-linux-initramfs/tree/main/lib/firmware/mrvl) |
| **Comparação** | Genérico linux-firmware: 522 KB, SHA256 `8839aa89...` — **DIFERENTE = Orbis custom confirmado** |
| **Status** | ✅ Pronto para build 7.0 |

### Por que não estava no NOR?
O `sd8797_uapsta.bin` é um blob de firmware carregado pelo driver `mwifiex` do kernel Linux.
No Orbis (PS4), ele está embutido no kernel ou em módulos `.sprx`, não como arquivo standalone.
A busca via FTP no PS4 (192.168.6.130:2121) percorreu `/system`, `/preinst`, `/system_ex`,
`/data`, `/mnt` — nenhum arquivo com nome `sd8797`, `uapsta`, `marvell` ou `88w8` encontrado.

### Dump NOR realizado (para referência)
| Item | Valor |
|------|-------|
| **Arquivo** | `boot_referencia/nor_sflash0.bin` |
| **Tamanho** | 32 MB (33.554.432 bytes) |
| **SHA256** | `6f0d32e6e9dd4ffb9935cfcd0be5d0ecaf1d80435e2be2c69935bdbfc327bd42` |
| **Método** | Payload `ps4-sflash0-dumper` via FTP (porta 2121) + binloader (9090) |
| **Partição C0020001** | Extraída: `boot_referencia/C0020001_wifi_calibration.bin` (159 KB, FW 9.50) |
| **Conclusão** | NOR contém calibração WiFi, **NÃO** o firmware mwifiex |

---

## Visão Geral

O PS4 usa firmware **customizado (Orbis)** para o Marvell 88W8797 (Torus 1). O firmware genérico do kernel.org **NÃO funciona**. O firmware foi obtido do repositório do feeRnt (mesmo dev do kernel neocine).

---

## Ferramentas Verificadas e Funcionais

### 1. **Andryshik345/ps4-sflash0-dumper** ⭐⭐⭐ (RECOMENDADO)
- **Tipo**: Payload PS4 (executa via GoldHEN/PSFree)
- **Saída**: Dump NOR direto para USB (não precisa FTP)
- **Release**: `v1.0.0-recompile` (suporta FW até 13.04)
- **Download**: https://github.com/Andryshik345/ps4-sflash0-dumper/releases/download/v1.0.0-recompile/ps4-sflash0-dumper.bin
- **Compilação**: Usa `ps4-payload-sdk` (Scene-Collective)

### 2. **Scene-Collective/ps4-payload-sdk** (Para compilar payloads)
- **Repo**: https://github.com/Scene-Collective/ps4-payload-sdk
- **Necessário para**: Compilar ps4-sflash0-dumper do source

### 3. **Faisal-Alzahrani/PS4-NOR-Validator** (PC - Validação/Reparo)
- **Tipo**: Ferramenta Windows/Linux (C, CMake)
- **Função**: Valida dump NOR, encontra regiões corrompidas, **habilita UART**
- **Release**: https://github.com/Faisal-Alzahrani/PS4-NOR-Validator/releases/tag/ps4 (tag: ps4)
- **⚠️ Sem binários no release** - precisa compilar: `cmake . && make`
- **Uso**: `./ps4nor nor_backup.bin` (Linux) ou `ps4nor.exe nor_backup.bin` (Windows)

### 4. **pearlxcore/PS4-Dump-Checker** (PC - Validação, ARQUIVADO)
- **Tipo**: Windows (.NET/C#)
- **Status**: Archived (Jul 2020), read-only
- **Release**: https://github.com/pearlxcore/PS4-Dump-Checker/releases/tag/v1
- **Download**: PS4.Dump.Checker.exe
- **Nota**: Só valida, não extrai firmware

---

## Método 1: Payload ps4-sflash0-dumper (Mais Fácil - USB)

### Pré-requisitos
- GoldHEN 2.4b18+ ou PSFree rodando no PS4
- USB formatado FAT32/exFAT (mín 50MB livre)

### Passos

```bash
# 1. Baixar payload compilado (PC)
wget https://github.com/Andryshik345/ps4-sflash0-dumper/releases/download/v1.0.0-recompile/ps4-sflash0-dumper.bin

# 2. Enviar para PS4 via GoldHEN Payload Loader
#    - Abrir http://IP_PS4 no navegador
#    - Ir em "Payload Loader"
#    - Selecionar ps4-sflash0-dumper.bin
#    - Executar

# 3. Aguardar LED do USB piscar (dump em progresso)
#    - Cria arquivo: /mnt/usb0/nor_backup.bin (32MB)
#    - Tamanho exato: 33554432 bytes

# 4. Retirar USB, plugar no PC
```

### Verificar Dump
```bash
ls -lh nor_backup.bin
# 32M nor_backup.bin

sha256sum nor_backup.bin
# Guardar hash para referência
```

---

## Método 2: Compilar do Source (Se Precisar Modificar)

```bash
# 1. Setup SDK
git clone https://github.com/Scene-Collective/ps4-payload-sdk
cd ps4-payload-sdk
make install  # Seguir instruções do repo

# 2. Compilar dumper
git clone https://github.com/Andryshik345/ps4-sflash0-dumper
cd ps4-sflash0-dumper
make clean && make
# Gera: ps4-sflash0-dumper.bin
```

---

## Método 3: ps4-nor-dumper (Linux no PS4 - Alternativo)

**Nota**: O repo original `ps4dev/ps4-nor-dumper` não existe mais no GitHub público.
Use o **Método 1** (payload USB) que é mais confiável.

---

## Extrair Dados WiFi/BT do Dump NOR (PC)

### O que ESTÁ no NOR: Partição C0020001 (Calibração WiFi)
O NOR contém **dados de calibração** do módulo WiFi/BT (MAC, configuração de antena, calibração de RF),
**NÃO** o firmware `sd8797_uapsta.bin`. A calibração extraída foi salva como referência.

```bash
# Extrair partição C0020001 (WiFi calibration) do NOR Baikal FW 12.52
dd if=nor_sflash0.bin of=C0020001_wifi_calibration.bin bs=1 skip=$((0x144200)) count=$((0x27B6E))
# SHA256: a calcular
```

### Opção A: PS4-NOR-Validator (Faisal-Alzahrani) - Windows/Linux
```bash
# ⚠️ Ferramenta INTERATIVA (bugada no Linux - usa pause/system())
# Compilar:
git clone https://github.com/Faisal-Alzahrani/PS4-NOR-Validator
cd PS4-NOR-Validator
cmake . && make

# Uso: copiar .bin para o diretório e executar
cp nor_sflash0.bin .
./ps4nor
# Menu: selecionar arquivo → Validate → opções de reparo/UART
```

### Opção B: Binwalk (Genérico)
```bash
# Instalar
apt install binwalk

# Escanear formatos no NOR
binwalk nor_sflash0.bin
# Nota: dados são criptografados/assinados, binwalk pode não detectar
```

### Opção C: Extração Direta via dd (Offsets Conhecidos do Parser)
```bash
# Partições identificadas no dump Baikal FW 12.52:
# SLB2:          0x4000
# WiFi C0020001: 0x144200 (159 KB, FW 9.50)
```

---

## Sobre o sd8797_uapsta.bin (Firmware Marvell 88W8797)

### ⚠️ NÃO ESTÁ NO NOR

O `sd8797_uapsta.bin` é o firmware do chip **Marvell 88W8797**, carregado pelo driver `mwifiex`
do kernel Linux. Este arquivo:
- Está armazenado no **sistema de arquivos Orbis** (HDD interno), não na NOR
- É um binário de ~500-600 KB com o formato padrão de firmware Marvell
- O PS4 usa uma versão **customizada (Orbis)** que difere da upstream

### Como obter o sd8797_uapsta.bin

| Método | Descrição | Status |
|--------|-----------|--------|
| **Do NOR dump** | ❌ Impossível - firmware não está na NOR | ❌ |
| **linux-firmware (genérico)** | `wget https://git.kernel.org/.../mrvl/sd8797_uapsta.bin` | ⚠️ Versão genérica, pode funcionar |
| **PS4 Linux Discord** | Comunidade compartilha o Orbis custom | 🔄 Pendente |
| **Desabilitar MWIFIEX_SDIO** | Remove suporte a Marvell (ok para Baikal-only) | ✅ **Recomendado** |
| **Extrair do Orbis (HDD)** | Acessar partição Orbis e copiar o firmware | 🔧 Complexo |

### Conclusão: Baikal não precisa de sd8797_uapsta.bin

Para builds **Baikal-only** (MT7668 WiFi):
- `CONFIG_MWIFIEX_SDIO` pode ser desabilitado com segurança
- O script `00-build-kernel-7.0.sh` já oferece essa opção automaticamente

---

## Verificação do Firmware Extraído

```bash
# Verificar se é binário válido
file sd8797_uapsta.bin
# Saída: "data"

# Tamanho típico
ls -lh sd8797_uapsta.bin
# ~500-600 KB (533976 bytes no genérico)

# Hash para comparação
sha256sum sd8797_uapsta.bin

# COMPARAÇÃO CRÍTICA: Deve DIFERIR do genérico
wget -q https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mrvl/sd8797_uapsta.bin -O sd8797_generic.bin
sha256sum sd8797_uapsta.bin sd8797_generic.bin
# HASHES DIFERENTES = Firmware Orbis customizado ✓
```

---

## Uso no Build 7.0

### Se tiver o sd8797_uapsta.bin (Orbis ou genérico)
```bash
# Colocar no kernel source tree
mkdir -p extra_firmware/mrvl
cp sd8797_uapsta.bin extra_firmware/mrvl/
```

### Se NÃO tiver (Baikal-only - recomendado)
```bash
# O script 00-build-kernel-7.0.sh pergunta automaticamente:
# "Deseja continuar e desabilitar MWIFIEX_SDIO? (y/N):"
# Responda 'y' para Baikal (usa MT7668, não Marvell)
```

### Status Atual da Extração
- [x] NOR dump obtido (`nor_sflash0.bin` de 32MB do PS4 real)
- [x] SHA256: `6f0d32e6e9dd4ffb9935cfcd0be5d0ecaf1d80435e2be2c69935bdbfc327bd42`
- [x] Partição `C0020001` (WiFi calibration) extraída para `boot_referencia/C0020001_wifi_calibration.bin`
- [ ] ~~`sd8797_uapsta.bin` extraído~~ ❌ Não está no NOR
- [ ] Build 7.0: desabilitar `CONFIG_MWIFIEX_SDIO` e compilar

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Payload não carrega | GoldHEN versão antiga? Atualizar para 2.4b18.9+ |
| USB não monta | Formatar FAT32, tentar outra porta USB |
| Dump < 32MB | Dump incompleto, repetir |
| Firmware não encontrado no dump | Usar PS4-NOR-Validator para achar offset |
| Hash igual ao genérico | Pegou firmware errado, buscar em outra partição |
| "ps4dev/ps4-nor-dumper" 404 | Repo movido/removido, use Andryshik345 |

---

## Links Diretos Resumo

| Ferramenta | Link Direto |
|------------|-------------|
| **ps4-sflash0-dumper.bin (v1.0.0-recompile)** | https://github.com/Andryshik345/ps4-sflash0-dumper/releases/download/v1.0.0-recompile/ps4-sflash0-dumper.bin |
| **ps4-payload-sdk** | https://github.com/Scene-Collective/ps4-payload-sdk |
| **PS4-NOR-Validator (source)** | https://github.com/Faisal-Alzahrani/PS4-NOR-Validator (compilar: `cmake . && make`) |
| **PS4-Dump-Checker.exe (v1, archivado)** | https://github.com/pearlxcore/PS4-Dump-Checker/releases/download/v1/PS4.Dump.Checker.exe |

---

## Checklist Rápido

### ✅ JÁ CONCLUÍDO (dump real do PS4 Baikal)
- [x] Payload `ps4-sflash0-dumper.bin` baixado ([release v1.0.0-recompile](https://github.com/Andryshik345/ps4-sflash0-dumper/releases/download/v1.0.0-recompile/ps4-sflash0-dumper.bin))
- [x] Payload enviado ao PS4 via binloader (`nc -w 3 192.168.6.130 9090 < payload.bin`)
- [x] `nor_sflash0.bin` (32MB) copiado para PC via FTP (porta 2121)
- [x] Dump salvo em `boot_referencia/nor_sflash0.bin`

### ❓ PENDENTE / ESCLARECIMENTOS
- [x] Partição `C0020001` (WiFi calibration) extraída: `boot_referencia/C0020001_wifi_calibration.bin` (159 KB)
- [ ] ~~`sd8797_uapsta.bin` extraído do NOR~~ ❌ **Impossível** - firmware não está na NOR
- [ ] Obter `sd8797_uapsta.bin` por outro método OU desabilitar `CONFIG_MWIFIEX_SDIO`
- [ ] Hash SHA256 do `sd8797_uapsta.bin` (quando obtido) **DIFERE** do genérico upstream
- [ ] Copiado para `extra_firmware/mrvl/` (se obtido)
- [ ] Build 7.0 compila sem erro (com ou sem MWIFIEX_SDIO)

---

## Notas Finais

1. **Faça backup da NOR** antes de qualquer modificação
2. **Não atualize FW do PS4** após dumpear (firmware pode mudar)
3. **Cada modelo PS4** pode ter firmware ligeiramente diferente
4. **Baikal (CUH-2216/7216)** usa MT7668 WiFi, mas o build.sh **exige** `sd8797_uapsta.bin` mesmo assim
5. Se não conseguir extrair: desabilite `CONFIG_MWIFIEX_SDIO` no script (perde WiFi Aeolia/Belize, ok para Baikal-only)