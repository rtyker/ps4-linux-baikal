#!/bin/bash
# Fault injection (mode 2 = real DMAC error, mode 1 = simulated abort) plus a regression of the normal DMA path.
# Usage: fault_and_regress.sh <path to the test .ko on the PS4>
# dmesg is read by line count (not by timestamp). Restores the SPM window to zero and reloads the HD module.
KO_TEST="$1"
P=/sys/module/baikal_memory/parameters
S=/sys/bus/pci/devices/0000:00:14.6/dma
DEV=/dev/baikal-memory
KO_HD=/lib/modules/7.0.8-Strawberry-ThinLTO-Baikal-+/kernel/drivers/misc/baikal-memory.ko
OFF=$((0x201000)); OFF0=$((0x1000)); LEN=4096
W=/tmp/fr; rm -rf $W; mkdir -p $W

st(){ echo "estado=$(cat $S/dma_state) dma_errors=$(cat $S/dma_errors) cpu_r=$(cat $S/cpu_bytes_read) dma_r=$(cat $S/dma_bytes_read)"; }
rdn(){ dd if=$DEV of=$1 bs=$3 count=1 iflag=skip_bytes skip=$2 2>/dev/null; }
nz(){ tr -d '\000' < "$1" | wc -c; }
mark(){ N0=$(dmesg | wc -l); }
newlog(){ dmesg | tail -n +$((N0+1)) | grep -iE "baikal|dmac" | cut -c1-160; }
load(){ rmmod baikal_memory; insmod "$KO_TEST" allow_write=1 use_dma=1 || { echo "FALHA ao carregar o modulo de teste"; exit 1; }; }

cleanup(){
  echo "== LIMPEZA"
  if [ "$(cat $P/allow_write 2>/dev/null)" = Y ]; then
    echo 0 > $P/use_dma
    head -c 65536 /dev/zero > $W/zero.bin
    dd if=$W/zero.bin of=$DEV bs=64k count=1 oflag=seek_bytes seek=$OFF conv=notrunc 2>/dev/null
    rdn $W/fin.bin $OFF 65536
    echo "janela restaurada: bytes nao-zero=$(nz $W/fin.bin) (esperado 0)"
  fi
  rmmod baikal_memory && insmod $KO_HD
  echo "modulo do HD de volta: $(st) use_dma=$(cat $P/use_dma) allow_write=$(cat $P/allow_write)"
  rm -rf $W
}
trap cleanup EXIT

echo 0 > $P/use_dma; rdn $W/o1.bin $OFF 65536; rdn $W/o0.bin $OFF0 $LEN
echo "originais: janela do padrao nao-zero=$(nz $W/o1.bin)  SPM offset 0 nao-zero=$(nz $W/o0.bin)"
[ "$(nz $W/o1.bin)" = 0 ] && [ "$(nz $W/o0.bin)" = 0 ] || { echo "ABORTADO: regioes nao estao zeradas"; exit 1; }
head -c 65536 /dev/urandom > $W/pat.bin

fault_case(){ # $1 = mode (1 simulated abort, 2 real DMAC error)
  echo; echo "################ MODO $1 ################"
  load
  dd if=$W/pat.bin of=$DEV bs=64k count=1 oflag=seek_bytes seek=$OFF conv=notrunc 2>/dev/null
  rdn $W/warm.bin $OFF 65536
  cmp -s $W/pat.bin $W/warm.bin && echo "bounce aquecido com o padrao (nao-zero=$(nz $W/warm.bin))" || { echo "ABORTADO: aquecimento difere"; exit 1; }
  echo "antes: $(st)"
  mark; echo $1 > $P/dma_fault_inject
  rdn $W/inj.bin $OFF0 $LEN
  echo "dma_fault_inject depois: $(cat $P/dma_fault_inject) (0 = consumido)"
  if [ "$(nz $W/inj.bin)" = 0 ]; then echo "RESULTADO: $(stat -c %s $W/inj.bin) bytes, TODOS ZERO = correto (fallback pela CPU devolveu o dado certo)"
  else echo "RESULTADO: ERRADO, $(nz $W/inj.bin) bytes nao-zero (dado velho do bounce, erro nao tratado)"; fi
  echo "depois: $(st)"
  echo "--- dmesg novo:"; newlog
  echo "== leitura seguinte do mesmo trecho (DMA deve estar desligado, CPU deve servir)"
  rdn $W/after.bin $OFF0 $LEN; echo "nao-zero=$(nz $W/after.bin)  $(st)"
  echo "== religar o DMA pelo sysfs (deve ser recusado ate recarregar o modulo)"
  echo 0 > $S/use_dma; echo 1 > $S/use_dma 2>&1 | head -n 1; echo "$(st)"
}
fault_case 2
fault_case 1

echo; echo "################ REGRESSAO do caminho normal (modulo novo, sem injecao) ################"
load; echo "carregado: $(st) dma_fault_inject=$(cat $P/dma_fault_inject)"
dd if=$W/pat.bin of=$DEV bs=64k count=1 oflag=seek_bytes seek=$OFF conv=notrunc 2>/dev/null
echo 0 > $P/use_dma; rdn $W/cpu.bin $OFF 65536; echo 1 > $P/use_dma
cmp -s $W/pat.bin $W/cpu.bin && echo "escrita pelo DMA + leitura pela CPU: OK" || echo "escrita pelo DMA + leitura pela CPU: DIFERE"
snap0=$(cat $S/dma_bytes_read); rdn $W/dma.bin $OFF 65536
cmp -s $W/pat.bin $W/dma.bin && echo "leitura DMA 64 KiB == padrao: OK (dma_r+$(( $(cat $S/dma_bytes_read)-snap0 )))" || echo "leitura DMA 64 KiB: DIFERE"
c0=$(cat $S/cpu_bytes_read); d0=$(cat $S/dma_bytes_read)
dd if=$DEV of=$W/un.bin bs=64k iflag=skip_bytes,count_bytes skip=$((OFF+1)) count=4097 2>/dev/null
tail -c +2 $W/pat.bin | head -c 4097 > $W/unexp.bin
cmp -s $W/un.bin $W/unexp.bin && echo "desalinhada +1 x 4097: OK (cpu+$(( $(cat $S/cpu_bytes_read)-c0 )) dma+$(( $(cat $S/dma_bytes_read)-d0 )), esperado 5/4092)" || echo "desalinhada: DIFERE"
d0=$(cat $S/dma_bytes_read)
for i in 1 2 3 4 5; do dd if=$DEV of=/dev/null bs=1M count=1 iflag=skip_bytes skip=4096 2>&1 | tail -n 1 | awk '{for(i=1;i<=NF;i++) if($i=="copied,") printf "%.0f ", 1048576/$(i+1)/1000000}'; done; echo "MB/s (5 x 1 MiB, dma_r+$(( $(cat $S/dma_bytes_read)-d0 )))"
dd if=$DEV of=$W/gap.bin bs=4k count=1 iflag=skip_bytes skip=$((0x401000)) 2>&1 | tail -n 1
echo "estado final da regressao: $(st)"
