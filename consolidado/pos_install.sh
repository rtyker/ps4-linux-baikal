#!/bin/bash

# PS4 Linux Pós-Instalação Script
# Automatiza todos os ajustes necessários após a instalação do Arch Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run this script as root"
        exit 1
    fi
}

# Function to confirm action
confirm_action() {
    local message="$1"
    read -p "$message (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Action skipped"
        return 1
    fi
    return 0
}

# Step 1: System Time Configuration
setup_system_time() {
    print_step "Configuring system time and timezone..."
    
    print_status "Setting timezone to America/Sao_Paulo"
    timedatectl set-timezone America/Sao_Paulo
    
    print_status "Enabling NTP time synchronization"
    timedatectl set-ntp true
    
    print_status "Disabling local RTC"
    timedatectl set-local-rtc 0
    
    print_status "Linking timezone file"
    ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
    
    print_status "Verifying current time settings:"
    timedatectl
}

# Step 2: Locale Configuration
setup_locale() {
    print_step "Configuring system locale..."
    
    print_status "Setting Brazilian keymap"
    loadkeys br-abnt2
    
    print_status "Generating locales"
    bash -c 'echo -e "en_US.UTF-8 UTF-8\npt_BR.UTF-8 UTF-8" > /etc/locale.gen'
    locale-gen
    
    print_status "Setting system locale"
    localectl set-locale LANG=pt_BR.UTF-8
    echo LANG=pt_BR.UTF-8 | tee /etc/locale.conf
    
    print_status "Creating vconsole.conf"
    cat > /etc/vconsole.conf << EOF
KEYMAP=br-abnt2
EOF
    
    print_status "Setting current keymap"
    setxkbmap br abnt2
    
    print_status "Locale configuration completed"
}

# Step 3: Swap File Setup
setup_swap() {
    print_step "Setting up swap file..."
    
    local swap_size="8G"
    
    print_status "Current swap status:"
    swapon --show
    
    if confirm_action "Remove existing swap and create new $swap_size swap file?"; then
        print_status "Removing existing swap"
        swapoff -a 2>/dev/null || true
        
        print_status "Creating $swap_size swap file"
        dd if=/dev/zero of=/swapfile bs=1M count=$((1024*8)) status=progress
        
        print_status "Setting permissions on swap file"
        chmod 600 /swapfile
        
        print_status "Formatting swap file"
        mkswap /swapfile
        
        print_status "Enabling swap file"
        swapon /swapfile
        
        print_status "Adding swap to fstab"
        echo '/swapfile none swap defaults 0 0' | tee -a /etc/fstab
        
        print_status "Setting swappiness to 90"
        sysctl vm.swappiness=90
        echo 'vm.swappiness=90' | tee /etc/sysctl.d/99-swappiness.conf
        
        print_status "Verifying swap setup:"
        free -h
    else
        print_warning "Swap setup skipped"
    fi
}

# Step 4: Distro Age Check
check_distro_age() {
    print_step "Checking distro age..."
    
    print_status "Distribution installation date:"
    ls -ld /
    
    print_warning "Check if this is a recent installation or an old one"
    print_warning "Older distros may need more extensive updates"
}

