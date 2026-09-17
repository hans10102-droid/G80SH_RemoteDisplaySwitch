@echo off
chcp 65001 >nul
schtasks /Delete /F /TN "Remote Display Switch"
schtasks /Delete /F /TN "Remote Display Restore (logon)"
schtasks /Delete /F /TN "Remote Display Restore (unlock)"
powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'RemoteDisplaySwitch.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1"
echo [OK] 작업 삭제, 감시자 종료, 디스플레이 구성 복원 완료.
pause
