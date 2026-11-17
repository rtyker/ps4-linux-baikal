#!/bin/bash
# Paired control: alternate "no-op" and "partial write" rounds with identical timing, snapshotting BAR5
# right before and right after the event. A write effect on BAR5 would show up as offsets that change
# in (almost) every write round and in no no-op round. Saves and restores the 2 KiB it touches.
P=/sys/module/baikal_memory/parameters
S=/sys/bus/pci/devices/0000:00:14.6/dma
DEV=/dev/baikal-memory
KO=/lib/modules/7.0.8-Strawberry-ThinLTO-Baikal-+/kernel/drivers/misc/baikal-memory.ko
BAR5=$((0x500000)); OFFEND=$((0x400800)); ROUNDS=10
W=/tmp/b5p; rm -rf $W; mkdir -p $W

snap(){ dd if=$DEV of=$1 bs=4096 count=64 iflag=skip_bytes skip=$BAR5 2>/dev/null; }
offs(){ cmp -l "$1" "$2" 2>/dev/null | awk '{print $1}'; }

cleanup(){
  echo "== LIMPEZA"
  if [ "$(cat $P/allow_write 2>/dev/null)" = Y ] && [ -f $W/orig_end.bin ]; then
    echo 0 > $P/use_dma
    dd if=$W/orig_end.bin of=$DEV bs=2048 count=1 oflag=seek_bytes seek=$OFFEND conv=notrunc 2>/dev/null
    dd if=$DEV of=$W/fin_end.bin bs=2048 count=1 iflag=skip_bytes skip=$OFFEND 2>/dev/null
    echo "fim da janela == original: $(cmp -s $W/fin_end.bin $W/orig_end.bin && echo SIM || echo NAO)"
  fi
  rmmod baikal_memory && insmod $KO
  echo "estado final: use_dma=$(cat $P/use_dma) allow_write=$(cat $P/allow_write) estado=$(cat $S/dma_state) err=$(cat $S/dma_errors)"
  rm -rf $W
}
trap cleanup EXIT

echo 0 > $P/use_dma
dd if=$DEV of=$W/orig_end.bin bs=2048 count=1 iflag=skip_bytes skip=$OFFEND 2>/dev/null
echo "original do fim da janela: nao-zero=$(tr -d '\000' < $W/orig_end.bin | wc -c)"
rmmod baikal_memory && insmod $KO allow_write=1 || { echo FALHA; exit 1; }
echo "allow_write=$(cat $P/allow_write) use_dma=$(cat $P/use_dma)"

for r in $(seq 1 $ROUNDS); do
  # no-op round: snapshot, do nothing, snapshot
  snap $W/a.bin; snap $W/b.bin; offs $W/a.bin $W/b.bin | sort -u > $W/noop_$r.txt
  # write round: snapshot, partial write (same position, new random data), snapshot
  head -c 4096 /dev/urandom > $W/data.bin
  snap $W/a.bin
  dd if=$W/data.bin of=$DEV bs=4096 count=1 oflag=seek_bytes seek=$OFFEND conv=notrunc 2>/dev/null
  snap $W/b.bin; offs $W/a.bin $W/b.bin | sort -u > $W/write_$r.txt
done

echo "== bytes da BAR5 que mudaram por rodada (cada rodada = 2 snapshots seguidos)"
echo -n "sem escrita : "; for r in $(seq 1 $ROUNDS); do echo -n "$(wc -l < $W/noop_$r.txt) "; done; echo
echo -n "com escrita : "; for r in $(seq 1 $ROUNDS); do echo -n "$(wc -l < $W/write_$r.txt) "; done; echo
cat $W/noop_*.txt  | sort | uniq -c | awk '{print $2, $1}' | sort -k1,1 > $W/cnt_noop.txt
cat $W/write_*.txt | sort | uniq -c | awk '{print $2, $1}' | sort -k1,1 > $W/cnt_write.txt
echo "offsets distintos que mudaram: sem escrita=$(wc -l < $W/cnt_noop.txt)  com escrita=$(wc -l < $W/cnt_write.txt)"
# suspicious = changed in >= 70% of the write rounds and in none of the no-op rounds
MIN=$(( (ROUNDS*7+9)/10 ))
awk -v min=$MIN 'NR==FNR{n[$1]=$2; next} ($2>=min) && !($1 in n){print $1, $2}' $W/cnt_noop.txt $W/cnt_write.txt > $W/susp.txt
echo "offsets que mudaram em >= $MIN das $ROUNDS rodadas COM escrita e em NENHUMA sem escrita: $(wc -l < $W/susp.txt)"
head -n 8 $W/susp.txt | tr '\n' ';'; echo
echo "offsets que mudaram em >= $MIN rodadas SEM escrita (voláteis frequentes): $(awk -v min=$MIN '$2>=min' $W/cnt_noop.txt | wc -l)"
dd if=$DEV of=$W/rb.bin bs=2048 count=1 iflag=skip_bytes skip=$OFFEND 2>/dev/null
head -c 2048 $W/data.bin > $W/exp.bin
echo "ultima escrita: fim da janela == 2048 primeiros bytes do dado: $(cmp -s $W/rb.bin $W/exp.bin && echo SIM || echo NAO)"
