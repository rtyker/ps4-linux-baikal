#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ps4-hdmi-hotplug — daemon de userspace que monitora a ponte MN864729
pelo ICC (0x10/0) e dispara reprobe do conector DRM quando o bit 0
do 0x10f4 (sink HDMI detected) sobe de 0 para 1.

Requisitos:
- Kernel com o driver ps4_bridge já carregado.
- /dev/icc existente (criado pelo icc_cmd na primeira execução).
- Executar como root (precisa acesso ao /dev/icc).

Uso:
  ps4-hdmi-hotplug.py [--interval 0.5] [--connector card0-HDMI-A-1] [--debug]
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

ICC_CMD = "/tmp/icc_cmd"
DRM_CONNECTOR = "/sys/class/drm/{}/status"
ICC_MAJOR = 0x10
ICC_MINOR = 0x0
REG_SINK_DETECT = 0x10f4
REG_TX_POWER = 0x7008
BIT_SINK_DETECT = 0
BIT_TX_POWER = 4

def read_reg(icc_cmd, reg):
    """Read one 16-byte block starting at reg via ICC 0x10/0 CMD_READ."""
    h = f"{reg:04x}"
    payload = f"040c00010108010110{h}00"
    try:
        out = subprocess.check_output(
            [icc_cmd, "raw", str(ICC_MAJOR), str(ICC_MINOR), payload, "--reply", "48", "--yes"],
            stderr=subprocess.PIPE, text=True, timeout=3
        )
    except subprocess.CalledProcessError:
        return None
    for line in out.splitlines():
        if line.startswith("reply"):
            parts = line.split()
            if len(parts) < 10 or parts[1] != "00" or parts[2] != "00":
                return None
            vals = parts[8:24]
            if len(vals) < 16:
                return None
            return int(vals[0], 16)  # first byte of the 16
    return None

def write_reg(icc_cmd, reg, val):
    """Write one byte at reg via ICC 0x10/0 CMD_WRITE (one byte)."""
    h = f"{reg:04x}"
    v = f"{val:02x}"
    payload = f"040c00010208020101{h}{v}"
    try:
        subprocess.check_output(
            [icc_cmd, "raw", str(ICC_MAJOR), str(ICC_MINOR), payload, "--reply", "32", "--yes"],
            stderr=subprocess.PIPE, text=True, timeout=3
        )
        return True
    except subprocess.CalledProcessError:
        return False

def trigger_reprobe(connector):
    status_path = DRM_CONNECTOR.format(connector)
    try:
        with open(status_path, "w") as f:
            f.write("detect\n")
        return True
    except Exception:
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interval", type=float, default=0.5, help="poll interval in seconds")
    parser.add_argument("--connector", default="card0-HDMI-A-1", help="DRM connector name")
    parser.add_argument("--debug", action="store_true", help="print each poll")
    args = parser.parse_args()

    if not Path(ICC_CMD).exists():
        print(f"ERRO: {ICC_CMD} não encontrado. Copie o icc_cmd para /tmp/icc_cmd antes.")
        return 1
    if os.geteuid() != 0:
        print("ERRO: precisa rodar como root (acesso ao /dev/icc).")
        return 1

    # ensure /dev/icc exists
    if not Path("/dev/icc").exists():
        try:
            subprocess.check_call([ICC_CMD, "selftest"], stderr=subprocess.PIPE)
        except subprocess.CalledProcessError:
            print("ERRO: selftest do icc_cmd falhou.")
            return 1
    else:
        # verify icc_cmd works with --yes
        try:
            subprocess.check_call([ICC_CMD, "raw", str(ICC_MAJOR), str(ICC_MINOR), "040c0001010801011010f400", "--reply", "48", "--yes"], stderr=subprocess.PIPE)
        except subprocess.CalledProcessError:
            print("ERRO: icc_cmd raw test falhou.")
            return 1

    print(f"[hdmi-hotplug] monitorando {args.connector} a cada {args.interval}s (Ctrl-C para sair)")

    last_sink = 0
    last_tx = 0

    try:
        while True:
            sink = read_reg(ICC_CMD, REG_SINK_DETECT)
            tx = read_reg(ICC_CMD, REG_TX_POWER)
            if sink is None or tx is None:
                if args.debug:
                    print("[debug] leitura falhou")
            else:
                sink_bit = (sink >> BIT_SINK_DETECT) & 1
                tx_bit = (tx >> BIT_TX_POWER) & 1
                if args.debug:
                    print(f"[debug] 0x10f4={sink:02x} bit0={sink_bit}  0x7008={tx:02x} bit4={tx_bit}")

                # edge 0->1 no sink detect
                if sink_bit == 1 and last_sink == 0:
                    print(f"[hotplug] sink detectado (0x10f4 bit0 0->1), disparando reprobe em {args.connector}")
                    trigger_reprobe(args.connector)

                last_sink = sink_bit
                last_tx = tx_bit

            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\n[hdmi-hotplug] encerrado")
    return 0

if __name__ == "__main__":
    sys.exit(main())