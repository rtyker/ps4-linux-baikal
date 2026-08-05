#!/usr/bin/env python3
import struct

DUMP_FILE = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/dumps_orbis/kmem_dump_1252.bin"
BADDR = 0xffffffffdc350000

# String offset known from RE_KERNEL_GBE_ATTACH.md
STRING_OFFSET = 0x7bdf60
STRING_VADDR = BADDR + STRING_OFFSET

print(f"Buscando referências para string SceGbeMtsCtrl (VADDR: {hex(STRING_VADDR)})")

PROBE_ADDR = 0xffffffffdc59ff50
print(f"Buscando referências para a função probe (VADDR: {hex(PROBE_ADDR)})")

ptr_bytes = struct.pack("<Q", PROBE_ADDR)

with open(DUMP_FILE, "rb") as f:
    data = f.read()

method_offsets = []
idx = 0
while True:
    idx = data.find(ptr_bytes, idx)
    if idx == -1:
        break
    method_offsets.append(idx)
    idx += 8

print(f"Encontrados {len(method_offsets)} ponteiros para a função probe: {[hex(x) for x in method_offsets]}")

# O ponteiro para a função attach deve estar dentro de uma device_method_t.
# device_method_t é: kobjop_desc_t *id (8 bytes), kobjop_t func (8 bytes).
# Então, o ponteiro da função (func) está no offset +8 da struct device_method_t.
# Vamos voltar e olhar o array de métodos ao redor desse ponto.

for m_off in method_offsets:
    # m_off é onde está o ponteiro da função.
    # O início do array de métodos pode ser um pouco antes.
    # Vamos assumir que a struct device_method_t começa em m_off - 8.
    array_start = m_off - 8
    
    # E vamos varrer pra cima e pra baixo pra mostrar os métodos (IDs e Funcs).
    print(f"\nExplorando vizinhança do offset {hex(array_start)}:")
    
    # Vamos varrer de array_start - 64 até array_start + 128
    for i in range(-4, 8):
        current_off = array_start + (i * 16)
        id_ptr, func_ptr = struct.unpack_from("<QQ", data, current_off)
        print(f"  Offset {hex(current_off)}: ID_DESC={hex(id_ptr)} -> FUNC={hex(func_ptr)}")
        
        # Tentar achar o nome do método
        if id_ptr >= BADDR and id_ptr < BADDR + len(data):
            desc_off = id_ptr - BADDR
            try:
                name_p = struct.unpack_from("<Q", data, desc_off + 16)[0]
                if name_p >= BADDR and name_p < BADDR + len(data):
                    name_off = name_p - BADDR
                    end_str = data.find(b'\x00', name_off)
                    if end_str != -1 and (end_str - name_off) < 30:
                        method_name = data[name_off:end_str].decode('ascii')
                        print(f"    -> Nome do método: {method_name}")
                        if "detach" in method_name or "shutdown" in method_name:
                            print(f"    ⭐⭐⭐ ALVO ENCONTRADO! {method_name} = {hex(func_ptr)}")
            except:
                pass


print(f"Encontrados {len(driver_offsets)} ponteiros para a string.")

for drv_off in driver_offsets:
    print(f"\nProvável driver_t struct em offset: {hex(drv_off)} (VADDR: {hex(BADDR + drv_off)})")
    
    # driver_t: 
    # const char *name; (8 bytes)
    # device_method_t *methods; (8 bytes)
    # size_t size; (8 bytes)
    
    name_ptr, methods_ptr, size = struct.unpack_from("<QQQ", data, drv_off)
    print(f"  name_ptr: {hex(name_ptr)}")
    print(f"  methods_ptr: {hex(methods_ptr)}")
    print(f"  softc_size: {hex(size)}")
    
    if methods_ptr >= BADDR and methods_ptr < BADDR + len(data):
        methods_off = methods_ptr - BADDR
        print(f"\nAnalisando device_method_t array em offset: {hex(methods_off)}")
        
        # device_method_t é uma struct de 16 bytes:
        # kobjop_desc_t *id; (8 bytes) - ponteiro para a descrição do método (ex: device_probe)
        # kobjop_t func; (8 bytes) - ponteiro para a função do driver (ex: mts_probe)
        
        m_idx = 0
        while True:
            id_ptr, func_ptr = struct.unpack_from("<QQ", data, methods_off + (m_idx * 16))
            if id_ptr == 0 and func_ptr == 0:
                break # Fim do array
                
            print(f"  Method {m_idx}: ID_DESC={hex(id_ptr)} -> FUNC={hex(func_ptr)}")
            
            # Tentar ler o nome do método a partir do kobjop_desc_t
            # kobjop_desc_t tem: int id (4), struct kobjop_desc *next (8)... e const char *name
            # No FreeBSD, kobjop_desc_t é:
            # unsigned int id; (4)
            # struct kobjop_desc *next; (8) mas alinhamento no amd64 coloca o next em offset 8
            # Na vdd: 
            # unsigned int id;
            # struct kobj_method *deflt;
            if id_ptr >= BADDR and id_ptr < BADDR + len(data):
                desc_off = id_ptr - BADDR
                # Lendo kobjop_desc_t (pode variar, vamos procurar um ponteiro de string nela)
                # Tentar offset 16 ou 24 pra achar o nome.
                # No FreeBSD 11:
                # unsigned int id; (0)
                # kobjop_t deflt; (8)
                # const char *name; (16)
                name_p = struct.unpack_from("<Q", data, desc_off + 16)[0]
                if name_p >= BADDR and name_p < BADDR + len(data):
                    name_off = name_p - BADDR
                    try:
                        end_str = data.find(b'\x00', name_off)
                        method_name = data[name_off:end_str].decode('ascii')
                        print(f"    -> Nome do método: {method_name}")
                        
                        if "detach" in method_name or "shutdown" in method_name or "suspend" in method_name:
                            print(f"    ⭐⭐⭐ ENCONTRADO ALVO: {method_name} = {hex(func_ptr)}")
                    except:
                        pass
            
            m_idx += 1
