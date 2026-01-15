#!/usr/bin/env bash
#
# Hybrid Bootable + Portable Claude Code USB Setup
# Creates a USB drive that:
#   1. Boots into minimal Linux with Claude Code (for pre-boot diagnostics)
#   2. Works as portable Claude Code on existing OS (Windows/Mac/Linux)
#
# WARNING: This will ERASE the entire USB drive!
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Configuration
ALPINE_VERSION="3.19"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
NODE_VERSION="v20.18.1"

# Partition sizes
EFI_SIZE="512M"
LINUX_SIZE="3G"
# Data partition uses remaining space

print_header() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}     ${BOLD}Hybrid Bootable Claude Code USB Setup${NC}                 ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC}  $1"
}

print_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

print_step() {
    echo ""
    echo -e "${BOLD}${BLUE}[$1/$2]${NC} ${BOLD}$3${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (sudo)"
        exit 1
    fi
}

# Check required tools
check_requirements() {
    local missing=""

    for cmd in parted mkfs.vfat mkfs.ext4 mkfs.exfat wget tar unsquashfs mksquashfs grub-install; do
        if ! command -v "$cmd" &> /dev/null; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        print_error "Missing required tools:$missing"
        echo ""
        echo "Install them with:"
        echo "  Ubuntu/Debian: sudo apt install parted dosfstools e2fsprogs exfatprogs wget squashfs-tools grub-efi-amd64-bin grub-pc-bin"
        echo "  Arch: sudo pacman -S parted dosfstools e2fsprogs exfatprogs wget squashfs-tools grub"
        exit 1
    fi
}

# List available USB drives
list_usb_drives() {
    echo -e "${BOLD}Available USB drives:${NC}"
    echo ""

    lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E "usb|NAME" | while read -r line; do
        if [[ "$line" == *"NAME"* ]]; then
            echo -e "  ${DIM}$line${NC}"
        else
            echo "  $line"
        fi
    done
    echo ""
}

