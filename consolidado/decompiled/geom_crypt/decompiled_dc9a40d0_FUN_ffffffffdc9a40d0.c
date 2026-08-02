// Extracted by PyGhidra (trace_partition_flag_origin.py)
// addr: 0x-00000002365bf30  name: FUN_ffffffffdc9a40d0
// callers (0):
// callees (0):


/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */

undefined8 * FUN_ffffffffdc9a40d0(long param_1,int param_2,undefined8 param_3)

{
  uint uVar1;
  long lVar2;
  code *pcVar3;
  uint uVar4;
  undefined8 *puVar5;
  uint *puVar6;
  ulong uVar7;
  
  lVar2 = *(long *)(*(long *)(*(long *)(param_1 + 0x88) + 0x18) + 0x98);
  if ((lVar2 == 0) ||
     (puVar5 = (undefined8 *)func_0xffffffffdc359520(0x38,0xffffffffddda5f20,0x101),
     puVar5 == (undefined8 *)0x0)) {
    return (undefined8 *)0x0;
  }
  puVar6 = (uint *)func_0xffffffffdc359520(0xb8,0xffffffffddda5f20,0x101);
  if (puVar6 == (uint *)0x0) {
    func_0xffffffffdc3596e0(puVar5,0xffffffffddda5f20);
    return (undefined8 *)0x0;
  }
  puVar6[0x22] = 0;
  uVar4 = (uint)(param_2 != 0) << 0xc | 0x2000000;
  *puVar6 = uVar4;
  puVar6[2] = (uint)(*(long *)(param_1 + 0x90) + 0x1ffU >> 9);
  uVar7 = *(ulong *)(param_1 + 0x18) >> 9;
  *(ulong *)(puVar6 + 8) = uVar7;
  *(ulong *)(puVar6 + 8) = uVar7 + *(long *)(lVar2 + 0x20);
  lVar2 = *(long *)(*(long *)(*(long *)(*(long *)(param_1 + 0x88) + 0x18) + 0x20) + 0x18);
  if (lVar2 != 0) {
    uVar1 = *(uint *)(lVar2 + 0x70);
    if ((int)uVar1 < 0) {
      if (1 < _DAT_ffffffffdea14d10) {
        func_0xffffffffdc630420(&UNK_ffffffffdce3e9af,2);
      }
      func_0xffffffffdc60d4c0(puVar6 + 10,0xffffffffdea14cf0,0x20);
    }
    else if ((uVar1 & 0x40000000) == 0) {
      if ((uVar1 & 0x20000000) == 0) {
        if ((uVar1 & 0x4000000) == 0) {
          if (1 < _DAT_ffffffffdea14d10) {
            func_0xffffffffdc630420(&UNK_ffffffffdce3ea36,2);
            uVar4 = *puVar6;
          }
          *puVar6 = uVar4 | 0x40000;
          *(undefined2 *)(puVar6 + 10) = 0x31;
        }
        else {
          if (1 < _DAT_ffffffffdea14d10) {
            func_0xffffffffdc630420(&UNK_ffffffffdce3ea14,2);
            uVar4 = *puVar6;
          }
          *puVar6 = uVar4 | 0x40000;
          *(undefined2 *)(puVar6 + 10) = 0x35;
        }
      }
      else {
        if (1 < _DAT_ffffffffdea14d10) {
          func_0xffffffffdc630420(&UNK_ffffffffdce3e9ef,2);
          uVar4 = *puVar6;
        }
        *puVar6 = uVar4 | 0x40000;
        *(undefined2 *)(puVar6 + 10) = 0x32;
      }
    }
    else {
      if (1 < _DAT_ffffffffdea14d10) {
        func_0xffffffffdc630420(&UNK_ffffffffdce3e9d1,2);
        uVar4 = *puVar6;
      }
      *puVar6 = uVar4 | 0x40000;
      *(undefined2 *)(puVar6 + 10) = 0x30;
    }
    puVar5[3] = param_1;
    puVar6[0x24] = 0;
    puVar6[0x25] = 0;
    *(undefined8 **)(puVar6 + 0x26) = puVar5;
    puVar5[2] = param_3;
    *puVar5 = puVar6;
    puVar5[1] = puVar6 + 0x24;
    return puVar5;
  }
  func_0xffffffffdcabbf00();
  func_0xffffffffdcabbe70(&LAB_ffffffffdc9a4342);
  func_0xffffffffdc460780(0x1b,&UNK_ffffffffdce3e998);
                    /* WARNING: Does not return */
  pcVar3 = (code *)invalidInstructionException();
  (*pcVar3)();
}

