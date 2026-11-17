#!/bin/bash
# Live test of the baikal_spm_blk block device (no swap yet). Usage: blk_test.sh <path to the .ko on the PS4>
KO="$1"
W=/dev/shm/blk; rm -rf $W; mkdir -p $W
DEV=/dev/baikal_spm0
SYS=/sys/block/baikal_spm0
PASS=0; FAIL=0
ok(){ if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS  $2"; else FAIL=$((FAIL+1)); echo "  FAIL  $2"; fi; }
cnt(){ echo "dma_bytes=$(cat $SYS/dma_bytes) cpu_bytes=$(cat $SYS/cpu_bytes) fallbacks=$(cat $SYS/dma_fallbacks) errors=$(cat $SYS/dma_errors) [$(cat $SYS/state)]"; }
rate(){ awk '{for(i=1;i<=NF;i++) if($i=="copied,") print $(i+3)" "$(i+4)}'; }

cleanup(){
  echo; echo "== LIMPEZA: zera o dispositivo e descarrega"
  if [ -b $DEV ]; then
    dd if=/dev/zero of=$DEV bs=1M oflag=direct 2>/dev/null
    dd if=$DEV bs=1M iflag=direct 2>/dev/null | tr -d '\000' | wc -c | xargs echo "bytes nao-zero depois de zerar (esperado 0):"
  fi
  echo 1 > /sys/module/baikal_spm_blk/parameters/use_dma 2>/dev/null
  rmmod baikal_spm_blk 2>&1 | head -n 2
  lsmod | grep -c baikal_spm_blk | xargs echo "modulo ainda carregado (esperado 0):"
  echo; echo "================ TOTAL: $PASS PASS, $FAIL FAIL ================"
  rm -rf $W
}
trap cleanup EXIT

echo "################ carga"
N0=$(dmesg | wc -l)
insmod "$KO" || { echo "insmod falhou"; dmesg | tail -n 8; exit 1; }
sleep 1
dmesg | tail -n +$((N0+1)) | grep -iE "baikal_spm|baikal-dmac|warn|BUG" | cut -c1-150
[ -b $DEV ]; ok $? "/dev/baikal_spm0 existe"
SZ=$(cat $SYS/size); ok $([ "$SZ" = $((180*1024*2)) ] && echo 0 || echo 1) "tamanho = 180 MiB ($SZ setores)"
echo "estado: $(cat $SYS/state)"

echo; echo "################ T1: integridade (direct): varios tamanhos e offsets, inclusive desalinhados em setor"
bad=0
for spec in "0 512" "8 4096" "1 512" "7 1536" "100 4096" "2048 65536" "4096 1048576" "10000 2097152" "12345 3145728" "30000 4194304"; do
  set -- $spec; sec=$1; len=$2
  head -c $len /dev/urandom > $W/p.bin
  dd if=$W/p.bin of=$DEV bs=512 seek=$sec oflag=direct conv=notrunc 2>/dev/null
  dd if=$DEV of=$W/r.bin bs=512 skip=$sec count=$((len/512)) iflag=direct 2>/dev/null
  cmp -s $W/p.bin $W/r.bin || { bad=$((bad+1)); echo "    diverge: setor=$sec tam=$len"; }
done
ok $bad "10 combinacoes de (setor, tamanho) gravadas e lidas de volta iguais"
echo "  $(cnt)"

echo; echo "################ T2: dispositivo inteiro (180 MiB) com dado aleatorio"
head -c $((180*1024*1024)) /dev/urandom > $W/full.bin
t0=$(date +%s.%N); dd if=$W/full.bin of=$DEV bs=1M oflag=direct 2>$W/w.err; t1=$(date +%s.%N)
dd if=$DEV of=$W/back.bin bs=1M iflag=direct 2>$W/r.err; t2=$(date +%s.%N)
cmp -s $W/full.bin $W/back.bin; ok $? "180 MiB gravados e relidos identicos (byte a byte)"
echo "  escrita: $(tail -n 1 $W/w.err | rate)   leitura: $(tail -n 1 $W/r.err | rate)"
echo "  $(cnt)"

echo; echo "################ T3: caminho com cache de pagina (sem O_DIRECT)"
head -c $((8*1024*1024)) /dev/urandom > $W/b.bin
dd if=$W/b.bin of=$DEV bs=4k seek=1000 conv=notrunc 2>/dev/null; sync; echo 3 > /proc/sys/vm/drop_caches
dd if=$DEV of=$W/br.bin bs=4k skip=1000 count=$((8*1024*1024/4096)) 2>/dev/null
cmp -s $W/b.bin $W/br.bin; ok $? "8 MiB bufferizados: gravar, sync, limpar o cache, ler: iguais"

echo; echo "################ T4: vazao (direct, 64 MiB)"
dd if=/dev/zero of=$DEV bs=1M count=64 oflag=direct 2>$W/w2.err; echo "  escrita 64 MiB: $(tail -n 1 $W/w2.err | rate)"
dd if=$DEV of=/dev/null bs=1M count=64 iflag=direct 2>$W/r2.err; echo "  leitura 64 MiB: $(tail -n 1 $W/r2.err | rate)"
dd if=$DEV of=/dev/null bs=4k count=4096 iflag=direct 2>$W/r3.err; echo "  leitura 16 MiB em blocos de 4 KiB: $(tail -n 1 $W/r3.err | rate)"

echo; echo "################ T5: modo so-CPU (use_dma=0) continua correto"
echo 0 > /sys/module/baikal_spm_blk/parameters/use_dma
d0=$(cat $SYS/dma_bytes); c0=$(cat $SYS/cpu_bytes)
head -c 262144 /dev/urandom > $W/c.bin
dd if=$W/c.bin of=$DEV bs=512 seek=5000 oflag=direct conv=notrunc 2>/dev/null
dd if=$DEV of=$W/cr.bin bs=512 skip=5000 count=512 iflag=direct 2>/dev/null
cmp -s $W/c.bin $W/cr.bin; ok $? "256 KiB pela CPU: gravados e lidos iguais"
ok $([ "$(( $(cat $SYS/dma_bytes)-d0 ))" = 0 ] && [ "$(( $(cat $SYS/cpu_bytes)-c0 ))" = 524288 ] && echo 0 || echo 1) "contadores: so CPU (cpu_bytes+524288, dma_bytes+0)"
echo 1 > /sys/module/baikal_spm_blk/parameters/use_dma
echo "  $(cnt)"

echo; echo "################ T6: limites"
dd if=$W/p.bin of=$DEV bs=512 seek=$((180*1024*2)) count=1 oflag=direct 2>$W/lim.err
grep -qiE "No space|Invalid|error" $W/lim.err; ok $? "escrever depois do fim do dispositivo e recusado"
dmesg | grep -iE "BUG:|Call Trace|WARNING:|baikal_spm_blk.*(error|failed)" | grep -v "baikal_dmac\|msi_device" | cut -c1-140 | tail -n 5
echo "(fim dos avisos)"
