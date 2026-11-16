#!/usr/bin/env python3
"""
ps4_cmtab_generator.py — Gera /etc/cryptmount/cmtab (ou algo equivalente) para as
partições do HD do PS4 acessíveis com a chave EAP.

ESQUEMA CORRETO (validado ao vivo em 2026-11-13, ver outros/docs/MONTAGEM_HD_INTERNO.md §2):

    ivoffset = (dev_no - 1) << 32

Atenção: a versão antiga deste script usava o LBA inicial da partição como
`ivoffset`. Essa hipótese foi REFUTADA — o LBA é o *data offset*, não o offset
do IV. Usar o LBA faz o dm-crypt decifrar lixo (nenhum magic UFS2 aparece).

Partições montáveis com a chave EAP:
    sda25 (update,   vfat)
    sda27 (user,     UFS2)
    sda29 (eap_user, UFS2)
As demais usam a chave SAMU/versioned (system/system_ex/system_data/app_reserved)
ou não são filesystem (sda13 = swap antigo).
"""

import os
import sys

# (nome no cmtab, partição, fstype, modo de mount)
EAP_PARTITIONS = [
    ("update",   25, "msdos", "ro,noatime,noexec"),
    ("user",     27, "ufs",   "ro,noatime,noexec,ufstype=ufs2"),
    ("eap_user", 29, "ufs",   "ro,noatime,noexec,ufstype=ufs2"),
]


def iv_offset(dev_no: int) -> int:
    """IV offset usado em CUH-1100+ (todo Baikal): (dev_no - 1) << 32."""
    return (dev_no - 1) << 32


def generate_cmtab(disk="sda", key_file="/etc/ps4-keys/eap_hdd_key.bin", dest_dir="/mnt/ps4_internal"):
    print("# /etc/cryptmount/cmtab para o HD interno do PS4 (chave EAP)")
    print("# Gerado por ps4_cmtab_generator.py")
    print("# ivoffset = (dev_no - 1) << 32  — validado ao vivo em 2026-11-13")
    print("# sda13 NÃO entra: é o swap antigo (chave versioned_key), não é UFS2.\n")

    for name, dev_no, fstype, opts in EAP_PARTITIONS:
        print(f"{name} {{")
        print(f"    dev=/dev/{disk}{dev_no}")
        print(f"    dir={dest_dir}/{disk}{dev_no}")
        print("    flags=user,nofsck")
        print(f"    fstype={fstype} mountoptions={opts}")
        print("    cipher=aes-xts-plain64")
        print(f"    ivoffset={iv_offset(dev_no)}")
        print(f"    keyfile={key_file}")
        print("    keyformat=raw")
        print("}\n")

    print("# Equivalente com dmsetup (o cryptsetup NÃO aceita iv_offset em modo plain):")
    for name, dev_no, _fstype, _opts in EAP_PARTITIONS:
        print(
            f"#   dmsetup create -r ps4_{disk}{dev_no} --table "
            f"\"0 $(blockdev --getsz /dev/{disk}{dev_no}) crypt aes-xts-plain64 "
            f"$(xxd -p -c 256 {key_file} | tr -d '\\n') {iv_offset(dev_no)} "
            f"/dev/{disk}{dev_no} 0\""
        )
    print("\n# Atalho recomendado (faz tudo, com detecção de FS e mount ro):")
    for name, dev_no, _fstype, _opts in EAP_PARTITIONS:
        print(f"#   /usr/local/bin/monta_particao.sh /dev/{disk}{dev_no}")


if __name__ == "__main__":
    disk = sys.argv[1] if len(sys.argv) > 1 else "sda"
    key = sys.argv[2] if len(sys.argv) > 2 else "/etc/ps4-keys/eap_hdd_key.bin"
    if disk.startswith("/dev/"):
        disk = os.path.basename(disk)
    generate_cmtab(disk, key)
