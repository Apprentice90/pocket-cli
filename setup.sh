#!/usr/bin/env bash
#
# Portable Claude Code USB Setup Script
# Downloads Node.js binaries for all platforms and installs Claude Code
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Platform selection (all enabled by default)
INSTALL_WIN=true
INSTALL_MAC_X64=true
INSTALL_MAC_ARM=true
INSTALL_LINUX_X64=true
INSTALL_LINUX_ARM=true

# Print colored output
print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}        ${BOLD}Portable Claude Code USB Setup${NC}                      ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local message=$3
    echo ""
    echo -e "${BOLD}${BLUE}[$step/$total]${NC} ${BOLD}$message${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "  ${DIM}$1${NC}"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

# Interactive menu
show_menu() {
    clear
    print_header
    echo -e "${BOLD}Select platforms to install:${NC}"
    echo -e "${DIM}(Toggle with number keys, press Enter when done)${NC}"
    echo ""

    if $INSTALL_WIN; then
        echo -e "  ${GREEN}[✓]${NC} ${BOLD}1${NC}  Windows x64         ${DIM}(~28MB)${NC}"
    else
        echo -e "  ${DIM}[ ]${NC} ${BOLD}1${NC}  Windows x64         ${DIM}(~28MB)${NC}"
    fi

    if $INSTALL_MAC_X64; then
        echo -e "  ${GREEN}[✓]${NC} ${BOLD}2${NC}  macOS Intel         ${DIM}(~40MB)${NC}"
    else
        echo -e "  ${DIM}[ ]${NC} ${BOLD}2${NC}  macOS Intel         ${DIM}(~40MB)${NC}"
    fi

    if $INSTALL_MAC_ARM; then
        echo -e "  ${GREEN}[✓]${NC} ${BOLD}3${NC}  macOS Apple Silicon ${DIM}(~38MB)${NC}"
    else
        echo -e "  ${DIM}[ ]${NC} ${BOLD}3${NC}  macOS Apple Silicon ${DIM}(~38MB)${NC}"
    fi

    if $INSTALL_LINUX_X64; then
        echo -e "  ${GREEN}[✓]${NC} ${BOLD}4${NC}  Linux x64           ${DIM}(~26MB)${NC}"
    else
        echo -e "  ${DIM}[ ]${NC} ${BOLD}4${NC}  Linux x64           ${DIM}(~26MB)${NC}"
    fi

    if $INSTALL_LINUX_ARM; then
        echo -e "  ${GREEN}[✓]${NC} ${BOLD}5${NC}  Android/Termux/Quest ${DIM}(~25MB)${NC}"
    else
        echo -e "  ${DIM}[ ]${NC} ${BOLD}5${NC}  Android/Termux/Quest ${DIM}(~25MB)${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}A${NC}  Select All"
    echo -e "  ${BOLD}N${NC}  Select None"
    echo ""

    # Calculate total size
    local total=0
    $INSTALL_WIN && total=$((total + 28))
    $INSTALL_MAC_X64 && total=$((total + 40))
    $INSTALL_MAC_ARM && total=$((total + 38))
    $INSTALL_LINUX_X64 && total=$((total + 26))
    $INSTALL_LINUX_ARM && total=$((total + 25))

    echo -e "${DIM}Total download size: ~${total}MB${NC}"
    echo ""
    echo -e "${YELLOW}Press Enter to continue, or number to toggle...${NC}"
}

run_menu() {
    while true; do
        show_menu
        read -rsn1 key

        case "$key" in
            1) INSTALL_WIN=$(! $INSTALL_WIN && echo true || echo false) ;;
            2) INSTALL_MAC_X64=$(! $INSTALL_MAC_X64 && echo true || echo false) ;;
            3) INSTALL_MAC_ARM=$(! $INSTALL_MAC_ARM && echo true || echo false) ;;
            4) INSTALL_LINUX_X64=$(! $INSTALL_LINUX_X64 && echo true || echo false) ;;
            5) INSTALL_LINUX_ARM=$(! $INSTALL_LINUX_ARM && echo true || echo false) ;;
            a|A)
                INSTALL_WIN=true
                INSTALL_MAC_X64=true
                INSTALL_MAC_ARM=true
                INSTALL_LINUX_X64=true
                INSTALL_LINUX_ARM=true
                ;;
            n|N)
                INSTALL_WIN=false
                INSTALL_MAC_X64=false
                INSTALL_MAC_ARM=false
                INSTALL_LINUX_X64=false
                INSTALL_LINUX_ARM=false
                ;;
            "") break ;;  # Enter key
        esac
    done

    # Check at least one platform selected
    if ! $INSTALL_WIN && ! $INSTALL_MAC_X64 && ! $INSTALL_MAC_ARM && ! $INSTALL_LINUX_X64 && ! $INSTALL_LINUX_ARM; then
        echo ""
        print_error "No platforms selected. Please select at least one."
        echo ""
        exit 1
    fi
}

