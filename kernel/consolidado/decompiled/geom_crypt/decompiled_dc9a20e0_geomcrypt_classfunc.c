// GEOM_CRYPT struct g_class extra function pointer
// addr: 0xdc9a20e0  entry: ffffffffdc9a20e0  name: FUN_ffffffffdc9a20e0


/* WARNING: Possible PIC construction at 0xffffffffdc9a2b08: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2c2f: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2c87: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2a91: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2bd5: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2fa0: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2b90: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2b43: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2f6e: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2d01: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2f41: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2ebc: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2e99: Changing call to branch */
/* WARNING: Possible PIC construction at 0xffffffffdc9a2590: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2e9e) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2ec1) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2f73) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2f46) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2b48) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2fa5) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2bda) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2a96) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2c34) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2b0d) */
/* WARNING: Removing unreachable block (ram,0xffffffffdc9a2595) */

ulong FUN_ffffffffdc9a20e0
                (long *param_1,long *param_2,long *param_3,long *param_4,undefined *param_5,
                undefined8 param_6)

{
  uint uVar1;
  code *pcVar2;
  int iVar3;
  int iVar4;
  ulong uVar5;
  undefined8 uVar6;
  uint *puVar7;
  undefined4 *puVar8;
  long *plVar9;
  long lVar10;
  undefined8 *puVar11;
  undefined8 *puVar12;
  long lVar13;
  long *extraout_RDX;
  ulong extraout_RDX_00;
  long *unaff_RBX;
  undefined1 *puVar14;
  undefined1 *puVar27;
  undefined1 *unaff_RBP;
  undefined *puVar28;
  uint uVar29;
  long *plVar30;
  long *plVar31;
  undefined4 uVar32;
  long *unaff_R14;
  long *unaff_R15;
  undefined8 *in_GS_OFFSET;
  undefined1 auVar33 [16];
  undefined *puStack_120;
  long *plStack_118;
  long lStack_110;
  long lStack_108;
  uint *puStack_100;
  undefined8 *puStack_f8;
  long lStack_f0;
  undefined4 *puStack_e8;
  long *plStack_e0;
  long *plStack_d8;
  uint uStack_cc;
  long alStack_c8 [2];
  undefined1 auStack_b8 [64];
  undefined8 uStack_78;
  undefined8 uStack_70;
  undefined8 uStack_68;
  undefined8 uStack_60;
  undefined8 uStack_58;
  undefined8 uStack_50;
  undefined8 uStack_48;
  undefined8 uStack_40;
  ulong uStack_38;
  undefined1 *puVar15;
  undefined1 *puVar16;
  undefined1 *puVar17;
  undefined1 *puVar18;
  undefined1 *puVar19;
  undefined1 *puVar20;
  undefined1 *puVar21;
  undefined1 *puVar22;
  undefined1 *puVar23;
  undefined1 *puVar24;
  undefined1 *puVar25;
  undefined1 *puVar26;
  
  puVar14 = &stack0xfffffffffffffff8;
  puVar15 = &stack0xfffffffffffffff8;
  puVar16 = &stack0xfffffffffffffff8;
  puVar17 = &stack0xfffffffffffffff8;
  puVar18 = &stack0xfffffffffffffff8;
  puVar19 = &stack0xfffffffffffffff8;
  puVar20 = &stack0xfffffffffffffff8;
  puVar21 = &stack0xfffffffffffffff8;
  puVar22 = &stack0xfffffffffffffff8;
  puVar23 = &stack0xfffffffffffffff8;
  puVar24 = &stack0xfffffffffffffff8;
  puVar25 = &stack0xfffffffffffffff8;
  puVar26 = &stack0xfffffffffffffff8;
  puVar27 = &stack0xfffffffffffffff8;
  uStack_38 = uRamffffffffdeaacea0;
  puStack_120 = (undefined *)0xffffffffdc9a211f;
  plStack_e0 = param_2;
  iVar3 = func_0xffffffffdc402940(param_3,&UNK_ffffffffdce3edac);
  if (iVar3 == 0) {
    puStack_120 = &UNK_ffffffffdc9a21c7;
    auVar33 = func_0xffffffffdc75abc0(param_1,&UNK_ffffffffdce3ede3,4);
    plVar9 = auVar33._8_8_;
    param_3 = auVar33._0_8_;
    if (param_3 == (long *)0x0) {
      puStack_120 = &UNK_ffffffffdc9a2460;
      func_0xffffffffdc75a780(param_1,&UNK_ffffffffdce3ede9,&UNK_ffffffffdce3ede3);
      iVar3 = 0x16;
    }
    else {
      if ((int)*param_3 < 1) {
        puVar28 = &UNK_ffffffffdce3edfa;
        register0x00000020 = (BADSPACEBASE *)&puStack_120;
        puStack_120 = &UNK_ffffffffdc9a2595;
        unaff_R14 = param_1;
        goto code_r0xffffffffdc75a780;
      }
      puStack_120 = &UNK_ffffffffdc9a21f2;
      puVar7 = (uint *)func_0xffffffffdc75aa10(param_1,&UNK_ffffffffdce3ee0d,&uStack_cc);
      if (puVar7 != (uint *)0x0) {
        if (uStack_cc == 4) {
          if (0x1ff < *puVar7) goto code_r0xffffffffdc9a25a0;
          puVar28 = &UNK_ffffffffdce3ee3c;
          param_4 = (long *)0x200;
          uStack_cc = *puVar7;
        }
        else {
          puVar28 = &UNK_ffffffffdce3ee15;
          param_4 = (long *)0x4;
        }
        plVar9 = (long *)(ulong)uStack_cc;
        register0x00000020 = (BADSPACEBASE *)&puStack_120;
        puStack_120 = &UNK_ffffffffdc9a2b48;
        puVar27 = puVar21;
        unaff_R14 = param_1;
code_r0xffffffffdc75a780:
        *(undefined1 **)((long)register0x00000020 + -8) = puVar27;
        *(long **)((long)register0x00000020 + -0x10) = unaff_R15;
        *(long **)((long)register0x00000020 + -0x18) = unaff_R14;
        *(long **)((long)register0x00000020 + -0x20) = param_3;
        *(long **)((long)register0x00000020 + -0x68) = plVar9;
        *(long **)((long)register0x00000020 + -0x60) = param_4;
        *(undefined **)((long)register0x00000020 + -0x58) = param_5;
        *(undefined8 *)((long)register0x00000020 + -0x50) = param_6;
        *(ulong *)((long)register0x00000020 + -0x28) = uRamffffffffdeaacea0;
        if (param_1 == (long *)0x0) {
          uVar5 = 0x16;
        }
        else {
          lVar10 = param_1[7];
          *(undefined **)((long)register0x00000020 + -0x80) = &UNK_ffffffffdc75a7bf;
          iVar3 = func_0xffffffffdc397ff0(lVar10);
          uVar29 = *(uint *)(param_1 + 6);
          uVar5 = (ulong)uVar29;
          if (iVar3 == 0) {
            if (uVar29 == 0) {
              *(int *)(param_1 + 6) = 0x16;
            }
            *(undefined1 **)((long)register0x00000020 + -0x38) =
                 (undefined1 *)((long)register0x00000020 + -0x78);
            *(undefined1 **)((long)register0x00000020 + -0x40) =
                 (undefined1 *)((long)register0x00000020 + 8);
            *(undefined8 *)((long)register0x00000020 + -0x48) = 0x3000000010;
            lVar10 = param_1[7];
            *(undefined **)((long)register0x00000020 + -0x80) = &UNK_ffffffffdc75a81c;
            func_0xffffffffdc397ca0(lVar10,puVar28,(undefined1 *)((long)register0x00000020 + -0x48))
            ;
            lVar10 = param_1[7];
            *(undefined **)((long)register0x00000020 + -0x80) = &UNK_ffffffffdc75a825;
            func_0xffffffffdc397f30(lVar10);
            if (cRamffffffffde583598 < '\0') {
              lVar10 = param_1[7];
              *(undefined **)((long)register0x00000020 + -0x80) = &UNK_ffffffffdc75a83a;
              uVar6 = func_0xffffffffdc397fc0(lVar10);
              *(undefined **)((long)register0x00000020 + -0x80) = &UNK_ffffffffdc75a84e;
              func_0xffffffffdc630420(&UNK_ffffffffdcb46760,param_1,uVar6);
            }
            uVar5 = (ulong)*(uint *)(param_1 + 6);
          }
          else if (uVar29 == 0) {
            *(int *)(param_1 + 6) = 0x11;
            uVar5 = 0x11;
          }
        }
        if (uRamffffffffdeaacea0 != *(ulong *)((long)register0x00000020 + -0x28)) {
          *(undefined **)((long)register0x00000020 + -0x80) = &UNK_ffffffffdc75a86a;
          func_0xffffffffdca17ba0();
                    /* WARNING: Does not return */
          pcVar2 = (code *)invalidInstructionException();
          (*pcVar2)();
        }
        return uVar5;
      }
code_r0xffffffffdc9a25a0:
      if ((int)*param_3 < 1) {
        iVar3 = 0;
      }
      else {
        param_4 = (long *)0x0;
        plStack_118 = param_3;
        puStack_100 = puVar7;
        do {
          puStack_e8 = (undefined4 *)CONCAT44(puStack_e8._4_4_,(int)param_4);
          puStack_120 = &UNK_ffffffffdc9a25dc;
          func_0xffffffffdc630720(alStack_c8,0x10,&UNK_ffffffffdce3ee53);
          puStack_120 = &UNK_ffffffffdc9a25e7;
          plVar9 = (long *)func_0xffffffffdc75aad0(param_1,alStack_c8);
          if (plVar9 == (long *)0x0) {
            puStack_120 = &UNK_ffffffffdc9a2e60;
            func_0xffffffffdc75a780(param_1,&UNK_ffffffffdce3ee59,(ulong)puStack_e8 & 0xffffffff);
            iVar3 = 0x16;
            break;
          }
          puStack_120 = &UNK_ffffffffdc9a2602;
          uVar6 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
          puStack_120 = &UNK_ffffffffdc9a2610;
          iVar3 = func_0xffffffffdc716350(plVar9,&UNK_ffffffffdce3ee6d,uVar6);
          if (iVar3 == 0) {
            puStack_120 = &UNK_ffffffffdc9a2620;
            lVar10 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
            plVar9 = (long *)((long)plVar9 + lVar10);
          }
          puStack_120 = &UNK_ffffffffdc9a262b;
          puVar11 = (undefined8 *)func_0xffffffffdc755930(plVar9);
          puVar8 = puStack_e8;
          param_3 = alStack_c8;
          unaff_R14 = param_1;
          if (puVar11 == (undefined8 *)0x0) {
            if (uRamffffffffdea14d10 != 0) {
              puStack_120 = &UNK_ffffffffdc9a2e8a;
              func_0xffffffffdc630420(&UNK_ffffffffdce3ee73,1,plVar9);
            }
            puVar28 = &UNK_ffffffffdce3ee9c;
            register0x00000020 = (BADSPACEBASE *)&puStack_120;
            puStack_120 = &UNK_ffffffffdc9a2e9e;
            puVar27 = puVar26;
            unaff_R15 = plVar9;
            goto code_r0xffffffffdc75a780;
          }
          puStack_120 = &UNK_ffffffffdc9a265e;
          func_0xffffffffdc630720(param_3,0x10,&UNK_ffffffffdce3eeb4,(ulong)puStack_e8 & 0xffffffff)
          ;
          puStack_120 = &UNK_ffffffffdc9a2669;
          unaff_R15 = (long *)func_0xffffffffdc75aad0(param_1,param_3);
          puStack_120 = &UNK_ffffffffdc9a2685;
          func_0xffffffffdc630720(param_3,0x10,&UNK_ffffffffdce3eec1,(ulong)puVar8 & 0xffffffff);
          puStack_120 = &UNK_ffffffffdc9a2697;
          auVar33 = func_0xffffffffdc75aa10(param_1,param_3,&uStack_cc);
          puVar7 = puStack_100;
          lVar10 = auVar33._0_8_;
          if (lVar10 == 0) {
            if (puStack_100 != (uint *)0x0) goto code_r0xffffffffdc9a26c9;
code_r0xffffffffdc9a26f7:
            uVar1 = *(uint *)(puVar11 + 10);
code_r0xffffffffdc9a26ff:
            param_4 = (long *)(ulong)uVar1;
          }
          else {
            uVar5 = (ulong)uStack_cc;
            if (uStack_cc != 0x10) {
              puStack_120 = &UNK_ffffffffdc9a26c2;
              func_0xffffffffdc630420(&UNK_ffffffffdce3eece,param_3);
              lVar10 = 0;
              uVar5 = extraout_RDX_00;
            }
            auVar33._8_8_ = uVar5;
            auVar33._0_8_ = lVar10;
            if (puVar7 == (uint *)0x0) goto code_r0xffffffffdc9a26f7;
code_r0xffffffffdc9a26c9:
            uVar6 = auVar33._0_8_;
            uVar29 = *puVar7;
            param_4 = (long *)(ulong)uVar29;
            uVar1 = *(uint *)(puVar11 + 10);
            if (uVar29 == 0) goto code_r0xffffffffdc9a26ff;
            auVar33._8_8_ = (ulong)param_4 % (ulong)uVar1;
            auVar33._0_8_ = uVar6;
            if ((int)((ulong)param_4 % (ulong)uVar1) != 0) {
              plVar9 = (long *)*puVar11;
              puVar28 = &UNK_ffffffffdce3eee7;
              register0x00000020 = (BADSPACEBASE *)&puStack_120;
              puStack_120 = &UNK_ffffffffdc9a2f73;
              puVar27 = puVar22;
              goto code_r0xffffffffdc75a780;
            }
          }
          plVar9 = auVar33._8_8_;
          if (0x20000 < (uint)param_4) {
            puVar28 = &UNK_ffffffffdce3ef08;
            register0x00000020 = (BADSPACEBASE *)&puStack_120;
            puStack_120 = &UNK_ffffffffdc9a2ec1;
            puVar27 = puVar25;
            goto code_r0xffffffffdc75a780;
          }
          param_5 = &UNK_ffffffffdce3e7c4;
          puStack_120 = &UNK_ffffffffdc9a2753;
          lStack_108 = auVar33._0_8_;
          func_0xffffffffdc630720(auStack_b8,0x40,&UNK_ffffffffdce3e7bf);
          for (param_3 = (long *)plStack_e0[0x14]; param_3 != (long *)0x0;
              param_3 = (long *)param_3[2]) {
            puStack_120 = &UNK_ffffffffdc9a2784;
            iVar3 = func_0xffffffffdc402940(*param_3,auStack_b8);
            if (iVar3 == 0) {
              puStack_120 = &UNK_ffffffffdc9a2cb0;
              func_0xffffffffdc75a780(param_1,&UNK_ffffffffdce3ef1c,auStack_b8);
              iVar3 = 0x11;
              goto code_r0xffffffffdc9a2d13;
            }
            if ((*(undefined8 **)(param_3[4] + 0x18) != (undefined8 *)0x0) &&
               (*(undefined8 **)(param_3[4] + 0x18) == puVar11)) {
              plVar9 = (long *)*puVar11;
              param_4 = (long *)*param_3;
              puVar28 = &UNK_ffffffffdce3ef38;
              register0x00000020 = (BADSPACEBASE *)&puStack_120;
              puStack_120 = &UNK_ffffffffdc9a2d06;
              puVar27 = puVar23;
              goto code_r0xffffffffdc75a780;
            }
          }
          puStack_120 = &UNK_ffffffffdc9a27b9;
          lStack_f0 = func_0xffffffffdc359520(0x78,0xffffffffddda5f20,0x101);
          iVar3 = 0xc;
          if (lStack_f0 == 0) break;
          puStack_120 = &UNK_ffffffffdc9a27f1;
          plStack_d8 = param_1;
          puVar12 = (undefined8 *)
                    func_0xffffffffdc754b20(plStack_e0,&UNK_ffffffffdce3e7d6,auStack_b8);
          lVar10 = lStack_f0;
          if (puVar12 == (undefined8 *)0x0) {
            puStack_120 = &UNK_ffffffffdc9a2f17;
            func_0xffffffffdc3596e0(lStack_f0,0xffffffffddda5f20);
            param_1 = plStack_d8;
            break;
          }
          param_4 = (long *)0x0;
          lStack_110 = lStack_f0 + 0x28;
          puStack_120 = &UNK_ffffffffdc9a2820;
          func_0xffffffffdc6c8d70(lStack_110,&UNK_ffffffffdce3e89e,0);
          puVar12[0x13] = lVar10;
          puVar12[9] = &UNK_ffffffffdc9a3750;
          puVar12[0xe] = &UNK_ffffffffdc9a3f80;
          puVar12[0xd] = &UNK_ffffffffdc9a3fc0;
          puVar12[0xc] = &UNK_ffffffffdc9a4020;
          puStack_120 = &UNK_ffffffffdc9a2863;
          unaff_R14 = (long *)func_0xffffffffdc755670(puVar12,&UNK_ffffffffdce3e7d6,*puVar12);
          *(int *)(unaff_R14 + 10) = *(int *)(puVar11 + 10);
          unaff_R14[9] = puVar11[9];
          if (1 < uRamffffffffdea14d10) {
            puStack_120 = &UNK_ffffffffdc9a2891;
            func_0xffffffffdc630420(&UNK_ffffffffdce3e7d9,2);
            if (1 < uRamffffffffdea14d10) {
              puStack_120 = &UNK_ffffffffdc9a28b1;
              func_0xffffffffdc630420(&UNK_ffffffffdce3e7f9,2,unaff_R14[9]);
            }
          }
          *(undefined4 *)(lVar10 + 0x70) = 0;
          puStack_f8 = puVar12;
          if (lStack_108 != 0) {
            puStack_120 = &UNK_ffffffffdc9a28e2;
            iVar3 = func_0xffffffffdc4b4390(*in_GS_OFFSET,0x2ab);
            if (iVar3 != 0) {
              if (lRam0000000000000018 != 0) {
                puStack_120 = &UNK_ffffffffdc9a2fc5;
                func_0xffffffffdc755440(0);
              }
              puStack_120 = &UNK_ffffffffdc9a2fcd;
              func_0xffffffffdc755520(0);
              puStack_120 = &UNK_ffffffffdc9a2fd5;
              func_0xffffffffdc755340(unaff_R14);
              puStack_120 = &UNK_ffffffffdc9a2fe1;
              func_0xffffffffdc6c8de0(lStack_110);
              puStack_120 = &UNK_ffffffffdc9a2ff4;
              func_0xffffffffdc3596e0(lStack_f0,0xffffffffddda5f20);
              puStack_120 = &UNK_ffffffffdc9a3000;
              func_0xffffffffdc754cf0(puStack_f8);
              param_1 = plStack_d8;
              break;
            }
            *(byte *)((long)unaff_R14 + 0x73) = *(byte *)((long)unaff_R14 + 0x73) | 4;
            *(byte *)((long)puVar11 + 0x73) = *(byte *)((long)puVar11 + 0x73) | 4;
            puStack_120 = &UNK_ffffffffdc9a2908;
            func_0xffffffffdc60d400(lVar10 + 0x50,0x20);
            puStack_120 = &UNK_ffffffffdc9a291c;
            func_0xffffffffdc60d4c0(lVar10 + 0x50,lStack_108,0x10);
            *(undefined4 *)(lVar10 + 0x70) = 1;
            param_4 = (long *)*puVar11;
            uStack_40 = 0;
            uStack_48 = 0;
            uStack_50 = 0;
            uStack_58 = 0;
            uStack_60 = 0;
            uStack_68 = 0;
            uStack_70 = 0;
            uStack_78 = 0;
            if (param_4 != (long *)0x0) {
              puStack_120 = &UNK_ffffffffdc9a2988;
              func_0xffffffffdc630720(&uStack_78,0x3f,&UNK_ffffffffdce3e586);
            }
            puStack_120 = &UNK_ffffffffdc9a2995;
            iVar3 = func_0xffffffffdc9a5ec0(&uStack_78,0x40);
            if (iVar3 != 0) {
              puStack_120 = &UNK_ffffffffdc9a29b0;
              func_0xffffffffdc630420(&UNK_ffffffffdce3e58e,&UNK_ffffffffdce3e59f,iVar3);
            }
          }
          if ((*(byte *)(puVar11 + 0xe) & 1) != 0) {
            *(byte *)(unaff_R14 + 0xe) = *(byte *)(unaff_R14 + 0xe) | 1;
          }
          puStack_120 = &UNK_ffffffffdc9a29c8;
          param_3 = (long *)func_0xffffffffdc755600(puStack_f8);
          puStack_120 = &UNK_ffffffffdc9a29d6;
          uVar29 = func_0xffffffffdc755b00(param_3,puVar11);
          if (uVar29 != 0) {
            plVar9 = (long *)*puVar11;
            puVar28 = &UNK_ffffffffdce3ef54;
            register0x00000020 = (BADSPACEBASE *)&puStack_120;
            puStack_120 = &UNK_ffffffffdc9a2f46;
            puVar27 = puVar24;
            param_1 = plStack_d8;
            unaff_R15 = (long *)(ulong)uVar29;
            goto code_r0xffffffffdc75a780;
          }
          puStack_120 = &UNK_ffffffffdc9a29e8;
          func_0xffffffffdc7558f0(unaff_R14,0);
          plVar30 = plStack_118;
          if ((*(byte *)((long)puVar11 + 0x73) & 4) != 0) {
            lVar10 = unaff_R14[9];
            lVar13 = lVar10 + 0xfffff;
            if (-1 < lVar10) {
              lVar13 = lVar10;
            }
            param_5 = (undefined *)(lVar13 >> 0x14);
            if (uRamffffffffdea14d10 == 0) {
              puStack_120 = &UNK_ffffffffdc9a2a5c;
              func_0xffffffffdc630420(&UNK_ffffffffdce3e875,*puStack_f8,(int)unaff_R14[10],param_5);
            }
            else {
              puStack_120 = &UNK_ffffffffdc9a2a44;
              func_0xffffffffdc630420(&UNK_ffffffffdce3e848,0);
            }
          }
          iVar3 = 0;
          param_4 = (long *)(ulong)((int)puStack_e8 + 1U);
          param_1 = plStack_d8;
        } while ((int)((int)puStack_e8 + 1U) < (int)*plVar30);
      }
    }
code_r0xffffffffdc9a2d13:
    uStack_78 = CONCAT44(uStack_78._4_4_,iVar3);
code_r0xffffffffdc9a2d25:
    puStack_120 = &UNK_ffffffffdc9a2d2f;
    func_0xffffffffdc75a870(param_1,&UNK_ffffffffdce3ef72,&uStack_78,4);
  }
  else {
    puStack_120 = (undefined *)0xffffffffdc9a2136;
    iVar3 = func_0xffffffffdc402940(param_3,&UNK_ffffffffdce3edb3);
    if (iVar3 == 0) {
      puStack_120 = &UNK_ffffffffdc9a223d;
      auVar33 = func_0xffffffffdc75abc0(param_1,&UNK_ffffffffdce3ede3,4);
      plVar30 = auVar33._0_8_;
      if (plVar30 == (long *)0x0) {
code_r0xffffffffdc9a256e:
        puVar28 = &UNK_ffffffffdce3ede9;
        plVar9 = (long *)&UNK_ffffffffdce3ede3;
        unaff_R14 = param_1;
        plVar30 = unaff_R15;
code_r0xffffffffdc9a2c85:
        register0x00000020 = (BADSPACEBASE *)&puStack_120;
        puStack_120 = &UNK_ffffffffdc9a2c8c;
        puVar27 = puVar16;
        unaff_R15 = plVar30;
        goto code_r0xffffffffdc75a780;
      }
      if ((int)*plVar30 < 1) {
code_r0xffffffffdc9a2a85:
        plVar9 = auVar33._8_8_;
        puVar28 = &UNK_ffffffffdce3edfa;
        register0x00000020 = (BADSPACEBASE *)&puStack_120;
        puStack_120 = &UNK_ffffffffdc9a2a96;
        puVar27 = puVar17;
        unaff_R14 = param_1;
        unaff_R15 = auVar33._0_8_;
        goto code_r0xffffffffdc75a780;
      }
      param_3 = (long *)0x0;
      do {
        puStack_120 = &UNK_ffffffffdc9a227f;
        param_4 = param_3;
        func_0xffffffffdc630720(alStack_c8,0x10,&UNK_ffffffffdce3ee53);
        puStack_120 = &UNK_ffffffffdc9a228d;
        plVar9 = (long *)func_0xffffffffdc75aad0(param_1,alStack_c8);
        if (plVar9 == (long *)0x0) goto code_r0xffffffffdc9a2d60;
        puStack_120 = &UNK_ffffffffdc9a22a8;
        uVar6 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
        puStack_120 = &UNK_ffffffffdc9a22b6;
        iVar3 = func_0xffffffffdc716350(plVar9,&UNK_ffffffffdce3ee6d,uVar6);
        if (iVar3 == 0) {
          puStack_120 = &UNK_ffffffffdc9a22c6;
          lVar10 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
          plVar9 = (long *)((long)plVar9 + lVar10);
        }
        puStack_120 = &UNK_ffffffffdc9a22d1;
        lVar10 = func_0xffffffffdc755930(plVar9);
        if ((lVar10 == 0) ||
           (param_4 = plStack_e0, *(long **)(*(long *)(lVar10 + 0x18) + 8) != plStack_e0)) {
          if (uRamffffffffdea14d10 != 0) {
            puStack_120 = &UNK_ffffffffdc9a2b72;
            func_0xffffffffdc630420(&UNK_ffffffffdce3ee73,1,plVar9);
          }
          puVar28 = &UNK_ffffffffdce3ee9c;
          unaff_R14 = plVar9;
          goto code_r0xffffffffdc9a2c85;
        }
        uVar29 = (int)param_3 + 1;
        param_3 = (long *)(ulong)uVar29;
      } while ((int)uVar29 < (int)*plVar30);
    }
    else {
      puStack_120 = (undefined *)0xffffffffdc9a214d;
      iVar3 = func_0xffffffffdc402940(param_3,&UNK_ffffffffdce3edbd);
      if (iVar3 == 0) {
        puStack_120 = &UNK_ffffffffdc9a2316;
        auVar33 = func_0xffffffffdc75abc0(param_1,&UNK_ffffffffdce3ede3,4);
        plVar9 = auVar33._8_8_;
        unaff_R15 = auVar33._0_8_;
        if (unaff_R15 == (long *)0x0) {
          puStack_120 = &UNK_ffffffffdc9a2b30;
          func_0xffffffffdc75a780(param_1,&UNK_ffffffffdce3ede9,&UNK_ffffffffdce3ede3);
          uVar32 = 0x16;
          plVar30 = param_1;
        }
        else {
          if ((int)*unaff_R15 < 1) {
            puVar28 = &UNK_ffffffffdce3edfa;
            register0x00000020 = (BADSPACEBASE *)&puStack_120;
            puStack_120 = &UNK_ffffffffdc9a2b95;
            puVar27 = puVar20;
            unaff_R14 = param_1;
            goto code_r0xffffffffdc75a780;
          }
          puStack_120 = &UNK_ffffffffdc9a2346;
          plStack_d8 = param_1;
          puVar8 = (undefined4 *)func_0xffffffffdc75abc0(param_1,&UNK_ffffffffdce3ef78,4);
          if ((int)*unaff_R15 < 1) {
            uVar32 = 0;
            plVar30 = plStack_d8;
          }
          else {
            plVar31 = (long *)0x0;
            puStack_e8 = puVar8;
            do {
              plVar30 = plStack_d8;
              puStack_120 = &UNK_ffffffffdc9a2381;
              param_4 = plVar31;
              func_0xffffffffdc630720(alStack_c8,0x10,&UNK_ffffffffdce3ee53);
              puStack_120 = &UNK_ffffffffdc9a238c;
              plVar9 = (long *)func_0xffffffffdc75aad0(plVar30,alStack_c8);
              plVar30 = plStack_d8;
              if (plVar9 == (long *)0x0) {
                puStack_120 = &UNK_ffffffffdc9a2ee1;
                func_0xffffffffdc75a780(plStack_d8,&UNK_ffffffffdce3ee59,plVar31);
                uVar32 = 0x16;
                break;
              }
              puStack_120 = &UNK_ffffffffdc9a23a7;
              uVar6 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
              puStack_120 = &UNK_ffffffffdc9a23b5;
              iVar3 = func_0xffffffffdc716350(plVar9,&UNK_ffffffffdce3ee6d,uVar6);
              if (iVar3 == 0) {
                puStack_120 = &UNK_ffffffffdc9a23c5;
                lVar10 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
                plVar9 = (long *)((long)plVar9 + lVar10);
              }
              param_3 = (long *)plStack_e0[0x14];
              while( true ) {
                if (param_3 == (long *)0x0) {
                  if (uRamffffffffdea14d10 != 0) {
                    puStack_120 = &UNK_ffffffffdc9a2bbf;
                    func_0xffffffffdc630420(&UNK_ffffffffdce3ef7e,1,plVar9);
                  }
                  puVar28 = &UNK_ffffffffdce3efa5;
                  register0x00000020 = (BADSPACEBASE *)&puStack_120;
                  puStack_120 = &UNK_ffffffffdc9a2bda;
                  puVar27 = puVar18;
                  param_1 = plStack_d8;
                  unaff_R14 = plVar9;
                  goto code_r0xffffffffdc75a780;
                }
                puStack_120 = &UNK_ffffffffdc9a23eb;
                iVar3 = func_0xffffffffdc402940(*param_3,plVar9);
                if (iVar3 == 0) break;
                param_3 = (long *)param_3[2];
              }
              if (puStack_e8 == (undefined4 *)0x0) {
                uVar32 = 0;
              }
              else {
                uVar32 = *puStack_e8;
              }
              puStack_120 = &UNK_ffffffffdc9a2417;
              uVar29 = func_0xffffffffdc9a33c0(param_3,uVar32);
              if (uVar29 != 0) {
                plVar9 = (long *)*param_3;
                puVar28 = &UNK_ffffffffdce3efbb;
                param_4 = (long *)(ulong)uVar29;
                register0x00000020 = (BADSPACEBASE *)&puStack_120;
                puStack_120 = &UNK_ffffffffdc9a2fa5;
                puVar27 = puVar19;
                param_1 = plStack_d8;
                unaff_R14 = (long *)(ulong)uVar29;
                goto code_r0xffffffffdc75a780;
              }
              uVar29 = (int)plVar31 + 1;
              plVar31 = (long *)(ulong)uVar29;
              uVar32 = 0;
              plVar30 = plStack_d8;
            } while ((int)uVar29 < (int)*unaff_R15);
          }
        }
        uStack_78 = CONCAT44(uStack_78._4_4_,uVar32);
        puStack_120 = &UNK_ffffffffdc9a2c21;
        func_0xffffffffdc75a870(plVar30,&UNK_ffffffffdce3ef72,&uStack_78,4);
      }
      else {
        puStack_120 = (undefined *)0xffffffffdc9a2164;
        iVar3 = func_0xffffffffdc402940(param_3,&UNK_ffffffffdce3edc5);
        if (iVar3 != 0) {
          puStack_120 = (undefined *)0xffffffffdc9a217b;
          iVar3 = func_0xffffffffdc402940(param_3,&UNK_ffffffffdce3edcb);
          if (iVar3 != 0) {
            if (uRamffffffffdeaacea0 == uStack_38) {
              puVar28 = &UNK_ffffffffdce3edd5;
              plVar9 = extraout_RDX;
              param_3 = unaff_RBX;
              puVar27 = unaff_RBP;
              goto code_r0xffffffffdc75a780;
            }
            goto LAB_ffffffffdc9a303e;
          }
          puStack_120 = &UNK_ffffffffdc9a2aaa;
          auVar33 = func_0xffffffffdc75aad0(param_1,&UNK_ffffffffdce3efe0);
          plVar9 = auVar33._8_8_;
          plVar30 = auVar33._0_8_;
          plStack_d8 = param_1;
          if (plVar30 == (long *)0x0) {
            puVar28 = &UNK_ffffffffdce3efe5;
            register0x00000020 = (BADSPACEBASE *)&puStack_120;
            puStack_120 = &UNK_ffffffffdc9a2c34;
            puVar27 = puVar15;
            unaff_R14 = param_1;
            goto code_r0xffffffffdc75a780;
          }
          puStack_120 = &UNK_ffffffffdc9a2ad0;
          iVar3 = func_0xffffffffdc4b4390(*in_GS_OFFSET,0x2ab);
          param_1 = plStack_d8;
          if (iVar3 == 0) {
            for (lVar10 = plStack_e0[0x14]; lVar10 != 0; lVar10 = *(long *)(lVar10 + 0x10)) {
              for (puVar11 = *(undefined8 **)(lVar10 + 0x28); puVar11 != (undefined8 *)0x0;
                  puVar11 = (undefined8 *)puVar11[1]) {
                puStack_120 = &UNK_ffffffffdc9a2cdb;
                iVar3 = func_0xffffffffdc402940(*puVar11,plVar30);
                if (iVar3 == 0) {
                  if (*(long *)(lVar10 + 0x20) == 0) {
                    puVar28 = &UNK_ffffffffdce3f00b;
                  }
                  else {
                    puVar11 = *(undefined8 **)(*(long *)(lVar10 + 0x20) + 0x18);
                    if (puVar11 == (undefined8 *)0x0) {
                      puVar28 = &UNK_ffffffffdce3f02c;
                    }
                    else {
                      uVar6 = *puVar11;
                      puStack_120 = &UNK_ffffffffdc9a2d96;
                      iVar3 = func_0xffffffffdc373320(uVar6,0x3f);
                      puStack_120 = &UNK_ffffffffdc9a2dab;
                      iVar3 = func_0xffffffffdc75a870(param_1,&UNK_ffffffffdce3f058,uVar6,iVar3 + 1)
                      ;
                      if ((iVar3 != 0) && (iVar3 != 0x16)) {
                        puStack_120 = &UNK_ffffffffdc9a2f59;
                        func_0xffffffffdc630420(&UNK_ffffffffdce3f063,iVar3);
                        goto code_r0xffffffffdc9a2c3a;
                      }
                      iVar3 = 0;
                      puStack_120 = &UNK_ffffffffdc9a2dd3;
                      lVar13 = func_0xffffffffdc75aa10(plStack_d8,&UNK_ffffffffdce3f07b,0);
                      if (lVar13 == 0) goto code_r0xffffffffdc9a2c3a;
                      lVar10 = *(long *)(lVar10 + 0x98);
                      if (lVar10 != 0) {
                        if (*(int *)(lVar10 + 0x70) == 1) {
                          puStack_120 = &UNK_ffffffffdc9a2e12;
                          iVar4 = func_0xffffffffdc75a870
                                            (plStack_d8,&UNK_ffffffffdce3f07b,lVar10 + 0x50,0x10);
                          if ((iVar4 != 0) && (iVar4 != 0x16)) {
                            puStack_120 = &UNK_ffffffffdc9a2e35;
                            func_0xffffffffdc630420(&UNK_ffffffffdce3f063,iVar4);
                            iVar3 = iVar4;
                          }
                        }
                        else {
                          puStack_120 = &UNK_ffffffffdc9a3033;
                          func_0xffffffffdc630420(&UNK_ffffffffdce3f0a4);
                          iVar3 = 1;
                        }
                        goto code_r0xffffffffdc9a2c3a;
                      }
                      puVar28 = &UNK_ffffffffdce3f086;
                    }
                  }
                  puStack_120 = &UNK_ffffffffdc9a301a;
                  func_0xffffffffdc630420(puVar28);
                  iVar3 = 9;
                  goto code_r0xffffffffdc9a2c3a;
                }
              }
              param_3 = (long *)0x0;
            }
            puVar28 = &UNK_ffffffffdce3f0cb;
            register0x00000020 = (BADSPACEBASE *)&puStack_120;
            puStack_120 = &UNK_ffffffffdc9a2b0d;
            plVar9 = plVar30;
            puVar27 = puVar14;
            unaff_R14 = param_1;
            unaff_R15 = (long *)0x0;
            goto code_r0xffffffffdc75a780;
          }
code_r0xffffffffdc9a2c3a:
          uStack_78 = CONCAT44(uStack_78._4_4_,iVar3);
          param_1 = plStack_d8;
          goto code_r0xffffffffdc9a2d25;
        }
        puStack_120 = &UNK_ffffffffdc9a247f;
        auVar33 = func_0xffffffffdc75abc0(param_1,&UNK_ffffffffdce3ede3,4);
        plVar30 = auVar33._0_8_;
        if (plVar30 == (long *)0x0) goto code_r0xffffffffdc9a256e;
        if ((int)*plVar30 < 1) goto code_r0xffffffffdc9a2a85;
        param_3 = (long *)0x0;
        plStack_d8 = param_1;
        do {
          puStack_120 = &UNK_ffffffffdc9a24c9;
          param_4 = param_3;
          func_0xffffffffdc630720(alStack_c8,0x10,&UNK_ffffffffdce3ee53);
          puStack_120 = &UNK_ffffffffdc9a24d8;
          plVar9 = (long *)func_0xffffffffdc75aad0(plStack_d8,alStack_c8);
          param_1 = plStack_d8;
          if (plVar9 == (long *)0x0) goto code_r0xffffffffdc9a2d60;
          puStack_120 = &UNK_ffffffffdc9a24ec;
          uVar6 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
          puStack_120 = &UNK_ffffffffdc9a24fa;
          iVar3 = func_0xffffffffdc716350(plVar9,&UNK_ffffffffdce3ee6d,uVar6);
          if (iVar3 == 0) {
            puStack_120 = &UNK_ffffffffdc9a2506;
            lVar10 = func_0xffffffffdc6bab70(&UNK_ffffffffdce3ee6d);
            plVar9 = (long *)((long)plVar9 + lVar10);
          }
          puStack_120 = &UNK_ffffffffdc9a2511;
          lVar10 = func_0xffffffffdc755930(plVar9);
          if ((lVar10 == 0) ||
             (param_4 = plStack_e0, *(long **)(*(long *)(lVar10 + 0x18) + 8) != plStack_e0)) {
            if (uRamffffffffdea14d10 != 0) {
              puStack_120 = &UNK_ffffffffdc9a2c74;
              func_0xffffffffdc630420(&UNK_ffffffffdce3ee73,1,plVar9);
            }
            puVar28 = &UNK_ffffffffdce3ee9c;
            param_3 = plVar9;
            param_1 = plStack_d8;
            unaff_R14 = (long *)&UNK_ffffffffdce3ee6d;
            goto code_r0xffffffffdc9a2c85;
          }
          puVar11 = *(undefined8 **)(*(long *)(lVar10 + 0x18) + 0x98);
          uVar29 = (int)param_3 + 1;
          param_3 = (long *)(ulong)uVar29;
          *puVar11 = 0;
          puVar11[1] = 0;
          puVar11[2] = 0;
          puVar11[3] = 0;
          puVar11[4] = 0;
        } while ((int)uVar29 < (int)*plVar30);
      }
    }
  }
  goto code_r0xffffffffdc9a2d2f;
code_r0xffffffffdc9a2d60:
  puStack_120 = &UNK_ffffffffdc9a2d67;
  func_0xffffffffdc75a780(param_1,&UNK_ffffffffdce3ee59,param_3);
code_r0xffffffffdc9a2d2f:
  if (uRamffffffffdeaacea0 == uStack_38) {
    return uRamffffffffdeaacea0;
  }
LAB_ffffffffdc9a303e:
  puStack_120 = &UNK_ffffffffdc9a3043;
  func_0xffffffffdca17ba0();
                    /* WARNING: Does not return */
  pcVar2 = (code *)invalidInstructionException();
  (*pcVar2)();
}

