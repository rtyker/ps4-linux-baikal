// Extracted by PyGhidra (trace_partition_flag_origin.py)
// addr: 0x-00000002365c219  name: FUN_ffffffffdc9a3de7
// callers (0):
// callees (1):
//   FUN_ffffffffdc9a40d0 @ 0x-00000002365bf30


/* WARNING: Possible PIC construction at 0xffffffffdc69c61c: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xffffffffdc69c621) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc69c627) */

void FUN_ffffffffdc9a3de7(void)

{
  code *pcVar1;
  int iVar2;
  uint uVar3;
  long *plVar4;
  long lVar5;
  byte *pbVar6;
  byte *unaff_RBX;
  undefined8 *puVar7;
  undefined1 *puVar8;
  undefined8 *puVar9;
  long unaff_RBP;
  ulong uVar10;
  undefined *puVar11;
  undefined8 uVar12;
  uint uVar13;
  long *unaff_R13;
  ulong uVar14;
  long *unaff_R14;
  undefined8 *puVar15;
  undefined8 unaff_R15;
  long *in_GS_OFFSET;
  undefined *in_stack_00000028;
  byte *in_stack_00000030;
  byte *in_stack_00000038;
  undefined8 in_stack_00000040;
  long *in_stack_00000048;
  ulong in_stack_00000050;
  byte *in_stack_00000058;
  undefined1 *in_stack_00000060;
  
  lVar5 = FUN_ffffffffdc9a40d0();
  if (lVar5 == 0) {
    func_0xffffffffdc9a43f0();
    puVar15 = (undefined8 *)in_stack_00000058;
    uVar14 = in_stack_00000050;
    plVar4 = in_stack_00000048;
    uVar12 = in_stack_00000040;
    unaff_RBX[0x30] = 0xc;
    unaff_RBX[0x31] = 0;
    unaff_RBX[0x32] = 0;
    unaff_RBX[0x33] = 0;
    lVar5 = *unaff_R13;
    if (lVar5 != *(long *)(unaff_RBP + -0x30)) goto code_r0xffffffffdc9a3f6f;
    in_stack_00000058 = in_stack_00000038;
    pbVar6 = *(byte **)(unaff_RBX + 0xa8);
    if (*(int *)(pbVar6 + 0x30) == 0) {
      *(undefined4 *)(pbVar6 + 0x30) = *(undefined4 *)(unaff_RBX + 0x30);
    }
    *(long *)(pbVar6 + 0x98) = *(long *)(pbVar6 + 0x98) + *(long *)(unaff_RBX + 0x98);
    in_stack_00000048 = (long *)&UNK_ffffffffdc75610c;
    in_stack_00000050 = lVar5;
    func_0xffffffffdc69bc80();
    iVar2 = *(int *)(pbVar6 + 0xa4);
    in_stack_00000030 = (byte *)(ulong)*(uint *)(pbVar6 + 0xa0);
    *(uint *)(pbVar6 + 0xa4) = iVar2 + 1U;
    if (*(uint *)(pbVar6 + 0xa0) != iVar2 + 1U) {
      return;
    }
    uVar13 = *(uint *)(pbVar6 + 0x30);
    uVar10 = (ulong)uVar13;
    puVar9 = &stack0x00000060;
    in_stack_00000038 = in_stack_00000058;
    unaff_R14 = *(long **)(pbVar6 + 0x80);
    in_stack_00000040 = uVar12;
    in_stack_00000048 = plVar4;
    in_stack_00000050 = uVar14;
    in_stack_00000058 = (byte *)puVar15;
    if (unaff_R14 == (long *)0x0) {
      *(uint *)(pbVar6 + 0x30) = uVar13;
                    /* WARNING: Could not recover jumptable at 0xffffffffdc69c641. Too many branches
                        */
                    /* WARNING: Treating indirect jump as call */
      (**(code **)(pbVar6 + 0x40))();
      return;
    }
    puVar15 = *(undefined8 **)(pbVar6 + 0x88);
    func_0xffffffffdc4ec700
              (2,&UNK_ffffffffdcb2b1ca,pbVar6,unaff_R14,*(undefined8 *)*unaff_R14,puVar15);
    *(long *)(pbVar6 + 0x20) = *(long *)(pbVar6 + 0x90);
    *(long *)(pbVar6 + 0x38) = *(long *)(pbVar6 + 0x90) - *(long *)(pbVar6 + 0x98);
    in_stack_00000028 = &UNK_ffffffffdc69c581;
    in_stack_00000030 = pbVar6;
    func_0xffffffffdc6c8300(0xffffffffde59c628,0,&UNK_ffffffffdcb2b345,0x5a);
    uVar12 = 0xffffffffddda5f70;
    if ((uRamffffffffddda5f70 & 1) != 0) {
      in_stack_00000028 = &UNK_ffffffffdc69c59d;
      func_0xffffffffdc4d4420(puVar15[0xc],in_stack_00000030);
    }
    if ((uRamffffffffddda5f70 & 2) != 0) {
      in_stack_00000028 = &UNK_ffffffffdc69c5b2;
      func_0xffffffffdc4d4420(unaff_R14[8],in_stack_00000030);
    }
    *(int *)((long)unaff_R14 + 0x4c) = *(int *)((long)unaff_R14 + 0x4c) + 1;
    *(int *)((long)puVar15 + 0x6c) = *(int *)((long)puVar15 + 0x6c) + 1;
    if ((uVar13 != 0xc) && (uVar13 != 0x23)) {
      *(uint *)(in_stack_00000030 + 0x30) = uVar13;
      lVar5 = lRamffffffffde59c618;
      in_stack_00000030[0x68] = 0;
      in_stack_00000030[0x69] = 0;
      in_stack_00000030[0x6a] = 0;
      in_stack_00000030[0x6b] = 0;
      in_stack_00000030[0x6c] = 0;
      in_stack_00000030[0x6d] = 0;
      in_stack_00000030[0x6e] = 0;
      in_stack_00000030[0x6f] = 0;
      *(byte **)(in_stack_00000030 + 0x70) = pbRamffffffffde59c620;
      *(byte **)pbRamffffffffde59c620 = in_stack_00000030;
      pbRamffffffffde59c620 = in_stack_00000030 + 0x68;
      in_stack_00000030[1] = in_stack_00000030[1] | 4;
      iRamffffffffde59c648 = iRamffffffffde59c648 + 1;
      in_stack_00000028 = &UNK_ffffffffdc69c698;
      func_0xffffffffdc6c85b0(0xffffffffde59c628,0,&UNK_ffffffffdcb2b345,0x61);
      if (lVar5 != 0) {
        return;
      }
      uVar12 = 0xffffffffde61cec0;
      puVar7 = (undefined8 *)&stack0x00000068;
      pbVar6 = in_stack_00000038;
      puVar8 = in_stack_00000060;
      uVar14 = in_stack_00000050;
      goto code_r0xffffffffdc4902b0;
    }
    in_stack_00000028 = &UNK_ffffffffdc69c5e0;
    lVar5 = func_0xffffffffdc6c85b0(0xffffffffde59c628,0,&UNK_ffffffffdcb2b345,0x61);
    if ((uVar13 == 0xc) && (lVar5 = -0x22186240, iRamffffffffdde79dc0 != 0)) {
      in_stack_00000028 = &UNK_ffffffffdc69c60a;
      lVar5 = func_0xffffffffdc630420(&UNK_ffffffffdcb2b211,in_stack_00000030,puVar15,*puVar15);
    }
    in_stack_00000030[0xa0] = 0;
    in_stack_00000030[0xa1] = 0;
    in_stack_00000030[0xa2] = 0;
    in_stack_00000030[0xa3] = 0;
    in_stack_00000030[0xa4] = 0;
    in_stack_00000030[0xa5] = 0;
    in_stack_00000030[0xa6] = 0;
    in_stack_00000030[0xa7] = 0;
    puVar7 = &stack0x00000028;
    in_stack_00000028 = &UNK_ffffffffdc69c621;
    unaff_RBX = in_stack_00000030;
    plVar4 = unaff_R14;
  }
  else {
    *(undefined **)(unaff_RBX + 0x40) = &UNK_ffffffffdc9a4590;
    *(long *)(unaff_RBX + 0x48) = lVar5;
    *(undefined8 *)(unaff_RBX + 0x50) = *(undefined8 *)(unaff_RBX + 0x28);
    *(undefined8 *)(unaff_RBX + 0x28) = unaff_R15;
    unaff_RBX[1] = unaff_RBX[1] | 0x10;
    lVar5 = *unaff_R13;
    if (lVar5 != *(long *)(unaff_RBP + -0x30)) {
code_r0xffffffffdc9a3f6f:
      func_0xffffffffdca17ba0();
                    /* WARNING: Does not return */
      pcVar1 = (code *)invalidInstructionException();
      (*pcVar1)();
    }
    puVar7 = (undefined8 *)&stack0x00000068;
    pbVar6 = in_stack_00000038;
    puVar9 = (undefined8 *)in_stack_00000060;
    uVar12 = in_stack_00000040;
    plVar4 = in_stack_00000048;
    uVar10 = in_stack_00000050;
    puVar15 = (undefined8 *)in_stack_00000058;
  }
  *(undefined8 **)((long)puVar7 + -8) = puVar9;
  *(undefined8 **)((long)puVar7 + -0x10) = puVar15;
  *(ulong *)((long)puVar7 + -0x18) = uVar10;
  *(long **)((long)puVar7 + -0x20) = plVar4;
  *(undefined8 *)((long)puVar7 + -0x28) = uVar12;
  *(byte **)((long)puVar7 + -0x30) = pbVar6;
  *(long *)((long)puVar7 + -0x38) = lVar5;
  puVar15 = (undefined8 *)unaff_R14[3];
  if (puVar15 == (undefined8 *)0x0) {
    puVar11 = &UNK_ffffffffdcb2b147;
code_r0xffffffffdc69c0e7:
    *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c0ee;
    func_0xffffffffdc630420(puVar11);
    *(long **)(unaff_RBX + 0x80) = unaff_R14;
    unaff_RBX[0x88] = 0;
    unaff_RBX[0x89] = 0;
    unaff_RBX[0x8a] = 0;
    unaff_RBX[0x8b] = 0;
    unaff_RBX[0x8c] = 0;
    unaff_RBX[0x8d] = 0;
    unaff_RBX[0x8e] = 0;
    unaff_RBX[0x8f] = 0;
    unaff_RBX[0x30] = 6;
    unaff_RBX[0x31] = 0;
    unaff_RBX[0x32] = 0;
    unaff_RBX[0x33] = 0;
                    /* WARNING: Could not recover jumptable at 0xffffffffdc69c119. Too many branches
                        */
                    /* WARNING: Treating indirect jump as call */
    (**(code **)(unaff_RBX + 0x40))();
    return;
  }
  if ((undefined8 *)*unaff_R14 == (undefined8 *)0x4) {
    puVar11 = &UNK_ffffffffdcb2b16c;
    goto code_r0xffffffffdc69c0e7;
  }
  uVar12 = *(undefined8 *)*unaff_R14;
  *(ulong *)((long)puVar7 + -0x40) = (ulong)*unaff_RBX;
  *(undefined8 *)((long)puVar7 + -0x48) = *puVar15;
  *(undefined **)((long)puVar7 + -0x50) = &UNK_ffffffffdc69c08d;
  func_0xffffffffdc4ec700(2,&UNK_ffffffffdcb2b19d,unaff_RBX,unaff_R14,uVar12,puVar15);
  *(long **)(unaff_RBX + 0x80) = unaff_R14;
  *(undefined8 **)(unaff_RBX + 0x88) = puVar15;
  unaff_RBX[0x30] = 0;
  unaff_RBX[0x31] = 0;
  unaff_RBX[0x32] = 0;
  unaff_RBX[0x33] = 0;
  unaff_RBX[0x98] = 0;
  unaff_RBX[0x99] = 0;
  unaff_RBX[0x9a] = 0;
  unaff_RBX[0x9b] = 0;
  unaff_RBX[0x9c] = 0;
  unaff_RBX[0x9d] = 0;
  unaff_RBX[0x9e] = 0;
  unaff_RBX[0x9f] = 0;
  unaff_RBX[1] = unaff_RBX[1] | 4;
  pbVar6 = unaff_RBX + 0xb0;
  if (uRamffffffffddda5f70 == 0) {
    *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c124;
    func_0xffffffffdc69dc30(pbVar6);
  }
  else {
    *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c0d5;
    func_0xffffffffdc69d870(pbVar6);
  }
  *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c13e;
  func_0xffffffffdc6c8300(0xffffffffde59c5f0,0,&UNK_ffffffffdcb2b345,0x5a);
  if ((plRamffffffffdddaeef0 != (long *)0x0) && (*(long *)(unaff_RBX + 0xd0) == 0)) {
    *(byte **)((long)puVar7 + -0x38) = pbVar6;
    uVar13 = 0;
    plVar4 = plRamffffffffdddaeef0;
    do {
      lVar5 = plVar4[3];
      pcVar1 = (code *)plVar4[2];
      *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c16a;
      uVar3 = (*pcVar1)(lVar5,unaff_RBX);
      plVar4 = (long *)*plVar4;
      uVar13 = uVar13 | uVar3;
    } while (plVar4 != (long *)0x0);
    pbVar6 = *(byte **)((long)puVar7 + -0x38);
    if (uVar13 == 0) {
      unaff_RBX[0xd0] = 0xff;
      unaff_RBX[0xd1] = 0xff;
      unaff_RBX[0xd2] = 0xff;
      unaff_RBX[0xd3] = 0xff;
      unaff_RBX[0xd4] = 0xff;
      unaff_RBX[0xd5] = 0xff;
      unaff_RBX[0xd6] = 0xff;
      unaff_RBX[0xd7] = 0xff;
    }
  }
  if ((uRamffffffffddda5f70 & 1) != 0) {
    uVar12 = puVar15[0xc];
    *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c1a5;
    func_0xffffffffdc4d4180(uVar12,pbVar6);
  }
  if ((uRamffffffffddda5f70 & 2) != 0) {
    lVar5 = unaff_R14[8];
    *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c1ba;
    func_0xffffffffdc4d4180(lVar5,pbVar6);
  }
  *(int *)(puVar15 + 0xd) = *(int *)(puVar15 + 0xd) + 1;
  *(int *)(unaff_R14 + 9) = (int)unaff_R14[9] + 1;
  if (*(long *)(unaff_RBX + 0xa8) == 0) {
    if (*unaff_RBX == 2) {
      plVar4 = (long *)(*in_GS_OFFSET + 0x500);
    }
    else {
      if (*unaff_RBX != 1) goto code_r0xffffffffdc69c200;
      plVar4 = (long *)(*in_GS_OFFSET + 0x4f0);
    }
    *plVar4 = *plVar4 + 1;
    plVar4[1] = plVar4[1] + *(long *)(unaff_RBX + 0x90);
  }
code_r0xffffffffdc69c200:
  lVar5 = lRamffffffffde59c5e0;
  unaff_RBX[0x68] = 0;
  unaff_RBX[0x69] = 0;
  unaff_RBX[0x6a] = 0;
  unaff_RBX[0x6b] = 0;
  unaff_RBX[0x6c] = 0;
  unaff_RBX[0x6d] = 0;
  unaff_RBX[0x6e] = 0;
  unaff_RBX[0x6f] = 0;
  *(byte **)(unaff_RBX + 0x70) = pbRamffffffffde59c5e8;
  *(byte **)pbRamffffffffde59c5e8 = unaff_RBX;
  pbRamffffffffde59c5e8 = unaff_RBX + 0x68;
  iRamffffffffde59c610 = iRamffffffffde59c610 + 1;
  *(undefined **)((long)puVar7 + -0x40) = &UNK_ffffffffdc69c248;
  func_0xffffffffdc6c85b0(0xffffffffde59c5f0,0,&UNK_ffffffffdcb2b345,0x61);
  if (lVar5 != 0) {
    return;
  }
  uVar12 = 0xffffffffde61cec8;
  pbVar6 = *(byte **)((long)puVar7 + -0x30);
  puVar8 = *(undefined1 **)((long)puVar7 + -8);
  uVar14 = *(ulong *)((long)puVar7 + -0x18);
code_r0xffffffffdc4902b0:
  while( true ) {
    *(undefined1 **)((long)puVar7 + -8) = puVar8;
    *(ulong *)((long)puVar7 + -0x10) = uVar14;
    *(byte **)((long)puVar7 + -0x18) = pbVar6;
    *(undefined **)((long)puVar7 + -0x20) = &UNK_ffffffffdc4902bf;
    func_0xffffffffdc595650();
    *(undefined **)((long)puVar7 + -0x20) = &UNK_ffffffffdc4902cd;
    iVar2 = func_0xffffffffdc596560(uVar12,0,0,0);
    *(undefined **)((long)puVar7 + -0x20) = &UNK_ffffffffdc4902d8;
    func_0xffffffffdc5956e0(uVar12);
    if (iVar2 == 0) break;
    *(undefined8 *)((long)puVar7 + -8) = *(undefined8 *)((long)puVar7 + -8);
    uVar12 = 0xffffffffdde7a308;
    pbVar6 = *(byte **)((long)puVar7 + -0x18);
    puVar8 = *(undefined1 **)((long)puVar7 + -8);
    uVar14 = *(ulong *)((long)puVar7 + -0x10);
  }
  return;
}

