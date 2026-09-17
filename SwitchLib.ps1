# SwitchLib.ps1 - 화면 전환 (Windows CCD API 전용, MultiMonitorTool 미사용)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'DispCfg.ps1')

$script:G80 = 'SAM7B0C'; $script:G50 = 'SAM79DF'; $script:DONGLE = 'BBC0104'
$script:AllIds = [string[]]@('SAM7B0C', 'SAM79DF', 'BBC0104')

function Get-Layout {
    $parts = ([Ccd2]::Active($AllIds)) -split '\|', 2
    [pscustomobject]@{ Active = @($parts[0] -split ',' | Where-Object { $_ }); Primary = $parts[1] }
}

function Is-RemoteLayout($l) { ($l.Active -contains $DONGLE) -and -not ($l.Active -contains $G80) -and -not ($l.Active -contains $G50) }
function Is-HomeLayout($l)   { ($l.Active -contains $G80) -and ($l.Active -contains $G50) -and -not ($l.Active -contains $DONGLE) -and $l.Primary -eq $G80 }

function Switch-ToRemote {
    $steps = @()
    for ($try = 1; $try -le 3; $try++) {
        $steps += "t${try}: " + [Ccd2]::Activate([string[]]@($DONGLE), [int[]]@(0), [int[]]@(0))
        Start-Sleep 2
        $l = Get-Layout
        if (Is-RemoteLayout $l) { break }
        Start-Sleep 2
    }
    [pscustomobject]@{ Ok = (Is-RemoteLayout $l); Steps = ($steps -join ' / '); Active = ($l.Active -join ','); Primary = $l.Primary }
}

function Switch-ToHome {
    $steps = @()
    for ($try = 1; $try -le 3; $try++) {
        $steps += "t${try}: " + [Ccd2]::Activate([string[]]@($G80, $G50), [int[]]@(0, -2560), [int[]]@(0, 340))
        Start-Sleep 2
        $l = Get-Layout
        if (Is-HomeLayout $l) { break }
        Start-Sleep 2
    }
    [pscustomobject]@{ Ok = (Is-HomeLayout $l); Steps = ($steps -join ' / '); Active = ($l.Active -join ','); Primary = $l.Primary }
}
