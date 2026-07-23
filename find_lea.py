#!/usr/bin/env python3
import struct

DUMP_FILE = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/dumps_orbis/kmem_dump_1252.bin"
BADDR = 0xffffffffdc350000
STRING_OFFSET = 0x7bdbac # "Baikal GBE controller"

print(f"Procurando LEA para a string em offset {hex(STRING_OFFSET)}")

with open(DUMP_FILE, "rb") as f:
    data = f.read()

# lea rsi, [rip + disp] -> 48 8d 35 [disp32]
# lea rdi, [rip + disp] -> 48 8d 3d [disp32]
# lea rdx, [rip + disp] -> 48 8d 15 [disp32]

for idx in range(0, len(data) - 7):
    # Check for LEA RDI, RSI, RDX
    if data[idx:idx+2] == b'\x48\x8d':
        op = data[idx+2]
        if op in [0x3d, 0x35, 0x15]:
            disp = struct.unpack_from("<i", data, idx+3)[0]
            # Next instruction address
            next_ins = idx + 7
            # Target = next_ins + disp
            target = next_ins + disp
            if target == STRING_OFFSET:
                print(f"Found LEA at offset {hex(idx)} (vaddr {hex(BADDR + idx)}) targeting string!")
                print(f"  Opcode: {data[idx:idx+7].hex()}")
