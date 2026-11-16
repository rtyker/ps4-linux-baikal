# icc_cmd — um comando ICC por vez, pelo `/dev/icc`

Ferramenta de userspace para a **Fase 1** do `others/docs/PLANO_S5_POWEROFF_ICC.md`. Ela manda o S5 (major 4, minor 1) **com o Linux rodando**, ou seja, com IRQs e LAPIC vivos. Assim a resposta da MCU chega e dá para separar:
- **H1 (contexto):** o comando está certo, mas o `pm_power_off` o envia num momento em que o ICC não funciona;
- **H2 (payload):** a MCU recebe e rejeita.

Não precisa de build de kernel. Usa o ioctl `ICC_IOCTL_CMD` que o `ps4-bpcie-icc` já expõe.

## Build (host)
```bash
cd /mnt/hdauxiliar/ps4-linux-baikal/others/tools/icc_cmd
./build.sh          # gera icc_cmd estático (roda no rootfs Arch sem depender da glibc dele)
```

## Uso (PS4, como root)
```bash
sshpass -p ps4 scp icc_cmd root@192.168.6.128:/tmp/
sshpass -p ps4 ssh root@192.168.6.128 /tmp/icc_cmd selftest   # 2/6 = versão do FW
```
O `selftest` valida a ferramenta com o mesmo comando que o driver manda no boot (`do_icc_init`). Só passar para o S5 se o selftest responder.

### Teste S5
1. No host, iniciar a UART (opcional, para ver o kernel): `./others/scripts/uart_start.sh 120 s5-fase1`.
2. No PS4:
   ```bash
   sync; mount -o remount,ro /
   /tmp/icc_cmd s5 --yes 2>&1 | tee /dev/kmsg
   ```
   Envia `4/1` com `{0,0,2,0,1,0}`, o mesmo payload do `icc_shutdown` original, que vai com 20 bytes depois do padding do driver.

| Resultado | Conclusão |
|---|---|
| Console desliga (luz apaga, fan para) | Payload certo → **H1**. Corrigir só o momento do envio (Fase 2A) |
| `ioctl ok` + reply, console continua ligado | MCU recebeu e não desligou → **H2/H3**. Guardar o reply (pode ter código de status) |
| `ioctl falhou: Connection timed out` | Problema no canal 4/x. Comparar com 4/0x38 (GBE), que exige retry |
| `ioctl falhou: Input/output error` | Checksum ou major/minor da resposta errados (ver `dmesg`) |

Registrar o resultado em `test_history` (`others/rea/ps4_hardware_memory.db`).

### `raw`
`icc_cmd raw <major> <minor> [payload_hex] [--reply N] --yes`: um comando arbitrário. **Só payloads de origem conhecida.** Nunca usar em laço para varrer minors (AGENTS.md: varrer ICC com data=1 derruba o console).

## Notas
- O driver chama `register_chrdev` sem `device_create`, então o udev não cria `/dev/icc`. A ferramenta cria `c 73 0` se ele não existir.
- O `_Static_assert` confere que o layout de `struct icc_cmd` bate com o do kernel x86_64 (40 bytes).
- O ioctl usa o mesmo mutex do driver. Se outro driver (fan, LED, RTC) estiver no meio de um comando, ele espera.
