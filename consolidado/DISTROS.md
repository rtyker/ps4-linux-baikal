# Distribuições Linux para PS4

## Catálogo de Distros Disponíveis

### Base Arch Linux

| Nome | Versão | Criador | Status |
|------|--------|---------|--------|
| **Psxitarch v3.1 (Unofficial)** | v3.1 | ITmania | **RECOMENDADA** - Interface LXDE, autologin, script de montagem HDD interno |
| CachyOS | RC | elokuba | Melhor visualmente (KDE), tudo funcionou, ocupa muito espaço |
| Garuda Linux | RC1 | elokuba | Disponível para teste |
| EndeavourOS | - | elokuba | Disponível |
| Manjaro | - | elokuba / Darkstorm | Disponível |
| ArchLinux PS4 | v2 | whitehax0r | Mínimo |
| ArchLinux PS4 | - | Darkstorm | Disponível |
| **Arch Minimal** | - | centi07 | **BOA PARA APRENDIZADO** - Vem "seca", precisa instalar tudo manualmente |
| **Arch Minimal v2** | 2026.07 | Oficial (Bootstrap) | **TESTANDO** - O Arch Linux mais puro e mínimo possível, gerado do bootstrap oficial |
| Psxitarch v3 | v3 | PS3ITA | Não abriu Xorg |
| Psxitarch v2 | v2 | PS3ITA | Versão antiga |
| SteamOS 3.0 | 3.0 | Nazky | SteamOS para PS4 |
| WinesapOS | 3.0 | Noob404 | Wine/Steam integrado |
| Salient OS | v2 | Darkstorm | Disponível |
| ArchLabs | - | Darkstorm | Disponível |
| ArcoLinux | - | Darkstorm | Disponível |
| BlackArch Linux | - | Darkstorm | Segurança/Pentest |
| Bluestar Linux | - | Darkstorm | Disponível |
| Mabox Linux | - | Darkstorm | Disponível |
| RebornOS | - | Darkstorm | Disponível |
| TEArch | - | Darkstorm | Edição Inglês |
| Catjaro | - | ITmania | Disponível |

### Base Fedora

| Nome | Versão | Criador | Status |
|------|--------|---------|--------|
| Fedora 38 | 38 | DF_AUS | Disponível |
| Fedora 37 | 37 | Wizbang | Disponível |
| Nobara | 36 | Noob404 | Fedora modificado para gaming |
| Nobara | 35 | Noob404 | Versão anterior |
| Fedora 35 | 35 | Noob404 | Disponível |
| Fedora 32 Tron | 32 | ITmania | Edição especial |
| Fedora 32 | 32 | Modded Warfare | Tutorial no YouTube |

### Base Ubuntu/Debian

| Nome | Versão | Criador | Status |
|------|--------|---------|--------|
| Pop!_OS | 22.04 | Noob404 | Disponível |
| Pop!_OS | 21.10 | Noob404 | Versão anterior |
| Xubuntu | 25.04 | triki1 | Disponível |
| Debian Sid/Forky | - | triki1 | Testing |
| Debian Trixie | - | triki1 | Testing |
| Lubuntu | 21.10 | ITmania | Leve |
| Ubuntu | 19.04 | ITmania | Versão antiga |

### Outras

| Nome | Versão | Criador | Status |
|------|--------|---------|--------|
| **Batocera 40** | 40 | Noob404 | **EXCELENTE** - Kodi + emuladores, sistema embarcado |
| Batocera v1 | v1 | Noob404 | Primeira versão |
| Debian | 11 | Darkstorm | Disponível |
| Debian | 10 | ITmania | Disponível |
| Encom OS | - | ITmania | Disponível |
| Deepin | - | ITmania | Disponível |
| Puppy Linux | - | - | Super leve |
| Bolt Pup | 22.04 | - | Base Ubuntu |
| Leon Pup | Beta v1 | - | Base Ubuntu |

## Distros Testadas

| Distro | Resultado | Observações |
|--------|-----------|-------------|
| **Steam4PS** | Funcionou parcialmente | Bugada, trabalhosa de configurar |
| **Arch Minimal** | Funcionou | Só funciona com payload 4GB, sistema "seco" |
| **Psxitarch v2** | Falhou | Não abriu Xorg |
| **Batocera 40** | **Funcionou bem** | Kodi + emuladores, sistema embarcado |
| **CachyOS** | **Funcionou** | Melhor visualmente (KDE), mas ocupa muito espaço |
| **Psxitarch v3.1** | **FUNCIONOU** | **Recomendada** - Interface leve LXDE, autologin |

## Detalhes das Distros Recomendadas

### Psxitarch v3.1 (ITmania)
- **Usuário/Senha**: psxita / changeit
- **Interface**: LXDE (leve)
- **Payload**: 3GB ou 4GB
- **Diferenciais**: Script de montagem de HDD interno fantástico, autologin
- **Download**: https://ps4linux.com/downloads/#Arch_based_PS4_Linux_Distros

### Arch Minimal (centi07)
- **Usuário/Senha**: root / ps4l, ps4lnux / ps4linux
- **Interface**: Nenhuma (linha de comando)
- **Payload**: 4GB (preferencial)
- **Download**: https://ps4linux.com/forums/d/413-archlinux-minimal
- **Git**: https://github.com/centi07/arch-ps4-aur

### Arch Minimal v2 (Bootstrap Oficial)
- **Origem**: Gerado diretamente do bootstrap oficial do Arch Linux (`archlinux-bootstrap-x86_64.tar.zst`).
- **Pasta**: `distros/arch_minimal_v2/`
- **Uso**: Pode ser utilizado como base de build no script consolidado executando:
  `sudo ./build_latest_distro.sh strawberry ../distros/arch_minimal_v2/arch_minimal_v2.tar`

### Batocera 40 (Noob404)
- **Foco**: Emuladores e Kodi
- **Ideal para**: Retro gaming e mídia
- **Payload**: 3GB

## Notas sobre Payloads e Boot

- **Payload 1GB**: Boot rápido na TV, mas com erros no Arch Minimal
- **Payload 2GB**: Não deu boot no Arch Minimal
- **Payload 3GB**: Deu boot na maioria das distros
- **Payload 4GB**: Recomendado para a maioria das situações
- Distros podem funcionar em TV mas não em monitor (fora de escala/tela preta)
