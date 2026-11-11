#!/usr/bin/env python3
import sys, struct
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

PFS_LE = (0x1332A0B).to_bytes(4, 'little')
PFS_BE = (0x1332A0B).to_bytes(4, 'big')

KEYS_32 = {
    'EAP':  bytes.fromhex('edf3f4d33b16a17bf4ea92070fe8af6b08c23c91f98006ae5b4f7d363c2bf0a3'),
    'ERK':  bytes.fromhex('7fcf0536d3b5f5bd09a5d7b3833f868bbe1f6d90803b4f54029e6265f6476af6'),
    'PROD': bytes.fromhex('e4090248c0aaa615eb00c761f6d1f1a83564c1f52883c9b47d63b58970d911c7'),
}

def get_key_candidates():
    candidates = {}
    for name, k in KEYS_32.items():
        # XTS-128 (32 bytes)
        candidates[f"{name}_xts128_asis"] = k
        candidates[f"{name}_xts128_swap"] = k[16:] + k[:16]
        candidates[f"{name}_xts128_r16"]  = k[:16][::-1] + k[16:][::-1]
        candidates[f"{name}_xts128_revall"] = k[::-1]
        
        # XTS-256 (64 bytes)
        z = b'\x00' * 32
        candidates[f"{name}_xts256_dup"]   = k + k
        candidates[f"{name}_xts256_k_z"]   = k + z
        candidates[f"{name}_xts256_z_k"]   = z + k
        candidates[f"{name}_xts256_sw_z"]  = (k[16:] + k[:16]) + z
    return candidates

def test_device(device_path, start_sector=57147392):
    print(f"=== Varredura Criptográfica XTS no Dispositivo: {device_path} (LBA: {start_sector}) ===")
    
    with open(device_path, 'rb') as f:
        data = f.read(1024 * 1024) # 1 MB sample
        
    num_sectors = len(data) // 512
    key_candidates = get_key_candidates()
    
    tweaks = {
        'zero': 0,
        'lba512': start_sector,
        'lba4k': start_sector // 8,
        'lba2x': start_sector * 2,
        'byte_off': start_sector * 512,
    }

    hits = 0
    total_tested = 0

    for kname, kbytes in key_candidates.items():
        for tname, base_tweak in tweaks.items():
            total_tested += 1
            for sec_idx in range(min(num_sectors, 64)):
                tweak_val = base_tweak + sec_idx
                tweak_bytes = tweak_val.to_bytes(16, 'little')
                
                try:
                    cipher = Cipher(algorithms.AES(kbytes), modes.XTS(tweak_bytes), backend=default_backend())
                    decryptor = cipher.decryptor()
                    sec_data = data[sec_idx*512 : (sec_idx+1)*512]
                    plain = decryptor.update(sec_data) + decryptor.finalize()
                    
                    off_le = plain.find(PFS_LE)
                    off_be = plain.find(PFS_BE)
                    
                    if off_le != -1 or off_be != -1:
                        endian = "LE" if off_le != -1 else "BE"
                        offset = off_le if off_le != -1 else off_be
                        magic_hex = plain[offset:offset+4].hex()
                        print(f"\n[🎉 HIT MAGNÍFICO!] Key={kname} Tweak={tname} ({tweak_val}) Sector={sec_idx} Magic={magic_hex} ({endian}) Offset={offset}")
                        print("   Primeiros 32 bytes do superbloco decriptado:", plain[:32].hex())
                        hits += 1
                except Exception:
                    pass

    print(f"\nVarredura concluída. Total de combinações testadas: {total_tested}. Hits encontrados: {hits}")

if __name__ == '__main__':
    dev = sys.argv[1] if len(sys.argv) > 1 else '/dev/sda27'
    lba = int(sys.argv[2]) if len(sys.argv) > 2 else 57147392
    test_device(dev, lba)
