#!/usr/bin/env bash
#
# Linux USB Autorun Setup for Claude Code
# Installs udev rules and systemd service for automatic USB detection and launch
#
# Requirements:
#   - Root access (run with sudo)
#   - systemd-based Linux distribution
#   - USB drive labeled "CLAUDE_CODE"
#
# Usage: sudo ./linux-autorun-setup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Configuration
USB_LABEL="CLAUDE_CODE"
UDEV_RULE="/etc/udev/rules.d/91-claude-code.rules"
SYSTEMD_SERVICE="/etc/systemd/system/claude-code-usb.service"
LAUNCH_SCRIPT="/usr/local/bin/claude-code-usb-launch.sh"

echo "================================================"
echo "  Claude Code USB Autorun Setup"
echo "================================================"
echo ""
echo "This will install:"
echo "  - udev rule: $UDEV_RULE"
echo "  - systemd service: $SYSTEMD_SERVICE"
echo "  - launch script: $LAUNCH_SCRIPT"
echo ""
echo "Your USB drive must be labeled: $USB_LABEL"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Get the user who will run Claude Code
REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" = "root" ]; then
    echo -e "${YELLOW}Warning: Running as root user. Claude will run as root.${NC}"
    read -p "Enter username to run Claude Code as (or press Enter for root): " REAL_USER
    [ -z "$REAL_USER" ] && REAL_USER="root"
fi

# Verify user exists
if ! id "$REAL_USER" &>/dev/null; then
    echo -e "${RED}Error: User '$REAL_USER' does not exist${NC}"
    exit 1
fi

echo ""
echo "Claude Code will run as user: $REAL_USER"
echo ""

# Create the launch script
echo "Creating launch script..."
cat > "$LAUNCH_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
#
# Claude Code USB Launch Helper
# Called by systemd when USB with CLAUDE_CODE label is inserted
#

USB_LABEL="CLAUDE_CODE"
LOG_FILE="/tmp/claude-code-usb.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log "USB launch script triggered"

# Find the mount point
MOUNT_POINT=""

# Wait for mount (up to 10 seconds)
for i in {1..20}; do
    # Check common mount locations
    for mp in "/media/$USER/$USB_LABEL" "/run/media/$USER/$USB_LABEL" "/mnt/$USB_LABEL"; do
        if [ -d "$mp" ] && [ -f "$mp/launch.sh" ]; then
            MOUNT_POINT="$mp"
            break 2
        fi
    done

    # Also check by label using findmnt
    mp=$(findmnt -rn -S LABEL="$USB_LABEL" -o TARGET 2>/dev/null | head -1)
    if [ -n "$mp" ] && [ -f "$mp/launch.sh" ]; then
        MOUNT_POINT="$mp"
        break
    fi

    sleep 0.5
done

if [ -z "$MOUNT_POINT" ]; then
    log "ERROR: Could not find mount point for $USB_LABEL"
    exit 1
fi

log "Found USB at: $MOUNT_POINT"

# Check for launch script
if [ ! -f "$MOUNT_POINT/launch.sh" ]; then
    log "ERROR: launch.sh not found at $MOUNT_POINT"
    exit 1
fi

log "Launching Claude Code..."

# Launch in a new terminal
# Try different terminal emulators
if command -v gnome-terminal &>/dev/null; then
    gnome-terminal -- bash -c "cd '$MOUNT_POINT' && ./launch.sh; exec bash"
elif command -v konsole &>/dev/null; then
    konsole -e bash -c "cd '$MOUNT_POINT' && ./launch.sh; exec bash"
elif command -v xfce4-terminal &>/dev/null; then
    xfce4-terminal -e "bash -c 'cd \"$MOUNT_POINT\" && ./launch.sh; exec bash'"
elif command -v xterm &>/dev/null; then
    xterm -e "cd '$MOUNT_POINT' && ./launch.sh; exec bash"
else
    log "ERROR: No supported terminal emulator found"
    exit 1
fi

log "Terminal launched successfully"
SCRIPT_EOF

chmod +x "$LAUNCH_SCRIPT"
echo -e "${GREEN}Created:${NC} $LAUNCH_SCRIPT"

# Create the udev rule
echo "Creating udev rule..."
cat > "$UDEV_RULE" << UDEV_EOF
# Claude Code USB Autorun
# Triggers systemd service when USB with label CLAUDE_CODE is inserted

ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="$USB_LABEL", TAG+="systemd", ENV{SYSTEMD_WANTS}="claude-code-usb.service"
UDEV_EOF

echo -e "${GREEN}Created:${NC} $UDEV_RULE"

# Create the systemd service
echo "Creating systemd service..."
cat > "$SYSTEMD_SERVICE" << SERVICE_EOF
[Unit]
Description=Claude Code USB Auto-Launch
After=local-fs.target

[Service]
Type=oneshot
User=$REAL_USER
Environment=DISPLAY=:0
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$REAL_USER")/bus
ExecStart=$LAUNCH_SCRIPT
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo -e "${GREEN}Created:${NC} $SYSTEMD_SERVICE"

# Reload udev and systemd
echo ""
echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

echo "Reloading systemd..."
systemctl daemon-reload

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "To test:"
echo "  1. Label your USB drive as '$USB_LABEL'"
echo "  2. Ensure launch.sh is on the USB root"
echo "  3. Insert the USB drive"
echo "  4. Claude Code should launch automatically"
echo ""
echo "To label a USB drive:"
echo "  - FAT32: sudo fatlabel /dev/sdX1 $USB_LABEL"
echo "  - ext4:  sudo e2label /dev/sdX1 $USB_LABEL"
echo "  - NTFS:  sudo ntfslabel /dev/sdX1 $USB_LABEL"
echo ""
echo "To uninstall, run: sudo ./linux-autorun-uninstall.sh"
echo ""
echo "Logs available at: /tmp/claude-code-usb.log"
echo "Service logs: journalctl -u claude-code-usb.service"
