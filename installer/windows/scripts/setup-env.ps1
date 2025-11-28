###############################################################################
# Windows Environment Setup Script
# Interactive configuration wizard for .env file
###############################################################################

param(
    [string]$InstallDir = "$env:ProgramFiles\GenAI Research"
)

$ErrorActionPreference = "Continue"  # Show errors but continue with the wizard

# Colors
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

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
    Write-Host ""
}

$EnvFile = Join-Path $InstallDir ".env"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "         GenAI Research - Environment Setup"
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host ""

# Check if .env already exists
if (Test-Path $EnvFile) {
    Write-Warning ".env file already exists"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  1) Keep existing configuration (exit)"
    Write-Host "  2) Reconfigure interactively"
    Write-Host "  3) Import from .env file (paste contents)"
    Write-Host "  4) Import from .env file (select file)"
    $option = Read-Host "Choice [1-4]"

    switch ($option) {
        "1" {
            Write-Info "Configuration cancelled - keeping existing .env"
            exit 0
        }
        "2" {
            # Continue with interactive configuration
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            Copy-Item $EnvFile "$EnvFile.backup.$timestamp"
            Write-Info "Existing configuration backed up to .env.backup.$timestamp"
        }
        "3" {
            # Import from pasted content
            Write-Info "Paste your .env file contents below."
            Write-Info "Press Ctrl+Z then Enter when done (or type END on a new line):"
            Write-Host ""

            $lines = @()
            do {
                $line = Read-Host
                if ($line -eq "END") { break }
                $lines += $line
            } while ($true)

            $content = $lines -join "`n"
            if ($content.Trim()) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                Copy-Item $EnvFile "$EnvFile.backup.$timestamp"
                Set-Content -Path $EnvFile -Value $content
                Write-Success ".env file updated from pasted content"
                Write-Info "Previous configuration backed up to .env.backup.$timestamp"
                exit 0
            } else {
                Write-Warning "No content provided, continuing with interactive setup"
            }
        }
        "4" {
            # Import from file
            Add-Type -AssemblyName System.Windows.Forms
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Title = "Select .env file"
            $openFileDialog.Filter = "Environment files (*.env)|*.env|All files (*.*)|*.*"
            $openFileDialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')

            if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $selectedFile = $openFileDialog.FileName
                if (Test-Path $selectedFile) {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    Copy-Item $EnvFile "$EnvFile.backup.$timestamp"
                    Copy-Item $selectedFile $EnvFile -Force
                    Write-Success ".env file updated from: $selectedFile"
                    Write-Info "Previous configuration backed up to .env.backup.$timestamp"
                    exit 0
                } else {
                    Write-Warning "Selected file not found, continuing with interactive setup"
                }
            } else {
                Write-Warning "No file selected, continuing with interactive setup"
            }
        }
        default {
            Write-Info "Invalid option, continuing with interactive setup"
        }
    }
}

# Start with template
$EnvTemplate = Join-Path $InstallDir ".env.template"
if (Test-Path $EnvTemplate) {
    Copy-Item $EnvTemplate $EnvFile
} else {
    Write-ErrorMsg "Template file not found: $EnvTemplate"
    exit 1
}

Write-Header "API Keys Configuration"

# OpenAI API Key
Write-Info "OpenAI API Key (for GPT-4, GPT-4o, etc.)"
$openaiKey = Read-Host "Enter OpenAI API Key (press Enter to skip)"
if ($openaiKey) {
    (Get-Content $EnvFile) -replace '^OPENAI_API_KEY=.*', "OPENAI_API_KEY=$openaiKey" | Set-Content $EnvFile
    Write-Success "OpenAI API key configured"
} else {
    Write-Warning "OpenAI API key not configured (cloud models will not be available)"
}

Write-Host ""

# Ollama information
Write-Header "Ollama (Local LLM Support)"

$ollamaInstalled = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaInstalled) {
    Write-Success "Ollama is installed"
} else {
    Write-Warning "Ollama is NOT installed"
    Write-Host ""
    Write-Host "To install Ollama for local model support:"
    Write-Host "  Download from: https://ollama.com/download/windows"
}

Write-Host ""
Write-Host "After installing Ollama, you must manually start the server and pull models:"
Write-Host ""
Write-Host "  1. Start Ollama server (in PowerShell):"
Write-Host "     ollama serve"
Write-Host ""
Write-Host "  2. In a NEW PowerShell window, pull models:"
Write-Host "     $InstallDir\scripts\pull-ollama-models.ps1 -Mode auto"
Write-Host ""
Write-Host "     Or pull individual models:"
Write-Host "     ollama pull llama3.1:8b"
Write-Host "     ollama pull granite3.2-vision:2b"
Write-Host ""
Write-Info "See $InstallDir\INSTALL.md for detailed instructions."

Write-Host ""
Write-Header "Database Configuration"

# Database password
Write-Info "PostgreSQL database password"
$dbPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$useGenerated = Read-Host "Use generated password? (Y/n)"
if ($useGenerated -eq "n" -or $useGenerated -eq "N") {
    $securePassword = Read-Host "Enter PostgreSQL password" -AsSecureString
    $dbPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
}

(Get-Content $EnvFile) -replace '^DB_PASSWORD=.*', "DB_PASSWORD=$dbPassword" | Set-Content $EnvFile
$databaseUrl = "postgresql://g3nA1-user:$dbPassword@postgres:5432/rag_memory"
(Get-Content $EnvFile) -replace '^DATABASE_URL=.*', "DATABASE_URL=$databaseUrl" | Set-Content $EnvFile
Write-Success "Database password configured"

Write-Host ""
Write-Header "Optional: LangSmith Tracing"

$enableLangSmith = Read-Host "Enable LangSmith tracing? (y/N)"
if ($enableLangSmith -eq "y" -or $enableLangSmith -eq "Y") {
    $langsmithKey = Read-Host "Enter LangSmith API key"
    $langsmithProject = Read-Host "Enter LangSmith project name"

    (Get-Content $EnvFile) -replace '^LANGCHAIN_API_KEY=.*', "LANGCHAIN_API_KEY=$langsmithKey" | Set-Content $EnvFile
    (Get-Content $EnvFile) -replace '^LANGSMITH_PROJECT=.*', "LANGSMITH_PROJECT=$langsmithProject" | Set-Content $EnvFile
    (Get-Content $EnvFile) -replace '^LANGSMITH_TRACING=.*', 'LANGSMITH_TRACING=true' | Set-Content $EnvFile
    Write-Success "LangSmith tracing enabled"
} else {
    (Get-Content $EnvFile) -replace '^LANGSMITH_TRACING=.*', 'LANGSMITH_TRACING=false' | Set-Content $EnvFile
    Write-Info "LangSmith tracing disabled"
}

Write-Host ""
Write-Header "Configuration Summary"

Write-Success "Environment configuration completed!"
Write-Host ""
Write-Host "Configuration file: $EnvFile"
Write-Host ""
Write-Info "Configured services:"
Write-Host "  - FastAPI Backend: http://localhost:9020"
Write-Host "  - Streamlit Web UI: http://localhost:8501"
Write-Host "  - PostgreSQL: localhost:5432"
Write-Host "  - ChromaDB: localhost:8001"
Write-Host "  - Redis: localhost:6379"
if ($ollamaInstalled) {
    Write-Host "  - Ollama: http://localhost:11434"
}

Write-Host ""
Write-Info "To start the application:"
Write-Host "  cd `"$InstallDir`""
Write-Host "  docker compose up -d"
Write-Host ""
Write-Info "Or use the Start Menu shortcut: GenAI Research"
Write-Host ""
