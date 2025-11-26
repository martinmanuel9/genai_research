###############################################################################
# Setup Script for WiX Installer
# Runs as custom action during MSI installation
# All output goes to MSI log displayed in progress dialog
#
# EXIT CODES: 0 = Success, 1 = Failure
###############################################################################

param(
    [string]$InstallDir = "$env:ProgramFiles\GenAI Research",
    [string]$EnvFilePath = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Load shared utilities in MSI mode
. "$PSScriptRoot\docker-utils.ps1" -ForMSI

###############################################################################
# MAIN INSTALLATION WORKFLOW
###############################################################################
try {
    Write-LogStep "GenAI Research - Installation Setup"
    Write-Log "Install Directory: $InstallDir"

    #==========================================================================
    # STEP 1: Verify .env File
    #==========================================================================
    Write-LogStep "STEP 1/4: Environment Configuration"

    $envFile = Join-Path $InstallDir ".env"

    if (-not (Test-Path $envFile)) {
        Write-LogError ".env file not found at: $envFile"
        throw ".env file is missing"
    }

    $envContent = Get-Content $envFile -Raw
    if (-not $envContent -or $envContent.Trim().Length -eq 0) {
        Write-LogError ".env file is empty"
        throw ".env file is empty"
    }

    $lineCount = (Get-Content $envFile | Measure-Object -Line).Lines
    Write-LogSuccess ".env file verified ($lineCount lines)"

    #==========================================================================
    # STEP 2: Verify Docker
    #==========================================================================
    Write-LogStep "STEP 2/4: Docker Verification"

    if (-not (Test-DockerRunning)) {
        Write-LogError "Docker Desktop is not running!"
        Write-Log "Please start Docker Desktop and run the installer again"
        throw "Docker is not running"
    }
    Write-LogSuccess "Docker is running"

    #==========================================================================
    # STEP 3: System Detection
    #==========================================================================
    Write-LogStep "STEP 3/4: System Detection"

    $recommendedModel = Get-RecommendedModel
    Write-LogSuccess "Recommended model: $recommendedModel"

    #==========================================================================
    # STEP 4: Build and Start
    #==========================================================================
    Write-LogStep "STEP 4/4: Building and Starting Services"

    $buildSuccess = Invoke-FullBuildWorkflow -InstallDir $InstallDir -StartContainers

    if (-not $buildSuccess) {
        throw "Build workflow failed"
    }

    #==========================================================================
    # INSTALLATION COMPLETE
    #==========================================================================
    Write-LogStep "INSTALLATION COMPLETE"
    Write-LogSuccess "=============================================="
    Write-LogSuccess "GenAI Research installed successfully!"
    Write-LogSuccess "=============================================="
    Write-LogSuccess ""
    Write-LogSuccess "Docker images: BUILT"
    Write-LogSuccess "Containers: RUNNING"
    Write-LogSuccess ""
    Write-LogSuccess "Application available at:"
    Write-LogSuccess "  Streamlit UI:  http://localhost:8501"
    Write-LogSuccess "  FastAPI:       http://localhost:9020"
    Write-LogSuccess "  ChromaDB:      http://localhost:8000"

    exit 0

} catch {
    Write-Log ""
    Write-LogError "=============================================="
    Write-LogError "INSTALLATION FAILED"
    Write-LogError "=============================================="
    Write-LogError "Error: $($_.Exception.Message)"
    Write-Log ""
    Write-Log "Troubleshooting:"
    Write-Log "1. Ensure Docker Desktop is running"
    Write-Log "2. Check that .env file is valid"
    Write-Log "3. Try running 'First-Time Setup' from Start Menu"

    exit 1
}
