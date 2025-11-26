###############################################################################
# Setup Script for WiX Installer
# Runs as deferred custom action with MSI logging
# All output goes to MSI log which is displayed in the progress dialog
###############################################################################

param(
    [string]$InstallDir = "$env:ProgramFiles\DIS Verification GenAI",
    [string]$EnvFilePath = ""
)

# Set error handling - stop on errors
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Don't show progress bars in MSI context

# Use Write-Host for MSI logging - it will appear in the installer progress
function Write-Log {
    param([string]$Message)
    Write-Host "CustomAction: $Message"
    [System.Console]::Out.Flush()  # Force flush output
    Start-Sleep -Milliseconds 50  # Brief pause so MSI can capture output
}

function Write-Progress-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "CustomAction: =========================================="
    Write-Host "CustomAction: $Message"
    Write-Host "CustomAction: =========================================="
    Write-Host ""
}

try {
    Write-Progress-Step "STEP 1/6: Environment Configuration"

    $envFile = Join-Path $InstallDir ".env"

    # Verify .env file exists (REQUIRED)
    if (-not (Test-Path $envFile)) {
        Write-Log "ERROR: .env file not found at: $envFile"
        Write-Log "The .env file is REQUIRED for the application to function"
        Write-Log "Installation cannot continue without a valid .env file"
        throw ".env file is missing - this should have been copied during installation"
    }

    # Validate .env file has content
    $envContent = Get-Content $envFile -Raw
    if (-not $envContent -or $envContent.Trim().Length -eq 0) {
        Write-Log "ERROR: .env file is empty"
        Write-Log "The .env file must contain valid configuration"
        throw ".env file is empty"
    }

    Write-Log ".env file verified successfully at: $envFile"
    $lineCount = (Get-Content $envFile | Measure-Object -Line).Lines
    Write-Log ".env file contains $lineCount lines of configuration"
    Write-Log "Step 1/6 Complete"

    ###########################################################################
    # STEP 2: Check Docker (REQUIRED)
    ###########################################################################
    Write-Progress-Step "STEP 2/6: Docker Verification"

    $dockerRunning = $false
    try {
        Write-Log "Checking Docker status..."
        $dockerInfo = docker info 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0) {
            $dockerRunning = $true
            Write-Log "Docker is running"
            Write-Log "Docker info retrieved successfully"
        } else {
            Write-Log "Docker info command failed with exit code: $LASTEXITCODE"
        }
    } catch {
        Write-Log "Exception while checking Docker: $($_.Exception.Message)"
        $dockerRunning = $false
    }

    if (-not $dockerRunning) {
        Write-Log "ERROR: Docker Desktop is not running!"
        Write-Log "Docker is REQUIRED for installation to complete"
        Write-Log "Please:"
        Write-Log "1. Start Docker Desktop"
        Write-Log "2. Wait for it to fully start"
        Write-Log "3. Run the installer again"
        throw "Docker is not running - cannot continue installation"
    }

    Write-Log "Step 2/6 Complete"

    ###########################################################################
    # STEP 3: Detect System
    ###########################################################################
    Write-Progress-Step "STEP 3/6: System Hardware Detection"

    $hasGPU = $false
    $totalRAM = 0
    $recommendedModel = ""

    try {
        # Detect GPU
        $gpus = Get-WmiObject Win32_VideoController
        foreach ($gpu in $gpus) {
            if ($gpu.Name -like "*NVIDIA*" -or $gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*") {
                $hasGPU = $true
                Write-Log "GPU detected: $($gpu.Name)"
            }
        }

        if (-not $hasGPU) {
            Write-Log "No dedicated GPU detected (CPU mode)"
        }

        # Detect RAM
        $ram = Get-WmiObject Win32_ComputerSystem
        $totalRAM = [math]::Round($ram.TotalPhysicalMemory / 1GB)
        Write-Log "System RAM: ${totalRAM}GB"

        # Determine recommended model
        if ($hasGPU -and $totalRAM -ge 16) {
            $recommendedModel = "llama3.1:8b"
        } elseif ($hasGPU) {
            $recommendedModel = "llama3.2:3b"
        } else {
            $recommendedModel = "llama3.2:1b"
        }

        Write-Log "Recommended model: $recommendedModel"
    } catch {
        Write-Log "Could not detect system specs: $($_.Exception.Message)"
        $recommendedModel = "llama3.2:1b"
    }

    Write-Log "Step 3/6 Complete"

    ###########################################################################
    # STEP 4: Download Models (if Ollama available and Docker running)
    ###########################################################################
    Write-Progress-Step "STEP 4/6: AI Model Download"

    $ollamaInstalled = Get-Command ollama -ErrorAction SilentlyContinue

    if (-not $ollamaInstalled) {
        Write-Log "Ollama not installed - skipping model download"
        Write-Log "Install Ollama from: https://ollama.com/download/windows"
        Write-Log "Then run 'First-Time Setup' from Start Menu"
        Write-Log "Step 4/6 Skipped (Ollama not available)"
    } elseif (-not $dockerRunning) {
        Write-Log "Docker not running - skipping model download"
        Write-Log "Run 'First-Time Setup' from Start Menu after starting Docker"
        Write-Log "Step 4/6 Skipped (Docker not available)"
    } else {
        Write-Log "Downloading AI models (this may take 5-10 minutes)..."

        # Download embedding model
        Write-Log "Downloading embedding model: snowflake-arctic-embed2"
        try {
            $pullOutput = ollama pull snowflake-arctic-embed2 2>&1
            if ($pullOutput) {
                $pullOutput | ForEach-Object {
                    if ($_ -and $_.ToString().Trim()) {
                        Write-Log $_
                    }
                }
            }
            Write-Log "Embedding model downloaded successfully"
        } catch {
            Write-Log "WARNING: Failed to download embedding model: $($_.Exception.Message)"
            Write-Log "You can download it later using: ollama pull snowflake-arctic-embed2"
        }

        # Download LLM model
        Write-Log "Downloading LLM model: $recommendedModel"
        try {
            $pullOutput = ollama pull $recommendedModel 2>&1
            if ($pullOutput) {
                $pullOutput | ForEach-Object {
                    if ($_ -and $_.ToString().Trim()) {
                        Write-Log $_
                    }
                }
            }
            Write-Log "LLM model downloaded successfully"
        } catch {
            Write-Log "WARNING: Failed to download LLM model: $($_.Exception.Message)"
            Write-Log "You can download it later using: ollama pull $recommendedModel"
        }

        Write-Log "Step 4/6 Complete"
    }

    ###########################################################################
    # STEP 5: Build Docker Images (REQUIRED)
    ###########################################################################
    Write-Progress-Step "STEP 5/6: Building Docker Containers"

    # Docker must be running at this point (we verified in Step 2)
    Set-Location $InstallDir

    # Build base dependencies
    Write-Log "Building base dependencies (this may take 5-10 minutes)..."
    Write-Log "Running: docker compose build base-poetry-deps"

    try {
        $buildOutput = docker compose build base-poetry-deps 2>&1
        $exitCode = $LASTEXITCODE

        # Log all output
        if ($buildOutput) {
            $buildOutput | ForEach-Object {
                if ($_ -and $_.ToString().Trim()) {
                    Write-Log $_
                }
            }
        }

        if ($exitCode -ne 0) {
            Write-Log "ERROR: Docker build failed with exit code: $exitCode"
            throw "Docker build failed for base-poetry-deps with exit code $exitCode"
        }

        Write-Log "Base dependencies built successfully"
    } catch {
        Write-Log "ERROR: Exception during base-poetry-deps build: $($_.Exception.Message)"
        throw
    }

    # Build application services
    Write-Log "Building application services (this may take 5-10 minutes)..."
    Write-Log "Running: docker compose build"

    try {
        $buildOutput = docker compose build 2>&1
        $exitCode = $LASTEXITCODE

        # Log all output
        if ($buildOutput) {
            $buildOutput | ForEach-Object {
                if ($_ -and $_.ToString().Trim()) {
                    Write-Log $_
                }
            }
        }

        if ($exitCode -ne 0) {
            Write-Log "ERROR: Docker build failed with exit code: $exitCode"
            throw "Docker build failed for application services with exit code $exitCode"
        }

        Write-Log "Application services built successfully"
    } catch {
        Write-Log "ERROR: Exception during application build: $($_.Exception.Message)"
        throw
    }

    Write-Log "Step 5/6 Complete"

    ###########################################################################
    # STEP 6: Start Services
    ###########################################################################
    Write-Progress-Step "STEP 6/6: Starting Application Services"

    Write-Log "Starting Docker containers..."
    Write-Log "Running: docker compose up -d"

    try {
        $upOutput = docker compose up -d 2>&1
        $exitCode = $LASTEXITCODE

        # Log all output
        if ($upOutput) {
            $upOutput | ForEach-Object {
                if ($_ -and $_.ToString().Trim()) {
                    Write-Log $_
                }
            }
        }

        if ($exitCode -ne 0) {
            Write-Log "WARNING: Failed to start services with exit code: $exitCode"
            Write-Log "You can start them manually with: docker compose up -d"
        } else {
            Write-Log "Services started successfully"
            Write-Log "Application will be available at http://localhost:8501"
        }
    } catch {
        Write-Log "WARNING: Exception while starting services: $($_.Exception.Message)"
        Write-Log "You can start them manually with: docker compose up -d"
    }

    Write-Log "Step 6/6 Complete"

    Write-Progress-Step "Installation Complete!"
    Write-Log "All setup steps finished"
    Write-Log "You can now launch the application from the Start Menu"
    Write-Log "The application will open at http://localhost:8501"

    exit 0

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack trace: $($_.ScriptStackTrace)"
    Write-Log "You can retry setup by running 'First-Time Setup' from Start Menu"
    exit 1
}
