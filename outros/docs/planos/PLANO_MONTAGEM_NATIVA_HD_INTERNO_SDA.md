# Plano de Implementação: Montagem Nativa do HD Interno (/dev/sda) no PS4 Linux

## Visão Geral e Objetivo
Com a comunicação SATA do controlador Ahci/Baikal 100% estabilizada no Kernel 7.0 (`20260730-sata-polling-fase-ab`), o disco interno (`/dev/sda` - Toshiba 1TB) está estável e sem resets. 

O objetivo final deste trabalho é **tornar a montagem das partições do HD interno a mais nativa e transparente possível** dentro da nossa distro customizada **Arch Minimal v2**.

---

## Estrutura em 3 Fases

```mermaid
flowchart TD
    subgraph FASE 1: Entendimento & Inspeção Read-Only
        A1[Conectar via SSH] --> A2[Inspecionar partições: sda1 a sda29]
        A2 --> A3[Identificar sistemas de arquivos: FAT32, ext4, UFS2/PFS]
        A3 --> A4[Entender mecanismo de chave /dev/ps4_keys e dm-crypt]
        A4 --> A5[Testes manuais de montagem -o ro]
    end

    subgraph FASE 2: Scripting Modular de Teste
        B1[Desenvolver /usr/local/bin/monta_particao.sh] --> B2[Suporte a auto-detecção FAT32 / ext4 / Orbis Crypto]
        B2 --> B3[Testar comandos simples: monta_particao.sh /dev/sda1]
        B3 --> B4[Desenvolver desmonta_particao.sh limpo]
    end

    subgraph FASE 3: Integração Nativa na Distro Customizada
        C1[Garantir suporte a cryptsetup/fuse/UFS no Kernel 7.0] --> C2[Adicionar pacotes/regras udev no Arch Minimal v2]
        C2 --> C3[Atualizar 01-build-image-7.0.sh para autostart/automount]
        C3 --> C4[Validação completa em boot frio + SSH/Desktop]
    end

    FASE 1 --> FASE 2 --> FASE 3
```

---

## User Review Required

> [!IMPORTANT]
> **GARANTIA INTEGRAL DE READ-ONLY (MODO SOMENTE-LEITURA)**
> - Nas Fases 1 e 2, **todas as partições serão montadas com `-o ro` (read-only)** ou passadas para o `dm-crypt`/`fuse` em modo seguro.
> - Nenhuma operação de escrita (`mkfs`, `dd of=`, `mount -o rw`) será executada no `/dev/sda` sem autorização explícita.
> - Todos os pontos de montagem serão criados em subdiretórios dedicados (ex: `/mnt/ps4_internal/sda1`, `/mnt/ps4_internal/sda27`), respeitando a regra imperativa do projeto de **nunca montar nada diretamente no diretório raiz `/mnt`**.

---

## Open Questions

> [!QUESTION]
> 1. **SSH e Acesso ao PS4**: O console PS4 está atualmente ligado e pronto para iniciarmos os testes de inspeção via SSH (`root@192.168.6.128`)?
> 2. **Utilitário de Referência**: Você possui algum script baixado ou de alguma distro (ex: Psxitarch v3.1 ou repositório da comunidade) que deseja que usemos como base primária de código na Fase 1?

---

## Detalhamento das Fases

### FASE 1: Entendimento, Inspeção e Testes Read-Only via SSH

1. **Varredura Completa do `/dev/sda`**:
   - Conectar via SSH (`root@192.168.6.128`) e executar comandos de diagnóstico não-destrutivos em todas as partições existentes:
     ```bash
     # Mapeamento do layout GPT
     lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTUUID /dev/sda

     # Tabela detalhada de partições GPT
     fdisk -l /dev/sda

     # Assinatura de blocos e cabeçalhos de arquivos
     blkid /dev/sda*

     # Identificação profunda de tipo de arquivo
     file -s /dev/sda*
     ```

2. **Análise dos Tipos de Partições Encontradas**:
   - **Partições FAT32/ext4 não criptografadas**: Montagem direta via Linux `mount -t vfat -o ro /dev/sda1 /mnt/ps4_internal/sda1`.
   - **Partições Criptografadas Orbis OS (PFS/UFS2)**:
     - Analisar o funcionamento de `/dev/ps4_keys` (dispositivo exposto pelo driver do kernel/payload) ou das chaves de boot.
     - Entender como os utilitários da comunidade usam `cryptsetup` (dm-crypt) com a chave EAP/SAMU para expor o bloco não-criptografado em `/dev/mapper/ps4_sdaX` antes de montar o UFS2/PFS.

3. **Testes Manuais de Montagem Read-Only**:
   - Criar diretório seguro: `mkdir -p /mnt/ps4_internal/sda1`
   - Testar montagem e validação com `ls -la` e `df -h`.

---

### FASE 2: Scripting Modular (`monta_particao.sh`)

1. **Desenvolvimento do Script `monta_particao.sh`**:
   - Criar um utilitário simples em bash que aceita como argumento o dispositivo (ex: `/dev/sda1` ou `/dev/sda27`).
   - O script identificará automaticamente:
     - Se é uma partição comum (FAT32/ext4) → executa `mount -o ro`.
     - Se é uma partição criptografada Orbis → carrega a chave necessária via `cryptsetup` / `/dev/ps4_keys` e realiza o mount read-only em `/mnt/ps4_internal/<particao>`.
   
2. **Sintaxe do Script Proposto**:
   ```bash
   # Exemplo de uso:
   sudo monta_particao.sh /dev/sda1
   sudo monta_particao.sh /dev/sda27

   # Desmontagem limpa:
   sudo desmonta_particao.sh /dev/sda27
   ```

---

### FASE 3: Integração Nativa na Distro Customizada (Arch Minimal v2)

1. **Requisitos de Kernel e Sistema**:
   - Verificar se o Kernel 7.0 tem suporte habilitado para `CONFIG_UFS_FS` (Read-Only FreeBSD UFS), `CONFIG_BLK_DEV_DM` e `CONFIG_DM_CRYPT`.
   - Incluir pacotes essenciais no rootfs Arch Linux: `cryptsetup`, `fuse2`, `fuse3`, `dosfstools`, `e2fsprogs`.

2. **Regras `udev` e Montagem Automática/Sob Demanda**:
   - Criar regra udev `/etc/udev/rules.d/99-ps4-internal-hdd.rules` para criar automaticamente symlinks amigáveis (ex: `/dev/ps4/user_data` -> `/dev/sda27`).
   - Integrar os scripts `monta_particao.sh` em `/usr/local/bin/` do Arch Minimal v2.
   - Atualizar `01-build-image-7.0.sh` para incluir essas regras e ferramentas nativamente na geração de novas imagens.

---

## Plano de Verificação

### Testes Manuais via SSH
1. **Verificação de Partições**: Executar `lsblk` no PS4 e confirmar a catalogação completa das 29 partições.
2. **Validação de Montagem Read-Only**: Confirmar que o comando `mount | grep sda` indica `ro` (read-only) e que tentativas de escrita (`touch /mnt/ps4_internal/sda1/teste.txt`) falham com `Read-only file system` (comportamento correto e seguro).
3. **Validação de I/O e Uptime**: Acompanhar `dmesg | tail -n 20` para verificar se não há exceções no barramento SATA durante acessos a arquivos grandes.
