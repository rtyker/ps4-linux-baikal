# Comunicação com o PS4 — Referência Rápida

**Data**: 2026-07-12
**Última verificação**: FTP funcional, 3 arquivos enviados com sucesso

---

## Dados da Rede

| Item | Valor |
|------|-------|
| PS4 IP | 192.168.6.130 |
| Máscara | 255.255.255.0 |
| Gateway | 192.168.6.1 |
| DNS | 62.210.38.117 |
| PC (WiFi) | 192.168.6.100 (wlp0s20f3) — **ATIVO** |
| PC (br0) | 192.168.6.101 — **DOWN** (não usar) |

---

## FTP (GoldHEN v2.2)

**IMPORTANTE**: Usar sempre `--interface wlp0s20f3` para forçar saída pela WiFi. Sem isso, curl usa br0 (192.168.6.101) que está DOWN e falha com "Não há rota para o host".

### Listar arquivos
```bash
curl --interface wlp0s20f3 --list-only ftp://192.168.6.130:2121/
```

### Upload de arquivo
```bash
curl --interface wlp0s20f3 -T /caminho/local/arquivo ftp://192.168.6.130:2121/caminho/ps4/arquivo
```

### Exemplo: enviar boot files
```bash
curl --interface wlp0s20f3 -T bzImage ftp://192.168.6.130:2121/data/linux/boot/bzImage
curl --interface wlp0s20f3 -T initramfs.cpio.gz ftp://192.168.6.130:2121/data/linux/boot/initramfs.cpio.gz
curl --interface wlp0s20f3 -T bootargs.txt ftp://192.168.6.130:2121/data/linux/boot/bootargs.txt
```

### Criar diretório
```bash
curl --interface wlp0s20f3 --ftp-create-dirs -T /dev/null ftp://192.168.6.130:2121/novo/diretorio/
```

---

## Payload (netcat)

```bash
nc -w 3 192.168.6.130 9090 < linux-3072mb.bin
```

---

## Caminhos de Boot no PS4 (payload lê nesta ordem)

1. `/mnt/usb0/` — USB drive (prioridade máxima)
2. `/mnt/usb1/` — segundo USB
3. `/data/linux/boot/` — HDD interno
4. `/user/system/boot/` — HDD interno (fallback)

**Arquivos necessários**: `bzImage`, `initramfs.cpio.gz`, `bootargs.txt` (opcional: `vram.txt`)

---

## Notas

- GoldHEN FTP só roda quando PS4 está no modo GoldHEN (não booted Linux)
- Para acessar FTP, PS4 precisa estar ligado e GoldHEN ativo
- Se ping falhar de primeiro tentar, sempre forçar `--interface wlp0s20f3`
