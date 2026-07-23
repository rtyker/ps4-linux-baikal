# PS4 Linux Pós-Instalação Script

## Descrição
O `pos_install.sh` é um script automatizado que configura todos os ajustes necessários após a instalação do Arch Linux no PS4. Ele organiza todas as instruções pós-instalação em um fluxo estruturado e interativo.

## Uso

### Pré-requisitos
- Ter o Arch Linux instalado no PS4
- Executar como root (`sudo ./pos_install.sh`)
- Conexão com internet para downloads e atualizações

### Execução
```bash
sudo ./pos_install.sh
```

## Fluxo do Script

### 1. Configuração de Tempo do Sistema
- Define timezone para America/Sao_Paulo
- Habilita sincronização NTP
- Desativa RTC local
- Verifica configurações de tempo

### 2. Configuração de Locale
- Define keymap brasileiro (br-abnt2)
- Gera locales pt_BR.UTF-8 e en_US.UTF-8
- Configura sistema para locale brasileiro
- Cria arquivo vconsole.conf

### 3. Configuração de Swap
- Cria arquivo de swap de 8GB
- Define permissões corretas
- Habilita swap
- Adiciona ao fstab
- Define swappiness para 90

### 4. Verificação da Idade da Distro
- Mostra data de instalação do sistema
- Ajuda a identificar se é uma instalação recente ou antiga

### 5. Reset do Banco de Dados do Pacman
- Limpa cache do pacman
- Reinitializa keyring
- Atualiza keyrings Arch e Chaotic
- Prepara para atualização completa

### 6. Atualização do Sistema
- Atualiza bancos de dados de pacotes
- Atualiza todos os pacotes do sistema
- Resolve dependências automaticamente

### 7. Configuração Mesa/Vulkan
- Instala pacotes Mesa e Vulkan para PS4
- Configura drivers gráficos
- Verifica instalação do Vulkan

### 8. Configuração Mesa Customizada (Opcional)
- Baixa e instala Mesa customizado para PS4
- Configura otimizações específicas
- Testa funcionalidade do Vulkan

### 9. Instalação de Pacotes Adicionais
- Instala Steam
- Instala suporte a joystick
- Instala RetroArch
- Instala ferramentas de rede

### 10. Verificação Final do Sistema
- Verifica todas as configurações
- Mostra status do sistema
- Confirma se tudo está funcionando

## Personalização

### Variáveis Editáveis
Você pode modificar o script para personalizar:

- Tamanho do arquivo de swap (`swap_size="8G"`)
- Pacotes adicionais na função `install_additional_packages`
- Keymap e locale padrão
- Opções de instalação

### Desabilitando Passos
Cada passo tem uma confirmação interativa. Você pode pular qualquer passo respondendo "N" quando solicitado.

## Solução de Problemas

### Problemas Comuns

#### 1. Pacman não consegue atualizar
```bash
# Resetar manualmente o pacman
sudo rm -rf /var/lib/pacman/sync/*
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman -Syy
```

#### 2. Vulkan não funciona
```bash
# Verificar drivers Vulkan
vulkaninfo | grep driverInfo

# Reinstalar Mesa
sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
```

#### 3. Swap não funciona
```bash
# Verificar status do swap
swapon --show
free -h

# Recriar swap
sudo swapoff -a
sudo rm /swapfile
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Logs do Script
O script não salva logs, mas você pode redirecionar a saída:
```bash
sudo ./pos_install.sh > install_log.txt 2>&1
```

## Referências

### Documentação Oficial
- [PS4 Linux Documentation](https://ps4linux.com/)
- [Arch Linux Wiki](https://wiki.archlinux.org/)
- [PS4 Linux Kernel FAQ](https://ps4linux.com/ps4-linux-kernel-faq/)

### Tutoriais
- [PS4 Pro Vulkan Fix](https://ps4linux.com/ps4-pro-fix-vulkan-fix-crash/)
- [Custom Mesa para PS4](https://github.com/noob404yt/ps4-custom-mesa-archlinux)
- [SteamOS 3 para PS4](https://ps4linux.com/steamos-3-ps4-nazky/)

## Changelog

### v1.0
- Script inicial completo
- Todos os passos pós-instalação implementados
- Interface interativa com confirmações
- Tratamento de erros básico
- Suporte a múltiplos tipos de distros (Arch, CachyOS)

## Licença
Este script é fornecido como está, sem garantias. Use por sua conta e risco.

## Contato
Para sugestões ou problemas, verifique a documentação oficial do PS4 Linux.