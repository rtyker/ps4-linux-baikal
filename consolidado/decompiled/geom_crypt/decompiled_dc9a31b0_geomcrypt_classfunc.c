// GEOM_CRYPT struct g_class extra function pointer
// addr: 0xdc9a31b0  entry: ffffffffdc9a31b0  name: FUN_ffffffffdc9a31b0


/* WARNING: Removing unreachable block (ram,0xffffffffdc9a3498) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a34ed) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a34a0) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a34fe) */

undefined8 FUN_ffffffffdc9a31b0(undefined8 param_1,undefined8 param_2,undefined8 *param_3)

{
  long lVar1;
  undefined8 *puVar2;
  code *pcVar3;
  int iVar4;
  undefined8 uVar5;
  undefined8 uStack_78;
  undefined8 uStack_70;
  undefined8 uStack_68;
  undefined8 uStack_60;
  undefined8 uStack_58;
  undefined8 uStack_50;
  undefined8 uStack_48;
  undefined8 uStack_40;
  long lStack_38;
  
  func_0xffffffffdc630420(&UNK_ffffffffdce3e44b,&UNK_ffffffffdce3e46d,*param_3,0);
  lStack_38 = lRamffffffffdeaacea0;
  lVar1 = param_3[0x13];
  if (lVar1 == 0) {
    uVar5 = 6;
  }
  else {
    if (*(int *)(lVar1 + 0x70) == 1) {
      uStack_40 = 0;
      uStack_48 = 0;
      uStack_50 = 0;
      uStack_58 = 0;
      uStack_60 = 0;
      uStack_68 = 0;
      uStack_70 = 0;
      uStack_78 = 0;
      iVar4 = func_0xffffffffdc9a5ec0(&uStack_78,0x40);
      if (iVar4 != 0) {
        func_0xffffffffdc630420(&UNK_ffffffffdce3e58e,&UNK_ffffffffdce3e59f,iVar4);
      }
    }
    puVar2 = (undefined8 *)param_3[5];
    if (puVar2 != (undefined8 *)0x0) {
      if (((*(int *)(puVar2 + 5) != 0) || (*(int *)((long)puVar2 + 0x2c) != 0)) ||
         (*(int *)(puVar2 + 6) != 0)) {
        uVar5 = 0x10;
        if (iRamffffffffdea14d10 != 0) {
          func_0xffffffffdc630420
                    (&UNK_ffffffffdce3e50c,1,*puVar2,*(int *)(puVar2 + 5),
                     *(undefined4 *)((long)puVar2 + 0x2c),*(undefined4 *)(puVar2 + 6));
        }
        goto code_r0xffffffffdc9a358b;
      }
      if ((*(byte *)((long)puVar2 + 0x73) & 4) != 0) {
        if (iRamffffffffdea14d10 == 0) {
          func_0xffffffffdc630420(&UNK_ffffffffdce3e566,*param_3);
        }
        else {
          func_0xffffffffdc630420(&UNK_ffffffffdce3e542,0);
        }
      }
    }
    func_0xffffffffdc6c8de0(lVar1 + 0x28);
    func_0xffffffffdc3596e0(lVar1,0xffffffffddda5f20);
    param_3[0x13] = 0;
    func_0xffffffffdc754ed0(param_3,6);
    uVar5 = 0;
  }
code_r0xffffffffdc9a358b:
  if (lRamffffffffdeaacea0 == lStack_38) {
    return uVar5;
  }
  func_0xffffffffdca17ba0();
                    /* WARNING: Does not return */
  pcVar3 = (code *)invalidInstructionException();
  (*pcVar3)();
}

