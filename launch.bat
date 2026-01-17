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

REM Set Claude config directory to USB drive (create if doesn't exist)
set "CLAUDE_CONFIG_DIR=%SCRIPT_DIR%\config"
if not exist "%CLAUDE_CONFIG_DIR%" mkdir "%CLAUDE_CONFIG_DIR%"

REM Create .claude.json to skip authentication if it doesn't exist
REM This marks onboarding as complete so API key can be used without login
if not exist "%CLAUDE_CONFIG_DIR%\.claude.json" (
    echo {"hasCompletedOnboarding": true, "lastOnboardingVersion": "2.1.0"} > "%CLAUDE_CONFIG_DIR%\.claude.json"
)

REM Set NODE_PATH so require() can find the modules
set "NODE_PATH=%SCRIPT_DIR%\claude-code\lib\node_modules"

REM Load API key from .env file if it exists
if exist "%SCRIPT_DIR%\.env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%SCRIPT_DIR%\.env") do (
        if not "%%a"=="" set "%%a=%%b"
    )
)

REM Check for Git Bash - try multiple locations
set "GIT_BASH_FOUND="

REM First check if we have bundled Git (PortableGit or MinGit)
if exist "%SCRIPT_DIR%\bin\git-win\cmd\git.exe" (
    REM Check for bash.exe (PortableGit) or sh.exe (MinGit)
    if exist "%SCRIPT_DIR%\bin\git-win\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=%SCRIPT_DIR%\bin\git-win\bin\bash.exe"
        set "GIT_BASH_FOUND=1"
        echo Using bundled PortableGit
    ) else if exist "%SCRIPT_DIR%\bin\git-win\usr\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=%SCRIPT_DIR%\bin\git-win\usr\bin\bash.exe"
        set "GIT_BASH_FOUND=1"
        echo Using bundled MinGit
    )
    REM Add both cmd and usr\bin to PATH for Unix utilities (cygpath, etc.)
    if defined GIT_BASH_FOUND (
        set "PATH=%SCRIPT_DIR%\bin\git-win\cmd;%SCRIPT_DIR%\bin\git-win\usr\bin;%SCRIPT_DIR%\bin\git-win\bin;%PATH%"
    )
)

REM Check standard Git for Windows locations
if not defined GIT_BASH_FOUND (
    if exist "C:\Program Files\Git\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files\Git\bin\bash.exe"
        set "PATH=C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;C:\Program Files\Git\bin;%PATH%"
        set "GIT_BASH_FOUND=1"
    )
)

if not defined GIT_BASH_FOUND (
    if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files (x86)\Git\bin\bash.exe"
        set "PATH=C:\Program Files (x86)\Git\cmd;C:\Program Files (x86)\Git\usr\bin;C:\Program Files (x86)\Git\bin;%PATH%"
        set "GIT_BASH_FOUND=1"
    )
)

REM Check if git is in PATH
if not defined GIT_BASH_FOUND (
    where git >nul 2>nul
    if not errorlevel 1 (
        for /f "delims=" %%i in ('where git 2^>nul') do (
            set "GIT_PATH=%%~dpi"
            goto :found_git_path
        )
        :found_git_path
        if exist "%GIT_PATH%..\bin\bash.exe" (
            set "CLAUDE_CODE_GIT_BASH_PATH=%GIT_PATH%..\bin\bash.exe"
            set "GIT_BASH_FOUND=1"
        )
    )
)

REM If no Git Bash found, prompt to download MinGit
if not defined GIT_BASH_FOUND goto :prompt_git_install
goto :git_ready

:prompt_git_install
echo.
echo Git Bash not found. Claude Code requires Git Bash on Windows.
echo.
echo MinGit should have been installed by setup.sh. Options:
echo   1. Download MinGit now (~35MB)
echo   2. Exit and run setup.sh again
echo.
set /p INSTALL_CHOICE="Enter choice (1 or 2): "

if "%INSTALL_CHOICE%"=="1" goto :do_mingit_install
echo.
echo Please run setup.sh to install all required components.
pause
exit /b 1

:do_mingit_install
call :download_mingit
if errorlevel 1 (
    echo.
    echo Failed to download MinGit. Please install Git for Windows manually.
    echo https://git-scm.com/downloads/win
    pause
    exit /b 1
)
REM MinGit has bash in usr\bin
set "CLAUDE_CODE_GIT_BASH_PATH=%SCRIPT_DIR%\bin\git-win\usr\bin\bash.exe"
set "PATH=%SCRIPT_DIR%\bin\git-win\cmd;%SCRIPT_DIR%\bin\git-win\usr\bin;%SCRIPT_DIR%\bin\git-win\bin;%PATH%"

:git_ready

REM Change to specified directory if provided, otherwise stay in current directory
if not "%~1"=="" (
    cd /d "%~1"
)

REM Launch Claude Code
echo Starting Claude Code...
echo Config stored at: %CLAUDE_CONFIG_DIR%
if defined CLAUDE_CODE_OAUTH_TOKEN (
    echo Auth: Subscription token loaded from .env
) else if defined ANTHROPIC_API_KEY (
    echo Auth: API key loaded from .env
) else (
    echo Auth: Not configured - see .env.example
)
echo.

REM Use the Windows batch wrapper
if exist "%SCRIPT_DIR%\claude-code\claude.cmd" (
    call "%SCRIPT_DIR%\claude-code\claude.cmd" --dangerously-skip-permissions %2 %3 %4 %5 %6 %7 %8 %9
) else (
    echo ERROR: Claude Code not found at %SCRIPT_DIR%\claude-code\claude.cmd
    echo Please run setup.sh first to install Claude Code.
    pause
)
exit /b 0

REM ========================================
REM Function to download MinGit
REM ========================================
:download_mingit
echo.
echo Downloading MinGit for Windows...
echo.

set "MINGIT_URL=https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip"
set "MINGIT_ZIP=%SCRIPT_DIR%\mingit.zip"
set "MINGIT_DIR=%SCRIPT_DIR%\bin\git-win"

REM Create directory
if not exist "%MINGIT_DIR%" mkdir "%MINGIT_DIR%"

REM Download using PowerShell (available on all modern Windows)
echo Downloading from GitHub...
powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%MINGIT_URL%' -OutFile '%MINGIT_ZIP%' -UseBasicParsing}"
if errorlevel 1 (
    echo Download failed.
    exit /b 1
)

REM Extract using PowerShell
echo Extracting MinGit...
powershell -Command "& {Expand-Archive -Path '%MINGIT_ZIP%' -DestinationPath '%MINGIT_DIR%' -Force}"
if errorlevel 1 (
    echo Extraction failed.
    del "%MINGIT_ZIP%" 2>nul
    exit /b 1
)

REM Clean up
del "%MINGIT_ZIP%" 2>nul

echo.
echo MinGit installed successfully!
echo.
exit /b 0
