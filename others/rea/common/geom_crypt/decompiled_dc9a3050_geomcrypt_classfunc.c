// GEOM_CRYPT struct g_class extra function pointer
// addr: 0xdc9a3050  entry: ffffffffdc9a3050  name: FUN_ffffffffdc9a3050


/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */

void FUN_ffffffffdc9a3050(void)

{
  code *pcVar1;
  int iVar2;
  undefined *puVar3;
  undefined8 uVar4;
  
  func_0xffffffffdc6c8d70(0xffffffffdea14d20,&UNK_ffffffffdce3e5b6,0,0);
  _DAT_ffffffffdea14d50 = 0;
  _DAT_ffffffffdea14d40 = 0;
  _DAT_ffffffffdea14d58 = &DAT_ffffffffdea14d50;
  _DAT_ffffffffdea14d48 = &DAT_ffffffffdea14d40;
  _DAT_ffffffffdea14d60 =
       func_0xffffffffdc59d3a0
                 (0x100000,0xffffffffdde4a8e0,1,0,0xffffffffffffffff,0x4000,0x1000000000000);
  if (_DAT_ffffffffdea14d60 == 0) {
    func_0xffffffffdcabbf00();
    func_0xffffffffdcabbe70(&LAB_ffffffffdc9a3143);
    puVar3 = &UNK_ffffffffdce3e5c8;
    uVar4 = 0x23;
  }
  else {
    _DAT_ffffffffdea14d68 =
         func_0xffffffffdc59d3a0
                   (0x100000,0xffffffffdde4a8e0,1,0,0xffffffffffffffff,0x4000,0x1000000000000);
    if (_DAT_ffffffffdea14d68 == 0) {
      func_0xffffffffdcabbf00();
      func_0xffffffffdcabbe70(&LAB_ffffffffdc9a3162);
      puVar3 = &UNK_ffffffffdce3e5ee;
      uVar4 = 0x27;
    }
    else {
      _DAT_ffffffffdea14d80 = &UNK_ffffffffdc9a35b0;
      _DAT_ffffffffdea14d88 = 0xffffffffdea14d70;
      iVar2 = func_0xffffffffdc496170();
      if (iVar2 == 0) {
        if (iRamffffffffdea14d10 == 0) {
          func_0xffffffffdc630420(&UNK_ffffffffdce3e660);
        }
        else {
          func_0xffffffffdc630420(&UNK_ffffffffdce3e641,0);
        }
        func_0xffffffffdc60d400(0xffffffffdea18000,0x70);
        iVar2 = func_0xffffffffdc5269e0(0xffffffffdea18000);
        if (iVar2 == 0) {
          iVar2 = func_0xffffffffdc9701f0(0xffffffffdea18000,0xffffffffdea14cf0);
          if (iVar2 == 0) {
            return;
          }
        }
        else if (iRamffffffffdea14d10 == 0) {
          func_0xffffffffdc630420(&UNK_ffffffffdce3e69d,iVar2);
        }
        else {
          func_0xffffffffdc630420(&UNK_ffffffffdce3e67b,0,iVar2);
        }
        func_0xffffffffdcabbf00();
        func_0xffffffffdcabbe70(&UNK_ffffffffdc9a372a);
        func_0xffffffffdc460780(0x1f,&UNK_ffffffffdce3e6bb);
                    /* WARNING: Does not return */
        pcVar1 = (code *)invalidInstructionException();
        (*pcVar1)();
      }
      func_0xffffffffdcabbf00();
      func_0xffffffffdcabbe70(&LAB_ffffffffdc9a3181);
      puVar3 = &UNK_ffffffffdce3e613;
      uVar4 = 0x2b;
    }
  }
  func_0xffffffffdc460780(uVar4,puVar3);
                    /* WARNING: Does not return */
  pcVar1 = (code *)invalidInstructionException();
  (*pcVar1)();
}

