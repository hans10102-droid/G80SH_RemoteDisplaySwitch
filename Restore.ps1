# Restore.ps1 - 평소 구성(G80SH + G50F, 동글 끔)으로 되돌린다.
#   -Auto : 로그온/잠금해제 작업에서 호출. 크롬 원격이 접속 중이면 건드리지 않는다.
#   (인자 없음) : 수동 비상 복구. 무조건 복원.
param([switch]$Auto)
# 관리자 작업 훅: 같은 폴더에 admin_hook.ps1 이 있으면 (작업 스케줄러의 관리자 권한으로) 실행 후 지우고 끝낸다.
$hook = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'admin_hook.ps1'
if (Test-Path $hook) { try { & $hook } finally { [IO.File]::Delete($hook) }; exit 0 }
$ErrorActionPreference = 'SilentlyContinue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$mmt  = Join-Path $base 'MultiMonitorTool.exe'
$log  = Join-Path $env:ProgramData 'RemoteDisplaySwitch.log'
$now  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if ($Auto) {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $e = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='chromoting'; Id=1,2; StartTime=$boot} -MaxEvents 1
    if ($e -and $e.Id -eq 1) { Add-Content $log "$now RESTORE skipped (remote connected)"; exit 0 }
}

. (Join-Path $base 'SwitchLib.ps1')
$s = Switch-ToHome
Add-Content $log ("{0} RESTORE {1} -> ok={2} active={3} primary={4}" -f $now, $(if ($Auto) { 'auto' } else { 'manual' }), $s.Ok, $s.Active, $s.Primary)
