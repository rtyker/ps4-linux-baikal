#!/usr/bin/env python3
import socket
import time
import base64
import os
import tarfile
import io

HOST = '192.168.6.128'
PORT = 23

def fetch_firmware():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((HOST, PORT))
    time.sleep(0.5)
    s.recv(4096)  # consume initial prompt/banner
    
    cmd = b"cd /lib/firmware/amdgpu && tar czf - gladius_*.bin | base64\necho '___END_OF_BASE64___'\nexit\n"
    s.sendall(cmd)
    
    data = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
        if b"___END_OF_BASE64___" in data:
            break
    s.close()
    
    text = data.decode('utf-8', errors='ignore')
    lines = text.splitlines()
    
    b64_lines = []
    capturing = False
    for line in lines:
        line = line.strip()
        if "___END_OF_BASE64___" in line:
            break
        if line.startswith("H4sI"):
            capturing = True
        if capturing and line:
            b64_lines.append(line)
            
    b64_str = "".join(b64_lines)
    raw_tar = base64.b64decode(b64_str)
    
    out_dir = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/firmware_gladius_real"
    os.makedirs(out_dir, exist_ok=True)
    
    with tarfile.open(fileobj=io.BytesIO(raw_tar), mode="r:gz") as tar:
        tar.extractall(path=out_dir)
        print(f"Extracted {len(tar.getmembers())} firmware files to {out_dir}:")
        for member in tar.getmembers():
            full_path = os.path.join(out_dir, member.name)
            print(f" - {member.name}: {os.path.getsize(full_path)} bytes")

if __name__ == '__main__':
    fetch_firmware()
