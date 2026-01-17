#!/usr/bin/env bash
#
# Linux USB Autorun Uninstall for Claude Code
# Removes udev rules and systemd service
#
# Usage: sudo ./linux-autorun-uninstall.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Configuration
UDEV_RULE="/etc/udev/rules.d/91-claude-code.rules"
SYSTEMD_SERVICE="/etc/systemd/system/claude-code-usb.service"
LAUNCH_SCRIPT="/usr/local/bin/claude-code-usb-launch.sh"

echo "================================================"
echo "  Claude Code USB Autorun Uninstall"
echo "================================================"
echo ""
echo "This will remove:"
echo "  - udev rule: $UDEV_RULE"
echo "  - systemd service: $SYSTEMD_SERVICE"
echo "  - launch script: $LAUNCH_SCRIPT"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Stop the service if running
if systemctl is-active --quiet claude-code-usb.service 2>/dev/null; then
    echo "Stopping service..."
    systemctl stop claude-code-usb.service
fi

# Remove files
echo ""
REMOVED=0

if [ -f "$UDEV_RULE" ]; then
    rm -f "$UDEV_RULE"
    echo -e "${GREEN}Removed:${NC} $UDEV_RULE"
    REMOVED=$((REMOVED + 1))
fi

if [ -f "$SYSTEMD_SERVICE" ]; then
    rm -f "$SYSTEMD_SERVICE"
    echo -e "${GREEN}Removed:${NC} $SYSTEMD_SERVICE"
    REMOVED=$((REMOVED + 1))
fi

if [ -f "$LAUNCH_SCRIPT" ]; then
    rm -f "$LAUNCH_SCRIPT"
    echo -e "${GREEN}Removed:${NC} $LAUNCH_SCRIPT"
    REMOVED=$((REMOVED + 1))
fi

if [ $REMOVED -eq 0 ]; then
    echo "No files found to remove. Already uninstalled?"
else
    # Reload udev and systemd
    echo ""
    echo "Reloading udev rules..."
    udevadm control --reload-rules

    echo "Reloading systemd..."
    systemctl daemon-reload

    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Uninstall Complete!${NC}"
    echo -e "${GREEN}================================================${NC}"
fi
