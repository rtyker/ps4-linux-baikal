# 📊 Teste #5 — Resultado da Tabela de Calibração Indexada (0x1bc-0x1d4)

**Data:** 2026-07-23  
**Status:** 🎉 **SUCESSO COMPLETO**

---

## 1. O que foi Implementado

1. **Correção de Limites de Array (Safe Sizing):**
   * Expandimos os arrays locais `calib_tbl` e `calib_msk` em `mts_phy_calibration()` de 32 para **128 elementos `u32`**.
   * Isso permitiu ao código acessar com total segurança os índices até `66` derivados da função decompilada da Sony sem estourar o limite de pilha nem gerar Kernel Panic.

2. **Ativação por Padrão:**
   * Alteramos a opção `enable_phy_calib_table` para `true` por padrão.

---

## 2. Execução ao Vivo no PS4

```text
[ 3986.653609] mts 0000:00:14.1: PHY calibration table: executando loop indexado 0x1bc-0x1d4...
[ 3986.721436] mts 0000:00:14.1: PHY calibration: loop 66 iteracoes concluido
[ 3986.721445] mts 0000:00:14.1: PHY calibration: concluída
[ 3986.721453] mts 0000:00:14.1: IMR (0x54) = 0x00000000
[ 3986.721634] mts 0000:00:14.1: MAC lido da SPM: 2c:cc:44:3f:69:5f
[ 3986.722104] mts 0000:00:14.1: mts registrado como eth0, MAC 2c:cc:44:3f:69:5f
[ 3986.726258] mts 0000:00:14.1: open (stage=4) carrier=1 rx=1 tx=1
[ 3986.726268] mts 0000:00:14.1: timer de polling iniciado (intervalo 10ms)
[ 3986.726272] mts 0000:00:14.1: NAPI habilitado
[ 3986.726276] mts 0000:00:14.1: interrupt habilitada, IMR=0x0000007d
[ 3986.726280] mts 0000:00:14.1: open concluido
[ 3986.736269] mts 0000:00:14.1: Link UP: 1000 Mbps Full duplex
```

---

## 3. Conclusão

* As 66 iterações de escrita da tabela indexada nos registradores `0x1bc-0x1d4` executaram sem travar o kernel.
* O driver completou a calibração com sucesso e registrou **`Link UP: 1000 Mbps Full duplex`**!
