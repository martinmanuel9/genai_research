###############################################################################
# Setup Script for WiX Installer
# Runs in a VISIBLE PowerShell window during MSI installation
# Output is shown in real-time AND logged to file for debugging
#
# EXIT CODES: 0 = Success, 1 = Failure
###############################################################################

param(
    [string]$InstallDir = "$env:ProgramFiles\GenAI Research"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Global flag to track if we should wait for user at the end
$script:WaitForUserAtEnd = $true

# Function to wait for user input (works in all PowerShell contexts)
function Wait-ForUserInput {
    param([string]$Message = "Press Enter to continue...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    # Use Read-Host which works in all contexts (unlike RawUI.ReadKey)
    Read-Host
}

# Setup logging - save to installation directory logs folder
$LogDir = Join-Path $InstallDir "logs"
$LogFile = $null
$StartTime = Get-Date

# Try to create log directory and file
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $LogFile = Join-Path $LogDir "install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    # Test we can write to the log file
    Set-Content -Path $LogFile -Value "GenAI Research Installation Log - $(Get-Date)" -ErrorAction Stop
    Write-Host "[INFO] Log file created: $LogFile" -ForegroundColor Cyan
} catch {
    # Fallback to temp directory if we can't write to install dir
    $LogDir = $env:TEMP
    $LogFile = Join-Path $LogDir "genai-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    try {
        Set-Content -Path $LogFile -Value "GenAI Research Installation Log - $(Get-Date)" -ErrorAction Stop
        Write-Host "[WARNING] Could not write to install directory, using temp: $LogFile" -ForegroundColor Yellow
    } catch {
        $LogFile = $null
        Write-Host "[WARNING] Could not create log file, continuing without logging" -ForegroundColor Yellow
    }
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"

    # Write to console with color
    Write-Host $logMessage -ForegroundColor $Color

    # Write to log file if available
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    }
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Log "[SUCCESS] $Message" -Color Green
}

function Write-LogError {
    param([string]$Message)
    Write-Log "[ERROR] $Message" -Color Red
}

function Write-LogWarning {
    param([string]$Message)
    Write-Log "[WARNING] $Message" -Color Yellow
}

function Write-LogStep {
    param([string]$Message)
    Write-Host ""
    Write-Log "=============================================="
    Write-Log $Message -Color Cyan
    Write-Log "=============================================="
    Write-Host ""
}

###############################################################################
# Set console appearance for maximum visibility
###############################################################################
try {
    # Set window title
    $host.UI.RawUI.WindowTitle = "GenAI Research - Installation Progress - DO NOT CLOSE"

    # Set colors for high visibility
    $host.UI.RawUI.BackgroundColor = "DarkBlue"
    $host.UI.RawUI.ForegroundColor = "White"

    # Try to maximize window and set buffer size
    try {
        $maxSize = $host.UI.RawUI.MaxPhysicalWindowSize
        $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($maxSize.Width, $maxSize.Height)
        $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size($maxSize.Width, 9999)
    } catch { }

    Clear-Host
} catch { }

###############################################################################
# Header - Large and prominent
###############################################################################
Write-Host ""
Write-Host ""
Write-Host "    ╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "    ║                                                                                ║" -ForegroundColor Green
Write-Host "    ║                    GENAI RESEARCH - INSTALLATION IN PROGRESS                   ║" -ForegroundColor Green
Write-Host "    ║                                                                                ║" -ForegroundColor Green
Write-Host "    ╠════════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "    ║                                                                                ║" -ForegroundColor Cyan
Write-Host "    ║   This window shows REAL-TIME installation progress. You will see:            ║" -ForegroundColor Cyan
Write-Host "    ║                                                                                ║" -ForegroundColor Cyan
Write-Host "    ║      • File verification and setup                                             ║" -ForegroundColor Cyan
Write-Host "    ║      • Docker image builds (this takes 10-20 minutes)                          ║" -ForegroundColor Cyan
Write-Host "    ║      • Container startup and health checks                                     ║" -ForegroundColor Cyan
Write-Host "    ║      • Service verification                                                    ║" -ForegroundColor Cyan
Write-Host "    ║                                                                                ║" -ForegroundColor Cyan
Write-Host "    ╠════════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
Write-Host "    ║                                                                                ║" -ForegroundColor Yellow
Write-Host "    ║   ██  DO NOT CLOSE THIS WINDOW - Installation will fail if closed!  ██        ║" -ForegroundColor Yellow
Write-Host "    ║                                                                                ║" -ForegroundColor Yellow
Write-Host "    ╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""
Write-Host ""

Write-Log "Install Directory: $InstallDir"
if ($LogFile) {
    Write-Log "Log File: $LogFile"
}
Write-Host ""