# Check for required tools
check_requirements() {
    local missing=""

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing="$missing curl/wget"
    fi

    if ! command -v tar &> /dev/null; then
        missing="$missing tar"
    fi

    # For zip extraction, check unzip, python3, or powershell
    if ! command -v unzip &> /dev/null; then
        if ! command -v python3 &> /dev/null && ! command -v powershell.exe &> /dev/null; then
            missing="$missing unzip/python3"
        fi
    fi

    if [ -n "$missing" ]; then
        print_error "Missing required tools:$missing"
        echo "       Please install them and try again."
        exit 1
    fi
}

# Download with built-in progress
download_file() {
    local url=$1
    local output=$2

    if command -v curl &> /dev/null; then
        curl -fL --progress-bar "$url" -o "$output"
    elif command -v wget &> /dev/null; then
        wget --show-progress -q "$url" -O "$output"
    fi
}

# Download and extract Node.js
download_node() {
    local platform=$1
    local filename=$2
    local target_dir=$3
    local size=$4

    # Download with progress bar
    echo -e "  ${DIM}Downloading (~${size})...${NC}"
    download_file "${NODE_BASE_URL}/${filename}" "${filename}"
    print_success "Downloaded $platform"

    # Extract with progress
    echo -e "  ${DIM}Extracting...${NC}"

    case "$filename" in
        *.zip)
            if command -v unzip &> /dev/null; then
                unzip "$filename" -d "$target_dir" | while read -r line; do
                    printf "\r  ${CYAN}⠿${NC} %s" "$(echo "$line" | tail -c 50)"
                done
            elif command -v python3 &> /dev/null; then
                python3 -c "import zipfile; zipfile.ZipFile('$filename').extractall('$target_dir')"
            elif command -v powershell.exe &> /dev/null; then
                powershell.exe -Command "Expand-Archive -Path '$filename' -DestinationPath '$target_dir' -Force"
            fi
            ;;
        *.tar.gz)
            tar -xvzf "$filename" -C "$target_dir" --no-same-owner 2>/dev/null | while read -r line; do
                printf "\r  ${CYAN}⠿${NC} %-60s" "$(echo "$line" | tail -c 55)"
            done
            ;;
        *.tar.xz)
            tar -xvJf "$filename" -C "$target_dir" --no-same-owner 2>/dev/null | while read -r line; do
                printf "\r  ${CYAN}⠿${NC} %-60s" "$(echo "$line" | tail -c 55)"
            done
            ;;
    esac

    printf "\r  ${GREEN}✓${NC} %-60s\n" "Extracted $platform"
    rm -f "$filename"
}

# Node.js version
NODE_VERSION="v20.18.1"
NODE_BASE_URL="https://nodejs.org/dist/${NODE_VERSION}"

# Run interactive menu
run_menu

# Clear and show header again
clear
print_header
check_requirements

echo -e "${DIM}Installing to: $SCRIPT_DIR${NC}"

# Count selected platforms for step numbering
TOTAL_STEPS=2  # directories + claude code install
$INSTALL_WIN && TOTAL_STEPS=$((TOTAL_STEPS + 1))
$INSTALL_MAC_X64 && TOTAL_STEPS=$((TOTAL_STEPS + 1))
$INSTALL_MAC_ARM && TOTAL_STEPS=$((TOTAL_STEPS + 1))
$INSTALL_LINUX_X64 && TOTAL_STEPS=$((TOTAL_STEPS + 1))
$INSTALL_LINUX_ARM && TOTAL_STEPS=$((TOTAL_STEPS + 1))

CURRENT_STEP=1

