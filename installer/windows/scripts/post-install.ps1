###############################################################################
# GenAI Research - First-Time Setup Wizard
# Interactive post-installation configuration
# Run from Start Menu "First-Time Setup" shortcut
###############################################################################

param(
    [string]$InstallDir = "$env:ProgramFiles\GenAI Research"
)

$ErrorActionPreference = "Continue"

# Function to wait for user input (works in all PowerShell contexts)
function Wait-ForKey {
    param([string]$Message = "Press Enter to continue...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    Read-Host
}

# Setup logging - try install dir first, fallback to temp
$LogDir = Join-Path $InstallDir "logs"
$LogFile = $null

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $LogFile = Join-Path $LogDir "setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Set-Content -Path $LogFile -Value "GenAI Research Setup Log - $(Get-Date)" -ErrorAction Stop
    Write-Host "[INFO] Log file: $LogFile" -ForegroundColor Cyan
} catch {
    # Fallback to temp directory
    $LogFile = Join-Path $env:TEMP "genai-setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    try {
        Set-Content -Path $LogFile -Value "GenAI Research Setup Log - $(Get-Date)" -ErrorAction Stop
        Write-Host "[WARNING] Using temp log: $LogFile" -ForegroundColor Yellow
    } catch {
        $LogFile = $null
        Write-Host "[WARNING] Could not create log file" -ForegroundColor Yellow
    }
}

# Load shared utilities (interactive mode)
. "$PSScriptRoot\docker-utils.ps1"

# Set log file in docker-utils
$script:LogFile = $LogFile

# Set console buffer for lots of output
try {
    $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(120, 9999)
} catch { }

###############################################################################
# MAIN SCRIPT
###############################################################################

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  GenAI Research - First-Time Setup Wizard" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Log "Installation Directory: $InstallDir"
Write-Host ""

Set-Location $InstallDir

###############################################################################
# STEP 1: Environment Configuration
###############################################################################
Write-LogStep "STEP 1/4: Environment Configuration"

$envFile = Join-Path $InstallDir ".env"
$envTemplate = Join-Path $InstallDir ".env.template"

if (Test-Path $envFile) {
    Write-LogWarning ".env file already exists"
    $overwrite = Read-Host "Do you want to reconfigure? (y/N)"
    if ($overwrite -eq "y" -or $overwrite -eq "Y") {
        Remove-Item $envFile -Force
    } else {
        Write-Log "Keeping existing .env file"
    }
}

if (-not (Test-Path $envFile)) {
    Write-Host ""
    Write-Host "Please paste your .env file contents below." -ForegroundColor Yellow
    Write-Host "When finished, type 'END' on a new line and press Enter." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Your .env file should contain:" -ForegroundColor DarkGray
    Write-Host "  - OPENAI_API_KEY=your-key-here" -ForegroundColor DarkGray
    Write-Host "  - DATABASE_URL, DB_PASSWORD, and other settings" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Start pasting now:" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $lines = @()
    $lineCount = 0
    do {
        $line = Read-Host
        if ($line -eq "END") { break }
        $lines += $line
        $lineCount++
        if ($lineCount % 5 -eq 0) {
            Write-Host "  ... $lineCount lines received ..." -ForegroundColor DarkGray
        }
    } while ($true)

    $content = $lines -join "`n"

    if ($content.Trim()) {
        Set-Content -Path $envFile -Value $content -Encoding UTF8
        if (Test-Path $envFile) {
            $fileSize = (Get-Item $envFile).Length
            Write-LogSuccess ".env file created ($fileSize bytes)"
        } else {
            Write-LogError "Failed to create .env file!"
            Wait-ForKey
            exit 1
        }
    } else {
        Write-LogError "No content provided!"
        if (Test-Path $envTemplate) {
            Write-Log "Creating .env from template..."
            Copy-Item $envTemplate $envFile
            Write-LogWarning "You'll need to edit the .env file manually with your API keys"
        } else {
            Write-LogError "No template file found. Cannot continue."
            Wait-ForKey
            exit 1
        }
    }
}

Write-LogSuccess "Step 1/4 Complete"

###############################################################################
# STEP 2: Docker Verification
###############################################################################
Write-LogStep "STEP 2/4: Docker Verification"

if (Test-DockerRunning) {
    Write-LogSuccess "Docker Desktop is running"
} else {
    Write-LogWarning "Docker Desktop is not running"
    $startDocker = Read-Host "Would you like to start Docker Desktop now? (Y/n)"

    if ($startDocker -ne "n" -and $startDocker -ne "N") {
        Write-Log "Starting Docker Desktop..."
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        Write-Log "Waiting for Docker to start (up to 2 minutes)..."

        $maxWait = 120
        $waited = 0
        while ($waited -lt $maxWait) {
            Start-Sleep -Seconds 5
            $waited += 5
            Write-Host "." -NoNewline
            if (Test-DockerRunning) {
                Write-Host ""
                Write-LogSuccess "Docker is now running!"
                break
            }
        }

        if (-not (Test-DockerRunning)) {
            Write-Host ""
            Write-LogError "Docker failed to start in time"
            Wait-ForKey
            exit 1
        }
    } else {
        Write-LogError "Docker is required to continue"
        Wait-ForKey
        exit 1
    }
}

Write-LogSuccess "Step 2/4 Complete"

###############################################################################
# STEP 3: Ollama Model Download (Optional)
###############################################################################
Write-LogStep "STEP 3/4: Model Download (Optional)"

$ollamaInstalled = Get-Command ollama -ErrorAction SilentlyContinue

