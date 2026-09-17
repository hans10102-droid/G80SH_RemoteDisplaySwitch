# Setup.ps1 (rev.2) - Setup.bat 에서 관리자 권한으로 호출
# 1) 평소 구성 저장: G80SH + G50F 사용, 동글 끊김
# 2) 원격 구성 자동 생성: 동글만 사용 (화면이 안 보이는 구간이라 사용자 조작 없이 처리 후 자동 복원)
# 3) 작업 스케줄러 등록
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $base
$mmt = Join-Path $base 'MultiMonitorTool.exe'
$physical = @('SAM7B0C', 'SAM79DF')   # G80SH, G50F (Short Monitor ID)

function Pause-Key($msg) { Write-Host $msg; [void][Console]::ReadKey($true) }

function Get-Monitors {
    $xml = Join-Path $env:TEMP 'rds_monitors.xml'
    Remove-Item $xml -ErrorAction SilentlyContinue
    & $mmt /sxml $xml | Out-Null
    for ($i = 0; $i -lt 20 -and -not (Test-Path $xml); $i++) { Start-Sleep -Milliseconds 250 }
    Start-Sleep -Milliseconds 300
    [xml]$doc = Get-Content $xml -Raw
    foreach ($it in $doc.DocumentElement.ChildNodes) {
        $h = @{}
        foreach ($c in $it.ChildNodes) { $h[$c.Name] = $c.InnerText }
        [pscustomobject]@{
            Name    = $h['name']
            ShortId = $h['short_monitor_id']
            Label   = $h['monitor_name']
            Active  = $h['active']
        }
    }
}

if (-not (Test-Path $mmt)) {
    Write-Host '[FAIL] MultiMonitorTool.exe 가 없습니다.'
    Write-Host '       https://www.nirsoft.net/utils/multi_monitor_tool.html 에서 64-bit zip 을 받아'
    Write-Host '       MultiMonitorTool.exe 를 이 폴더에 넣고 다시 실행하세요.'
    Pause-Key '아무 키나 누르면 종료'; exit 1
}

Write-Host "`n 현재 디스플레이:"
$mons = @(Get-Monitors)
$mons | Format-Table Name, ShortId, Label, Active -AutoSize | Out-Host

$dongle = @($mons | Where-Object { $_.ShortId -and ($physical -notcontains $_.ShortId) })
if ($dongle.Count -ne 1) {
    Write-Host "[FAIL] 동글을 특정할 수 없습니다 (G80SH/G50F 외 모니터 $($dongle.Count)개)."
    Write-Host '       동글만 추가로 꽂힌 상태에서 다시 실행하세요.'
    Pause-Key '아무 키나 누르면 종료'; exit 1
}
$dongleId = $dongle[0].ShortId
Write-Host " 동글: $dongleId ($($dongle[0].Label))"

Write-Host ''
Write-Host '============================================================'
Write-Host ' [1/3] 평소(home) 구성 저장'
Write-Host '       설정 > 시스템 > 디스플레이 에서 동글 화면을'
Write-Host '       "이 디스플레이 연결 끊기" 로 해제하고,'
Write-Host '       G80SH / G50F 배치와 주 모니터를 평소대로 맞춘 뒤 키를 누르세요.'
Write-Host '============================================================'
Pause-Key ''
$act = @(Get-Monitors | Where-Object { $_.Active -eq 'Yes' } | ForEach-Object { $_.ShortId })
if ($act -contains $dongleId -or -not ($act -contains 'SAM7B0C')) {
    Write-Host "[FAIL] 활성 디스플레이: $($act -join ', ')  - 동글은 끊기고 G80SH 는 켜져 있어야 합니다."
    Pause-Key '아무 키나 누르면 종료'; exit 1
}
& $mmt /SaveConfig (Join-Path $base 'home.cfg') | Out-Null
Write-Host ' -> home.cfg 저장'