print_step $CURRENT_STEP $TOTAL_STEPS "Creating directory structure"
mkdir -p claude-code config
$INSTALL_WIN && mkdir -p bin/node-win
$INSTALL_MAC_X64 && mkdir -p bin/node-mac
$INSTALL_MAC_ARM && mkdir -p bin/node-mac-arm
$INSTALL_LINUX_X64 && mkdir -p bin/node-linux
$INSTALL_LINUX_ARM && mkdir -p bin/node-linux-arm
print_success "Directories created"
CURRENT_STEP=$((CURRENT_STEP + 1))

if $INSTALL_WIN; then
    print_step $CURRENT_STEP $TOTAL_STEPS "Downloading Node.js for Windows x64"
    download_node "Windows x64" "node-${NODE_VERSION}-win-x64.zip" "bin/node-win" "28MB"
    CURRENT_STEP=$((CURRENT_STEP + 1))
fi

if $INSTALL_MAC_X64; then
    print_step $CURRENT_STEP $TOTAL_STEPS "Downloading Node.js for macOS Intel"
    download_node "macOS x64" "node-${NODE_VERSION}-darwin-x64.tar.gz" "bin/node-mac" "40MB"
    CURRENT_STEP=$((CURRENT_STEP + 1))
fi

if $INSTALL_MAC_ARM; then
    print_step $CURRENT_STEP $TOTAL_STEPS "Downloading Node.js for macOS Apple Silicon"
    download_node "macOS ARM64" "node-${NODE_VERSION}-darwin-arm64.tar.gz" "bin/node-mac-arm" "38MB"
    CURRENT_STEP=$((CURRENT_STEP + 1))
fi

if $INSTALL_LINUX_X64; then
    print_step $CURRENT_STEP $TOTAL_STEPS "Downloading Node.js for Linux x64"
    download_node "Linux x64" "node-${NODE_VERSION}-linux-x64.tar.xz" "bin/node-linux" "26MB"
    CURRENT_STEP=$((CURRENT_STEP + 1))
fi

if $INSTALL_LINUX_ARM; then
    print_step $CURRENT_STEP $TOTAL_STEPS "Downloading Node.js for Android/Termux/Quest"
    download_node "Linux ARM64" "node-${NODE_VERSION}-linux-arm64.tar.xz" "bin/node-linux-arm" "25MB"
    CURRENT_STEP=$((CURRENT_STEP + 1))
fi

print_step $CURRENT_STEP $TOTAL_STEPS "Installing Claude Code"

# Detect current platform for npm install
OS="$(uname -s)"
ARCH="$(uname -m)"
NODE_BIN=""

case "$OS" in
    Darwin)
        if [ "$ARCH" = "arm64" ] && $INSTALL_MAC_ARM; then
            NODE_BIN="$SCRIPT_DIR/bin/node-mac-arm/node-${NODE_VERSION}-darwin-arm64/bin"
            print_info "Using macOS ARM64 Node.js"
        elif $INSTALL_MAC_X64; then
            NODE_BIN="$SCRIPT_DIR/bin/node-mac/node-${NODE_VERSION}-darwin-x64/bin"
            print_info "Using macOS x64 Node.js"
        fi
        ;;
    Linux)
        if ([ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]) && $INSTALL_LINUX_ARM; then
            NODE_BIN="$SCRIPT_DIR/bin/node-linux-arm/node-${NODE_VERSION}-linux-arm64/bin"
            print_info "Using Linux ARM64 Node.js"
        elif $INSTALL_LINUX_X64; then
            NODE_BIN="$SCRIPT_DIR/bin/node-linux/node-${NODE_VERSION}-linux-x64/bin"
            print_info "Using Linux x64 Node.js"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*)
        if $INSTALL_WIN; then
            NODE_BIN="$SCRIPT_DIR/bin/node-win/node-${NODE_VERSION}-win-x64"
            print_info "Using Windows x64 Node.js"
        fi
        ;;
esac

