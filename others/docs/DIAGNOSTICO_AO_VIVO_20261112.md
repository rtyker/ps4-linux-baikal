# Diagnóstico Ao Vivo — PS4 Baikal (2026-11-12)

**Comando:** coleta de hardware + diagnóstico em tempo real no console PS4

## Resultados principais

### CPU
```
lscpu: AMD DG1501SML87LB, família 22, modelo 67, 8 cores/8 threads, sem SMT
Microcode: 0x7043001
BogoMIPS: ~3188/core
```

### Memória
```
MemTotal: 7.06 GiB | Disponível: 6.03 GiB | Swap: 0 B (desabilitado)
```

### GPU
```
amdgpu 0000:00:01.0: Gladius [1002:9924]
HDMI-A-1: 1920x1080@60 ativo
OpenGL 4.6 (radeonsi), Vulkan 1.4.363 (radv)
```

### Armazenamento
```
/dev/sda: Toshiba MQ04ABF100 1TB HDD, 5400 rpm, SMART PASSED
          1 setor realocado, 4247h power-on
/dev/sdb: Kingston SV300S37A120G 120GB SSD (via USB 3.0 JMS578)
          sdb1=vfat BOOT, sdb2=ext4 psxitarch (rootfs /)
```

### Rede
```
eth0 (GBE Baikal 00:14.1): DOWN, NO-CARRIER — driver mts carregado, PHY não acorda
wlan0: UP, 192.168.6.128/24
```

### Sensores
```
CPU: 54.2°C (crit 100°C) | Fan: 0 RPM
```

### CIFS
```
/mnt/hdauxiliar montado via CIFS com credentials=/etc/samba/credentials
uid=1001,gid=1001 — escrita sem sudo confirmada em downloads/ (755)
```

## Arquivos de diagnóstico gerados neste levantamento
- others/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md (este levantamento completo)
