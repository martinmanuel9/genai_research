###############################################################################
# Launch Script for GenAI Research
# Used from Start Menu shortcut - builds if needed, then starts the app
###############################################################################

param(
    [string]$InstallDir = "$env:ProgramFiles\GenAI Research"
)

$ErrorActionPreference = "Continue"

# Load shared utilities (interactive mode)
. "$PSScriptRoot\docker-utils.ps1"

function Wait-ForKey {
    Write-Host ""
    Write-Host "Press any key to close this window..."
    $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

###############################################################################
# MAIN SCRIPT
###############################################################################

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  GenAI Research - Application Launcher" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

# Check Docker
Write-Log "Checking Docker..."
if (-not (Test-DockerRunning)) {
    Write-LogError "Docker Desktop is not running!"
    Write-Log "Please start Docker Desktop and try again."
    Wait-ForKey
    exit 1
}
Write-LogSuccess "Docker is running"

# Change to install directory
Set-Location $InstallDir

# Check .env file
$envFile = Join-Path $InstallDir ".env"
if (-not (Test-Path $envFile)) {
    Write-LogError ".env file not found!"
    Write-Log "Please run 'First-Time Setup' from the Start Menu first."
    Wait-ForKey
    exit 1
}
Write-LogSuccess ".env file found"

# Check if images need to be built
Write-Log "Checking Docker images..."

if (-not (Test-DockerImagesExist)) {
    Write-LogWarning "Docker images not found - building now..."
    Write-Log "This is a one-time process (10-20 minutes)"
    Write-Host ""

    $buildSuccess = Invoke-FullBuildWorkflow -InstallDir $InstallDir -StartContainers:$false

    if (-not $buildSuccess) {
        Write-LogError "Build failed"
        Wait-ForKey
        exit 1
    }
} else {
    Write-LogSuccess "Docker images found"
}

# Check if containers are already running
if (Test-ContainersRunning) {
    Write-LogSuccess "Application is already running!"
    Write-Host ""
    Write-Log "Opening web interface..."
    Start-Process "http://localhost:8501"
    Write-Host ""
    Write-Host "Services:" -ForegroundColor Yellow
    Write-Host "  - Streamlit UI:  http://localhost:8501"
    Write-Host "  - FastAPI:       http://localhost:9020"
    Write-Host "  - ChromaDB:      http://localhost:8000"
    Wait-ForKey
    exit 0
}

# Start containers
if (-not (Start-DockerContainers -WorkingDirectory $InstallDir -WaitSeconds 15)) {
    Write-LogError "Failed to start services"
    Write-Log "Check logs with: docker compose logs"
    Wait-ForKey
    exit 1
}

Write-Host ""
Write-LogSuccess "═══════════════════════════════════════════════════════════════"
Write-LogSuccess "  Application started successfully!"
Write-LogSuccess "═══════════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "Services:" -ForegroundColor Yellow
Write-Host "  - Streamlit UI:  http://localhost:8501"
Write-Host "  - FastAPI:       http://localhost:9020"
Write-Host "  - ChromaDB:      http://localhost:8000"
Write-Host ""
Write-Log "Opening web interface in your browser..."
Start-Process "http://localhost:8501"
Write-Host ""
Write-Host "To stop: Use 'Stop Services' shortcut or run: docker compose down"

Wait-ForKey
