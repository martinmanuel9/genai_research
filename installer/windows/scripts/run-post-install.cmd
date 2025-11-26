@echo off
REM Wrapper to run post-install.ps1 with a visible, persistent PowerShell window

SET "INSTALL_DIR=%~1"
IF "%INSTALL_DIR%"=="" SET "INSTALL_DIR=%ProgramFiles%\DIS Verification GenAI"

echo.
echo ========================================================================
echo   DIS Verification GenAI - First-Time Setup
echo ========================================================================
echo.
echo This wizard will help you configure your installation.
echo.
pause

REM Run PowerShell in a new window that stays open
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%INSTALL_DIR%\scripts\post-install.ps1' -InstallDir '%INSTALL_DIR%'; Write-Host ''; Write-Host 'Setup complete. Press any key to close...'; $null = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')"

echo.
echo Setup wizard completed.
echo.
