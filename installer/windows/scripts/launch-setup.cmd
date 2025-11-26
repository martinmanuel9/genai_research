@echo off
REM ============================================================================
REM GenAI Research - Setup Launcher
REM This batch file launches the PowerShell setup script in a visible window
REM ============================================================================

title GenAI Research Setup - DO NOT CLOSE THIS WINDOW

echo.
echo ============================================================================
echo   GenAI Research - Setup Starting
echo ============================================================================
echo.
echo   This window will show the installation progress.
echo   Please DO NOT close this window until setup is complete.
echo.
echo ============================================================================
echo.

cd /d "%~dp0.."

REM Run the PowerShell setup script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-during-install.ps1" -InstallDir "%~dp0.."

REM The PowerShell script handles its own "Press Enter to continue" prompt
REM This batch file will exit after PowerShell exits
