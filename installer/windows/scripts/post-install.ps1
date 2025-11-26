###############################################################################
# Windows Post-Installation Script
# Runs DURING MSI installation with visible terminal output
# Streamlined workflow: .env creation → compute detection → model download → docker build
###############################################################################

param(
    [string]$InstallDir = "$env:ProgramFiles\DIS Verification GenAI"
)

$ErrorActionPreference = "Continue"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

# Set console buffer to handle lots of output
try {
    $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(120, 9999)
} catch {
    # Ignore if we can't set buffer size
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  DIS Verification GenAI - First-Time Setup" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Info "Installation Directory: $InstallDir"
Write-Host ""

# Change to install directory
Set-Location $InstallDir

###############################################################################
# STEP 1: Create .env file
###############################################################################
Write-Step "STEP 1/5: Environment Configuration"

$envFile = Join-Path $InstallDir ".env"
$envTemplate = Join-Path $InstallDir ".env.template"

if (Test-Path $envFile) {
    Write-Warning ".env file already exists"
    $overwrite = Read-Host "Do you want to reconfigure? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Info "Keeping existing .env file"
    } else {
        Remove-Item $envFile
    }
}

if (-not (Test-Path $envFile)) {
    Write-Host "Please paste your .env file contents below."
    Write-Host "When finished, type 'END' on a new line and press Enter."
    Write-Host ""
    Write-Host "TIP: Your .env file should contain:" -ForegroundColor Yellow
    Write-Host "  - OPENAI_API_KEY=your-key-here" -ForegroundColor Yellow
    Write-Host "  - DATABASE_URL, DB_PASSWORD, and other settings" -ForegroundColor Yellow
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
        Write-Host ""
        Write-Info "Saving .env file to: $envFile"
        Set-Content -Path $envFile -Value $content -Encoding UTF8

        if (Test-Path $envFile) {
            $fileSize = (Get-Item $envFile).Length
            Write-Success ".env file created successfully! (Size: $fileSize bytes)"

            # Show first few lines for verification
            Write-Host ""
            Write-Host "First few lines of your .env file:" -ForegroundColor Yellow
            Get-Content $envFile -TotalCount 3 | ForEach-Object {
                $maskedLine = $_ -replace '(KEY|PASSWORD|SECRET)=.*', '$1=***HIDDEN***'
                Write-Host "  $maskedLine" -ForegroundColor DarkGray
            }
            Write-Host "  ..." -ForegroundColor DarkGray
        } else {
            Write-ErrorMsg "Failed to create .env file!"
            Write-Host "Press any key to exit..."
            $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            exit 1
        }
    } else {
        Write-ErrorMsg "No content provided!"

        if (Test-Path $envTemplate) {
            Write-Info "Creating .env from template instead..."
            Copy-Item $envTemplate $envFile
            Write-Warning "You'll need to edit the .env file manually with your API keys"
            Write-Info "Location: $envFile"
        } else {
            Write-ErrorMsg "No template file found. Cannot continue."
            Write-Host "Press any key to exit..."
            $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            exit 1
        }
    }
}

Write-Host ""
Write-Success "✓ Step 1/5 Complete: Environment configuration"

###############################################################################
# STEP 2: Check Docker
###############################################################################
Write-Step "STEP 2/5: Docker Verification"

$dockerRunning = $false
try {
    $null = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dockerRunning = $true
        Write-Success "Docker Desktop is running"
    }
} catch {
    $dockerRunning = $false
}

if (-not $dockerRunning) {
    Write-Warning "Docker Desktop is not running"
    Write-Info "Please start Docker Desktop before continuing"
    $startDocker = Read-Host "Would you like to start Docker Desktop now? (Y/n)"
    if ($startDocker -ne "n" -and $startDocker -ne "N") {
        Write-Info "Starting Docker Desktop..."
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        Write-Info "Waiting for Docker to start (this may take 30-60 seconds)..."

        # Wait for Docker to be ready
        $maxWait = 120
        $waited = 0
        while ($waited -lt $maxWait) {
            Start-Sleep -Seconds 5
            $waited += 5
            try {
                $null = docker info 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $dockerRunning = $true
                    Write-Success "Docker is now running!"
                    break
                }
            } catch {
                Write-Host "." -NoNewline
            }
        }

        if (-not $dockerRunning) {
            Write-ErrorMsg "Docker failed to start in time"
            Write-Info "Please start Docker manually and run 'First-Time Setup' from Start Menu"
            Write-Host "Press any key to exit..."
            $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            exit 1
        }
    } else {
        Write-ErrorMsg "Docker is required to continue"
        Write-Info "Please start Docker Desktop and run 'First-Time Setup' from Start Menu"
        Write-Host "Press any key to exit..."
        $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
}

