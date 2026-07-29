#!/usr/bin/env python3
"""
harness_mts_driver_stage.py — Carrega o driver `mts` num estágio de bring-up e
confere o que ele reporta contra o baseline medido da BAR0.

Uso:
    python3 harness_mts_driver_stage.py [estagio]     # default 1

    0  probe + mapeia BAR0, nenhuma escrita
    1  + dump de registradores e sonda MDIO         <-- comece por aqui
    2  + aloca aneis DMA e programa 0x3c/0x40/0x44/0x48
    3  + habilita MAC cores e escreve IMR
    4  + pci_set_master(), IRQ e register_netdev()

O driver e MODULO justamente para isso: um estagio ruim nao impede o console de
subir, e da para avancar um degrau por vez.

VERIFICACAO: o driver imprime no dmesg os valores que le da BAR0. Este harness
compara esses valores com a tabela `bar0_register_map` (1024 dwords medidos na
Fase 13). Divergencia significa que o driver esta lendo errado — ou que o
estagio anterior mexeu no hardware.

Grava em test_history (Fase 16) e write_sweep_results ('MTS_DRIVER_STAGE').
"""

import socket
import subprocess
import sys
import time
import re
import sqlite3
import datetime

PS4_IP = "192.168.6.128"
PS4_PORT = 23
DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

BAR0_BASE = 0xc2000000
MODULO = "mts"

RE_DUMP = re.compile(r'\+0x([0-9a-f]{3})\s*=\s*0x([0-9a-f]{8})', re.I)
RE_MDIO = re.compile(r'MDIO devad=(\S+)\s+reg=(\S+)\s+\(([^)]*)\)\s*=\s*0x([0-9a-f]{4})', re.I)


def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Carregando driver mts...');
    """, (ts, phase, test_name, target, initial_action))
    tid = cur.lastrowid
    conn.commit()
    conn.close()
    return tid


def update_test_progress(test_id, action, info, status="PENDING"):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("UPDATE test_history SET action_taken=?, complementary_info=?, status=? WHERE id=?;",
                (action, info, status, test_id))
    conn.commit()
    conn.close()
    print(f"[{status}] {action} -> {info[:110]}")


def log_cmp(offset, esperado, lido, bate, notes):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, 'MTS_DRIVER_STAGE', ?, NULL, ?, NULL, 1, 1, NULL, ?, ?, ?);
    """, (hex(BAR0_BASE + offset), f"BAR0+{offset:#05x}", esperado, lido,
          "BATE" if bate else "DIVERGE", ts, notes))
    conn.commit()
    conn.close()


def carregar_baseline():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    base = {}
    for addr, s1, cls in cur.execute(
            "SELECT address, sample1, classification FROM bar0_register_map;"):
        base[int(addr, 16) - BAR0_BASE] = (s1, cls)
    conn.close()
    return base


def read_until_prompt(s, prompt=b"~ # ", timeout=12):
    data = b""
    end = time.time() + timeout
    while time.time() < end:
        try:
            s.settimeout(0.5)
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
            if prompt in data:
                break
        except socket.timeout:
            pass
    return data


def run_cmd(s, cmd, wait=0.5, timeout=15):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s, timeout=timeout).decode('ascii', errors='replace')


def check_ping():
    try:
        return subprocess.run(["ping", "-c", "1", "-W", "2", PS4_IP],
                              capture_output=True, timeout=5).returncode == 0
    except Exception:
        return False


