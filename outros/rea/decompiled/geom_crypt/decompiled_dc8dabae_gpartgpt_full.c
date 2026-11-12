// Full-context decompile of function containing 0xdc8dabae
// Function entry: ffffffffdc8d9e30 name: FUN_ffffffffdc8d9e30


/* WARNING: Type propagation algorithm not settling */

void FUN_ffffffffdc8d9e30(undefined8 *param_1)

{
  uint *puVar1;
  byte *pbVar2;
  char cVar3;
  ushort uVar4;
  int iVar5;
  long lVar6;
  undefined8 *puVar7;
  byte bVar8;
  uint uVar9;
  undefined4 uVar10;
  undefined8 *puVar11;
  long lVar12;
  long lVar13;
  ushort *puVar14;
  undefined8 uVar15;
  ushort *puVar16;
  short sVar17;
  ushort *puVar18;
  ulong uVar19;
  long *plVar20;
  undefined8 uVar21;
  undefined8 *puVar22;
  undefined8 *puVar23;
  ulong uVar24;
  ushort *puVar25;
  ulong uVar26;
  undefined8 *in_GS_OFFSET;
  long lStack_a8;
  undefined8 *puStack_a0;
  undefined8 *puStack_98;
  undefined8 *puStack_90;
  uint uStack_84;
  undefined8 uStack_80;
  ulong uStack_78;
  ushort uStack_70;
  undefined6 uStack_6e;
  undefined8 *puStack_50;
  undefined8 *puStack_48;
  undefined8 *puStack_40;
  ushort *puStack_38;
  
  param_1[4] = *in_GS_OFFSET;
  func_0xffffffffdc524770(&UNK_ffffffffdcdc4690,0x44,0x200,0);
  puStack_90 = param_1 + 0x1c;
  puVar1 = (uint *)(param_1 + 0x20);
  puVar22 = param_1 + 0x17;
  puStack_a0 = param_1 + 0x12;
  pbVar2 = (byte *)(param_1 + 0x16);
  puStack_98 = param_1;
  puStack_50 = puVar22;
  do {
    puVar11 = puStack_90;
    func_0xffffffffdc6c8300(puStack_90,0,&UNK_ffffffffdcdc44ee,0x28da);
    uVar9 = *puVar1;
    if (uVar9 == 0) {
      func_0xffffffffdc48fe00(puVar1,puVar11,0,&UNK_ffffffffdcdc46b3,0);
      uVar9 = *puVar1;
    }
    *puVar1 = 0;
    uStack_84 = uVar9;
    func_0xffffffffdc6c85b0(puVar11,0,&UNK_ffffffffdcdc44ee,0x28e0);
    if ((uStack_84 & 1) != 0) {
      while( true ) {
        func_0xffffffffdc6c8300(puVar22,0,&UNK_ffffffffdcdc44ee,0x2690);
        lVar6 = param_1[0x92];
        if (lVar6 == 0) break;
        lVar13 = *(long *)(lVar6 + 8);
        param_1[0x92] = lVar13;
        if (lVar13 == 0) {
          param_1[0x96] = 0;
        }
        *(undefined8 *)(lVar6 + 8) = 0;
        func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x2692);
        func_0xffffffffdc6c8300(puStack_a0,0,&UNK_ffffffffdcdc44ee,0x2695);
        lVar13 = param_1[0x21];
        if (lVar13 == 0) {
          func_0xffffffffdc750770(lVar6);
        }
        else {
          puVar25 = *(ushort **)(lVar6 + 0x10);
          puVar14 = *(ushort **)(lVar13 + 0x24);
          if (((*(uint *)(lVar6 + 0x18) < 8) || ((char)puVar14[2] != (char)puVar25[2])) ||
             ((*puVar14 | 0x8000) != *puVar25)) {
            func_0xffffffffdc5b7b80(*param_1,&UNK_ffffffffdcdc46e6,*puVar25,(char)puVar14[2]);
            func_0xffffffffdc750770(lVar6);
            puVar22 = puStack_50;
          }
          else {
            if (puVar25[3] == 0) {
              *(undefined4 *)(lVar13 + 0x4e) = 0;
              if (*puVar14 == 0xaa) {
                *(uint *)(param_1 + 0x9a) = *(uint *)(param_1 + 0x9a) | 8;
              }
            }
            else {
              func_0xffffffffdc5b7b80(*param_1,&UNK_ffffffffdcdc46bd,*puVar14);
              *(undefined4 *)(lVar13 + 0x4e) = 5;
            }
            uVar9 = *(uint *)(lVar13 + 0x20);
            *(uint *)(lVar13 + 0x20) = uVar9 | 1;
            if ((*(int *)(param_1 + 0x23) == 0) || ((uVar9 & 2) == 0)) {
              *(ushort **)(lVar13 + 0x32) = puVar25;
              *(long *)(lVar13 + 0x42) = lVar6;
              *(short *)(lVar13 + 0x4a) = (short)*(undefined4 *)(lVar6 + 0x18) + -8;
            }
            else {
              *(uint *)(param_1 + 0x9a) = *(uint *)(param_1 + 0x9a) & 0xffffffbf;
              *(uint *)(param_1 + 0x9a) = *(uint *)(param_1 + 0x9a) | 0x80;
              func_0xffffffffdc8d6280(0x10004,0,0);
              func_0xffffffffdc750770(lVar6);
            }
            puVar22 = puStack_50;
            func_0xffffffffdc69d9a0(&uStack_78);
            *(ulong *)(lVar13 + 0x10) = uStack_78 * 1000000 + CONCAT62(uStack_6e,uStack_70);
            *pbVar2 = *pbVar2 | 2;
            func_0xffffffffdc4902b0();
          }
        }
        func_0xffffffffdc6c85b0(puStack_a0,0,&UNK_ffffffffdcdc44ee,0x26d7);
      }
      func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x2692);
      while( true ) {
        func_0xffffffffdc6c8300(puVar22,0,&UNK_ffffffffdcdc44ee,0x28bb);
        lVar6 = param_1[0x93];
        if (lVar6 == 0) break;
        lVar13 = *(long *)(lVar6 + 8);
        param_1[0x93] = lVar13;
        if (lVar13 == 0) {
          param_1[0x97] = 0;
        }
        *(undefined8 *)(lVar6 + 8) = 0;
        func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x28bd);
        iVar5 = *(int *)(lVar6 + 0x18);
        puVar25 = *(ushort **)(lVar6 + 0x10);
        puVar11 = (undefined8 *)func_0xffffffffdc5b6b00(*param_1);
        puStack_38 = puVar25;
        if ((byte)puVar25[1] != 0 || *(byte *)((long)puVar25 + 3) != 0) {
          if ((*(byte *)((long)puVar25 + 3) == 1) && (lVar13 = 0x4e0, (byte)puVar25[1] == 0))
          goto code_r0xffffffffdc8da1e5;
          goto code_r0xffffffffdc8da21b;
        }
        lVar13 = 0x4d8;
code_r0xffffffffdc8da1e5:
        puVar7 = *(undefined8 **)((long)puVar11 + lVar13);
        if (puVar7 == (undefined8 *)0x0) goto code_r0xffffffffdc8da21b;
        switch(*puVar25 & 0xfff) {
        case 1:
        case 2:
        case 4:
        case 6:
        case 7:
        case 0xd:
        case 0xe:
        case 0xf:
        case 0x10:
        case 0x11:
        case 0x12:
        case 0x13:
        case 0x14:
        case 0x15:
        case 0x16:
        case 0x17:
        case 0x18:
        case 0x1a:
        case 0x1b:
        case 0x1c:
        case 0x1d:
        case 0x1e:
        case 0x20:
        case 0x21:
        case 0x24:
        case 0x25:
        case 0x26:
        case 0x27:
        case 0x28:
        case 0x2e:
        case 0x31:
        case 0x42:
        case 0x43:
        case 0x44:
        case 0x46:
        case 0x47:
        case 0x48:
        case 0x4d:
        case 0x51:
        case 0x55:
          break;
        case 3:
          if (*(char *)((long)puVar7 + 0x3e) == '\0') {
            uVar15 = *puVar7;
            uVar21 = 1;
code_r0xffffffffdc8da6c1:
            func_0xffffffffdc530200(uVar15,uVar21,0,0);
          }
          break;
        default:
          func_0xffffffffdc630420(&UNK_ffffffffdcdc4723);
          break;
        case 8:
          if (*(char *)((long)puVar7 + 0x3e) == '\0') {
            func_0xffffffffdc6c8300(puVar11 + 0xe,0,&UNK_ffffffffdcdc44ee,0x27f4);
            *(undefined4 *)(puVar7 + 9) = 1;
            func_0xffffffffdc4902b0((long)puVar7 + 0x44);
            func_0xffffffffdc6c85b0(puVar11 + 0xe,0,&UNK_ffffffffdcdc44ee,0x27f7);
            uVar15 = *puVar7;
            uVar21 = 2;
            goto code_r0xffffffffdc8da6c1;
          }
          break;
        case 9:
          if (*(char *)((long)puVar7 + 0x3e) == '\0') {
            func_0xffffffffdc6c8300(puVar11 + 0xe,0,&UNK_ffffffffdcdc44ee,0x27fd);
            *(undefined4 *)(puVar7 + 9) = 2;
            func_0xffffffffdc4902b0((long)puVar7 + 0x44);
            func_0xffffffffdc6c85b0(puVar11 + 0xe,0,&UNK_ffffffffdcdc44ee,0x2801);
            uVar15 = *puVar7;
            uVar21 = 8;
            goto code_r0xffffffffdc8da6c1;
          }
          break;
        case 10:
          if (*(int *)(puVar11 + 0x23) != 0) {
            puVar23 = puVar11 + 0x12;
            func_0xffffffffdc6c8300(puVar23,0,&UNK_ffffffffdcdc44ee,0x2808);
            *(uint *)(puVar11 + 0x9a) = *(uint *)(puVar11 + 0x9a) & 0xffffff7f;
            uVar15 = 0x280d;
            goto code_r0xffffffffdc8da7d9;
          }
          break;
        case 0xb:
          if (*(int *)(puVar11 + 0x23) != 0) {
            puVar23 = puVar11 + 0x12;
            func_0xffffffffdc6c8300(puVar23,0,&UNK_ffffffffdcdc44ee,0x2815);
            if ((((*(uint *)(puVar11 + 0x9a) & 0x40) == 0) &&
                (*(uint *)(puVar11 + 0x9a) = *(uint *)(puVar11 + 0x9a) & 0xffffff7f,
                (*(uint *)(puVar11 + 0x9a) & 4) == 0)) && ((*(uint *)(puVar11 + 0x9a) & 0x10) == 0))
            {
              *(uint *)(puVar11 + 0x9a) = *(uint *)(puVar11 + 0x9a) | 0x40;
            }
            *(byte *)(puVar11 + 0x16) = *(byte *)(puVar11 + 0x16) | 1;
            func_0xffffffffdc4902b0(puVar11 + 0x16);
            uVar15 = 0x2824;
            goto code_r0xffffffffdc8da7d9;
          }
          break;
        case 0x19:
          if (*(char *)((long)puVar7 + 0x3e) == '\0') {
            uVar15 = *puVar7;
            uVar21 = 4;
            goto code_r0xffffffffdc8da6c1;
          }
          break;
        case 0x2b:
          if (*(char *)((long)puVar7 + 0x3e) == '\0') {
            puVar23 = puVar11 + 0xe;
            func_0xffffffffdc6c8300(puVar23,0,&UNK_ffffffffdcdc44ee,0x285f);
            *(undefined4 *)(puVar7 + 9) = 0;
            func_0xffffffffdc4902b0((long)puVar7 + 0x44);
            uVar15 = 0x2862;
            goto code_r0xffffffffdc8da7d9;
          }
          break;
        case 0x2c:
          if (*(char *)((long)puVar7 + 0x3e) == '\x01') {
            puVar22 = puVar11 + 0x17;
            puStack_40 = puVar11;
            func_0xffffffffdc6c8300(puVar22,0,&UNK_ffffffffdcdc44ee,0x2866);
            uStack_78 = 0;
            func_0xffffffffdc60d4c0(&uStack_78,puStack_38 + 3,6);
            uVar26 = uStack_78;
            plVar20 = (long *)puVar7[10];
            while (plVar20 != (long *)0x0) {
              while (((plVar20[2] ^ uVar26) & 0xffffffffffff) != 0) {
                plVar20 = (long *)*plVar20;
                if (plVar20 == (long *)0x0) goto code_r0xffffffffdc8da427;
              }
              func_0xffffffffdc8d6ab0(puVar7);
              plVar20 = (long *)puVar7[10];
            }
code_r0xffffffffdc8da427:
            func_0xffffffffdc8dce00(puStack_40 + 0x51);
            uVar15 = 0x2872;
            goto code_r0xffffffffdc8daf71;
          }
          break;
        case 0x2d:
          if (*(char *)((long)puVar7 + 0x3e) == '\x01') {
            puVar22 = puVar11 + 0x17;
            puStack_40 = puVar11;
            func_0xffffffffdc6c8300(puVar22,0,&UNK_ffffffffdcdc44ee,0x2876);
            puVar25 = puStack_38 + 3;
            func_0xffffffffdc8dce00(puStack_40 + 0x51);
            puVar11 = puStack_40;
            uStack_80 = puVar25;
            puStack_48 = puVar22;
            if ((*(byte *)(puStack_40 + 0x62) & 1) == 0) {
              puVar25 = (ushort *)(puStack_40 + 0x62);
              lVar13 = 0;
code_r0xffffffffdc8dae2a:
              func_0xffffffffdc60d400(puVar25,0x30);
              *(byte *)puVar25 = (byte)*puVar25 | 1;
              func_0xffffffffdc60d4c0(puVar11 + lVar13 * 6 + 100,uStack_80,6);
              puVar22 = puStack_48;
              uStack_80 = puVar25;
              if (puVar25 != (ushort *)0x0) {
                puVar14 = (ushort *)((long)puStack_38 + (long)iVar5);
                puVar25 = puStack_38 + 6;
code_r0xffffffffdc8dae83:
                do {
                  do {
                    puVar16 = puVar25;
                    puVar18 = puVar16 + 2;
                    if ((puVar14 < puVar18) || (*puVar16 != 0x168)) goto code_r0xffffffffdc8daf60;
                    puVar25 = (ushort *)((long)puVar18 + (ulong)puVar16[1]);
                    if (puVar14 < puVar25) goto code_r0xffffffffdc8daf60;
                  } while ((*puVar18 & 0xfc) != 0);
                  uVar24 = (ulong)puVar16[1] - 6;
                  uVar26 = 0;
                  do {
                    if (uVar24 < uVar26 + 2) goto code_r0xffffffffdc8dae83;
                    bVar8 = *(byte *)((long)puVar16 + uVar26 + 0xb);
                    uVar19 = uVar26 + 2 + (ulong)bVar8;
                    if (uVar24 < uVar19) goto code_r0xffffffffdc8dae83;
                    lVar13 = uVar26 + 10;
                    uVar26 = uVar19;
                  } while (*(byte *)((long)puVar16 + lVar13) != 0x2d);
                } while (0x1a < bVar8);
                func_0xffffffffdc60d4c0(&uStack_78);
                *(byte *)uStack_80 = (byte)*uStack_80 | 2;
                if ((*(byte *)((long)puStack_40 + 0x304) & 1) == 0) {
                  *(byte *)((long)uStack_80 + 5) = 1;
                  bVar8 = func_0xffffffffdc716290();
                  *(byte *)((long)uStack_80 + 0xf) = bVar8 & 0xf | 0x10;
                  *(undefined4 *)(puStack_40 + 0x61) = 0;
                  uVar9 = (uint)*(byte *)((long)uStack_80 + 0xf);
                }
                else {
                  *(byte *)((long)uStack_80 + 5) = 4;
                  uVar9 = 0;
                }
                *(uint *)((long)puStack_40 + 0x30c) = uVar9;
                uStack_80[0x10] = 0xfff;
                uStack_80[0x11] = 0xfff;
                uStack_80[0x12] = 0xfff;
                uStack_80[0x13] = 0xfff;
                uStack_80[0x14] = 0xfff;
                uStack_80[0x15] = 0xfff;
                uStack_80[0x16] = 0xfff;
                uStack_80[0x17] = 0xfff;
              }
            }
            else {
              if ((*(byte *)(puStack_40 + 0x68) & 1) == 0) {
                puVar25 = (ushort *)(puStack_40 + 0x68);
                lVar13 = 1;
                goto code_r0xffffffffdc8dae2a;
              }
              if ((*(byte *)(puStack_40 + 0x6e) & 1) == 0) {
                puVar25 = (ushort *)(puStack_40 + 0x6e);
                lVar13 = 2;
                goto code_r0xffffffffdc8dae2a;
              }
              if ((*(byte *)(puStack_40 + 0x74) & 1) == 0) {
                puVar25 = (ushort *)(puStack_40 + 0x74);
                lVar13 = 3;
                goto code_r0xffffffffdc8dae2a;
              }
              if ((*(byte *)(puStack_40 + 0x7a) & 1) == 0) {
                puVar25 = (ushort *)(puStack_40 + 0x7a);
                lVar13 = 4;
                goto code_r0xffffffffdc8dae2a;
              }
              if ((*(byte *)(puStack_40 + 0x80) & 1) == 0) {
                puVar25 = (ushort *)(puStack_40 + 0x80);
                lVar13 = 5;
                goto code_r0xffffffffdc8dae2a;
              }
              if ((*(byte *)(puStack_40 + 0x86) & 1) == 0) {
                puVar25 = (ushort *)(puStack_40 + 0x86);
                lVar13 = 6;
                goto code_r0xffffffffdc8dae2a;
              }
              if ((*(byte *)(puStack_40 + 0x8c) & 1) == 0) {
                lVar13 = 7;
                puVar25 = (ushort *)(puStack_40 + 0x8c);
                goto code_r0xffffffffdc8dae2a;
              }
            }
code_r0xffffffffdc8daf60:
            uVar15 = 0x2879;
            goto code_r0xffffffffdc8daf71;
          }
          break;
        case 0x33:
          puVar22 = puVar11 + 0x17;
          func_0xffffffffdc6c8300(puVar22,0,&UNK_ffffffffdcdc44ee,0x2880);
          puVar25 = puStack_38;
          if ((puStack_38[6] & 0x20) == 0) {
            lVar13 = puVar7[1];
            uVar26 = (ulong)(puStack_38[6] >> 2 & 0xf);
            if (*(char *)((long)puVar7 + 0x3e) == '\x01') {
              lVar12 = func_0xffffffffdc8dcf90(lVar13 + 0x288);
              if ((lVar12 != 0) && (*(char *)(lVar12 + 6 + uVar26) == '\0')) {
                *(byte *)(lVar12 + 0x16) = *(byte *)((long)puStack_38 + 0xb);
                *(ushort *)(lVar12 + 0x17) = puStack_38[6];
                *(ushort *)(lVar12 + 0x19) = puStack_38[7];
                *(ushort *)(lVar12 + 0x1b) = puStack_38[8];
                *(undefined1 *)(lVar12 + 6 + uVar26) = 1;
                *(byte *)(lVar13 + 0xd9) = *(byte *)(lVar13 + 0xd9) | 2;
                goto code_r0xffffffffdc8dac57;
              }
            }
            else if ((*(char *)((long)puVar7 + 0x3e) == '\0') &&
                    (*(char *)(lVar13 + 0x25e + uVar26) == '\0')) {
              func_0xffffffffdc60d4c0(lVar13 + 0x268,(byte *)((long)puStack_38 + 5),6);
              *(byte *)(lVar13 + 0x26e) = *(byte *)((long)puVar25 + 0xb);
              *(ushort *)(lVar13 + 0x26f) = puVar25[6];
              *(ushort *)(lVar13 + 0x271) = puVar25[7];
              *(ushort *)(lVar13 + 0x273) = puVar25[8];
              *(undefined1 *)(lVar13 + 0x25e + uVar26) = 1;
              *(byte *)(lVar13 + 0xd8) = *(byte *)(lVar13 + 0xd8) | 2;
code_r0xffffffffdc8dac57:
              func_0xffffffffdc4902b0(lVar13 + 0xd8);
            }
          }
          uVar15 = 0x2882;
          goto code_r0xffffffffdc8daf71;
        case 0x34:
          puStack_40 = puVar11 + 0x17;
          func_0xffffffffdc6c8300(puStack_40,0,&UNK_ffffffffdcdc44ee,0x2885);
          puVar25 = puStack_38;
          if (*(char *)((long)puVar7 + 0x3e) == '\x01') {
            puVar14 = (ushort *)func_0xffffffffdc8dcf90(puVar7[1] + 0x288);
            puVar22 = puStack_40;
            if (puVar14 != (ushort *)0x0) goto code_r0xffffffffdc8dab1c;
          }
          else {
            puVar22 = puStack_40;
            if ((*(char *)((long)puVar7 + 0x3e) == '\0') &&
               ((*(byte *)((long)puVar7 + 0x4c) & 1) != 0)) {
              puVar14 = (ushort *)(puVar7[1] + 600);
code_r0xffffffffdc8dab1c:
              uVar4 = *(ushort *)((long)puVar25 + 0xb);
              puVar22 = puStack_40;
              if (-1 < (short)uVar4) {
                if ((uVar4 & 0x800) == 0) {
                  if (*(short *)((long)puVar25 + 0xd) == 0x25) {
                    *(byte *)((long)puVar14 + 5) = 3;
                  }
                  else {
                    *(byte *)((long)puVar14 + 5) = 0;
                  }
                }
                else {
                  uStack_78 = (ulong)(uVar4 >> 0xc & 7) << 0x30;
                  puStack_38 = puVar14;
                  func_0xffffffffdc60d4c0(&uStack_78,(byte *)((long)puVar25 + 5),6);
                  uVar26 = uStack_78;
                  puVar22 = puStack_40;
                  for (puVar11 = (undefined8 *)puVar7[10]; puVar11 != (undefined8 *)0x0;
                      puVar11 = (undefined8 *)*puVar11) {
                    while (puVar11[2] == uVar26) {
                      func_0xffffffffdc8d6ab0(puVar7);
                      puVar11 = (undefined8 *)puVar7[10];
                      puVar22 = puStack_40;
                      if (puVar11 == (undefined8 *)0x0) goto code_r0xffffffffdc8dad06;
                    }
                  }
code_r0xffffffffdc8dad06:
                  *(byte *)((long)puStack_38 + (ulong)(uVar4 >> 0xc) + 6) = 0;
                }
              }
            }
          }
          uVar15 = 0x2887;
          goto code_r0xffffffffdc8daf71;
        case 0x37:
          puStack_40 = puVar11 + 0x17;
          func_0xffffffffdc6c8300(puStack_40,0,&UNK_ffffffffdcdc44ee,0x288a);
          puVar25 = puStack_38;
          if (*(char *)((long)puVar7 + 0x3e) == '\x01') {
            lVar13 = func_0xffffffffdc8dcf90(puVar7[1] + 0x288);
            if (lVar13 != 0) {
              uVar10 = 0x400;
              cVar3 = *(char *)(lVar13 + 0xe);
              goto joined_r0xffffffffdc8dab7f;
            }
          }
          else if ((*(char *)((long)puVar7 + 0x3e) == '\0') &&
                  ((*(byte *)((long)puVar7 + 0x4c) & 1) != 0)) {
            lVar13 = puVar7[1] + 600;
            uVar10 = 4;
            cVar3 = *(char *)(puVar7[1] + 0x266);
joined_r0xffffffffdc8dab7f:
            if (cVar3 == '\0') {
              uVar26 = (ulong)uStack_80 >> 0x20;
              uStack_80 = (ushort *)CONCAT44((int)uVar26,uVar10);
              if (*(byte *)((long)puVar25 + 0xb) == 0) {
                uStack_78 = (ulong)((byte)puStack_38[2] & 0xfffffff7) << 0x30;
                func_0xffffffffdc60d4c0(&uStack_78,(byte *)((long)puStack_38 + 5),6);
                uVar26 = uStack_78;
                for (puVar22 = (undefined8 *)puVar7[10]; puVar22 != (undefined8 *)0x0;
                    puVar22 = (undefined8 *)*puVar22) {
                  while (puVar22[2] == uVar26) {
                    func_0xffffffffdc8d6ab0(puVar7);
                    puVar22 = (undefined8 *)puVar7[10];
                    if (puVar22 == (undefined8 *)0x0) goto code_r0xffffffffdc8dab8e;
                  }
                }
              }
code_r0xffffffffdc8dab8e:
              *(ushort *)(lVar13 + 0x1d) =
                   (*(byte *)((long)puStack_38 + 0xb) & 1) << 0xb |
                   (ushort)(byte)puStack_38[2] << 0xc;
              *(undefined1 *)(lVar13 + 0xe) = 1;
              *(uint *)(puVar7[1] + 0xd8) = *(uint *)(puVar7[1] + 0xd8) | (uint)uStack_80;
              func_0xffffffffdc4902b0(puVar7[1] + 0xd8);
            }
          }
          uVar15 = 0x288d;
          puVar22 = puStack_40;
          goto code_r0xffffffffdc8daf71;
        case 0x50:
          puVar23 = puVar11 + 0x17;
          func_0xffffffffdc6c8300(puVar23,0,&UNK_ffffffffdcdc44ee,0x289e);
          *(byte *)(puVar11 + 0x1b) = *(byte *)(puVar11 + 0x1b) | 0x10;
          func_0xffffffffdc4902b0(puVar11 + 0x1b);
          uVar15 = 0x28a1;
code_r0xffffffffdc8da7d9:
          func_0xffffffffdc6c85b0(puVar23,0,&UNK_ffffffffdcdc44ee,uVar15);
          break;
        case 0x59:
          puStack_40 = puVar11 + 0x17;
          func_0xffffffffdc6c8300(puStack_40,0,&UNK_ffffffffdcdc44ee,0x28a8);
          puVar18 = puStack_38;
          puVar14 = (ushort *)((long)iVar5 + (long)puStack_38);
          func_0xffffffffdc60d400(&uStack_78);
          puVar25 = puVar18 + 4;
          if (puVar25 <= puVar14) {
            puVar18 = puVar18 + 2;
            uStack_80 = puVar14;
            puStack_48 = puVar7;
            do {
              puVar22 = puStack_48;
              if (((*puVar18 != 0x199) ||
                  (uStack_80 < (ushort *)((ulong)puVar18[1] + (long)puVar25))) ||
                 (7 < (byte)puVar25[3])) break;
              lStack_a8 = (ulong)((byte)puVar25[3] & 0xfffffff7) << 0x30;
              puStack_38 = (ushort *)((ulong)puVar18[1] + (long)puVar25);
              func_0xffffffffdc60d4c0(&lStack_a8,puVar25,6);
              for (puVar22 = (undefined8 *)puVar22[10]; puVar22 != (undefined8 *)0x0;
                  puVar22 = (undefined8 *)*puVar22) {
                if (puVar22[2] == lStack_a8) {
                  if (puVar25[5] != 0) {
                    sVar17 = 7;
                    uVar26 = 0;
                    do {
                      bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      if ((bVar8 & 1) != 0) {
                        uStack_70 = (puVar25[4] + sVar17) - 7 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                        bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      }
                      if ((bVar8 & 2) != 0) {
                        uStack_70 = (puVar25[4] + sVar17) - 6 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                        bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      }
                      if ((bVar8 & 4) != 0) {
                        uStack_70 = (puVar25[4] + sVar17) - 5 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                        bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      }
                      if ((bVar8 & 8) != 0) {
                        uStack_70 = (puVar25[4] + sVar17) - 4 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                        bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      }
                      if ((bVar8 & 0x10) != 0) {
                        uStack_70 = (puVar25[4] + sVar17) - 3 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                        bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      }
                      if ((bVar8 & 0x20) != 0) {
                        uStack_70 = (puVar25[4] + sVar17) - 2 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                        bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      }
                      if ((bVar8 & 0x40) != 0) {
                        uStack_70 = (puVar25[4] + sVar17) - 1 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                        bVar8 = *(byte *)((long)puVar25 + uVar26 + 0xc);
                      }
                      if ((char)bVar8 < '\0') {
                        uStack_70 = puVar25[4] + sVar17 & 0xfff;
                        func_0xffffffffdc8dd110(puStack_48,puVar22,&uStack_78,0xffffffffffffffff);
                      }
                      uVar26 = uVar26 + 1;
                      sVar17 = sVar17 + 8;
                    } while (uVar26 < puVar25[5]);
                  }
                  break;
                }
              }
              puVar25 = puStack_38 + 2;
              puVar18 = puStack_38;
            } while (puVar25 <= uStack_80);
          }
          uVar15 = 0x28ab;
          puVar22 = puStack_40;
code_r0xffffffffdc8daf71:
          func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,uVar15);
          puVar22 = puStack_50;
        }
