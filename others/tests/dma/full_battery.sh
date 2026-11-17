#!/bin/bash
# Full DMA validation battery on the live PS4 with the fixed module loaded from /tmp.
# Usage: full_battery.sh <path to the module .ko on the PS4>
# Every check prints PASS or FAIL. Writes only inside the validated window (SPM 0x200000, 64 KiB) and the
# last 2 KiB of the BAR2 window; both are saved first and restored at the end. dmesg is read by line count.
KO="$1"
P=/sys/module/baikal_memory/parameters
S=/sys/bus/pci/devices/0000:00:14.6/dma
DEV=/dev/baikal-memory
KVER=7.0.8-Strawberry-ThinLTO-Baikal-+
KO_HD=/lib/modules/$KVER/kernel/drivers/misc/baikal-memory.ko
DMAC=/lib/modules/$KVER/kernel/drivers/dma/baikal-dmac.ko
OFF=$((0x201000)); OFFEND=$((0x400800)); OFF0=$((0x1000))
W=/tmp/fb; rm -rf $W; mkdir -p $W
PASS=0; FAIL=0

ok(){ if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS  $2"; else FAIL=$((FAIL+1)); echo "  FAIL  $2"; fi; }
st(){ echo "estado=$(cat $S/dma_state) err=$(cat $S/dma_errors) cpu_r=$(cat $S/cpu_bytes_read) dma_r=$(cat $S/dma_bytes_read) cpu_w=$(cat $S/cpu_bytes_written) dma_w=$(cat $S/dma_bytes_written)"; }
rdf(){ dd if=$DEV of=$1 bs=64k iflag=skip_bytes,count_bytes skip=$2 count=$3 2>/dev/null; }
nz(){ tr -d '\000' < "$1" | wc -c; }
mark(){ N0=$(dmesg | wc -l); }
newlog(){ dmesg | tail -n +$((N0+1)) | grep -iE "baikal|dmac" | cut -c1-150; }
load(){ rmmod baikal_memory 2>/dev/null; lsmod | grep -q '^baikal_dmac' || insmod $DMAC; insmod "$KO" "$@" || { echo "FALHA ao carregar $KO"; exit 1; }; }
wr(){ dd if=$1 of=$DEV bs=64k oflag=seek_bytes seek=$2 conv=notrunc 2>&1; }

cleanup(){
  echo; echo "== LIMPEZA"
  if [ "$(cat $P/allow_write 2>/dev/null)" = Y ]; then
    echo 0 > $P/use_dma
    [ -f $W/orig_win.bin ] && wr $W/orig_win.bin $OFF >/dev/null
    [ -f $W/orig_end.bin ] && wr $W/orig_end.bin $OFFEND >/dev/null
    rdf $W/fin_win.bin $OFF 65536; rdf $W/fin_end.bin $OFFEND 2048
    cmp -s $W/fin_win.bin $W/orig_win.bin; a=$?; cmp -s $W/fin_end.bin $W/orig_end.bin; b=$?
    ok $a "janela de 64 KiB restaurada == original"; ok $b "fim da janela (2 KiB) restaurado == original"
  fi
  rmmod baikal_memory 2>/dev/null; lsmod | grep -q '^baikal_dmac' || insmod $DMAC; insmod $KO_HD
  echo "modulo do HD de volta: $(st) use_dma=$(cat $P/use_dma) allow_write=$(cat $P/allow_write)"
  echo; echo "================ TOTAL: $PASS PASS, $FAIL FAIL ================"
  rm -rf $W
}
trap cleanup EXIT

echo "################ PREPARO"
load use_dma=0
rdf $W/orig_win.bin $OFF 65536; rdf $W/orig_end.bin $OFFEND 2048; rdf $W/o0.bin $OFF0 4096
echo "originais nao-zero: janela=$(nz $W/orig_win.bin) fim=$(nz $W/orig_end.bin) spm0=$(nz $W/o0.bin)"
[ "$(nz $W/orig_win.bin)" = 0 ] && [ "$(nz $W/orig_end.bin)" = 0 ] && [ "$(nz $W/o0.bin)" = 0 ] || { echo "ABORTADO: regioes nao estao zeradas"; exit 1; }
head -c 65536 /dev/urandom > $W/pat.bin; head -c 4096 /dev/urandom > $W/pat2.bin; head -c 4097 /dev/urandom > $W/pat3.bin; head -c 65536 /dev/urandom > $W/pat4.bin

echo; echo "################ T1/T2: leitura de 1 MiB, CPU contra DMA (allow_write=0)"
load use_dma=0; rdf $W/t1.bin 4096 1048576
load use_dma=1; echo "carregado: $(st) fault=$(cat $P/dma_fault_inject)"
ok $([ "$(cat $S/dma_state)" = "ativo DMAC1" ] && echo 0 || echo 1) "estado ativo DMAC1 ao carregar"
rdf $W/t2.bin 4096 1048576; cmp -s $W/t1.bin $W/t2.bin; ok $? "1 MiB: DMA == CPU"
d0=$(cat $S/dma_bytes_read); rates=""
for i in 1 2 3 4 5 6 7 8; do r=$(dd if=$DEV of=/dev/null bs=1M count=1 iflag=skip_bytes skip=4096 2>&1 | tail -n 1 | awk '{for(i=1;i<=NF;i++) if($i=="copied,") printf "%.0f", 1048576/$(i+1)/1000000}'); rates="$rates $r"; done
echo "  vazao 1 MiB (MB/s):$rates"; min=$(echo $rates | tr ' ' '\n' | sort -n | head -1)
ok $([ "$min" -ge 500 ] && echo 0 || echo 1) "vazao minima >= 500 MB/s (minimo $min)"
ok $([ $(( $(cat $S/dma_bytes_read)-d0 )) = 8388608 ] && echo 0 || echo 1) "contador dma_r subiu 8 MiB nas 8 leituras"

echo; echo "################ T5: allow_write=0 recusa escrita (DMA ativo)"
rdf $W/b5.bin $OFF 65536
out=$(wr $W/pat.bin $OFF); echo "$out" | grep -q "Operation not permitted"; ok $? "dd devolve Operation not permitted"
rdf $W/a5.bin $OFF 65536; cmp -s $W/b5.bin $W/a5.bin; ok $? "janela nao mudou (hash de leitura real)"

echo; echo "################ T6b: lacuna 0x401000 e leitura cruzando o fim da janela"
dd if=$DEV of=$W/g1.bin bs=4k count=1 iflag=skip_bytes skip=$((0x401000)) 2>$W/g1.err; ok $([ "$(stat -c %s $W/g1.bin)" = 0 ] && ! grep -qi "error" $W/g1.err && echo 0 || echo 1) "lacuna: 0 bytes e sem erro"
dd if=$DEV of=$W/g2.bin bs=64k iflag=skip_bytes,count_bytes skip=$OFFEND count=8192 2>/dev/null; ok $([ "$(stat -c %s $W/g2.bin)" = 2048 ] && echo 0 || echo 1) "leitura de 8 KiB a partir de 0x400800 devolve so 2048 B"

echo; echo "################ T7: rmmod baikal_dmac com o canal pego"
echo "refcnt dmac=$(cat /sys/module/baikal_dmac/refcnt)"
rmmod baikal_dmac 2>/dev/null; ok $([ "$(lsmod | grep -c '^baikal_dmac')" = 1 ] && echo 0 || echo 1) "rmmod falha com o canal em uso"
echo 0 > $S/use_dma; ok $([ "$(cat $S/dma_state)" = "sem canal" ] && echo 0 || echo 1) "use_dma=0 pelo sysfs devolve o canal (sem canal)"
rmmod baikal_dmac 2>/dev/null; ok $([ "$(lsmod | grep -c '^baikal_dmac')" = 0 ] && echo 0 || echo 1) "rmmod passa depois de devolver o canal"
c0=$(cat $S/cpu_bytes_read); rdf $W/t7.bin 4096 65536; ok $([ $(( $(cat $S/cpu_bytes_read)-c0 )) = 65536 ] && echo 0 || echo 1) "leitura sem dmac segue pela CPU"

echo; echo "################ T8: baikal_memory ANTES do baikal_dmac"
rmmod baikal_memory; insmod "$KO" use_dma=1; echo "sem dmac: $(st)"
ok $([ "$(cat $S/dma_state)" = "sem canal" ] && echo 0 || echo 1) "funciona sem o baikal_dmac (sem canal)"
rdf $W/t8a.bin 4096 65536; ok $([ "$(stat -c %s $W/t8a.bin)" = 65536 ] && echo 0 || echo 1) "leitura sem dmac devolve 64 KiB"
insmod $DMAC; sleep 2; d0=$(cat $S/dma_bytes_read); rdf $W/t8b.bin 4096 65536
ok $([ $(( $(cat $S/dma_bytes_read)-d0 )) = 65536 ] && echo 0 || echo 1) "depois do dmac subir, a leitura passa ao DMA sozinha (estado: $(cat $S/dma_state))"

echo; echo "################ escrita (allow_write=1)"
load use_dma=1 allow_write=1; echo "$(st) allow_write=$(cat $P/allow_write)"
echo; echo "---- T4: padrao 64 KiB por DMA e leitura de volta"
snapw=$(cat $S/dma_bytes_written); wr $W/pat.bin $OFF >/dev/null
ok $([ $(( $(cat $S/dma_bytes_written)-snapw )) = 65536 ] && echo 0 || echo 1) "escrita passou pelo DMA (dma_w+65536)"
echo 0 > $P/use_dma; rdf $W/rbc.bin $OFF 65536; echo 1 > $P/use_dma; rdf $W/rbd.bin $OFF 65536
cmp -s $W/pat.bin $W/rbc.bin; ok $? "readback pela CPU == padrao"; cmp -s $W/pat.bin $W/rbd.bin; ok $? "readback pelo DMA == padrao"
echo "---- T3: leituras desalinhadas contra o padrao conhecido"
badn=0; for o in 1 3 8189; do for s in 1 3 255 4097; do
  rdf $W/t.bin $((OFF+o)) $s; tail -c +$((o+1)) $W/pat.bin | head -c $s > $W/e.bin
  cmp -s $W/t.bin $W/e.bin || { badn=$((badn+1)); echo "    diverge: off=+$o size=$s"; }; done; done
ok $badn "12 leituras desalinhadas (+1,+3,+0x1ffd x 1,3,255,4097) identicas ao padrao"
c0=$(cat $S/cpu_bytes_read); d0=$(cat $S/dma_bytes_read); rdf $W/t.bin $((OFF+1)) 65535; tail -c +2 $W/pat.bin | head -c 65535 > $W/e.bin
cmp -s $W/t.bin $W/e.bin; ok $? "+1 x 65535 identica ao padrao"
ok $([ $(( $(cat $S/cpu_bytes_read)-c0 )) = 3 ] && [ $(( $(cat $S/dma_bytes_read)-d0 )) = 65532 ] && echo 0 || echo 1) "cabeca/cauda pela CPU (3 B) e miolo pelo DMA (65532 B)"
echo "---- T3w: escrita desalinhada 4097 B em +1"
snapc=$(cat $S/cpu_bytes_written); snapd=$(cat $S/dma_bytes_written); wr $W/pat3.bin $((OFF+1)) >/dev/null
rdf $W/t.bin $OFF 4099; { head -c 1 $W/pat.bin; cat $W/pat3.bin; dd if=$W/pat.bin bs=1 skip=4098 count=1 2>/dev/null; } > $W/e.bin
cmp -s $W/t.bin $W/e.bin; ok $? "escrita desalinhada correta e bytes vizinhos preservados"
ok $([ $(( $(cat $S/cpu_bytes_written)-snapc )) = 5 ] && [ $(( $(cat $S/dma_bytes_written)-snapd )) = 4092 ] && echo 0 || echo 1) "escrita: cpu_w+5 e dma_w+4092"
wr $W/pat.bin $OFF >/dev/null
echo "---- T6: escrita atravessando o fim da janela (4096 B a partir de 0x400800)"
out=$(dd if=$W/pat2.bin of=$DEV bs=4096 count=1 oflag=seek_bytes seek=$OFFEND conv=notrunc 2>&1)
echo "$out" | grep -q "2048 bytes"; ok $? "gravou so 2048 B (escrita parcial)"; echo "$out" | grep -q "Operation not permitted"; ok $? "EPERM no resto"
rdf $W/t.bin $OFFEND 2048; head -c 2048 $W/pat2.bin > $W/e.bin; cmp -s $W/t.bin $W/e.bin; ok $? "conteudo do fim da janela confere"

echo; echo "################ FALHAS (dma_fault_inject)"
echo "---- F1: erro REAL do DMAC (modo 2) em leitura, bounce aquecido com dado nao-zero"
load use_dma=1 allow_write=1; wr $W/pat.bin $OFF >/dev/null; rdf $W/warm.bin $OFF 65536
mark; echo 2 > $P/dma_fault_inject; rdf $W/inj.bin $OFF0 4096
ok $([ "$(nz $W/inj.bin)" = 0 ] && [ "$(stat -c %s $W/inj.bin)" = 4096 ] && echo 0 || echo 1) "leitura devolveu os 4096 B zerados corretos (nao o dado velho do bounce)"
ok $([ "$(cat $S/dma_errors)" = 1 ] && echo 0 || echo 1) "dma_errors=1"
ok $([ "$(cat $S/dma_state)" = "desligado: erro anterior" ] && echo 0 || echo 1) "DMA desligado (estado: $(cat $S/dma_state))"
newlog | grep -q "erro do DMAC (INT_FLAG=0x2)"; ok $? "dmesg tem o erro do DMAC (INT_FLAG=0x2)"
newlog | grep -q "falhou (resultado 3)"; ok $? "dmesg tem 'Transferencia DMA falhou (resultado 3)'"
c0=$(cat $S/cpu_bytes_read); rdf $W/n.bin $OFF 65536; cmp -s $W/n.bin $W/pat.bin; ok $? "leituras seguintes corretas pela CPU"
ok $([ $(( $(cat $S/cpu_bytes_read)-c0 )) = 65536 ] && echo 0 || echo 1) "e contadas como CPU"
echo 0 > $S/use_dma; echo 1 > $S/use_dma 2>/dev/null; ok $([ "$(cat $S/dma_state)" = "desligado: erro anterior" ] && echo 0 || echo 1) "religar pelo sysfs nao reativa o DMA"
echo "---- F2: aborto simulado (modo 1) em ESCRITA"
load use_dma=1 allow_write=1; mark; echo 1 > $P/dma_fault_inject
wr $W/pat4.bin $OFF >/dev/null; echo 0 > $P/use_dma; rdf $W/rb.bin $OFF 65536; cmp -s $W/rb.bin $W/pat4.bin; ok $? "escrita com falha injetada deixou o dado certo na SPM (fallback pela CPU)"
ok $([ "$(cat $S/dma_errors)" = 1 ] && echo 0 || echo 1) "dma_errors=1 apos falha na escrita"
echo "---- F3: recuperacao ao recarregar o modulo"
load use_dma=1 allow_write=1; ok $([ "$(cat $S/dma_state)" = "ativo DMAC1" ] && [ "$(cat $S/dma_errors)" = 0 ] && echo 0 || echo 1) "depois de recarregar: ativo DMAC1 e dma_errors=0"
d0=$(cat $S/dma_bytes_read); rdf $W/rec.bin $OFF 65536; cmp -s $W/rec.bin $W/pat4.bin; ok $? "leitura apos recuperar == dado esperado"
ok $([ $(( $(cat $S/dma_bytes_read)-d0 )) = 65536 ] && echo 0 || echo 1) "e voltou a passar pelo DMA"

echo; echo "################ T9: 2 leitores simultaneos por 20 s"
wr $W/pat.bin $OFF >/dev/null; H=$(sha256sum < $W/pat.bin | cut -d' ' -f1); d0=$(cat $S/dma_bytes_read)
reader(){ id=$1; end=$((SECONDS+20)); n=0; bad=0; while [ $SECONDS -lt $end ]; do dd if=$DEV of=$W/r$id.bin bs=64k count=1 iflag=skip_bytes skip=$OFF 2>/dev/null; h=$(sha256sum < $W/r$id.bin | cut -d' ' -f1); [ "$h" = "$H" ] || bad=$((bad+1)); n=$((n+1)); done; echo "$n $bad" > $W/res$id.txt; }
reader 1 & reader 2 & wait
read n1 b1 < $W/res1.txt; read n2 b2 < $W/res2.txt
echo "  leitor 1: $n1 leituras, $b1 divergentes; leitor 2: $n2 leituras, $b2 divergentes"
ok $([ "$b1" = 0 ] && [ "$b2" = 0 ] && echo 0 || echo 1) "0 divergencias nos dois leitores"
ok $([ $(( $(cat $S/dma_bytes_read)-d0 )) = $(( (n1+n2)*65536 )) ] && echo 0 || echo 1) "toda a leitura passou pelo DMA (dma_r+$(( $(cat $S/dma_bytes_read)-d0 )))"
ok $([ "$(cat $S/dma_errors)" = 0 ] && echo 0 || echo 1) "dma_errors=0"

echo; echo "################ T9f: 2 leitores por 20 s COM uma falha injetada no meio (aos 5 s)"
load use_dma=1 allow_write=1; wr $W/pat.bin $OFF >/dev/null; mark
reader 1 & reader 2 & ( sleep 5; echo 1 > $P/dma_fault_inject ) & wait
read n1 b1 < $W/res1.txt; read n2 b2 < $W/res2.txt
echo "  leitor 1: $n1 leituras, $b1 divergentes; leitor 2: $n2 leituras, $b2 divergentes"
ok $([ "$b1" = 0 ] && [ "$b2" = 0 ] && echo 0 || echo 1) "0 divergencias mesmo com a falha no meio"
ok $([ "$(cat $S/dma_errors)" = 1 ] && [ "$(cat $S/dma_state)" = "desligado: erro anterior" ] && echo 0 || echo 1) "a falha foi contada uma vez e o DMA desligou"
echo "  $(st)"
echo "  dmesg novo:"; newlog | sed 's/^/    /'
echo; echo "---- erros/oops no dmesg durante toda a bateria?"
dmesg | grep -iE "oops|BUG:|Call Trace|WARNING:" | cut -c1-140 | head -n 5; echo "(fim)"