if (-not $ollamaInstalled) {
    Write-LogWarning "Ollama is not installed"
    Write-Log "Ollama provides local LLM support for privacy and cost savings"
    $installOllama = Read-Host "Would you like to open the Ollama download page? (Y/n)"

    if ($installOllama -ne "n" -and $installOllama -ne "N") {
        Start-Process "https://ollama.com/download/windows"
        Write-Log "After installing Ollama, run this setup again to download models"
    }
    Write-LogSuccess "Step 3/4 Complete (Ollama skipped)"
} else {
    Write-LogSuccess "Ollama is installed"

    Write-Host ""
    Write-Host "Model download options:" -ForegroundColor Yellow
    Write-Host "  1) Auto   - Auto-detect GPU and pull appropriate models"
    Write-Host "  2) Quick  - Lightweight models only (~6.6 GB)"
    Write-Host "  3) Recommended - Production-ready models (~9 GB)"
    Write-Host "  4) Vision - Vision/multimodal models only (~11.5 GB)"
    Write-Host "  5) Full   - All models including 70B variants (100+ GB)"
    Write-Host "  6) Skip model download"
    Write-Host ""

    $modelChoice = Read-Host "Select option [1-6] (Enter for Auto)"

    $pullMode = switch ($modelChoice.Trim()) {
        "1" { "auto" }
        "2" { "quick" }
        "3" { "recommended" }
        "4" { "vision" }
        "5" { "full" }
        "6" { "" }
        "" { "auto" }
        default { "auto" }
    }

    if ($pullMode) {
        Write-Host ""

        # Wait for Ollama service to be ready before pulling models
        Write-Log "Waiting for Ollama service to be ready..."
        $maxAttempts = 12
        $ollamaReady = $false

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
                $ollamaReady = $true
                Write-LogSuccess "Ollama is ready!"
                break
            } catch {
                Write-Host "  Waiting... (attempt $attempt of $maxAttempts)" -ForegroundColor DarkGray
                Start-Sleep -Seconds 5
            }
        }

        if (-not $ollamaReady) {
            Write-LogWarning "Ollama service is not responding after 60 seconds"
            Write-Log "You can pull models manually later with:"
            Write-Host "  $InstallDir\scripts\pull-ollama-models.ps1 -Mode $pullMode" -ForegroundColor Yellow
        } else {
            Write-Log "Running model pull script with mode: $pullMode"

            $pullScript = Join-Path $InstallDir "scripts\pull-ollama-models.ps1"
            if (Test-Path $pullScript) {
                & $pullScript -Mode $pullMode
            } else {
                Write-LogWarning "Pull script not found at: $pullScript"
                Write-Log "Falling back to basic model pull..."
                ollama pull snowflake-arctic-embed2
                ollama pull llama3.2:3b
            }

            Write-LogSuccess "Models downloaded"
        }
    }

    Write-LogSuccess "Step 3/4 Complete"
}

###############################################################################
# STEP 4: Build Docker Images
###############################################################################
Write-LogStep "STEP 4/4: Building Docker Images"

$doBuild = $true

if (Test-DockerImagesExist) {
    Write-LogSuccess "Docker images already exist"
    $rebuild = Read-Host "Do you want to rebuild them? (y/N)"
    $doBuild = ($rebuild -eq "y" -or $rebuild -eq "Y")
}

if ($doBuild) {
    Write-Log "This is a ONE-TIME process that takes 10-20 minutes."
    Write-Host ""

    $proceedBuild = Read-Host "Proceed with Docker build? (Y/n)"
    if ($proceedBuild -eq "n" -or $proceedBuild -eq "N") {
        Write-LogWarning "Build skipped. Run this setup again when ready."
        Wait-ForKey
        exit 0
    }

    $buildSuccess = Invoke-FullBuildWorkflow -InstallDir $InstallDir -StartContainers:$false

    if (-not $buildSuccess) {
        Write-LogError "Build failed"
        Wait-ForKey
        exit 1
    }
}

Write-LogSuccess "Step 4/4 Complete"

###############################################################################
# Start Services
###############################################################################
Write-LogStep "Starting Application"

$startNow = Read-Host "Start the application now? (Y/n)"

if ($startNow -ne "n" -and $startNow -ne "N") {
    if (-not (Start-DockerContainers -WorkingDirectory $InstallDir -WaitSeconds 15)) {
        Write-LogError "Failed to start services"
        Write-Log "Check logs with: docker compose logs"
        Wait-ForKey
        exit 1
    }

    Write-Host ""
    Write-LogSuccess "═══════════════════════════════════════════════════════════════"
    Write-LogSuccess "  Setup Complete! Application is running."
    Write-LogSuccess "═══════════════════════════════════════════════════════════════"
    Write-Host ""
    Write-Host "Services:" -ForegroundColor Yellow
    Write-Host "  - Streamlit UI:  http://localhost:8501"
    Write-Host "  - FastAPI:       http://localhost:9020"
    Write-Host "  - ChromaDB:      http://localhost:8001"
    Write-Host ""
    Write-Log "Opening web interface..."
    Start-Process "http://localhost:8501"
} else {
    Write-Host ""
    Write-LogSuccess "═══════════════════════════════════════════════════════════════"
    Write-LogSuccess "  Setup Complete! Ready to launch."
    Write-LogSuccess "═══════════════════════════════════════════════════════════════"
    Write-Host ""
    Write-Log "To start the application:"
    Write-Host "  - Use 'GenAI Research' shortcut from Start Menu"
    Write-Host "  - Or run: docker compose up -d"
}

Write-Host ""
Write-Log "Documentation: $InstallDir\README.md"
if ($LogFile) {
    Write-Log "Log file: $LogFile"
}

Wait-ForKey "Press Enter to close this window..."