# Step 5: Pacman Database Reset
reset_pacman_db() {
    print_step "Resetting pacman database (recommended before updates)..."
    
    if confirm_action "Reset pacman database? This may take a while..."; then
        print_status "Commenting community repository temporarily"
        sed -i 's/\[community\]/;[community]/' /etc/pacman.conf
        
        print_status "Cleaning pacman sync database"
        rm -rf /var/lib/pacman/sync/*
        
        print_status "Cleaning pacman GPG keys"
        rm -rf /etc/pacman.d/gnupg
        
        print_status "Initializing pacman keyring"
        pacman-key --init
        
        print_status "Populating Arch Linux keys"
        pacman-key --populate archlinux
        
        # Check if it's a CachyOS distro
        if grep -q "cachyos" /etc/os-release; then
            print_status "Populating CachyOS keys"
            pacman-key --populate cachyos
            pacman -Syy cachyos-keyring
        fi
        
        print_status "Restoring community repository"
        sed -i 's/;\[community\]/[community]/' /etc/pacman.conf
        
        print_status "Updating Arch and Chaotic keyrings"
        pacman -Syy archlinux-keyring chaotic-keyring --overwrite '*'
        
        print_status "Cleaning package cache"
        pacman -Scc
        
        print_status "Pacman database reset completed"
    else
        print_warning "Pacman database reset skipped"
    fi
}

# Step 6: System Update
update_system() {
    print_step "Updating system packages..."
    
    if confirm_action "Update system packages? This may take a while..."; then
        print_status "Updating package databases"
        pacman -Syy
        
        print_status "Upgrading all packages"
        pacman -Syyuu --overwrite '*'
        
        print_status "System update completed"
    else
        print_warning "System update skipped"
    fi
}

# Step 7: Mesa/Vulkan Setup
setup_mesa_vulkan() {
    print_step "Setting up Mesa/Vulkan for PS4..."
    
    if confirm_action "Install Mesa/Vulkan packages for PS4?"; then
        print_status "Installing Mesa and Vulkan packages"
        pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon --noconfirm
        
        print_status "Verifying Vulkan installation"
        if command -v vulkaninfo >/dev/null 2>&1; then
            vulkaninfo | grep driverInfo || true
        else
            print_warning "vulkaninfo not found, Vulkan may not be properly installed"
        fi
        
        print_status "Mesa/Vulkan setup completed"
    else
        print_warning "Mesa/Vulkan setup skipped"
    fi
}

# Step 8: Custom Mesa Setup (Optional)
setup_custom_mesa() {
    print_step "Setting up custom Mesa for PS4..."
    
    if confirm_action "Download and install custom PS4 Mesa? This requires internet..."; then
        print_status "Creating download directory"
        local mesa_dir="/home/noob404"
        mkdir -p "$mesa_dir"
        chmod -R ugo+rw "$mesa_dir"
        cd "$mesa_dir"
        
        print_status "Downloading custom Mesa packages"
        wget -c https://github.com/noob404yt/ps4-custom-mesa-archlinux/releases/download/v1/custom-mesa-arch-v1-ps4linux.tar.xz
        
        if [ -f "custom-mesa-arch-v1-ps4linux.tar.xz" ]; then
            print_status "Extracting Mesa packages"
            tar -xvf custom-mesa-arch-v1-ps4linux.tar.xz
            
            if [ -f "mesa.sh" ]; then
                print_status "Running custom Mesa setup"
                source mesa.sh
                
                print_status "Testing Vulkan installation"
                vulkaninfo | grep driverInfo || true
                
                print_status "Custom Mesa setup completed"
            else
                print_error "mesa.sh not found in downloaded package"
            fi
        else
            print_error "Failed to download custom Mesa package"
        fi
        
        print_status "Returning to original directory"
        cd - > /dev/null
    else
        print_warning "Custom Mesa setup skipped"
    fi
}

# Step 9: Additional Package Installation
install_additional_packages() {
    print_step "Installing additional useful packages..."
    
    if confirm_action "Install additional useful packages (steam, joystick, retroarch)?"; then
        print_status "Installing gaming and utility packages"
        pacman -S steam joystick retroarch network-manager-applet polkit-gnome --noconfirm
        
        print_status "Additional packages installed"
    else
        print_warning "Additional packages installation skipped"
    fi
}

# Step 10: Final System Check
final_system_check() {
    print_step "Performing final system check..."
    
    print_status "Checking system time:"
    timedatectl
    
    print_status "Checking locale settings:"
    localectl status
    
    print_status "Checking swap status:"
    free -h
    
    print_status "Checking disk usage:"
    df -h
    
    print_status "Checking system uptime and load:"
    uptime
    
    print_status "Final system check completed"
}

# Main execution
main() {
    echo "=== PS4 Linux Pós-Instalação Script ==="
    echo ""
    print_warning "This script will configure your PS4 Linux installation"
    print_warning "Make sure you have internet connection for package updates"
    echo ""
    
    check_root
    
    echo "Starting post-installation configuration..."
    echo ""
    
    # Execute all steps
    setup_system_time
    echo ""
    
    setup_locale
    echo ""
    
    setup_swap
    echo ""
    
    check_distro_age
    echo ""
    
    reset_pacman_db
    echo ""
    
    update_system
    echo ""
    
    setup_mesa_vulkan
    echo ""
    
    setup_custom_mesa
    echo ""
    
    install_additional_packages
    echo ""
    
    final_system_check
    echo ""
    
    print_status "🎉 Post-installation configuration completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Test your system: Try running some applications"
    echo "2. Check Vulkan support: vulkaninfo | grep driverInfo"
    echo "3. Configure network if needed: nm-connection-editor"
    echo "4. Reboot system: sudo reboot"
    echo ""
    print_warning "Remember to test your system before final use!"
}

# Run main function
main "$@"