code_r0xffffffffdc8da21b:
        param_1 = puStack_98;
        if ((*(uint *)(lVar6 + 0x1c) & 1) == 0) {
          if ((*(uint *)(lVar6 + 0x1c) & 0x40000) == 0) {
            func_0xffffffffdc561180(uRamffffffffde582f88,lVar6,0);
          }
        }
        else {
          func_0xffffffffdc750880(lVar6);
          param_1 = puStack_98;
        }
      }
      func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x28bd);
      lVar6 = *(long *)param_1[0x9b];
      while( true ) {
        func_0xffffffffdc6c8300(puVar22,0,&UNK_ffffffffdcdc44ee,0x28f0);
        lVar13 = param_1[0x94];
        if (lVar13 == 0) break;
        lVar12 = *(long *)(lVar13 + 8);
        param_1[0x94] = lVar12;
        if (lVar12 == 0) {
          param_1[0x98] = 0;
        }
        *(undefined8 *)(lVar13 + 8) = 0;
        func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x28f2);
        if (lVar6 == 0) {
          if ((*(uint *)(lVar13 + 0x1c) & 1) == 0) {
            if ((*(uint *)(lVar13 + 0x1c) & 0x40000) == 0) {
              func_0xffffffffdc561180(uRamffffffffde582f88,lVar13,0);
            }
          }
          else {
            func_0xffffffffdc750880(lVar13);
          }
        }
        else {
          *(long *)(lVar13 + 0x28) = lVar6;
          *(long *)(lVar6 + 0xd8) = *(long *)(lVar6 + 0xd8) + 1;
          (**(code **)(lVar6 + 0x170))(lVar6);
        }
      }
      func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x28f2);
      lVar6 = *(long *)param_1[0x9c];
      while( true ) {
        func_0xffffffffdc6c8300(puVar22,0,&UNK_ffffffffdcdc44ee,0x2906);
        lVar13 = param_1[0x95];
        if (lVar13 == 0) break;
        lVar12 = *(long *)(lVar13 + 8);
        param_1[0x95] = lVar12;
        if (lVar12 == 0) {
          param_1[0x99] = 0;
        }
        *(undefined8 *)(lVar13 + 8) = 0;
        func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x2908);
        if (lVar6 == 0) {
          if ((*(uint *)(lVar13 + 0x1c) & 1) == 0) {
            if ((*(uint *)(lVar13 + 0x1c) & 0x40000) == 0) {
              func_0xffffffffdc561180(uRamffffffffde582f88,lVar13,0);
            }
          }
          else {
            func_0xffffffffdc750880(lVar13);
          }
        }
        else {
          *(long *)(lVar13 + 0x28) = lVar6;
          *(long *)(lVar6 + 0xd8) = *(long *)(lVar6 + 0xd8) + 1;
          (**(code **)(lVar6 + 0x170))(lVar6);
        }
      }
      func_0xffffffffdc6c85b0(puVar22,0,&UNK_ffffffffdcdc44ee,0x2908);
    }
    if ((uStack_84 & 0x20000) != 0) {
      func_0xffffffffdc524510();
    }
  } while( true );
}

