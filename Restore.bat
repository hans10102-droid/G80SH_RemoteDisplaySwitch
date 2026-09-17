@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1"
echo [OK] 평소 디스플레이 구성으로 복원했습니다.
pause
