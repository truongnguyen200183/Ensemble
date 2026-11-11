@echo off
chcp 65001 >nul
title Ensemble Collab - Universal Installer
echo ========================================================================
echo   ENSEMBLE COLLAB - UNIVERSAL INSTALLER
echo   Khoi chay trinh cai dat tu dong cho Windows & WSL...
echo ========================================================================
echo.

:: Chạy PowerShell Script với quyền Bypass ExecutionPolicy
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [LOI] Qua trinh cai dat gap loi (Exit Code: %ERRORLEVEL%).
    pause
)
