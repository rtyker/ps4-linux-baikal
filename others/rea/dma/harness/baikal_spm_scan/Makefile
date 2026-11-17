# Out-of-tree build of the read-only SPM scan module against the PS4 kernel tree.
# Flags follow harness/build_dma_modules.sh: the PS4 kernel has no MODVERSIONS, and the
# tree may have no vmlinux, so BTF is dropped (a module with BTF from another build
# fails to load: "failed to validate module BTF").
# Usage: make            (KDIR defaults to kernel/kernel_build_7.0)
KDIR ?= /mnt/hdauxiliar/ps4-linux-baikal/kernel/kernel_build_7.0
obj-m := baikal_spm_scan.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=x86_64 LLVM=1 CC=clang \
	    KBUILD_MODPOST_WARN=1 CONFIG_DEBUG_INFO_BTF_MODULES= modules
	objcopy --remove-section=.BTF --remove-section=.BTF.base baikal_spm_scan.ko 2>/dev/null || true

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
