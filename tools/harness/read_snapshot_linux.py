#!/usr/bin/env python3
import mmap
import struct
import os
import sys

def main():
    if os.geteuid() != 0:
        print("Execute como root! (sudo python3 read_snapshot_linux.py)")
        sys.exit(1)

    print("[*] Lendo snapshot de hardware direto do /dev/mem (0x680000)...")
    
    with open("/dev/mem", "rb") as f:
        # Pular ate 0x680000
        f.seek(0x680000)
        data = f.read(792) # 256 + 256 + 256 + 24
        
    print("\n==========================================")
    print("=== GOLDEN SNAPSHOT: ORBIS HARDWARE STATE ===")
    print("==========================================\n")

    pci_gbe = struct.unpack('<64I', data[0:256])
    pci_acpi = struct.unpack('<64I', data[256:512])
    pci_sata = struct.unpack('<64I', data[512:768])
    
    glue_0xc890a030 = struct.unpack('<I', data[768:772])[0]
    gbe_0xc2000000 = struct.unpack('<I', data[772:776])[0]
    gbe_0xc2000004 = struct.unpack('<I', data[776:780])[0]
    gbe_0xc2000054 = struct.unpack('<I', data[780:784])[0]
    gbe_0xc2000100 = struct.unpack('<I', data[784:788])[0]
    gbe_0xc2000118 = struct.unpack('<I', data[788:792])[0]

    print("--- 00:14.1 (GBE) PCI Config Space (primeiros 64 bytes) ---")
    for i in range(16):
        print(f"0x{i*4:02x}: {pci_gbe[i]:08x}")

    print("\n--- 00:14.0 (ACPI) PCI Config Space (primeiros 16 bytes) ---")
    for i in range(4):
        print(f"0x{i*4:02x}: {pci_acpi[i]:08x}")

    print("\n--- 00:14.2 (SATA) PCI Config Space (primeiros 16 bytes) ---")
    for i in range(4):
        print(f"0x{i*4:02x}: {pci_sata[i]:08x}")

    print("\n--- BAR2 Pervasive Glue ---")
    print(f"0xc890a030: {glue_0xc890a030:08x}")

    print("\n--- BAR0 GBE MAC Registers ---")
    print(f"0xc2000100: {gbe_0xc2000100:08x}")
    print(f"0xc2000118 (B2_CHIP_ID/B2_MAC_CFG): {gbe_0xc2000118:08x}")
    print(f"0xc2000000: {gbe_0xc2000000:08x}")
    print(f"0xc2000004: {gbe_0xc2000004:08x}")
    print(f"0xc2000054 (IMR): {gbe_0xc2000054:08x}")

    print("==========================================\n")

if __name__ == "__main__":
    main()