# Fallback: use any available Node.js
if [ -z "$NODE_BIN" ] || [ ! -d "$NODE_BIN" ]; then
    if $INSTALL_LINUX_X64 && [ -d "$SCRIPT_DIR/bin/node-linux/node-${NODE_VERSION}-linux-x64/bin" ]; then
        NODE_BIN="$SCRIPT_DIR/bin/node-linux/node-${NODE_VERSION}-linux-x64/bin"
        print_info "Fallback: Using Linux x64 Node.js"
    elif $INSTALL_MAC_X64 && [ -d "$SCRIPT_DIR/bin/node-mac/node-${NODE_VERSION}-darwin-x64/bin" ]; then
        NODE_BIN="$SCRIPT_DIR/bin/node-mac/node-${NODE_VERSION}-darwin-x64/bin"
        print_info "Fallback: Using macOS x64 Node.js"
    elif $INSTALL_MAC_ARM && [ -d "$SCRIPT_DIR/bin/node-mac-arm/node-${NODE_VERSION}-darwin-arm64/bin" ]; then
        NODE_BIN="$SCRIPT_DIR/bin/node-mac-arm/node-${NODE_VERSION}-darwin-arm64/bin"
        print_info "Fallback: Using macOS ARM64 Node.js"
    elif $INSTALL_LINUX_ARM && [ -d "$SCRIPT_DIR/bin/node-linux-arm/node-${NODE_VERSION}-linux-arm64/bin" ]; then
        NODE_BIN="$SCRIPT_DIR/bin/node-linux-arm/node-${NODE_VERSION}-linux-arm64/bin"
        print_info "Fallback: Using Linux ARM64 Node.js"
    fi
fi

if [ -z "$NODE_BIN" ]; then
    print_error "No compatible Node.js found for this system"
    exit 1
fi

export PATH="$NODE_BIN:$PATH"
export npm_config_prefix="$SCRIPT_DIR/claude-code"

echo -e "  ${DIM}Installing @anthropic-ai/claude-code...${NC}"
# Use --no-bin-links for exFAT compatibility (no symlink support)
npm install -g @anthropic-ai/claude-code --no-bin-links 2>&1 | tee /tmp/npm_install.log | while read -r line; do
    printf "\r  ${CYAN}⠿${NC} %-60s" "$(echo "$line" | tail -c 55)"
done

# Check if install succeeded
if [ -d "$SCRIPT_DIR/claude-code/lib/node_modules/@anthropic-ai/claude-code" ]; then
    printf "\r  ${GREEN}✓${NC} %-60s\n" "Claude Code installed"

    # Create manual bin wrapper since --no-bin-links skips symlinks
    mkdir -p "$SCRIPT_DIR/claude-code/bin"
    cat > "$SCRIPT_DIR/claude-code/bin/claude" << 'WRAPPER'
#!/usr/bin/env node
require('@anthropic-ai/claude-code/cli.js');
WRAPPER
    chmod +x "$SCRIPT_DIR/claude-code/bin/claude" 2>/dev/null || true

    # Create Windows batch wrapper
    cat > "$SCRIPT_DIR/claude-code/claude.cmd" << WINWRAPPER
@echo off
node "%~dp0lib\\node_modules\\@anthropic-ai\\claude-code\\cli.js" %*
WINWRAPPER

else
    printf "\r  ${RED}✗${NC} %-60s\n" "Claude Code install failed"
    echo ""
    echo -e "${RED}npm install log:${NC}"
    cat /tmp/npm_install.log
    exit 1
fi

# Final summary
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║${NC}                    ${BOLD}${GREEN}Setup Complete!${NC}                         ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Installed platforms:${NC}"
$INSTALL_WIN && echo -e "  ${GREEN}✓${NC} Windows x64"
$INSTALL_MAC_X64 && echo -e "  ${GREEN}✓${NC} macOS Intel"
$INSTALL_MAC_ARM && echo -e "  ${GREEN}✓${NC} macOS Apple Silicon"
$INSTALL_LINUX_X64 && echo -e "  ${GREEN}✓${NC} Linux x64"
$INSTALL_LINUX_ARM && echo -e "  ${GREEN}✓${NC} Android/Termux/Quest"
echo ""
echo -e "${BOLD}To launch Claude Code:${NC}"
$INSTALL_WIN && echo -e "  ${YELLOW}Windows:${NC}       Double-click ${BOLD}launch.bat${NC}"
($INSTALL_MAC_X64 || $INSTALL_MAC_ARM || $INSTALL_LINUX_X64) && echo -e "  ${YELLOW}Mac/Linux:${NC}     Run ${BOLD}./launch.sh${NC}"
$INSTALL_LINUX_ARM && echo -e "  ${YELLOW}Android/Quest:${NC} In Termux, run ${BOLD}bash ./launch.sh${NC}"
echo ""
echo -e "${DIM}On first run, authenticate once. Credentials are stored${NC}"
echo -e "${DIM}in config/ and persist across machines.${NC}"
echo ""
