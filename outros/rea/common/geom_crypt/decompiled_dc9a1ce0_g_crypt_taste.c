// Extraído via r2ghidra a partir de memoriateste.bin (kmem_dump_1252.bin)
// addr: 0xffffffffdc9a1ce0  name: g_crypt_taste
// arquivo fonte original Orbis: W:\Build\J02690760\sys\freebsd\sys\geom\geom_crypt.c
// papel: Função taste do GEOM_CRYPT — avalia cada partição no disk attach e inicializa a flag +0x70.

#include <stdint.h>
#include <stddef.h>

typedef uint64_t ulong;
typedef uint32_t uint32_t;
typedef uint64_t uint64_t;
typedef int64_t int64_t;

ulong * g_crypt_taste(int64_t *arg1, int64_t *arg2)
{
    int64_t iVar1;
    int iVar3;
    int64_t iVar4;
    uint64_t uVar5;
    ulong *unaff_RBX = (ulong *)arg2;
    ulong *puVar9;

    // Log de depuração do GEOM: "GEOM_CRYPT: g_crypt_taste"
    func_0xffffffffdc4ec700(1, "GEOM_CRYPT", "g_crypt_taste", *arg1, *arg2);

    if (0 < *(unaff_RBX + 0x2c)) {
        if (*(uint32_t *)0xffffffffdea14d10 == 0) {
            printf("GEOM_CRYPT[%u]: taste failed\n");
        } else {
            printf("GEOM_CRYPT[%u]: taste failed (quiet)\n");
        }
        return NULL;
    }

    // Criar instância geom e registrar callbacks de classe
    iVar4 = func_0xffffffffdc359520(0x78, (void *)0xffffffffddda5f20, 0x101);
    if (iVar4 == 0) return NULL;

    puVar9 = (ulong *)func_0xffffffffdc754b20();
    if (puVar9 == NULL) {
        func_0xffffffffdc3596e0(iVar4, (void *)0xffffffffddda5f20);
        return NULL;
    }

    // Callbacks do GEOM_CRYPT:
    puVar9[0x13] = iVar4;
    puVar9[9]  = 0xffffffffdc9a3750; // orphan / cleanup
    puVar9[0xe] = 0xffffffffdc9a3f80; // access
    puVar9[0xd] = 0xffffffffdc9a3fc0; // ioctl
    puVar9[0xc] = 0xffffffffdc9a4020; // start

    // Define mediasize e sectorsize
    iVar4 = func_0xffffffffdc755670(puVar9, (void *)0xffffffffdce3e7d6, *puVar9);
    *(iVar4 + 0x50) = *(unaff_RBX + 10);
    *(iVar4 + 0x48) = unaff_RBX[9];

    // Configuração das flags do provider (EAP key vs main key)
    if ((*(uint8_t *)(unaff_RBX + 0xe) & 1) != 0) {
        // Bit 31 (EAP key) ativado para partições de dados/sistema PS4
        *(uint32_t *)(iVar4 + 0x70) |= 0x80000000;
    }

    return puVar9;
}