###############################################################################
# STEP 0: Verify Installation Directory Contents
###############################################################################
Write-LogStep "STEP 0/6: Verifying Installation Directory"

Write-Log "Checking installation directory: $InstallDir"

if (-not (Test-Path $InstallDir)) {
    Write-LogError "Installation directory does not exist: $InstallDir"
    Write-LogError "This is a critical error - the MSI did not install files correctly."
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

# Check for critical files
$criticalFiles = @(
    "docker-compose.yml",
    "Dockerfile.base",
    "pyproject.toml",
    "VERSION"
)

$missingFiles = @()
foreach ($file in $criticalFiles) {
    $filePath = Join-Path $InstallDir $file
    if (Test-Path $filePath) {
        Write-LogSuccess "Found: $file"
    } else {
        Write-LogError "MISSING: $file"
        $missingFiles += $file
    }
}

# Check for critical directories
$criticalDirs = @("src", "scripts")
foreach ($dir in $criticalDirs) {
    $dirPath = Join-Path $InstallDir $dir
    if (Test-Path $dirPath) {
        $fileCount = (Get-ChildItem -Path $dirPath -Recurse -File).Count
        Write-LogSuccess "Found: $dir/ ($fileCount files)"
    } else {
        Write-LogError "MISSING: $dir/"
        $missingFiles += "$dir/"
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host ""
    Write-LogError "Critical files are missing from the installation!"
    Write-LogError "Missing: $($missingFiles -join ', ')"
    Write-Host ""
    Write-Log "This usually means:"
    Write-Log "  1. The MSI installer was built incorrectly"
    Write-Log "  2. The installation was interrupted"
    Write-Log "  3. Antivirus software blocked file extraction"
    Write-Host ""
    Write-Log "Please try:"
    Write-Log "  1. Uninstall the application from Add/Remove Programs"
    Write-Log "  2. Download a fresh copy of the installer"
    Write-Log "  3. Temporarily disable antivirus during installation"
    Write-Log "  4. Run the installer as Administrator"
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

Write-LogSuccess "All critical files verified"

###############################################################################
# STEP 1: Verify .env File
###############################################################################
Write-LogStep "STEP 1/6: Verifying .env File"

$envFile = Join-Path $InstallDir ".env"

if (-not (Test-Path $envFile)) {
    Write-LogError ".env file not found at: $envFile"
    Write-LogError "Please ensure you provided the .env file path during installation"
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

$envContent = Get-Content $envFile -Raw
if (-not $envContent -or $envContent.Trim().Length -eq 0) {
    Write-LogError ".env file is empty"
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

$lineCount = (Get-Content $envFile | Measure-Object -Line).Lines
Write-LogSuccess ".env file verified ($lineCount lines)"

###############################################################################
# STEP 2: Verify Docker
###############################################################################
Write-LogStep "STEP 2/6: Checking Docker Desktop"

Write-Log "Checking if Docker is running..."

$dockerRunning = $false
try {
    $dockerInfo = docker info 2>&1
    $dockerRunning = ($LASTEXITCODE -eq 0)
} catch {
    $dockerRunning = $false
}

if (-not $dockerRunning) {
    Write-LogError "Docker Desktop is NOT running!"
    Write-Host ""
    Write-LogWarning "Please:"
    Write-Log "1. Start Docker Desktop from the Start Menu"
    Write-Log "2. Wait for Docker to fully start (whale icon in system tray)"
    Write-Log "3. Run 'First-Time Setup' from Start Menu"
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

Write-LogSuccess "Docker is running!"

# Show Docker version
$dockerVersion = docker --version 2>&1
Write-Log "Docker version: $dockerVersion"

###############################################################################
# STEP 3: System Detection
###############################################################################
Write-LogStep "STEP 3/6: Detecting System Hardware"

try {
    $gpus = Get-WmiObject Win32_VideoController
    $hasGPU = $false
    foreach ($gpu in $gpus) {
        if ($gpu.Name -like "*NVIDIA*" -or $gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*") {
            $hasGPU = $true
            Write-Log "GPU detected: $($gpu.Name)"
        }
    }
    if (-not $hasGPU) {
        Write-Log "No dedicated GPU detected (will use CPU mode)"
    }

    $ram = Get-WmiObject Win32_ComputerSystem
    $totalRAM = [math]::Round($ram.TotalPhysicalMemory / 1GB)
    Write-Log "System RAM: ${totalRAM}GB"
} catch {
    Write-LogWarning "Could not detect system specifications"
}

Write-LogSuccess "System detection complete"

###############################################################################
# STEP 4: Build Docker Images
###############################################################################
Write-LogStep "STEP 4/6: Building Docker Images"

Set-Location $InstallDir

Write-Host ""
Write-Log "This is the longest step - typically 10-20 minutes" -Color Yellow
Write-Log "You will see Docker build output below..." -Color Yellow
Write-Host ""
Write-Host "────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

# Build base-poetry-deps
Write-Host ""
Write-Log ">>> Building base-poetry-deps..." -Color Cyan
Write-Host ""

$baseBuildStart = Get-Date
docker compose build base-poetry-deps 2>&1 | ForEach-Object {
    Write-Host $_
    Add-Content -Path $LogFile -Value $_ -ErrorAction SilentlyContinue
}
$baseExitCode = $LASTEXITCODE
$baseBuildDuration = [math]::Round(((Get-Date) - $baseBuildStart).TotalMinutes, 1)

Write-Host ""
if ($baseExitCode -eq 0) {
    Write-LogSuccess "base-poetry-deps built successfully! (${baseBuildDuration} minutes)"
} else {
    Write-LogError "base-poetry-deps build FAILED (exit code: $baseExitCode)"
    Write-Host ""
    if ($LogFile) { Write-Log "Check the log file for details: $LogFile" }
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

# Build all application services
Write-Host ""
Write-Log ">>> Building application services..." -Color Cyan
Write-Host ""

$appBuildStart = Get-Date
docker compose build 2>&1 | ForEach-Object {
    Write-Host $_
    Add-Content -Path $LogFile -Value $_ -ErrorAction SilentlyContinue
}
$appExitCode = $LASTEXITCODE
$appBuildDuration = [math]::Round(((Get-Date) - $appBuildStart).TotalMinutes, 1)

Write-Host ""
if ($appExitCode -eq 0) {
    Write-LogSuccess "Application services built successfully! (${appBuildDuration} minutes)"
} else {
    Write-LogError "Application build FAILED (exit code: $appExitCode)"
    Write-Host ""
    if ($LogFile) { Write-Log "Check the log file for details: $LogFile" }
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

Write-Host "────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

# Verify images were built
Write-Host ""
Write-Log "Verifying Docker images..."

$images = docker images --format "{{.Repository}}:{{.Tag}}" 2>&1
Write-Log "Built images:"
$images | ForEach-Object { Write-Log "  - $_" }

###############################################################################
# STEP 5: Start Services
###############################################################################
Write-LogStep "STEP 5/6: Starting Application Services"

Write-Log "Starting Docker containers..."

docker compose up -d 2>&1 | ForEach-Object {
    Write-Host $_
    Add-Content -Path $LogFile -Value $_ -ErrorAction SilentlyContinue
}
$upExitCode = $LASTEXITCODE

if ($upExitCode -ne 0) {
    Write-LogError "Failed to start containers (exit code: $upExitCode)"
    Wait-ForUserInput "Press Enter to exit..."
    exit 1
}

Write-Log "Waiting 20 seconds for services to initialize..."
Start-Sleep -Seconds 20

# Verify containers are running
Write-Log "Checking container status..."

$running = docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>&1
Write-Host ""
Write-Log "Container Status:"
$running | ForEach-Object { Write-Log "  $_" }

$runningCount = (docker compose ps --status running --format "{{.Name}}" 2>&1 | Measure-Object -Line).Lines

###############################################################################
# STEP 6: Verify Services
###############################################################################
Write-LogStep "STEP 6/6: Verifying Services"

if ($runningCount -gt 0) {
    Write-LogSuccess "$runningCount container(s) running"
} else {
    Write-LogWarning "No containers appear to be running"
    Write-Log "You may need to start services manually using the Start Menu shortcut"
}

###############################################################################
# INSTALLATION COMPLETE
###############################################################################
$totalDuration = [math]::Round(((Get-Date) - $StartTime).TotalMinutes, 1)

Write-Host ""
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                                  ║" -ForegroundColor Green
Write-Host "║              INSTALLATION COMPLETED SUCCESSFULLY!                ║" -ForegroundColor Green
Write-Host "║                                                                  ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-LogSuccess "Total installation time: $totalDuration minutes"
Write-LogSuccess "Containers running: $runningCount"
Write-Host ""
Write-Log "Application URLs:" -Color Cyan
Write-Log "  • Streamlit UI:  http://localhost:8501" -Color White
Write-Log "  • FastAPI:       http://localhost:9020" -Color White
Write-Log "  • ChromaDB:      http://localhost:8000" -Color White
Write-Host ""
Write-Log "Use Start Menu shortcuts to manage the application."
if ($LogFile) {
    Write-Log "Log file saved to: $LogFile"
}
Write-Host ""

# ALWAYS wait for user input before closing
Wait-ForUserInput "Press Enter to close this window..."

exit 0