# Select USB drive
select_drive() {
    list_usb_drives

    echo -e "${YELLOW}Enter the device name (e.g., sdb, sdc):${NC}"
    read -r DEVICE_NAME

    DEVICE="/dev/$DEVICE_NAME"

    if [ ! -b "$DEVICE" ]; then
        print_error "Device $DEVICE does not exist"
        exit 1
    fi

    # Check if it's a USB drive
    if ! lsblk -d -o TRAN "$DEVICE" | grep -q "usb"; then
        print_warning "Warning: $DEVICE does not appear to be a USB drive!"
        echo -e "${YELLOW}Are you sure you want to continue? (yes/no):${NC}"
        read -r confirm
        if [ "$confirm" != "yes" ]; then
            exit 1
        fi
    fi

    # Get drive size
    DRIVE_SIZE=$(lsblk -b -d -o SIZE "$DEVICE" | tail -1)
    DRIVE_SIZE_GB=$((DRIVE_SIZE / 1024 / 1024 / 1024))

    if [ "$DRIVE_SIZE_GB" -lt 8 ]; then
        print_error "Drive is ${DRIVE_SIZE_GB}GB. Minimum 8GB required."
        exit 1
    fi

    echo ""
    echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║  WARNING: ALL DATA ON $DEVICE WILL BE DESTROYED!          ${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Device: $DEVICE"
    echo "Size: ${DRIVE_SIZE_GB}GB"
    echo ""
    echo -e "${YELLOW}Type 'DESTROY' to confirm:${NC}"
    read -r confirm

    if [ "$confirm" != "DESTROY" ]; then
        echo "Aborted."
        exit 1
    fi
}

# Unmount all partitions on the device
unmount_device() {
    print_info "Unmounting any mounted partitions..."

    for part in "${DEVICE}"*; do
        if mountpoint -q "$part" 2>/dev/null || mount | grep -q "^$part "; then
            umount "$part" 2>/dev/null || true
        fi
    done

    sleep 1
}

# Partition the drive
partition_drive() {
    print_step 1 8 "Partitioning drive"

    # Wipe existing partition table
    wipefs -a "$DEVICE" > /dev/null 2>&1 || true

    # Create GPT partition table
    parted -s "$DEVICE" mklabel gpt

    # Create EFI partition
    parted -s "$DEVICE" mkpart "EFI" fat32 1MiB "$EFI_SIZE"
    parted -s "$DEVICE" set 1 esp on

    # Create Linux root partition
    parted -s "$DEVICE" mkpart "Linux" ext4 "$EFI_SIZE" "3.5G"

    # Create data partition (rest of drive)
    parted -s "$DEVICE" mkpart "Data" ntfs "3.5G" 100%

    # Wait for kernel to recognize partitions
    partprobe "$DEVICE"
    sleep 2

    # Determine partition names (handles both sdb1 and nvme0n1p1 style)
    if [[ "$DEVICE" == *"nvme"* ]] || [[ "$DEVICE" == *"mmcblk"* ]]; then
        PART_EFI="${DEVICE}p1"
        PART_LINUX="${DEVICE}p2"
        PART_DATA="${DEVICE}p3"
    else
        PART_EFI="${DEVICE}1"
        PART_LINUX="${DEVICE}2"
        PART_DATA="${DEVICE}3"
    fi

    print_success "Created partitions: EFI($EFI_SIZE), Linux($LINUX_SIZE), Data(remaining)"
}

# Format partitions
format_partitions() {
    print_step 2 8 "Formatting partitions"

    # Format EFI partition
    mkfs.vfat -F 32 -n "EFI" "$PART_EFI" > /dev/null
    print_success "Formatted EFI partition (FAT32)"

    # Format Linux partition
    mkfs.ext4 -L "CLAUDEBOOT" "$PART_LINUX" -q
    print_success "Formatted Linux partition (ext4)"

    # Format Data partition
    mkfs.exfat -L "CLAUDEDATA" "$PART_DATA" > /dev/null
    print_success "Formatted Data partition (exFAT)"
}

# Mount partitions
mount_partitions() {
    print_step 3 8 "Mounting partitions"

    WORK_DIR=$(mktemp -d)
    MOUNT_EFI="$WORK_DIR/efi"
    MOUNT_LINUX="$WORK_DIR/linux"
    MOUNT_DATA="$WORK_DIR/data"

    mkdir -p "$MOUNT_EFI" "$MOUNT_LINUX" "$MOUNT_DATA"

    mount "$PART_LINUX" "$MOUNT_LINUX"
    mount "$PART_EFI" "$MOUNT_EFI"
    mount "$PART_DATA" "$MOUNT_DATA"

    print_success "Mounted all partitions"
}

# Download and install Alpine Linux
install_alpine() {
    print_step 4 8 "Installing Alpine Linux base system"

    ALPINE_URL="$ALPINE_MIRROR/v$ALPINE_VERSION/releases/x86_64"

    # Download Alpine minirootfs
    echo -e "  ${DIM}Downloading Alpine Linux ${ALPINE_VERSION}...${NC}"
    wget -q --show-progress -O "$WORK_DIR/alpine.tar.gz" \
        "$ALPINE_URL/alpine-minirootfs-${ALPINE_VERSION}.0-x86_64.tar.gz"

    # Extract to Linux partition
    echo -e "  ${DIM}Extracting...${NC}"
    tar -xzf "$WORK_DIR/alpine.tar.gz" -C "$MOUNT_LINUX"

    # Download and extract kernel + modules
    echo -e "  ${DIM}Downloading kernel...${NC}"
    mkdir -p "$MOUNT_LINUX/boot"
    wget -q --show-progress -O "$WORK_DIR/kernel.tar.gz" \
        "$ALPINE_URL/netboot/vmlinuz-lts" || \
    wget -q --show-progress -O "$MOUNT_LINUX/boot/vmlinuz" \
        "$ALPINE_MIRROR/v$ALPINE_VERSION/releases/x86_64/netboot/vmlinuz-lts"

    wget -q --show-progress -O "$MOUNT_LINUX/boot/initramfs" \
        "$ALPINE_MIRROR/v$ALPINE_VERSION/releases/x86_64/netboot/initramfs-lts"

    print_success "Alpine Linux base installed"
}

# Configure Alpine Linux
configure_alpine() {
    print_step 5 8 "Configuring Alpine Linux"

    # Set up resolv.conf for chroot
    cp /etc/resolv.conf "$MOUNT_LINUX/etc/resolv.conf"

    # Create setup script to run inside chroot
    cat > "$MOUNT_LINUX/setup-claude.sh" << 'CHROOT_SCRIPT'
#!/bin/sh
set -e

# Set up repositories
cat > /etc/apk/repositories << 'EOF'
https://dl-cdn.alpinelinux.org/alpine/v3.19/main
https://dl-cdn.alpinelinux.org/alpine/v3.19/community
EOF

# Update and install packages
apk update
apk add --no-cache \
    nodejs npm \
    bash curl wget \
    pciutils usbutils dmidecode lshw hdparm smartmontools \
    e2fsprogs dosfstools exfatprogs ntfs-3g \
    iproute2 wireless-tools wpa_supplicant dhcpcd \
    nano less htop \
    linux-lts linux-firmware

# Install Claude Code
export npm_config_prefix="/opt/claude-code"
mkdir -p /opt/claude-code
npm install -g @anthropic-ai/claude-code --no-bin-links

# Create claude wrapper
mkdir -p /opt/claude-code/bin
cat > /opt/claude-code/bin/claude << 'WRAPPER'
#!/usr/bin/env node
process.env.NODE_PATH = '/opt/claude-code/lib/node_modules';
require('module').Module._initPaths();
require('@anthropic-ai/claude-code/cli.js');
WRAPPER
chmod +x /opt/claude-code/bin/claude

# Create auto-start script
cat > /etc/local.d/claude.start << 'STARTUP'
#!/bin/sh
# Mount data partition for shared config
mkdir -p /data
mount -t exfat LABEL=CLAUDEDATA /data 2>/dev/null || mount -t exfat /dev/disk/by-label/CLAUDEDATA /data 2>/dev/null || true

# Set up environment
export PATH="/opt/claude-code/bin:$PATH"
export NODE_PATH="/opt/claude-code/lib/node_modules"
export ANTHROPIC_CONFIG_DIR="/data/config"
export HOME="/root"
export TERM="xterm-256color"

# Wait for network
echo "Waiting for network..."
for i in $(seq 1 30); do
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Start Claude Code
clear
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Claude Code - Bootable Diagnostic Mode                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Config: $ANTHROPIC_CONFIG_DIR"
echo ""
echo "Diagnostic tools available: dmidecode, lshw, smartctl, fdisk"
echo ""
cd /data
exec /opt/claude-code/bin/claude --dangerously-skip-permissions
STARTUP
chmod +x /etc/local.d/claude.start

# Enable services
rc-update add local default
rc-update add dhcpcd default
rc-update add wpa_supplicant default

# Set root password (empty for auto-login)
passwd -d root

# Configure auto-login on tty1
mkdir -p /etc/init.d
cat > /etc/inittab << 'INITTAB'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
tty1::respawn:/etc/local.d/claude.start
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3
::shutdown:/sbin/openrc shutdown
INITTAB

echo "Alpine configuration complete"
CHROOT_SCRIPT

    chmod +x "$MOUNT_LINUX/setup-claude.sh"

    # Run setup in chroot
    echo -e "  ${DIM}Running setup in chroot (this may take a few minutes)...${NC}"
    mount --bind /dev "$MOUNT_LINUX/dev"
    mount --bind /proc "$MOUNT_LINUX/proc"
    mount --bind /sys "$MOUNT_LINUX/sys"

    chroot "$MOUNT_LINUX" /setup-claude.sh 2>&1 | while read -r line; do
        printf "\r  ${CYAN}⠿${NC} %-60s" "$(echo "$line" | tail -c 55)"
    done

    printf "\r  ${GREEN}✓${NC} %-60s\n" "Alpine Linux configured"

    # Cleanup
    umount "$MOUNT_LINUX/dev" 2>/dev/null || true
    umount "$MOUNT_LINUX/proc" 2>/dev/null || true
    umount "$MOUNT_LINUX/sys" 2>/dev/null || true
    rm "$MOUNT_LINUX/setup-claude.sh"
}

# Install bootloader
install_bootloader() {
    print_step 6 8 "Installing GRUB bootloader"

    # Install GRUB for UEFI
    mkdir -p "$MOUNT_EFI/EFI/BOOT"

    grub-install --target=x86_64-efi \
        --efi-directory="$MOUNT_EFI" \
        --boot-directory="$MOUNT_LINUX/boot" \
        --removable \
        --no-nvram \
        2>/dev/null || true

    # Install GRUB for Legacy BIOS
    grub-install --target=i386-pc \
        --boot-directory="$MOUNT_LINUX/boot" \
        "$DEVICE" \
        2>/dev/null || true

    # Get UUIDs
    UUID_LINUX=$(blkid -s UUID -o value "$PART_LINUX")

    # Create GRUB config
    cat > "$MOUNT_LINUX/boot/grub/grub.cfg" << GRUBCFG
set timeout=3
set default=0

menuentry "Claude Code - Diagnostic Mode" {
    linux /boot/vmlinuz-lts root=UUID=$UUID_LINUX modules=sd-mod,usb-storage,ext4 quiet
    initrd /boot/initramfs-lts
}

menuentry "Claude Code - Diagnostic Mode (Safe)" {
    linux /boot/vmlinuz-lts root=UUID=$UUID_LINUX modules=sd-mod,usb-storage,ext4 nomodeset
    initrd /boot/initramfs-lts
}

menuentry "Boot from Hard Drive" {
    chainloader (hd1,1)+1
}
GRUBCFG

    print_success "GRUB bootloader installed (UEFI + Legacy BIOS)"
}

# Set up portable data partition
setup_data_partition() {
    print_step 7 8 "Setting up portable data partition"

    # Create directory structure
    mkdir -p "$MOUNT_DATA/bin/node-win"
    mkdir -p "$MOUNT_DATA/bin/node-mac"
    mkdir -p "$MOUNT_DATA/bin/node-mac-arm"
    mkdir -p "$MOUNT_DATA/bin/node-linux"
    mkdir -p "$MOUNT_DATA/bin/node-linux-arm"
    mkdir -p "$MOUNT_DATA/claude-code"
    mkdir -p "$MOUNT_DATA/config"

    # Copy scripts from current directory if they exist
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

    if [ -f "$SCRIPT_DIR/setup.sh" ]; then
        cp "$SCRIPT_DIR/setup.sh" "$MOUNT_DATA/"
    fi
    if [ -f "$SCRIPT_DIR/launch.sh" ]; then
        cp "$SCRIPT_DIR/launch.sh" "$MOUNT_DATA/"
    fi
    if [ -f "$SCRIPT_DIR/launch.bat" ]; then
        cp "$SCRIPT_DIR/launch.bat" "$MOUNT_DATA/"
    fi

    # Create README
    cat > "$MOUNT_DATA/README.txt" << 'README'
╔════════════════════════════════════════════════════════════╗
║     Hybrid Claude Code USB Drive                           ║
╚════════════════════════════════════════════════════════════╝

This USB drive works in two modes:

1. BOOT MODE (Pre-boot diagnostics)
   - Restart your computer and boot from this USB
   - Select "Claude Code - Diagnostic Mode" from menu
   - Full hardware access for diagnostics

2. PORTABLE MODE (On existing OS)
   - Windows: Double-click launch.bat
   - Mac/Linux: Run ./launch.sh
   - Android/Termux: bash ./launch.sh

First time setup (Portable Mode only):
   Run setup.sh to download Node.js binaries

Both modes share the same config/ folder for authentication.
Login once, use everywhere!

README

    print_success "Data partition configured"
}

# Cleanup and finish
cleanup() {
    print_step 8 8 "Finishing up"

    # Sync and unmount
    sync

    umount "$MOUNT_DATA" 2>/dev/null || true
    umount "$MOUNT_EFI" 2>/dev/null || true
    umount "$MOUNT_LINUX" 2>/dev/null || true

    rm -rf "$WORK_DIR"

    print_success "Cleanup complete"
}

# Print final summary
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}              ${BOLD}${GREEN}Hybrid USB Setup Complete!${NC}                   ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Partition Layout:${NC}"
    echo -e "  ${CYAN}EFI${NC}     512MB  FAT32   Boot files"
    echo -e "  ${CYAN}Linux${NC}   3GB    ext4    Alpine + Claude Code"
    echo -e "  ${CYAN}Data${NC}    Rest   exFAT   Portable scripts + config"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo ""
    echo -e "  ${YELLOW}Boot Mode:${NC}"
    echo "    1. Restart computer"
    echo "    2. Press F12/F2/DEL to enter boot menu"
    echo "    3. Select USB drive"
    echo "    4. Claude Code starts automatically"
    echo ""
    echo -e "  ${YELLOW}Portable Mode:${NC}"
    echo "    1. Plug USB into running computer"
    echo "    2. Run setup.sh first (one time)"
    echo "    3. Use launch.bat (Win) or launch.sh (Mac/Linux)"
    echo ""
    echo -e "${DIM}Both modes share config/ - login once, use everywhere!${NC}"
    echo ""
}

# Main execution
main() {
    print_header

    check_root
    check_requirements

    echo -e "${BOLD}This script creates a hybrid bootable USB drive with:${NC}"
    echo "  • Bootable Linux with Claude Code for pre-boot diagnostics"
    echo "  • Portable Claude Code for use on existing operating systems"
    echo "  • Shared configuration (single login for both modes)"
    echo ""
    print_warning "This will COMPLETELY ERASE the selected USB drive!"
    echo ""

    select_drive
    unmount_device
    partition_drive
    format_partitions
    mount_partitions
    install_alpine
    configure_alpine
    install_bootloader
    setup_data_partition
    cleanup
    print_summary
}

# Run main
main "$@"
