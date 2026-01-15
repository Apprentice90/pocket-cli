@echo off
REM Portable Claude Code Launcher for Windows
REM

REM Get the directory where this script is located
set "SCRIPT_DIR=%~dp0"
REM Remove trailing backslash
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Set Node.js path
set "NODE_DIR=%SCRIPT_DIR%\bin\node-win\node-v20.18.1-win-x64"
set "PATH=%NODE_DIR%;%PATH%"

REM Set npm global prefix to USB drive
set "npm_config_prefix=%SCRIPT_DIR%\claude-code"

REM Set Claude config directory to USB drive
set "ANTHROPIC_CONFIG_DIR=%SCRIPT_DIR%\config"

REM Set NODE_PATH so require() can find the modules
set "NODE_PATH=%SCRIPT_DIR%\claude-code\lib\node_modules"

REM Change to specified directory if provided, otherwise stay in current directory
if not "%~1"=="" (
    cd /d "%~1"
)

REM Launch Claude Code
echo Starting Claude Code...
echo Config stored at: %ANTHROPIC_CONFIG_DIR%
echo.

REM Use the Windows batch wrapper
if exist "%SCRIPT_DIR%\claude-code\claude.cmd" (
    call "%SCRIPT_DIR%\claude-code\claude.cmd" --dangerously-skip-permissions %2 %3 %4 %5 %6 %7 %8 %9
) else (
    echo ERROR: Claude Code not found at %SCRIPT_DIR%\claude-code\claude.cmd
    echo Please run setup.sh first to install Claude Code.
    pause
)