Write-Host ''
Write-Host '============================================================'
Write-Host ' [2/3] 원격(remote) 구성 자동 생성'
Write-Host '       약 10초간 모든 물리 모니터가 꺼졌다가 자동으로 돌아옵니다.'
Write-Host '       아무것도 만지지 말고 기다리세요.'
Write-Host '============================================================'
Pause-Key ' 준비되면 키를 누르세요'
& $mmt /enable $dongleId | Out-Null;          Start-Sleep 3
& $mmt /SetPrimary $dongleId | Out-Null;      Start-Sleep 2
& $mmt /disable SAM7B0C SAM79DF | Out-Null;   Start-Sleep 3
$actR = @(Get-Monitors | Where-Object { $_.Active -eq 'Yes' } | ForEach-Object { $_.ShortId })
# /SaveConfig 는 끊긴 모니터 항목을 빠뜨려 LoadConfig 시 G80SH 가 안 꺼진다 (09-17 20:52).
# home.cfg 를 기준으로 물리 모니터는 Width/Height=0, 동글만 해상도를 채워 remote.cfg 를 만든다.
$tmp = Join-Path $env:TEMP 'rds_remote_saved.cfg'
& $mmt /SaveConfig $tmp | Out-Null
Start-Sleep 1
$dongleSec = ((Get-Content $tmp -Raw) -split '(?=\[Monitor\d+\])' | Where-Object { $_ -match "MonitorID=MONITOR\\$dongleId\\" }) | Select-Object -First 1
$sections = (Get-Content (Join-Path $base 'home.cfg') -Raw) -split '(?=\[Monitor\d+\])' | Where-Object { $_.Trim() }
$outSec = foreach ($s in $sections) {
    if ($s -match "MonitorID=MONITOR\\$dongleId\\") { ($dongleSec -replace '\[Monitor\d+\]', ($s -split "`r?`n")[0]) -replace 'PositionX=-?\d+','PositionX=0' -replace 'PositionY=-?\d+','PositionY=0' }
    else { $s -replace 'BitsPerPixel=\d+','BitsPerPixel=0' -replace 'Width=\d+','Width=0' -replace 'Height=\d+','Height=0' -replace 'DisplayFrequency=\d+','DisplayFrequency=0' -replace 'PositionX=-?\d+','PositionX=0' -replace 'PositionY=-?\d+','PositionY=0' }
}
($outSec | ForEach-Object { $_.TrimEnd() }) -join "`r`n" | Set-Content (Join-Path $base 'remote.cfg') -Encoding ASCII
& $mmt /LoadConfig (Join-Path $base 'home.cfg') | Out-Null
Start-Sleep 3
Write-Host " -> remote.cfg 저장 (당시 활성: $($actR -join ', '))  / 평소 구성 복원"
if ($actR.Count -ne 1 -or $actR[0] -ne $dongleId) {
    Write-Host '[WARN] 원격 구성에 동글만 남지 않았습니다. 설치를 중단합니다.'
    Pause-Key '아무 키나 누르면 종료'; exit 1
}
Set-Content (Join-Path $env:ProgramData 'RemoteDisplaySwitch.state') 'home'

Write-Host ''
Write-Host ' [3/3] 작업 등록'
$ps = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File"
schtasks /Create /F /TN "Remote Display Switch" /SC ONLOGON /RL HIGHEST /TR "$ps \`"$base\RemoteDisplaySwitch.ps1\`"" | Out-Host
schtasks /Create /F /TN "Remote Display Restore (logon)" /SC ONLOGON /RL HIGHEST /TR "$ps \`"$base\Restore.ps1\`" -Auto" | Out-Host
schtasks /Create /F /TN "Remote Display Restore (unlock)" /RL HIGHEST /TR "$ps \`"$base\Restore.ps1\`" -Auto" /SC ONEVENT /EC Security /MO "*[System[EventID=4801]]" | Out-Host

Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$base\RemoteDisplaySwitch.ps1`""
Write-Host ''
Write-Host " [OK] 완료. 로그: $env:ProgramData\RemoteDisplaySwitch.log"
Write-Host '      비상 복구: Restore.bat 실행 또는 동글 뽑기'
Pause-Key '아무 키나 누르면 종료'
