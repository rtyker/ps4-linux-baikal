# 🏆 Chave EAP do HD obtida ao vivo via EAPDumper + análise do IV (2026-07-31)

## Resumo

A chave EAP real do HD interno foi obtida com sucesso ao vivo (payload GoldHEN), resolvendo
a Seção 21.3 do plano (chave zerada no dump). Porém, o **tweak/IV** da cifra XTS continua
em aberto — a decriptação de `sda27`/`sda13` ainda não funciona localmente.

## A chave (CANÔNICA, estável)

```
edf3f4d33b16a17bf4ea92070fe8af6b 08c23c91f98006ae5b4f7d363c2bf0a3
```
- Fonte: EAPDumper v0.2.0 (`ps4-linux-payloads/EAPDumper.bin`), injetado via porta 9090
  (GoldHEN BinLoader) no FW 12.52 (raw `0x12520001`).
- Scanner cego encontrou a chave em offset `0x026C4CF0` = `kern_off_eap_hdd_key` do magic.h
  (= VA `0xffffffffdea14cf0` com base `0xffffffffdc350000` — validação cruzada com RE).
- Gravada em `/data/hddeap/eap_hdd_key.{bin,hex,txt}` + `eap_offset_scan.txt`, baixados
  via FTP 2121 do GoldHEN. Cópia canônica em `keys/eap/eap_hdd_key.bin`.
- Estatística: entropia 4.875 bits/byte, 30/32 únicos — aparência de chave aleatória de
  eFuse/Southbridge (não derivada de ERK/PROD).

## Estabilidade (5 dumps, 3 boots)

- Chave estática entre boots (entropia 4.88 constante no offset real `0x026C4CF0`).
- **Scanner do EAPDumper sofre de falso-positivo:** grava sempre `top[0]` (`main.c:914`).
  Em 4/5 dumps um candidato espúrio `0x0283A8C0` (determinístico dentro do boot, mas que
  muda entre boots) teve score maior. Só o dump 1 (boot 1) gravou a chave correta.
- KASLR muda a base do kernel por boot (`0xFFFFFFFF8AD4C000`/`D028C000`/`854E4000`).
- **Recomendação:** para dumps futuros, usar variante do EAPDumper com offset fixo
  `0x026C4CF0`.

## Tweak/IV ainda em aberto (bloqueador atual)

O `g_crypt_create_provider` decompilado revela a fórmula do IV:
```
puVar6[2] = size >> 9;              // setores 512
uVar7 = arg1[0x18] >> 9;            // offset do provider (setores)
puVar6[8] = uVar7 + iVar2[0x20];    // IVOFFSET = LBA_absoluto + campo_extra
```
→ tweak do setor N = `LBA_absoluto_particao + N + iVar2[0x20]`. O `iVar2[0x20]` é um campo
extra de outra estrutura (g_geom/g_provider) ainda não identificado — provavelmente é o
`ivoffset` que falta nas nossas varreduras.

O EAP branch NÃO seta o bit `0x40000` (que as chaves ID 0x30/0x31/0x32/0x35 setam) — a EAP
usa a chave direta de 32 bytes. Confirmado: `edf3f4d3...` é usada diretamente.

Varreduras XTS negativas com a chave real:
- `sda27_8MB.bin`: 504 combos × 128 setores (tweaks {0, absLBA 57147392, (dev_no-1)<<32 p/
  dev_no 0..30 em 512/4096, +absLBA}, chave as-is/rev16 × halves as-is/swap).
- `sda13_4MB.bin`: 380 combos × 4096 setores (mesmos tweaks com absLBA 19398656).
- ZERO hits de magic PFS `0x1332A0B` / UFS2 `0x19540119`.

## Próximos passos (em ordem de valor)

1. **RE do `iVar2[0x20]`** (campo ivoffset extra) — identificar de qual estrutura vem e
   como é calculado. Fontes: estrutura `g_geom`/`g_provider` do FreeBSD, `g_part_gpt`
   (`dc8dabae`, mas confirmado ausente do dump — pode ser `g_part` de outra classe), ou
   `g_crypt_classfunc` (`dc9a20e0`, 812 linhas, ainda não analisado para ivoffset).
2. **Payloader:** variante do EAPDumper com offset fixo `0x026C4CF0` para dumps garantidos.
3. **Teste direto no Linux do PS4** (kernel 7.0): `cryptsetup open -c aes-xts-plain64
   --skip <LBA>` com a chave real, tentar montar UFS2/PFS. Ainda precisa do tweak certo.

## Regra operacional (dumper)

- Payload server (9090) e FTP (2121) do GoldHEN aceitam **1 conexão por vez**; é preciso
  desativar/reativar cada um a cada tentativa. Ver `keys/TESTES_EAPDUMPER_2026-07-31.md`.

## Arquivos

- `keys/INDEX.md` — índice versionado das chaves (EAP canônica, ERK candidata, PROD descartada).
- `keys/TESTES_EAPDUMPER_2026-07-31.md` — log dos 5 dumps + varreduras XTS + regra operacional.
- `keys/eap/eap_hdd_key.bin` (md5 `29dbc12f...`), `keys/erk/`, `keys/prod/`.
- `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md` Seção 22 (resultados completos).
- `consolidado/decompiled/geom_crypt/decompiled_dc9a40d0_g_crypt_create.c` (fórmula do IV).
