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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-during-install.ps1" -InstallDir "%~dp0.."

echo.
echo ============================================================================
echo   Setup script has finished.
echo   Press any key to close this window...
echo ============================================================================
pause > nul
