#!/bin/bash
# Real swap test on the SPM block device. Usage: swap_test.sh <path to baikal-spm-blk.ko on the PS4>
# Confines a memory hog to a small cgroup so the kernel must page out through the SPM device (priority 200,
# above zram's 100, only for this test), then verifies every 1 MiB block by CRC after paging it back in.
KO="$1"
DEV=/dev/baikal_spm0
SYS=/sys/block/baikal_spm0
W=/dev/shm/swt; rm -rf $W; mkdir -p $W
PASS=0; FAIL=0
ok(){ if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS  $2"; else FAIL=$((FAIL+1)); echo "  FAIL  $2"; fi; }
cnt(){ echo "dma_bytes=$(cat $SYS/dma_bytes) cpu_bytes=$(cat $SYS/cpu_bytes) fallbacks=$(cat $SYS/dma_fallbacks) errors=$(cat $SYS/dma_errors) [$(cat $SYS/state)]"; }
vm(){ grep -E "^(pswpin|pswpout) " /proc/vmstat | tr '\n' ' '; }

cleanup(){
  echo; echo "== LIMPEZA"
  swapoff $DEV 2>&1 | head -n 2
  swapon --show | sed 's/^/  /'
  if [ -b $DEV ]; then dd if=/dev/zero of=$DEV bs=1M oflag=direct 2>/dev/null; dd if=$DEV bs=1M iflag=direct 2>/dev/null | tr -d '\000' | wc -c | xargs echo "bytes nao-zero depois de zerar (esperado 0):"; fi
  rmmod baikal_spm_blk 2>&1 | head -n 2; lsmod | grep -c baikal_spm_blk | xargs echo "modulo carregado (esperado 0):"
  echo; echo "================ TOTAL: $PASS PASS, $FAIL FAIL ================"
  rm -rf $W
}
trap cleanup EXIT

cat > $W/hog.py <<'PY'
import sys, zlib, random, time
n = int(sys.argv[1]); seed = int(sys.argv[2]); passes = int(sys.argv[3])
rng = random.Random(seed)
blocks, crcs = [], []
t0 = time.time()
for i in range(n):
    b = bytearray(rng.randbytes(1 << 20))
    blocks.append(b)
    crcs.append(zlib.crc32(b))
t_alloc = time.time() - t0
bad = 0
order = list(range(n))
for p in range(passes):
    rng.shuffle(order)
    t1 = time.time()
    for i in order:
        if zlib.crc32(blocks[i]) != crcs[i]:
            bad += 1
    print(f"hog seed={seed}: pass {p+1} verified {n} MiB in {time.time()-t1:.2f} s, {bad} bad so far", flush=True)
print(f"hog seed={seed}: allocated {n} MiB in {t_alloc:.2f} s, total corrupted blocks={bad}", flush=True)
sys.exit(1 if bad else 0)
PY

echo "################ preparo"
N0=$(dmesg | wc -l)
insmod "$KO" || { echo "insmod falhou"; exit 1; }
sleep 1; [ -b $DEV ]; ok $? "dispositivo criado ($(cat $SYS/state))"
mkswap -L spm $DEV 2>&1 | tail -n 1 | sed 's/^/  /'
swapon -p 200 $DEV; ok $? "swapon -p 200 $DEV"
swapon --show | sed 's/^/  /'

echo; echo "################ S1: 1 processo, limite de 48 MiB de RAM, 140 MiB de dados, 3 passadas aleatorias"
echo "vmstat antes: $(vm)"; echo "SPM antes: $(cnt)"
t0=$(date +%s.%N)
timeout 240 systemd-run --scope --quiet -p MemoryMax=48M -p MemorySwapMax=infinity python3 $W/hog.py 140 1 3 2>&1 | sed 's/^/  /'
rc=${PIPESTATUS[0]}; t1=$(date +%s.%N)
ok $rc "hog terminou sem bloco corrompido (rc=$rc, $(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.1f", b-a}') s)"
echo "vmstat depois: $(vm)"; echo "SPM depois: $(cnt)"
pout=$(grep -E "^pswpout " /proc/vmstat | awk '{print $2}'); pin=$(grep -E "^pswpin " /proc/vmstat | awk '{print $2}')
ok $([ "$pout" -gt 10000 ] && echo 0 || echo 1) "o kernel realmente paginou para fora (pswpout=$pout paginas = $((pout*4/1024)) MiB)"
ok $([ "$pin" -gt 10000 ] && echo 0 || echo 1) "e paginou de volta (pswpin=$pin paginas = $((pin*4/1024)) MiB)"
ok $([ "$(cat $SYS/dma_errors)" = 0 ] && [ "$(cat $SYS/dma_fallbacks)" = 0 ] && echo 0 || echo 1) "sem erro nem fallback do DMA durante o swap"
ok $([ "$(cat $SYS/dma_bytes)" -gt 50000000 ] && echo 0 || echo 1) "os dados passaram pelo DMA ($(cat $SYS/dma_bytes) bytes)"

echo; echo "################ S2: 3 processos ao mesmo tempo (40 MiB cada, limite de 16 MiB cada)"
echo "vmstat antes: $(vm)"
for s in 11 12 13; do
  ( timeout 240 systemd-run --scope --quiet -p MemoryMax=16M -p MemorySwapMax=infinity python3 $W/hog.py 40 $s 3 > $W/h$s.out 2>&1; echo $? > $W/h$s.rc ) &
done
wait
for s in 11 12 13; do tail -n 1 $W/h$s.out | sed 's/^/  /'; done
ok $([ "$(cat $W/h11.rc $W/h12.rc $W/h13.rc | tr -d '\n')" = "000" ] && echo 0 || echo 1) "3 processos concorrentes, nenhum bloco corrompido"
echo "vmstat depois: $(vm)"; echo "SPM depois: $(cnt)"
ok $([ "$(cat $SYS/dma_errors)" = 0 ] && echo 0 || echo 1) "dma_errors continua 0"

echo; echo "################ S3: swap com o DMA desligado (use_dma=0): lento mas correto"
echo 0 > /sys/module/baikal_spm_blk/parameters/use_dma
timeout 240 systemd-run --scope --quiet -p MemoryMax=16M -p MemorySwapMax=infinity python3 $W/hog.py 30 21 1 2>&1 | sed 's/^/  /'
ok ${PIPESTATUS[0]} "hog so pela CPU, sem corromper"
echo 1 > /sys/module/baikal_spm_blk/parameters/use_dma
echo "SPM: $(cnt)"

echo; echo "################ avisos do kernel durante o teste"
dmesg | tail -n +$((N0+1)) | grep -iE "BUG:|Call Trace|WARNING:|hung task|blocked for more|oom|Out of memory|baikal_spm_blk.*(fail|error)" | cut -c1-150
echo "(fim)"