Write-Host ""
Write-Success "✓ Step 2/5 Complete: Docker verification"

###############################################################################
# STEP 3: Detect compute capabilities
###############################################################################
Write-Step "STEP 3/5: System Detection"

Write-Info "Detecting system hardware..."
$hasNvidiaGPU = $false
$hasAMDGPU = $false
$totalRAM = 0
$recommendedModel = ""

try {
    # Detect GPU
    $gpus = Get-WmiObject Win32_VideoController
    foreach ($gpu in $gpus) {
        if ($gpu.Name -like "*NVIDIA*") {
            $hasNvidiaGPU = $true
            Write-Info "  ✓ NVIDIA GPU detected: $($gpu.Name)"
        } elseif ($gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*") {
            $hasAMDGPU = $true
            Write-Info "  ✓ AMD GPU detected: $($gpu.Name)"
        }
    }

    if (-not $hasNvidiaGPU -and -not $hasAMDGPU) {
        Write-Info "  • No dedicated GPU detected (CPU mode)"
    }

    # Detect RAM
    $ram = Get-WmiObject Win32_ComputerSystem
    $totalRAM = [math]::Round($ram.TotalPhysicalMemory / 1GB)
    Write-Info "  • System RAM: ${totalRAM}GB"
} catch {
    Write-Warning "Could not detect system specifications"
    $totalRAM = 8  # Assume minimum
}

# Determine recommended model
if ($hasNvidiaGPU -or $hasAMDGPU) {
    if ($totalRAM -ge 16) {
        $recommendedModel = "llama3.1:8b"
    } else {
        $recommendedModel = "llama3.2:3b"
    }
} else {
    $recommendedModel = "llama3.2:1b"
}

Write-Success "System detection complete. Recommended model: $recommendedModel"
Write-Host ""
Write-Success "✓ Step 3/5 Complete: System detection"

###############################################################################
# STEP 4: Download Ollama models
###############################################################################
Write-Step "STEP 4/5: Model Download"

# Check if Ollama is installed
$ollamaInstalled = Get-Command ollama -ErrorAction SilentlyContinue

if (-not $ollamaInstalled) {
    Write-Warning "Ollama is not installed"
    Write-Info "Ollama provides local LLM support (recommended for privacy and cost savings)"
    $installOllama = Read-Host "Would you like to install Ollama now? (Y/n)"

    if ($installOllama -ne "n" -and $installOllama -ne "N") {
        Write-Info "Opening Ollama download page in your browser..."
        Start-Process "https://ollama.com/download/windows"
        Write-Host ""
        Write-Warning "After installing Ollama, please run 'First-Time Setup' from Start Menu again"
        Write-Host "Press any key to exit..."
        $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 0
    } else {
        Write-Info "Skipping Ollama installation (you can install it later)"
        Write-Host ""
        Write-Success "✓ Step 4/5 Complete: Model download (Ollama skipped)"
    }
} else {
    Write-Success "Ollama is installed"
    Write-Host ""
    Write-Info "Recommended model for your system: $recommendedModel"
    Write-Host ""
    Write-Host "Available models:" -ForegroundColor Yellow
    Write-Host "  1) llama3.2:1b  - Lightweight (1.3 GB) - Fast, CPU-friendly" -ForegroundColor White
    Write-Host "  2) llama3.2:3b  - Medium (2.0 GB) - Good balance" -ForegroundColor White
    Write-Host "  3) llama3.1:8b  - Large (4.7 GB) - Best quality (GPU recommended)" -ForegroundColor White
    Write-Host "  4) Skip model download (configure later)" -ForegroundColor White
    Write-Host ""

    $modelChoice = Read-Host "Select model [1-4] (press Enter for recommended: $recommendedModel)"

    $selectedModel = ""
    switch ($modelChoice.Trim()) {
        "1" { $selectedModel = "llama3.2:1b" }
        "2" { $selectedModel = "llama3.2:3b" }
        "3" { $selectedModel = "llama3.1:8b" }
        "4" {
            Write-Info "Skipping model download"
            $selectedModel = ""
        }
        "" { $selectedModel = $recommendedModel }
        default { $selectedModel = $recommendedModel }
    }

    if ($selectedModel) {
        Write-Host ""
        Write-Info "Downloading models (this may take several minutes)..."
        Write-Host ""
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

        # Always pull embedding model (small, required)
        Write-Info "Step 4a: Pulling embedding model (required): snowflake-arctic-embed2"
        ollama pull snowflake-arctic-embed2

        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMsg "Failed to download embedding model"
        } else {
            Write-Success "Embedding model downloaded successfully"
        }

        Write-Host ""

        # Pull selected LLM
        Write-Info "Step 4b: Pulling LLM model: $selectedModel"
        ollama pull $selectedModel

        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""

        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMsg "Failed to download model: $selectedModel"
            Write-Warning "You can download models manually later with: ollama pull <model-name>"
        } else {
            Write-Success "Model downloaded successfully: $selectedModel"
        }
    }

    Write-Host ""
    Write-Success "✓ Step 4/5 Complete: Model download"
}