def main():
    estagio = int(sys.argv[1]) if len(sys.argv) > 1 else 1

    print("=" * 78)
    print(f"DRIVER mts — carregando com stage={estagio}")
    print("=" * 78)

    baseline = carregar_baseline()
    print(f"Baseline: {len(baseline)} dwords da Fase 13.\n")

    test_id = create_test_record(
        "Fase 16",
        f"Driver mts em stage={estagio} (bring-up MTS)",
        "GBE Baikal 00:14.1 via driver mts",
        f"insmod mts.ko stage={estagio}"
    )

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(12)
        s.connect((PS4_IP, PS4_PORT))
        read_until_prompt(s, timeout=4)
        update_test_progress(test_id, "Conexão Telnet", "Conectado na porta 23.")
    except Exception as e:
        update_test_progress(test_id, "Conexão Telnet", f"ERRO: {e}", status="FAIL_CONNECTION")
        print(f"ERRO DE CONEXÃO: {e}")
        sys.exit(1)

    # O boot de debug roda a partir do INITRAMFS — o rootfs psxitarch (onde o
    # modulo esta instalado) nao vem montado. Dentro do PS4 nosso HD e o sdb;
    # o sda e o HDD interno do console. Localizamos pela LABEL para nao depender
    # da ordem de enumeracao.
    # a saida do telnet traz o comando ecoado e o prompt junto; pegar so a
    # linha que e puramente numerica
    montado_raw = run_cmd(s, "mount | grep -c psxitarch", wait=0.5)
    montado_n = next((int(l.strip()) for l in montado_raw.splitlines()
                      if l.strip().isdigit()), 0)
    if montado_n == 0:
        print("--- rootfs psxitarch nao montado; montando ---")
        dev = run_cmd(s, "blkid 2>/dev/null | grep psxitarch | cut -d: -f1", wait=0.6)
        dev = next((l.strip() for l in dev.splitlines()
                    if l.strip().startswith("/dev/")), "/dev/sdb2")
        print(f"    dispositivo: {dev}")
        mnt = run_cmd(s, f"mkdir -p /mnt/root && mount -o ro {dev} /mnt/root 2>&1; echo rc=$?",
                      wait=1.2, timeout=20)
        print("   ", " ".join(mnt.split())[:160])
        update_test_progress(test_id, "Montagem do rootfs", f"{dev} -> /mnt/root")
        modbase = "/mnt/root/lib/modules"
    else:
        modbase = "/lib/modules"

    kver = run_cmd(s, "uname -r", wait=0.4)
    kver = next((l.strip() for l in kver.splitlines()
                 if l.strip() and "uname" not in l and "~ #" not in l), "")
    ko = f"{modbase}/{kver}/kernel/drivers/net/ethernet/sony/{MODULO}.ko"
    print(f"--- modulo esperado em: {ko}")

    existe = run_cmd(s, f"ls -la {ko} 2>&1", wait=0.5)
    print("   ", " ".join(existe.split())[:160])

    # o sky2 pode estar segurando o dispositivo
    run_cmd(s, "echo -n '0000:00:14.1' > /sys/bus/pci/drivers/sky2/unbind 2>/dev/null; true", wait=0.4)
    run_cmd(s, f"rmmod {MODULO} 2>/dev/null; true", wait=0.5)
    run_cmd(s, "dmesg -c > /dev/null 2>&1 || true", wait=0.4)

    print(f"--- carregando {MODULO} stage={estagio} ---")
    saida = run_cmd(s, f"insmod {ko} stage={estagio} 2>&1; echo rc=$?",
                    wait=1.5, timeout=25)
    print(saida.strip()[:400])

    if "rc=0" not in saida:
        update_test_progress(test_id, "insmod FALHOU",
                             f"nao foi possivel carregar {ko}: {saida.strip()[:300]}",
                             status="FAIL_INSMOD")
        print("\n!!! insmod falhou — nada foi carregado !!!")
        s.close()
        return

    if not check_ping():
        update_test_progress(test_id, "ABORTADO — perda de ping ao carregar",
                             f"stage={estagio}", status="ABORTED_PING_LOST")
        print("\n!!! console parou de responder ao carregar o driver !!!")
        return

    dmesg = run_cmd(s, "dmesg | tail -60", wait=1.0, timeout=20)
    print("\n--- dmesg ---")
    print(dmesg.strip()[:3000])

    # --- confere o dump do driver contra o baseline ---
    lidos = {int(o, 16): v.lower() for o, v in RE_DUMP.findall(dmesg)}
    batem = divergem = 0
    detalhes = []

    for off, lido in sorted(lidos.items()):
        if off not in baseline:
            continue
        esperado, cls = baseline[off]
        # voláteis e clear-on-read mudam sozinhos: não contam como divergência
        if cls == "VOLATILE" or off in (0x100, 0x104, 0x128, 0x12c):
            continue
        bate = (esperado or "").lower() == lido
        if bate:
            batem += 1
        else:
            divergem += 1
            detalhes.append(f"+0x{off:03x}: baseline={esperado} driver={lido}")
        log_cmp(off, esperado, lido, bate, f"stage={estagio} cls={cls}")

    print(f"\n--- comparação com o baseline ---")
    print(f"  batem: {batem} | divergem: {divergem}")
    for d in detalhes[:20]:
        print(f"    {d}")

    mdio = RE_MDIO.findall(dmesg)
    if mdio:
        print("\n--- MDIO ---")
        vistos = set()
        for devad, reg, nome, val in mdio:
            print(f"    devad={devad} reg={reg} ({nome}) = 0x{val}")
            vistos.add(val)
        print(f"    valores distintos: {len(vistos)}"
              f"  -> {'PHY responde' if len(vistos) > 1 else 'transacao NAO completou'}")

    iplink = run_cmd(s, "ip link show", wait=0.5)
    s.close()

    if "eth0" in iplink:
        status, veredito = "OK_ETH0_ACTIVE", "eth0 APARECEU"
    elif divergem == 0 and batem > 0:
        status, veredito = "OK_DUMP_CONFERE", f"driver leu {batem} registradores iguais ao baseline"
    elif divergem:
        status, veredito = "DIVERGENCIA", f"{divergem} registradores divergem do baseline"
    else:
        status, veredito = "SEM_DADOS", "driver nao produziu dump comparavel"

    update_test_progress(test_id, f"Driver mts stage={estagio}",
                         f"{veredito}\nbatem={batem} divergem={divergem}\n{dmesg.strip()[:1500]}",
                         status=status)

    print("\n" + "=" * 78)
    print(veredito)
    print("=" * 78)


if __name__ == "__main__":
    main()
