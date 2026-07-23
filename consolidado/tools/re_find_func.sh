#!/usr/bin/env bash
# re_find_func.sh — localiza o INÍCIO REAL da função que contém um endereço, e opcionalmente decompila.
#
# Motivação: em 2026-07-21 uma análise inteira foi invalidada porque o endereço
# "0xffffffffdc5a0c80" foi tratado como início de função quando na verdade caía no MEIO
# de uma instrução. O r2ghidra decompila QUALQUER endereço sem reclamar, produzindo
# pseudo-código plausível porém falso (sinais: variáveis "unaff_XXX"/"in_XXX" no corpo,
# ausência de prólogo, lixo tipo "*in_RAX = *in_RAX + in_RAX;" na primeira linha).
#
# SEMPRE rodar este script antes de decompilar um endereço novo.
#
# HISTÓRICO DE BUGS DESTA FERRAMENTA (todos encontrados validando achados reais,
# nenhum hipotético — ver consolidado/RE_IF_MSK.md e RE_KERNEL_GBE_ATTACH.md):
#   #1 (2026-07-21): usava "pd N" (N INSTRUÇÕES) em vez de "pD N" (N BYTES) —
#       a janela ultrapassava o alvo e "tail -1" pegava o prólogo da função
#       SEGUINTE.
#   #2 (2026-07-21): "pD 0x1200 @ (ADDR-0x1200)" desmontava um window de BYTES
#       a partir de um offset ARBITRÁRIO, não alinhado a início de instrução
#       (x86 é de tamanho variável) — produzia lixo por um trecho e podia
#       pular por cima do prólogo real. Trocado por "pd -N @ ADDR" (desmontagem
#       para trás relativa ao próprio endereço, que o r2 alinha sozinho).
#   #3 (2026-07-21): "pd -N @ ADDR" não inclui a instrução NO PRÓPRIO ADDR —
#       um endereço que É o prólogo (como 0xdc4c4ff0, confirmado por RE real)
#       não batia na busca. Corrigido concatenando "pd 1 @ ADDR".
#
# Uso:
#   ./re_find_func.sh <dump.bin> <0xVADDR>            # só localiza o prólogo
#   ./re_find_func.sh <dump.bin> <0xVADDR> <saida.txt> # localiza e decompila
set -euo pipefail

BIN="${1:?uso: $0 <dump.bin> <0xVADDR> [saida.txt]}"
ADDR="${2:?uso: $0 <dump.bin> <0xVADDR> [saida.txt]}"
OUT="${3:-}"

R2="r2 -q -e bin.relocs.apply=true -e scr.color=0"

# Varre para trás procurando "push rbp; mov rbp,rsp" (prólogo padrão do FreeBSD/amd64).
# 0x1200 bytes cobre folgadamente as funções grandes vistas neste kernel (a maior
# analisada até agora, fcn.ffffffffdc5a0ba0, tem 4493 bytes — ajuste se precisar).
# A aritmética vai em python: endereços de kernel (0xffffffff...) estouram o int
# de 64 bits COM SINAL do bash e viram negativo.
START=$(python3 -c "print(hex($ADDR - 0x1200))")

# Passo 1: se o próprio endereço é alvo de um CALL, ele JÁ é início de função.
# Necessário porque nem toda função usa frame pointer — 0xdc7c8a70, por exemplo, é
# chamada por `call` mas não começa com "push rbp", e o scan de prólogo do passo 2
# acabaria devolvendo a função anterior.
if $R2 -c "/r $ADDR" "$BIN" 2>/dev/null | grep -q 'CALL'; then
  echo "endereço consultado : $ADDR"
  echo "início real da func : $ADDR  (confirmado: é alvo de CALL)"
  $R2 -c "af @ $ADDR; afi @ $ADDR" "$BIN" 2>/dev/null | grep -E '^(addr|size|realsz|num-bbs|num-instrs|args):' || true
  if [ -n "$OUT" ]; then
    $R2 -c "af @ $ADDR; pdg @ $ADDR" "$BIN" > "$OUT" 2>&1
    echo "decompilado salvo em: $OUT ($(wc -l < "$OUT") linhas)"
    grep -qE 'unaff_R|in_RAX|in_stack_' "$OUT" && echo "AVISO: contém unaff_/in_ — limites podem estar errados." >&2
  fi
  exit 0
fi

# Passo 2: varrer para trás atrás do prólogo.
#
# ATENÇÃO (bug #1, 2026-07-21): usar pD (N BYTES) e não pd (N INSTRUÇÕES). Com
# "pd 1200" a desmontagem passa longe do endereço alvo e o "tail -1" acaba
# pegando o prólogo da função SEGUINTE (consulta a 0xdc7c8a70 retornava
# 0xdc7c8b80).
#
# ATENÇÃO (bug #2, 2026-07-21, mais grave): "pD 0x1200 @ START" desmonta um
# WINDOW DE BYTES FIXO a partir de START = ADDR-0x1200 — um offset ARBITRÁRIO,
# não necessariamente alinhado a um início de instrução (x86 é de tamanho
# variável). Desmontar a partir de um byte que não é fronteira de instrução
# produz LIXO por um trecho até o decoder "ressincronizar" em outro ponto
# qualquer — e esse lixo pode conter um "push rbp" espúrio, OU pode fazer o
# decoder pular por cima do prólogo real (caso confirmado: consulta a
# 0xdc4c4ff0, que começa de verdade com "push rbp" — visível ao desmontar a
# partir de um ponto correto — resolvia erradamente para 0xdc4c4e90 porque a
# janela fixa começava desalinhada).
#
# Correção: usar "pd -N @ ADDR" (desmontagem PARA TRÁS relativa ao próprio
# ADDR). O motor de análise do r2 resolve o alinhamento sozinho nesse modo
# (tenta candidatos e escolhe o mais consistente), em vez de um recorte cru de
# bytes a partir de uma conta aritmética nossa.
# "pd -N @ ADDR" mostra as N instruções ANTES de ADDR, sem incluir a instrução
# no próprio ADDR — bug #3, pego ao validar o achado do usuário: ADDR podia
# SER o prólogo (caso de 0xdc4c4ff0) e a busca não olhava para ele mesmo.
# "pd 1 @ ADDR" cobre esse ponto cego.
FOUND=$( { $R2 -c "pd -80 @ $ADDR" "$BIN" 2>/dev/null; $R2 -c "pd 1 @ $ADDR" "$BIN" 2>/dev/null; } \
  | grep -E '^\s+0x[0-9a-f]+\s+55\s+push rbp' \
  | tail -1 | grep -oE '0x[0-9a-f]+' | head -1 || true)

if [ -z "$FOUND" ]; then
  echo "ERRO: nenhum prólogo encontrado em [$START, $ADDR]. Aumente a janela ou confira o endereço." >&2
  exit 1
fi

echo "endereço consultado : $ADDR"
echo "início real da func : $FOUND"
$R2 -c "af @ $FOUND; afi @ $FOUND" "$BIN" 2>/dev/null | grep -E '^(addr|size|realsz|num-bbs|num-instrs|args):' || true

if [ -n "$OUT" ]; then
  $R2 -c "af @ $FOUND; pdg @ $FOUND" "$BIN" > "$OUT" 2>&1
  echo "decompilado salvo em: $OUT ($(wc -l < "$OUT") linhas)"
  # Sanidade: acusa os marcadores típicos de decompilação inválida.
  if grep -qE 'unaff_R|in_RAX|in_stack_' "$OUT"; then
    echo "AVISO: saída contém variáveis unaff_/in_ — pode indicar limites de função errados." >&2
  fi
fi
