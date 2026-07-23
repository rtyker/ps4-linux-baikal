#!/usr/bin/env python3
"""
harness_gbe.py — Test Harness oficial do projeto PS4 Linux Baikal (Varredura Ampla Otimizada).

Executa varredura sistemática em bloco estendido:
 1. BAR2 Pervasive (0xc890a000 .. 0xc890a100) — 64 palavras (256 bytes).
 2. BAR4 Efuses/Trim (0xc900c000 .. 0xc900c100) — 64 palavras (256 bytes).
 3. BAR0 GbE MMIO (0xc2000000 .. 0xc2000200) — 128 palavras (512 bytes).
 4. Sondagem ICC em Lote (/proc/ps4_icc).
 5. Auto-cadastro transacional de safe_to_read = 1 no SQLite (ps4_hardware_memory.db).
 6. Dispara capture_dmesg.py e salva dmesg.log.
"""

import socket
import time
import sys
import datetime
import sqlite3
import re
import subprocess

from mmio_write import build_write_cmd, parse_write_result

PS4_IP = "192.168.6.128"
PS4_PORT = 23

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

# Gerador de intervalos seguros de 4 bytes alinhados
def generate_range_targets(base_addr, count, name_prefix, base_bar, desc_prefix):
    targets = []
    for i in range(count):
        addr = base_addr + (i * 4)
        offset_hex = hex(i * 4)
        reg_name = f"{name_prefix}_{offset_hex.upper()}"
        desc = f"{desc_prefix} Offset {hex(addr)}"
        targets.append((reg_name, addr, desc, base_bar))
    return targets

def get_db_connection():
    return sqlite3.connect(DB_PATH)