###############################################################################
# STEP 5: Build Docker images
###############################################################################
Write-Step "STEP 5/5: Building Docker Images"

Write-Info "This process will build the application Docker images."
Write-Info "This is a ONE-TIME process that takes 5-15 minutes."
Write-Info "You'll see all the build output below."
Write-Host ""

$proceedBuild = Read-Host "Proceed with Docker build? (Y/n)"
if ($proceedBuild -eq "n" -or $proceedBuild -eq "N") {
    Write-Warning "Build skipped. You can build later by running 'First-Time Setup' from Start Menu"
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 0
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  Step 5a: Building base-poetry-deps" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

docker compose build base-poetry-deps

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-ErrorMsg "Failed to build base-poetry-deps image"
    Write-Info "You can try again later by running 'First-Time Setup' from Start Menu"
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Host ""
Write-Success "✓ Step 5a Complete: Base dependencies built"
Write-Host ""

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  Step 5b: Building application services" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

docker compose build

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-ErrorMsg "Failed to build application services"
    Write-Info "You can try again later by running 'First-Time Setup' from Start Menu"
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Host ""
Write-Success "✓ Step 5b Complete: Application services built"
Write-Host ""

###############################################################################
# STEP 6: Start services
###############################################################################
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Step 5c: Starting Application" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$startNow = Read-Host "Start the application now? (Y/n)"
if ($startNow -ne "n" -and $startNow -ne "N") {
    Write-Host ""
    Write-Info "Starting services..."
    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    docker compose up -d

    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-ErrorMsg "Failed to start services"
        Write-Info "Check logs with: docker compose logs"
        Write-Host ""
        Write-Host "Press any key to exit..."
        $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }

    Write-Host ""
    Write-Info "Waiting for services to initialize (15 seconds)..."
    Start-Sleep -Seconds 15

    Write-Host ""
    Write-Success "✓ Application started successfully!"
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Setup Complete!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Info "Services running:"
    Write-Host "  • Streamlit UI:  http://localhost:8501" -ForegroundColor Cyan
    Write-Host "  • FastAPI:       http://localhost:9020" -ForegroundColor Cyan
    Write-Host "  • ChromaDB:      http://localhost:8000" -ForegroundColor Cyan
    Write-Host ""
    Write-Info "Opening web interface in your browser..."
    Start-Process "http://localhost:8501"
    Write-Host ""
    Write-Info "To stop services: Use 'Stop Services' shortcut or run: docker compose down"
} else {
    Write-Host ""
    Write-Success "✓ Build complete! Services not started."
    Write-Host ""
    Write-Info "To start the application later:"
    Write-Host "  • Use the 'DIS Verification GenAI' shortcut from Start Menu"
    Write-Host "  • Or run: cd '$InstallDir' && docker compose up -d"
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Info "Documentation: $InstallDir\README.md"
Write-Info "Need help? Check: $InstallDir\INSTALL.md"
Write-Host ""
Write-Host "Press any key to close this window..."
$null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
