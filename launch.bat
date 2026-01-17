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

REM Portable credentials: sync from USB to local on startup
REM Claude stores OAuth credentials in %USERPROFILE%\.claude\ regardless of CLAUDE_CONFIG_DIR
set "USB_CREDS=%SCRIPT_DIR%\config\.credentials.json"
set "LOCAL_CLAUDE_DIR=%USERPROFILE%\.claude"
set "LOCAL_CREDS=%LOCAL_CLAUDE_DIR%\.credentials.json"

if not exist "%LOCAL_CLAUDE_DIR%" mkdir "%LOCAL_CLAUDE_DIR%"

REM If USB has credentials, copy them to local (enables cross-machine portability)
if exist "%USB_CREDS%" (
    copy /y "%USB_CREDS%" "%LOCAL_CREDS%" >nul 2>&1
    echo Auth: Credentials loaded from USB
)

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

REM First check if we have bundled PortableGit
if exist "%SCRIPT_DIR%\bin\git-win\bin\bash.exe" (
    set "CLAUDE_CODE_GIT_BASH_PATH=%SCRIPT_DIR%\bin\git-win\bin\bash.exe"
    set "GIT_BASH_FOUND=1"
    set "PATH=%SCRIPT_DIR%\bin\git-win\cmd;%SCRIPT_DIR%\bin\git-win\usr\bin;%SCRIPT_DIR%\bin\git-win\bin;%PATH%"
    echo Using bundled PortableGit
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
echo PortableGit should have been installed by setup.sh. Options:
echo   1. Download PortableGit now (~55MB)
echo   2. Exit and run setup.sh again
echo.
set /p INSTALL_CHOICE="Enter choice (1 or 2): "

if "%INSTALL_CHOICE%"=="1" goto :do_git_install
echo.
echo Please run setup.sh to install all required components.
pause
exit /b 1

:do_git_install
call :download_portablegit
if errorlevel 1 (
    echo.
    echo Failed to download PortableGit. Please install Git for Windows manually.
    echo https://git-scm.com/downloads/win
    pause
    exit /b 1
)
set "CLAUDE_CODE_GIT_BASH_PATH=%SCRIPT_DIR%\bin\git-win\bin\bash.exe"
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

REM Check Node.js is accessible
where node >nul 2>nul
if errorlevel 1 (
    echo ERROR: Node.js not found in PATH
    echo Expected at: %NODE_DIR%
    pause
    exit /b 1
)

REM Use the Windows batch wrapper
if exist "%SCRIPT_DIR%\claude-code\claude.cmd" (
    call "%SCRIPT_DIR%\claude-code\claude.cmd" --dangerously-skip-permissions %2 %3 %4 %5 %6 %7 %8 %9
) else (
    echo ERROR: Claude Code not found at %SCRIPT_DIR%\claude-code\claude.cmd
    echo Please run setup.sh first to install Claude Code.
    pause
    exit /b 1
)

REM After exit: save credentials back to USB (captures new logins)
if exist "%LOCAL_CREDS%" (
    copy /y "%LOCAL_CREDS%" "%USB_CREDS%" >nul 2>&1
    echo Credentials saved to USB
)

REM Keep window open if double-clicked
echo.
pause
exit /b 0

REM ========================================
REM Function to download PortableGit
REM ========================================
:download_portablegit
echo.
echo Downloading PortableGit for Windows...
echo.

set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/PortableGit-2.47.1-64-bit.7z.exe"
set "GIT_EXE=%SCRIPT_DIR%\portablegit.7z.exe"
set "GIT_DIR=%SCRIPT_DIR%\bin\git-win"

REM Create directory
if not exist "%GIT_DIR%" mkdir "%GIT_DIR%"

REM Download using PowerShell
echo Downloading from GitHub (~55MB)...
powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%GIT_URL%' -OutFile '%GIT_EXE%' -UseBasicParsing}"
if errorlevel 1 (
    echo Download failed.
    exit /b 1
)

REM Extract using the self-extracting archive
echo Extracting PortableGit (this may take a moment)...
"%GIT_EXE%" -y -o"%GIT_DIR%"
if errorlevel 1 (
    echo Extraction failed.
    del "%GIT_EXE%" 2>nul
    exit /b 1
)

REM Clean up
del "%GIT_EXE%" 2>nul

echo.
echo PortableGit installed successfully!
echo.
exit /b 0
