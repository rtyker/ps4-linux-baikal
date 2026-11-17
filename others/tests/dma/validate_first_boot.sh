#!/bin/bash
# First-boot validation of tag 20261116-dma-final on the live PS4 (read-only: no writes to the SPM).
S=/sys/bus/pci/devices/0000:00:14.6/dma
P=/sys/module/baikal_memory/parameters
DEV=/dev/baikal-memory
KVER=7.0.8-Strawberry-ThinLTO-Baikal-+
M=/lib/modules/$KVER/kernel/drivers/misc/baikal-memory.ko

echo "== kernel em execucao"
uname -r; uname -v; uptime -p
echo -n "cmdline tem root=LABEL=psxitarch: "; grep -c "root=LABEL=psxitarch" /proc/cmdline

echo "== modulo carregado no boot (sem parametros, pelo rootfs gravado)"
lsmod | grep -E '^baikal|^virt_dma'
echo -n "baikal-memory.ko em uso e o gravado no HD? sha do arquivo: "; sha256sum "$M" | cut -c1-16
echo -n "strings novas no arquivo (esperado 2): "; strings "$M" | grep -c "ativo DMAC%d\|habilitado sob demanda"
echo "use_dma=$(cat $P/use_dma) allow_write=$(cat $P/allow_write) dma_min=$(cat $P/dma_min)"
echo "dma_state=$(cat $S/dma_state) dma_errors=$(cat $S/dma_errors)"

echo "== dmesg do baikal-memory / baikal-dmac no boot"
dmesg | grep -iE "baikal-memory|baikal-dmac|baikal_memory" | cut -c1-140 | head -n 25

echo "== leitura de 1 MiB a quente, 10 medidas (DMA) e contadores"
c0=$(cat $S/cpu_bytes_read); d0=$(cat $S/dma_bytes_read)
for i in 1 2 3 4 5 6 7 8 9 10; do
  dd if=$DEV of=/dev/null bs=1M count=1 iflag=skip_bytes skip=4096 2>&1 | tail -n 1 \
    | awk '{for(i=1;i<=NF;i++) if($i=="copied,") printf "%.0f\n", 1048576/$(i+1)/1000000}'
done | sort -n | tr '\n' ' '; echo "(MB/s, ordenado)"
echo "contadores: cpu_r+$(( $(cat $S/cpu_bytes_read)-c0 )) dma_r+$(( $(cat $S/dma_bytes_read)-d0 )) err=$(cat $S/dma_errors) estado=$(cat $S/dma_state)"

echo "== leitura desalinhada (+1, 4097 B): cabeca/cauda CPU, miolo DMA"
c0=$(cat $S/cpu_bytes_read); d0=$(cat $S/dma_bytes_read)
dd if=$DEV of=/dev/null bs=64k iflag=skip_bytes,count_bytes skip=$((0x201001)) count=4097 2>/dev/null
echo "cpu_r+$(( $(cat $S/cpu_bytes_read)-c0 )) dma_r+$(( $(cat $S/dma_bytes_read)-d0 ))  (esperado cpu 5 / dma 4092)"

echo "== lacuna 0x401000: leitura deve devolver 0 bytes sem erro"
dd if=$DEV of=/dev/null bs=4k count=1 iflag=skip_bytes skip=$((0x401000)) 2>&1 | tail -n 1

echo "== erros no dmesg?"
dmesg | grep -iE "oops|BUG:|Call Trace|baikal.*(erro|error|falhou)" | cut -c1-140 | head -n 10
echo "(fim)"
