#!/bin/bash

# PS4 Linux Installation Script
# Automates HDD preparation and distro installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Phase 1: Input Validation
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run this script as root"
        exit 1
    fi
}

check_parameter() {
    if [ $# -ne 1 ]; then
        print_error "Usage: $0 <distro_tar_file>"
        echo "Example: $0 /mnt/t/downloads/PS4/linux_in_ps4/distros/psxitarch3.1-unoficial/psxitarch_v3.1-ITm.tar.xz"
        exit 1
    fi
}

validate_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        exit 1
    fi
    if [ ! -r "$file" ]; then
        print_error "Cannot read file: $file"
        exit 1
    fi
}

check_disk() {
    if [ ! -e "/dev/sda" ]; then
        print_error "Disk /dev/sda not found"
        exit 1
    fi
}

# Phase 2: Pre-flight Operations
setup_mount_points() {
    print_status "Setting up mount points..."
    mkdir -p /mnt/boot /mnt/root
}

cleanup_mounts() {
    print_status "Cleaning up existing mounts..."
    umount /dev/sda1 /dev/sda2 2>/dev/null || true
    print_warning "Some mounts may not have existed"
}

# Phase 3: Partition Creation
create_partitions() {
    print_status "Creating partitions..."
    
    # Clear existing partition table
    fdisk /dev/sda <<EOF
o
n
p
1

+50M
t
b
a
1
n
p
2


w
EOF
    
    if [ $? -ne 0 ]; then
        print_error "Failed to create partitions"
        exit 1
    fi
    
    print_status "Partitions created successfully"
}

# Phase 4: Filesystem Formatting
format_partitions() {
    print_status "Formatting filesystems..."
    
    # Format FAT32 boot partition
    mkfs.vfat -F 32 /dev/sda1
    if [ $? -ne 0 ]; then
        print_error "Failed to format FAT32 partition"
        exit 1
    fi
    
    # Format ext4 root partition
    mkfs.ext4 -L psxitarch /dev/sda2
    if [ $? -ne 0 ]; then
        print_error "Failed to format ext4 partition"
        exit 1
    fi
    
    print_status "Filesystems formatted successfully"
}

# Phase 5: Boot Files Management
setup_boot_partition() {
    print_status "Setting up boot partition..."
    
    # Mount boot partition
    mount /dev/sda1 /mnt/boot
    if [ $? -ne 0 ]; then
        print_error "Failed to mount boot partition"
        exit 1
    fi
    
    # Copy required files
    local distros_dir="/mnt/t/downloads/PS4/linux_in_ps4/distros"
    
    # Check if required files exist
    for file in bzImage initramfs.cpio.gz bootargs.txt; do
        if [ ! -f "$distros_dir/$file" ]; then
            print_error "Required file not found: $distros_dir/$file"
            umount /mnt/boot
            exit 1
        fi
        cp "$distros_dir/$file" /mnt/boot/
        print_status "Copied: $file"
    done
    
    # Create dummy bootlog.txt if it doesn't exist
    if [ ! -f "/mnt/boot/bootlog.txt" ]; then
        touch /mnt/boot/bootlog.txt
        print_status "Created dummy bootlog.txt"
    fi
    
    # Sync and unmount
    sync
    umount /mnt/boot
    
    if [ $? -ne 0 ]; then
        print_error "Failed to unmount boot partition"
        exit 1
    fi
    
    print_status "Boot partition setup completed"
}

# Phase 6: Distro Installation
install_distro() {
    local distro_file="$1"
    
    print_status "Installing distro: $distro_file"
    
    # Mount root partition
    mount /dev/sda2 /mnt/root
    if [ $? -ne 0 ]; then
        print_error "Failed to mount root partition"
        exit 1
    fi
    
    # Extract distro
    local extract_cmd=""
    if [[ "$distro_file" == *.tar.xz ]]; then
        extract_cmd="tar -xvJpf"
    elif [[ "$distro_file" == *.tar ]]; then
        extract_cmd="tar -xvpf"
    else
        print_error "Unsupported distro format: $distro_file"
        umount /mnt/root
        exit 1
    fi
    
    $extract_cmd "$distro_file" -C /mnt/root --numeric-owner
    if [ $? -ne 0 ]; then
        print_error "Failed to extract distro"
        umount /mnt/root
        exit 1
    fi
    
    # Unmount root partition
    umount /mnt/root
    
    if [ $? -ne 0 ]; then
        print_error "Failed to unmount root partition"
        exit 1
    fi
    
    print_status "Distro installation completed"
}

# Phase 7: Final Cleanup
cleanup() {
    print_status "Installation completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Connect the HDD to your PS4"
    echo "2. Load the payload using Payload Guest app"
    echo "3. Boot from the installed distro"
    echo ""
    print_warning "Make sure to test the installation before proceeding"
}

# Main execution
main() {
    print_status "Starting PS4 Linux installation..."
    
    # Phase 1: Input validation
    check_sudo
    check_parameter "$@"
    validate_file "$1"
    check_disk
    
    # Phase 2: Pre-flight operations
    setup_mount_points
    cleanup_mounts
    
    # Phase 3: Partition creation
    create_partitions
    
    # Phase 4: Filesystem formatting
    format_partitions
    
    # Phase 5: Boot files management
    setup_boot_partition
    
    # Phase 6: Distro installation
    install_distro "$1"
    
    # Phase 7: Final cleanup
    cleanup
}

# Run main function with all parameters
main "$@"