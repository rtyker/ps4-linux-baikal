// Extraído via r2ghidra a partir de memoriateste.bin (kmem_dump_1252.bin)
// addr: 0xffffffffdc9a40d0  name: g_crypt_create_provider
// arquivo fonte original Orbis: W:\Build\J02690760\sys\freebsd\sys\geom\geom_crypt.c
// papel: Função central do GEOM_CRYPT — inicializa o contexto de criptografia da partição HD.

#include <stdint.h>
#include <stddef.h>

typedef uint64_t ulong;
typedef uint32_t uint32_t;
typedef uint64_t uint64_t;
typedef int64_t int64_t;

ulong * g_crypt_create_provider(int64_t arg1, int64_t arg2, int64_t arg3)
{
    uint32_t uVar1;
    int64_t iVar2;
    uint32_t uVar4;
    ulong *puVar5;
    uint32_t *puVar6;
    uint64_t uVar7;
    
    // Obter contexto da estrutura do provider GEOM
    iVar2 = *(*(*(arg1 + 0x88) + 0x18) + 0x98);
    if ((iVar2 == 0) || (puVar5 = func_0xffffffffdc359520(0x38, 0xffffffffddda5f20, 0x101), puVar5 == NULL)) {
        return NULL;
    }
    puVar6 = func_0xffffffffdc359520(0xb8, 0xffffffffddda5f20, 0x101);
    if (puVar6 == NULL) {
        func_0xffffffffdc3596e0(puVar5, 0xffffffffddda5f20);
        return NULL;
    }
    puVar6[0x22] = 0;
    uVar4 = (arg2 != 0) << 0xc | 0x2000000;
    *puVar6 = uVar4;
    puVar6[2] = *(arg1 + 0x90) + 0x1ffU >> 9; // Tamanho em setores de 512B
    uVar7 = *(arg1 + 0x18) >> 9;              // Offset em setores
    *(puVar6 + 8) = uVar7;
    *(puVar6 + 8) = uVar7 + *(iVar2 + 0x20);  // Offset absoluto no disco

    iVar2 = *(*(*(*(arg1 + 0x88) + 0x18) + 0x20) + 0x18);
    if (iVar2 != 0) {
        // Seleção do algoritmo/chave por flags de tipo da partição EAP
        uVar1 = *(iVar2 + 0x70);
        
        if ((int32_t)uVar1 < 0) {
            // Bit 31 setado: EAP KEY (ERK/RIV)
            if (1 < *0xffffffffdea14d10) {
                printf("GEOM_CRYPT[%u]: applying eap key\n", 2);
            }
            // Copia 32 bytes de ERK do blob de chave EAP em 0xffffffffdea14cf0 (SCE_EAP_HDD__KEY)
            bcopy((void *)0xffffffffdea14cf0, (void *)(puVar6 + 10), 0x20);
        }
        else if ((uVar1 & 0x40000000) == 0) {
            if ((uVar1 & 0x20000000) == 0) {
                if ((uVar1 & 0x4000000) == 0) {
                    // MAIN KEY (ID 0x31)
                    if (1 < *0xffffffffdea14d10) {
                        printf("GEOM_CRYPT[%u]: applying main key\n", 2);
                    }
                    *puVar6 = uVar4 | 0x40000;
                    *(puVar6 + 10) = 0x31;
                }
                else {
                    // EXT KEY (ID 0x35)
                    if (1 < *0xffffffffdea14d10) {
                        printf("GEOM_CRYPT[%u]: applying ext key\n", 2);
                    }
                    *puVar6 = uVar4 | 0x40000;
                    *(puVar6 + 10) = 0x35;
                }
            }
            else {
                // MAIN KEY 2 (ID 0x32)
                if (1 < *0xffffffffdea14d10) {
                    printf("GEOM_CRYPT[%u]: applying main key 2\n", 2);
                }
                *puVar6 = uVar4 | 0x40000;
                *(puVar6 + 10) = 0x32;
            }
        }
        else {
            // XTS KEY (ID 0x30)
            if (1 < *0xffffffffdea14d10) {
                printf("GEOM_CRYPT[%u]: applying XTS\n", 2);
            }
            *puVar6 = uVar4 | 0x40000;
            *(puVar6 + 10) = 0x30;
        }

        puVar5[3] = arg1;
        puVar6[0x24] = 0;
        puVar6[0x25] = 0;
        *(puVar6 + 0x26) = puVar5;
        puVar5[2] = arg3;
        *puVar5 = puVar6;
        puVar5[1] = puVar6 + 0x24;
        return puVar5;
    }
    
    panic("geom_crypt error");
    return NULL;
}
