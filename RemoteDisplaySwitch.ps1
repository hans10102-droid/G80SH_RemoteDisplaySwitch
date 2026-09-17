# RemoteDisplaySwitch.ps1  (rev.6, 2026-09-18)
# 규칙
#  1. 원격이 아닐 때: 동글(BBC0104) 절대 사용 안 함. G80SH + G50F 평소 구성 유지 (어긋나면 즉시 복원)
#     단, 화면 절전으로 G80SH를 켤 수 없는 동안은 복구하지 않는다 (재인식 루프·장치음 방지, rev.6)
#  2. 원격일 때: 동글만 사용, G80SH/G50F 사용 안 함
#  3. 원격이 끝나면: 평소 구성으로 즉시 복원 + 리셋(사람이 PC 앞에서 쓰다가 끝낸 것과 같은 상태로)
#     → 원격 종료 뒤 화면 절전 때 나는 G80SH 재인식 루프 제거 목적
#     리셋 방식: reset_mode.txt (rewake | restartdev | gpureset | off), 기본 rewake
#
# 스크립트 파일(RemoteDisplaySwitch.ps1 / SwitchLib.ps1 / DispCfg.ps1)이 바뀌면 스스로 재시작한다 (수정 시 UAC 불필요).
# 로그: C:\ProgramData\RemoteDisplaySwitch.log

$ErrorActionPreference = 'SilentlyContinue'
$base     = Split-Path -Parent $MyInvocation.MyCommand.Path
$self     = $MyInvocation.MyCommand.Path
$mmt      = Join-Path $base 'MultiMonitorTool.exe'
$modeFile = Join-Path $base 'reset_mode.txt'
$log      = Join-Path $env:ProgramData 'RemoteDisplaySwitch.log'
$g80Dev   = 'DISPLAY\SAM7B0C\7&16B8DDB4&0&UID256'

function Log($m) {
    Add-Content $log ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
    $f = Get-Item $log -ErrorAction SilentlyContinue
    if ($f -and $f.Length -gt 300KB) { Get-Content $log -Tail 400 | Set-Content $log }
}

if (-not (Test-Path $mmt)) { Log 'MISSING MultiMonitorTool.exe - abort'; exit 1 }

$mutex = New-Object System.Threading.Mutex($false, 'Local\RemoteDisplaySwitch')
if (-not $mutex.WaitOne(15000)) { exit 0 }

. (Join-Path $base 'SwitchLib.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class RdsInput {
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);
    public static uint Wake() {
        var a = new INPUT[2];
        a[0].type = 0; a[0].u.mi.dx = 1;  a[0].u.mi.dwFlags = 1;
        a[1].type = 0; a[1].u.mi.dx = -1; a[1].u.mi.dwFlags = 1;
        SetThreadExecutionState(0x00000002); // ES_DISPLAY_REQUIRED (1회, 화면 켜기 + 절전 타이머 리셋)
        return SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@

function Get-ResetMode { $m = Get-Content $modeFile -ErrorAction SilentlyContinue | Select-Object -First 1; if ($m) { $m.Trim().ToLower() } else { 'rewake' } }

function Do-Reset {
    $mode = Get-ResetMode
    switch ($mode) {
        'rewake'     { $r = "wake=" + [RdsInput]::Wake() }
        'restartdev' { $r = ((& pnputil.exe /restart-device $g80Dev 2>&1) -join ' ') -replace '\s+', ' '; Start-Sleep 3; $r += " wake=" + [RdsInput]::Wake() }
        'gpureset'   { $r = "restart-device display adapter: " + (((& pnputil.exe /restart-device (Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -match 'VEN_1002&DEV_7550' } | Select-Object -First 1).InstanceId 2>&1) -join ' ') -replace '\s+', ' '); Start-Sleep 5; $r += " wake=" + [RdsInput]::Wake() }
        default      { $r = 'no action' }
    }
    Log ("RESET mode={0} -> {1}" -f $mode, $r)
}

$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
function Get-Remote {
    $e = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='chromoting'; Id=1,2; StartTime=$boot} -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($e) { [pscustomobject]@{ Active = ($e.Id -eq 1); At = $e.TimeCreated } } else { [pscustomobject]@{ Active = $false; At = $boot } }
}

function Get-Stamp { ($self, (Join-Path $base 'SwitchLib.ps1'), (Join-Path $base 'DispCfg.ps1') | ForEach-Object { (Get-Item $_).LastWriteTimeUtc.Ticks }) -join '|' }
$stamp = Get-Stamp

Log ("watcher started (rev.6) reset={0}" -f (Get-ResetMode))
$wasRemote = (Get-Remote).Active
$lastTry = [datetime]::MinValue
$pendingReset = $false
$asleepLogged = $false

while ($true) {
    # 자기 갱신
    if ((Get-Stamp) -ne $stamp) {
        Log 'script changed - restarting'
        $mutex.ReleaseMutex(); $mutex.Dispose()
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`""
        exit 0
    }

    $r = Get-Remote
    if (-not $r.Active -and $wasRemote) {
        # 해제 직후 같은 초 재접속(세션 교체) 무시: 3초 뒤 다시 확인
        Start-Sleep 3
        $r = Get-Remote
        if (-not $r.Active) { $pendingReset = $true; $lastTry = [datetime]::MinValue; Log ("remote ended at {0:HH:mm:ss}" -f $r.At) }
    }
    $wasRemote = $r.Active

    $l = Get-Layout
    $canTry = ((Get-Date) - $lastTry).TotalSeconds -ge 15

    if ($r.Active) {
        $pendingReset = $false
        if (-not (Is-RemoteLayout $l) -and $canTry) {
            $lastTry = Get-Date
            $s = Switch-ToRemote
            Log ("REMOTE layout -> ok={0} active={1} primary={2} [{3}]" -f $s.Ok, $s.Active, $s.Primary, $s.Steps)
        }
    }
    else {
        # 화면 절전 중에는 G80SH 링크가 끊겨 평소 구성이 어긋나 보인다.
        # 그때 복구를 시도하면 모니터를 다시 붙였다 떼며 재인식 루프와 장치 연결/해제음이 반복된다 -> 깨어난 뒤에 고친다.
        # (원격이 끝난 직후 복원 $pendingReset 은 예외: 리셋이 화면을 깨운다)
        $avail = Get-Available
        $homeAsleep = -not ($avail -contains $G80)
        if ($homeAsleep -and -not $pendingReset) {
            if (-not $asleepLogged) { Log ("home monitor not attachable (asleep) - skip repair [available: {0}]" -f ($avail -join ',')); $asleepLogged = $true }
        }
        else {
            if ($asleepLogged) { Log 'home monitor back - resume repair'; $asleepLogged = $false }
            if (-not (Is-HomeLayout $l) -and $canTry) {
                $lastTry = Get-Date
                $s = Switch-ToHome
                Log ("HOME layout -> ok={0} active={1} primary={2} [{3}]" -f $s.Ok, $s.Active, $s.Primary, $s.Steps)
                $l = Get-Layout
            }
        }
        if ($pendingReset -and (Is-HomeLayout $l)) { $pendingReset = $false; Start-Sleep 2; Do-Reset }
    }
    Start-Sleep -Seconds 2
}
