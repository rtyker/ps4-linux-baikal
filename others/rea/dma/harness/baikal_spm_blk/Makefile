# Out-of-tree build of baikal-spm-blk for fast iteration (same flags as harness/build_dma_modules.sh).
# The shipped driver comes from kernel/patches/baikal-spm-blk.patch and the official build.
KDIR ?= /mnt/hdauxiliar/ps4-linux-baikal/kernel/kernel_build_7.0
obj-m := baikal-spm-blk.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=x86_64 LLVM=1 CC=clang W=1 \
	    KBUILD_MODPOST_WARN=1 CONFIG_DEBUG_INFO_BTF_MODULES= modules
	objcopy --remove-section=.BTF --remove-section=.BTF.base baikal-spm-blk.ko 2>/dev/null || true

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
