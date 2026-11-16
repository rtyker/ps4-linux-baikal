# Makefile para aeolia_dmac_test.c
# Compilar contra o kernel do PS4 (kernel/kernel_build_7.0)
# Uso: make KDIR=/mnt/hdauxiliar/ps4-linux-baikal/kernel/kernel_build_7.0

KDIR ?= /mnt/hdauxiliar/ps4-linux-baikal/kernel/kernel_build_7.0
CC := ccache clang
LLVM := 1
ARCH := x86_64

obj-m := aeolia_dmac_test.o

aeolia_dmac_test-y := aeolia_dmac_test.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules CC="$(CC)" LLVM=$(LLVM) ARCH=$(ARCH)

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

# Compilação isolada do .o (para validação rápida sem .ko)
aeolia_dmac_test.o: aeolia_dmac_test.c
	$(MAKE) -C $(KDIR) M=$(PWD) CC="$(CC)" LLVM=$(LLVM) ARCH=$(ARCH) $@