def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando bloco de testes...');
    """, (ts, phase, test_name, target, initial_action))
    test_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return test_id

def update_test_progress(test_id, action, info, status="PENDING"):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("""
    UPDATE test_history
    SET action_taken = ?, complementary_info = ?, status = ?
    WHERE id = ?;
    """, (action, info, status, test_id))
    conn.commit()
    conn.close()
    print(f"[{status}] {action} -> {info[:80]}...")

def mark_register_safe_in_db(name, addr, desc, bar_name, raw_val):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    hex_match = re.search(r'\b([0-9a-fA-F]{8})\b', raw_val)
    clean_val = hex_match.group(1) if hex_match else raw_val.strip()

    if addr >= 0xc9000000:
        offset = hex(addr - 0xc9000000)
    elif addr >= 0xc8800000:
        offset = hex(addr - 0xc8800000)
    else:
        offset = hex(addr)

    cursor.execute("SELECT id FROM hardware_registers WHERE reg_name = ? OR (base_bar = ? AND reg_offset = ?);", (name, bar_name, offset))
    exists = cursor.fetchone()
    if exists:
        cursor.execute("""
        UPDATE hardware_registers
        SET safe_to_read = 1, description = ?
        WHERE id = ?;
        """, (f"{desc} (Valor lido ao vivo: 0x{clean_val})", exists[0]))
    else:
        cursor.execute("""
        INSERT INTO hardware_registers (device, base_bar, reg_offset, reg_name, description, safe_to_read, safe_to_write, risk_level)
        VALUES ('Baikal Hardware', ?, ?, ?, ?, 1, 0, 'SAFE');
        """, (bar_name, offset, name, f"{desc} (Valor lido ao vivo: 0x{clean_val})"))
    conn.commit()
    conn.close()

def read_until_prompt(s, prompt=b"~ # ", timeout=5):
    data = b""
    end_time = time.time() + timeout
    while time.time() < end_time:
        try:
            s.settimeout(0.5)
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
            if prompt in data:
                break
        except socket.timeout:
            pass
    return data

def run_cmd(s, test_id, cmd, action_name, wait=0.3):
    update_test_progress(test_id, f"ENVIANDO: {action_name}", f"Executando {cmd}", status="PENDING")
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    res = read_until_prompt(s).decode('ascii', errors='replace')
    update_test_progress(test_id, f"CONCLUÍDO: {action_name}", res.strip(), status="PENDING")
    return res

def run_capture_dmesg():
    try:
        res = subprocess.run(["python3", "capture_dmesg.py", PS4_IP, str(PS4_PORT)], capture_output=True, text=True, timeout=15)
        print(f"[CAPTURE DMESG] {res.stdout.strip()}")
        return res.stdout
    except Exception as e:
        print(f"[CAPTURE DMESG ERRO] {e}")
        return str(e)

def main():
    print("=" * 60)
    print("HARNESS OFICIAL GBE — VARREDURA AMPLA SISTEMÁTICA (SQLITE AUTO-MAPPING)")
    print("=" * 60)

    test_id = create_test_record("Fase 6", "Varredura Ampla Otimizada BAR2/BAR4/BAR0/ICC", "Baikal Southbridge (00:14.1 / BAR2 / BAR4 / BAR0)", "Conectando ao Telnet")

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((PS4_IP, PS4_PORT))
        read_until_prompt(s, timeout=3)
        update_test_progress(test_id, "Conexão Telnet", "Conectado com sucesso na porta 23.", status="PENDING")
    except Exception as e:
        err_msg = f"ERRO DE CONEXÃO: {e}"
        update_test_progress(test_id, "Conexão Telnet", err_msg, status="FAIL_CONNECTION")
        print(err_msg)
        sys.exit(1)

    details = []

    # 1. Checagem inicial eth0
    iplink_init = run_cmd(s, test_id, "ip link show", "Checagem Inicial ip link")
    if "eth0" in iplink_init:
        final_info = f"🎉 VITÓRIA! Interface eth0 JÁ ATIVA!\n\n{iplink_init.strip()}"
        update_test_progress(test_id, "ETH0 DETECTADA", final_info, status="OK_ETH0_ACTIVE")
        s.close()
        run_capture_dmesg()
        sys.exit(0)

    # 2. Leitura PCI Config Space
    cfg = run_cmd(s, test_id, "hexdump -C /sys/bus/pci/devices/0000:00:14.1/config | head -n 4", "Leitura PCI Config 64B")
    details.append(f"=== PCI CONFIG ===\n{cfg.strip()}")

    # 3. BLOCO 1: BAR2 Pervasive Region (0xc890a000 .. 0xc890a0fc - 64 palavras)
    log_bar2 = ["=== VARREDURA SISTEMÁTICA BAR2 PERVASIVE (0xc890a000 .. 0xc890a0fc) ==="]
    bar2_targets = generate_range_targets(0xc890a000, 64, "BAR2_PERV", "BAR2 (0xc8800000)", "BAR2 Pervasive")
    for name, addr, desc, bar_name in bar2_targets:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.15).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_bar2.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_bar2))

    # 4. BLOCO 2: BAR4 Efuses Region (0xc900c000 .. 0xc900c0fc - 64 palavras)
    log_bar4 = ["=== VARREDURA SISTEMÁTICA BAR4 EFUSES (0xc900c000 .. 0xc900c0fc) ==="]
    bar4_targets = generate_range_targets(0xc900c000, 64, "BAR4_EFUSE", "BAR4 (0xc9000000)", "BAR4 Efuse")
    for name, addr, desc, bar_name in bar4_targets:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.15).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_bar4.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_bar4))

    # 5. BLOCO 3: BAR0 GbE MMIO Region 1 (0xc2000000 .. 0xc20001fc - 128 palavras)
    log_bar0 = ["=== VARREDURA SISTEMÁTICA BAR0 MMIO (0xc2000000 .. 0xc20001fc) ==="]
    bar0_targets = generate_range_targets(0xc2000000, 128, "BAR0_MMIO", "BAR0 (0xc2000000)", "BAR0 MMIO")
    for name, addr, desc, bar_name in bar0_targets:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.12).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_bar0.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_bar0))

    # 6. BLOCO 4: BAR0 GbE MMIO Region 2 (0xc2000200 .. 0xc20003fc - 128 palavras)
    log_bar0_2 = ["=== VARREDURA SISTEMÁTICA BAR0 MMIO 2 (0xc2000200 .. 0xc20003fc) ==="]
    bar0_targets_2 = generate_range_targets(0xc2000200, 128, "BAR0_MMIO_2", "BAR0 (0xc2000000)", "BAR0 MMIO Region 2")
    for name, addr, desc, bar_name in bar0_targets_2:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.12).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_bar0_2.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_bar0_2))

    # 7. BLOCO 5: BAR2 BPCIE USB/SATA Region (0xc8980000 .. 0xc898003c - 16 palavras)
    log_bpcie = ["=== VARREDURA BAR2 BPCIE USB/SATA (0xc8980000 .. 0xc898003c) ==="]
    bpcie_targets = generate_range_targets(0xc8980000, 16, "BAR2_BPCIE", "BAR2 (0xc8800000)", "BAR2 BPCIE Glue")
    for name, addr, desc, bar_name in bpcie_targets:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.12).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_bpcie.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_bpcie))

    # 8. BLOCO 6: BAR0 GbE MMIO Region 3 (0xc2000400 .. 0xc20005fc - 128 palavras)
    log_bar0_3 = ["=== VARREDURA SISTEMÁTICA BAR0 MMIO 3 (0xc2000400 .. 0xc20005fc) ==="]
    bar0_targets_3 = generate_range_targets(0xc2000400, 128, "BAR0_MMIO_3", "BAR0 (0xc2000000)", "BAR0 MMIO Region 3")
    for name, addr, desc, bar_name in bar0_targets_3:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.12).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_bar0_3.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_bar0_3))

    # 9. BLOCO 7: AHCI SATA Controller BAR5 (0xce800000 .. 0xce8000fc - 64 palavras)
    log_ahci = ["=== VARREDURA AHCI SATA BAR5 (0xce800000 .. 0xce8000fc) ==="]
    ahci_targets = generate_range_targets(0xce800000, 64, "AHCI_SATA", "BAR5 (0xce800000)", "AHCI SATA Controller")
    for name, addr, desc, bar_name in ahci_targets:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.12).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_ahci.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_ahci))

    # 10. BLOCO 8: xHCI USB 3.0 Controller BAR0 (0xce000000 .. 0xce0000fc - 64 palavras)
    log_xhci = ["=== VARREDURA xHCI USB3 BAR0 (0xce000000 .. 0xce0000fc) ==="]
    xhci_targets = generate_range_targets(0xce000000, 64, "XHCI_USB3", "BAR0 (0xce000000)", "xHCI USB3 Controller")
    for name, addr, desc, bar_name in xhci_targets:
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        val = run_cmd(s, test_id, cmd, f"Read {name} ({hex(addr)})", wait=0.12).strip()
        line = f"[{name}] {hex(addr)} = {val}"
        log_xhci.append(line)
        if val and len(val) >= 4 and "error" not in val.lower():
            mark_register_safe_in_db(name, addr, desc, bar_name, val)
    details.append("\n".join(log_xhci))

    # 6. BLOCO 4: Sondagem ICC Ampliada
    log_icc = ["=== SONDAGEM ICC AMPLIADA (/proc/ps4_icc) ==="]
    for maj in [0x0e, 0x05]:
        for minor in range(0x00, 0x15):
            icc_cmd = f"echo '{maj} {minor}' > /proc/ps4_icc && cat /proc/ps4_icc"
            res_icc = run_cmd(s, test_id, icc_cmd, f"ICC Major {hex(maj)} Minor {hex(minor)}", wait=0.2).strip()
            log_icc.append(f"[ICC Maj {hex(maj)} Min {hex(minor)}] -> {res_icc}")
    details.append("\n".join(log_icc))

    # 11. BLOCO 9: SEQUÊNCIA DE PULSO 4-PASSO DO BIT 10 (0x0400) NA BAR2
    #
    # CORRIGIDO 2026-07-22: este bloco usava `devmem`, que NÃO EXISTE neste
    # sistema (exit 127) e era mascarado por `2>/dev/null` — ou seja, NENHUMA
    # execução histórica deste harness chegou a escrever coisa alguma aqui.
    # Agora usa printf octal + dd (mmio_write.py) e ABORTA o bloco se a escrita
    # não for confirmada, em vez de seguir e reportar "sem efeito".
    # Ver memory/devmem-nao-existe-usar-dd-octal.md
    update_test_progress(test_id, "BIT 10 GBE PULSE", "Iniciando sequência de pulso de 4 passos no Bit 10 (0x0400) da BAR2", status="PENDING")

    pulso_passos = [
        (0xc890a034, 0x00000400, "Passo 1: Hold Mask Bit 10 (0x0400)"),
        (0xc890a030, 0x000016c9, "Passo 2: Clock Strobe Bit 10"),
        (0xc890a034, 0x00000000, "Passo 3: Release Hold Mask"),
    ]
    pulso_ok = True
    for addr_w, val_w, label_w in pulso_passos:
        saida_w = run_cmd(s, test_id, build_write_cmd(addr_w, val_w), label_w)
        ok_w, detalhe_w = parse_write_result(saida_w)
        if not ok_w:
            update_test_progress(
                test_id, f"ESCRITA FALHOU: {label_w}",
                f"{hex(addr_w)}: {detalhe_w}. A escrita NÃO ocorreu — "
                f"não interpretar o resultado como 'pulso sem efeito'.",
                status="FAIL_ESCRITA_NAO_OCORREU")
            details.append(f"=== BLOCO 9 ABORTADO ===\n{label_w} em {hex(addr_w)}: {detalhe_w}")
            pulso_ok = False
            break
        update_test_progress(test_id, f"escrita confirmada: {label_w}", detalhe_w)
        time.sleep(0.15)

    if pulso_ok:
        time.sleep(0.2)

    # Passo 4: leitura pós-pulso da BAR0 0x118.
    # NOTA 2026-07-22: 0x118 é B2_CONN_TYP no mapa do sky2, NÃO o chip id.
    # B2_CHIP_ID é 0x11b (1 byte) — o byte mais alto deste dword. E o hardware
    # é MTS, não Yukon, então nenhum dos dois rótulos vale aqui de fato.
    chip_post = run_cmd(s, test_id, "dd if=/dev/mem bs=4 count=1 skip=$(( 0xc2000118 / 4 )) 2>/dev/null | od -An -tx4", "Passo 4: Leitura BAR0 0x118 pós-pulso").strip()
    details.append(f"=== BAR0 0x118 PÓS-PULSO BIT 10 (B2_CONN_TYP, não chip id) ===\nBAR0 0x118: {chip_post}")

    # 12. Finalização e Rebind sky2
    run_cmd(s, test_id, "echo -n '0000:00:14.1' > /sys/bus/pci/drivers/sky2/unbind 2>/dev/null || true", "Unbind sky2")
    time.sleep(0.3)
    run_cmd(s, test_id, "echo -n '0000:00:14.1' > /sys/bus/pci/drivers/sky2/bind 2>/dev/null", "Bind sky2")
    time.sleep(0.5)

    iplink = run_cmd(s, test_id, "ip link show", "Checagem Final ip link")
    details.append(f"=== IP LINK ===\n{iplink.strip()}")

    full_log = "\n\n".join(details)
    status_final = "OK_ETH0_ACTIVE" if "eth0" in iplink else "OK_FULL_SCAN_COMPLETE"

    update_test_progress(test_id, "Varredura Ampla Concluída", full_log, status=status_final)
    s.close()

    print("\nExecutando capture_dmesg.py para gerar dmesg.log local...")
    run_capture_dmesg()

    print("=" * 60)
    print(f"VARREDURA AMPLA CONCLUÍDA COM SUCESSO! (ID: {test_id}, STATUS: {status_final})")
    print("=" * 60)

if __name__ == "__main__":
    main()
