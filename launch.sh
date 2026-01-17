#!/usr/bin/env bash
#
# Portable Claude Code Launcher for macOS, Linux, Android (Termux), and Quest
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Node.js version (must match setup.sh)
NODE_VERSION="v20.18.1"

# Detect OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Darwin)
        # macOS
        if [ "$ARCH" = "arm64" ]; then
            NODE_DIR="$SCRIPT_DIR/bin/node-mac-arm/node-${NODE_VERSION}-darwin-arm64"
            echo "Detected: macOS Apple Silicon"
        else
            NODE_DIR="$SCRIPT_DIR/bin/node-mac/node-${NODE_VERSION}-darwin-x64"
            echo "Detected: macOS Intel"
        fi
        ;;
    Linux)
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            NODE_DIR="$SCRIPT_DIR/bin/node-linux-arm/node-${NODE_VERSION}-linux-arm64"
            echo "Detected: Linux ARM64 (Android/Termux/Quest)"
        else
            NODE_DIR="$SCRIPT_DIR/bin/node-linux/node-${NODE_VERSION}-linux-x64"
            echo "Detected: Linux x64"
        fi
        ;;
    *)
        echo "Unsupported OS: $OS"
        echo "Use launch.bat for Windows"
        exit 1
        ;;
esac

# Set up environment
export PATH="$NODE_DIR/bin:$SCRIPT_DIR/claude-code/bin:$PATH"
export npm_config_prefix="$SCRIPT_DIR/claude-code"
export NODE_PATH="$SCRIPT_DIR/claude-code/lib/node_modules"

# Config directory: use local on Linux (avoids exfat permission issues), USB on macOS
USB_CONFIG="$SCRIPT_DIR/config"
USB_CREDS="$USB_CONFIG/.credentials.json"
LOCAL_CLAUDE_DIR="$HOME/.claude"
LOCAL_CREDS="$LOCAL_CLAUDE_DIR/.credentials.json"

if [ "$OS" = "Linux" ]; then
    # Linux: use local config dir to avoid FAT/exFAT permission issues
    export CLAUDE_CONFIG_DIR="$HOME/.pocket-claude"
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo "Config: Using local directory (Linux)"
else
    # macOS: use USB config directly (HFS+/APFS handle permissions fine)
    export CLAUDE_CONFIG_DIR="$USB_CONFIG"
    mkdir -p "$CLAUDE_CONFIG_DIR"
fi

mkdir -p "$LOCAL_CLAUDE_DIR"

# Portable credentials: sync from USB to local on startup
if [ -f "$USB_CREDS" ]; then
    cp "$USB_CREDS" "$LOCAL_CREDS" 2>/dev/null
    echo "Auth: Credentials loaded from USB"
fi

# Create .claude.json to skip authentication if it doesn't exist
if [ ! -f "$CLAUDE_CONFIG_DIR/.claude.json" ]; then
    cat > "$CLAUDE_CONFIG_DIR/.claude.json" << 'CLAUDEJSON'
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "2.1.0"
}
CLAUDEJSON
fi

# Load API key from .env file if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    # Export variables from .env (skip comments and empty lines)
    set -a
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        case "$key" in
            \#*|"") continue ;;
        esac
        # Remove surrounding quotes from value if present
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "$key=$value"
    done < "$SCRIPT_DIR/.env"
    set +a
fi

echo "Config: $CLAUDE_CONFIG_DIR"
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "Auth: Subscription token loaded from .env"
elif [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "Auth: API key loaded from .env"
else
    echo "Auth: Not configured - see .env.example"
fi
echo ""

# Change to specified directory if provided
if [ -n "$1" ] && [ -d "$1" ]; then
    cd "$1"
    shift
fi

# Launch Claude Code with any remaining arguments
claude --dangerously-skip-permissions "$@"
EXIT_CODE=$?

# After exit: save credentials back to USB (captures new logins)
if [ -f "$LOCAL_CREDS" ]; then
    cp "$LOCAL_CREDS" "$USB_CREDS" 2>/dev/null && echo "Credentials saved to USB"
fi

exit $EXIT_CODE
