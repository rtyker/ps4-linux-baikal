# TODO: Habilitar Rede Ethernet e Netconsole no PS4

Este guia contém as etapas necessárias para fazer a interface de rede cabeada (`eth0`) ser detectada e funcionar no PS4, resolvendo o erro `eth0 doesn't exist` no boot.

---

## 1. Contexto do Problema
* O kernel do PS4 tentou iniciar o `netconsole` usando a interface `eth0`, mas falhou com `eth0 doesn't exist, aborting`.
* No `ip addr`, apenas `lo`, `wlan0` (WiFi) e interfaces `ap` estão presentes. A placa de rede física (Realtek RTL8111) não foi inicializada.
* **Causas identificadas:**
  1. O driver de rede com fio (`r8169`) é um módulo do kernel (`.ko`) e a pasta `/usr/lib/modules/` da imagem (gerada a partir do bootstrap) está vazia.
  2. Falta o firmware da placa Realtek em `/usr/lib/firmware/rtl_nic/`.

---

## 2. Passos para Solução (Executar no PC Host com o HD USB montado)

### Passo 1: Instalar os Módulos do Kernel no HD
No PC Host onde o kernel Neocine foi compilado, monte a partição rootfs do HD (ext4, ex: em `/mnt/root`). A partir do diretório onde o código-fonte do kernel foi compilado, execute:

```bash
sudo make modules_install INSTALL_MOD_PATH=/mnt/root
```
*Isso criará a estrutura `/mnt/root/usr/lib/modules/5.4.247-neocine-1.1/` com todos os drivers do kernel, incluindo o `r8169.ko`.*

### Passo 2: Copiar os Firmwares da Realtek para o HD
Ainda com o HD montado no PC Host, copie a pasta de firmware da Realtek do seu PC para o HD:

```bash
sudo mkdir -p /mnt/root/usr/lib/firmware/rtl_nic
sudo cp -r /usr/lib/firmware/rtl_nic/* /mnt/root/usr/lib/firmware/rtl_nic/
```

### Passo 3: Sincronizar e Desmontar
Aplique as alterações gravadas em disco e desmonte as partições de forma segura antes de ejetar o HD:

```bash
sync
sudo umount /mnt/root
```

---

## 3. Teste no PS4
1. Conecte o HD USB e o cabo de rede no PS4.
2. Configure o PC Host com o IP estático `192.168.0.1/24`:
   ```bash
   sudo ip address add 192.168.0.1/24 dev <nome_da_interface_ethernet>
   sudo ip link set <nome_da_interface_ethernet> up
   ```
3. Abra um terminal no PC Host e escute na porta UDP 6666 para receber as mensagens do netconsole:
   ```bash
   nc -u -l -p 6666
   ```
4. Envie o payload no PS4. Os logs do kernel devem começar a fluir imediatamente no terminal do PC.
