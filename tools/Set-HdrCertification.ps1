# Set-HdrCertification.ps1
# Odyssey G80SH(32", True Black 500)의 Windows "HDR 인증" 표시를 채워 넣는 스크립트
# 관리자 권한 PowerShell에서 실행:  powershell -ExecutionPolicy Bypass -File .\Set-HdrCertification.ps1
# 되돌리기:                          powershell -ExecutionPolicy Bypass -File .\Set-HdrCertification.ps1 -Undo

param([switch]$Undo)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "관리자 권한 PowerShell에서 실행해 주세요." -ForegroundColor Red; exit 1
}

# 모니터 이름 -> DisplayHdrLevel GUID 목록 (Multi-String, 여러 개 가능)
$Targets = @{
    'G80SH' = @(
        '3B6DAA9E-3794-4D85-897E-93AE990D275D'   # VESA DisplayHDR 500 True Black (1.1)
        'F9310F0E-93B2-4A58-8642-17358D8CB2E3'   # AMD FreeSync Premium Pro
    )
}

function Get-EdidName([string]$InstanceId) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters"
    $edid = (Get-ItemProperty -Path $p -Name EDID -ErrorAction SilentlyContinue).EDID
    if (-not $edid -or $edid.Length -lt 128) { return $null }
    for ($i = 54; $i -le 108; $i += 18) {                 # 4개의 18바이트 descriptor
        if ($edid[$i] -eq 0 -and $edid[$i+1] -eq 0 -and $edid[$i+3] -eq 0xFC) {
            $s = [Text.Encoding]::ASCII.GetString($edid[($i+5)..($i+17)])
            return ($s -replace "`n.*$", '').Trim()
        }
    }
    return $null
}

$found = $false
foreach ($dev in (Get-PnpDevice -Class Monitor -PresentOnly)) {
    $iid  = $dev.InstanceId
    $name = Get-EdidName $iid
    $drv  = (Get-PnpDeviceProperty -InstanceId $iid -KeyName 'DEVPKEY_Device_Driver' -ErrorAction SilentlyContinue).Data
    if (-not $drv) { continue }
    $key  = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$drv"
    Write-Host ("[{0}]  {1}  ->  {2}" -f $(if ($name) { $name } else { 'unknown' }), $iid, $key) -ForegroundColor Gray

    $match = $Targets.Keys | Where-Object { $name -and $name -like "*$_*" } | Select-Object -First 1
    if (-not $match) { continue }
    $found = $true

    if ($Undo) {
        Remove-ItemProperty -Path $key -Name DisplayHdrLevel -ErrorAction SilentlyContinue
        Write-Host "  -> DisplayHdrLevel 삭제 ($name)" -ForegroundColor Yellow
    } else {
        $old = (Get-ItemProperty -Path $key -Name DisplayHdrLevel -ErrorAction SilentlyContinue).DisplayHdrLevel
        if ($old) { Write-Host "  기존 값: $($old -join ', ')" -ForegroundColor DarkGray }
        New-ItemProperty -Path $key -Name DisplayHdrLevel -PropertyType MultiString -Value $Targets[$match] -Force | Out-Null
        Write-Host "  -> DisplayHdrLevel 설정 완료 ($name): $($Targets[$match] -join ', ')" -ForegroundColor Green
    }
}

if (-not $found) { Write-Host "대상 모니터(G80SH)를 찾지 못했습니다. 위 목록의 이름을 확인해 주세요." -ForegroundColor Red; exit 1 }
Write-Host "`n재부팅(또는 로그아웃/로그인) 후 설정 > 시스템 > 디스플레이 > 고급 디스플레이에서 확인하세요." -ForegroundColor Cyan
