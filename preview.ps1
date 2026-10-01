[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
try { & (Join-Path $env:SystemRoot "System32\chcp.com") 65001 | Out-Null } catch {}
$NoUi = $false
$addr = @()
try { $addr = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "100.*" } | ForEach-Object { "{0}/{1}" -f $_.IPAddress, $_.PrefixLength }) } catch {}
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$fp = "SHA256:(미리보기 예시 지문)"
function Show-BrandHeader {
    if ($NoUi) { return }
    $ornamentTop = '╭' + ('─' * 40) + ' ◆ ' + ('─' * 40) + '╮'
    $ornamentBottom = '╰' + ('─' * 40) + ' ◆ ' + ('─' * 40) + '╯'
    $logo = @(
        '    ⢀⣴⣿⠁',
        '  ⣴⣴⣿⣿⣿⣴⣧',
        '⢀⣾⣿⣿⣿⣿⣿⣿⣿⣦',
        '⣾⣿⠟⠛⢿⣿⡿⠛⠻⣿⣧',
        '⣿⡇ ⠿⠗⣿ ⠸⠿⢺⣿',
        '⠈⠻⢶⣶⣾⣿⣷⣶⡶⠟⠁'
    )
    $title = @(
        '██████╗ ██████╗  ██████╗ ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗',
        '██╔════╝██╔═══██╗██╔═══██╗██║ ██╔╝██╔══██╗██╔══██╗██╔══██╗██╔════╝',
        '██║     ██║   ██║██║   ██║█████╔╝ ███████║██████╔╝██████╔╝███████╗',
        '██║     ██║   ██║██║   ██║██╔═██╗ ██╔══██║██╔═══╝ ██╔═══╝ ╚════██║',
        '╚██████╗╚██████╔╝╚██████╔╝██║  ██╗██║  ██║██║     ██║     ███████║',
        ' ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚══════╝'
    )
    Write-Host $ornamentTop -ForegroundColor DarkYellow
    for ($index = 0; $index -lt $logo.Count; $index++) {
        Write-Host ($logo[$index].PadRight(19)) -NoNewline -ForegroundColor DarkYellow
        Write-Host $title[$index] -ForegroundColor DarkYellow
    }
    Write-Host $ornamentBottom -ForegroundColor DarkYellow
}

function Wait-ForUserClose {
    if ($NoUi -or -not [Environment]::UserInteractive -or $Host.Name -ne 'ConsoleHost') { return }
    try {
        if ([Console]::IsInputRedirected) { return }
        Write-Host ''
        Write-Host '아무 키나 누르면 창이 닫힙니다.' -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
    } catch {}
}

function Show-ResultScreen {
    param([bool]$Succeeded, [System.Collections.IDictionary]$Data)
    if ($NoUi) { return }
    Clear-Host
    Show-BrandHeader
    Write-Host ''
    Write-Host (-join ('─' * 58)) -ForegroundColor DarkGray
    if ($Succeeded) {
        Write-Host 'SSH 연결 준비가 완료되었습니다.' -ForegroundColor Green
    } else {
        Write-Host 'SSH 연결 준비를 완료하지 못했습니다.' -ForegroundColor Red
    }
    Write-Host (-join ('─' * 58)) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('PC             : {0}' -f $Data.ComputerName)
    Write-Host ('Windows 사용자 : {0}' -f $Data.TargetUser)
    Write-Host ('주소           : {0}' -f ($Data.LanAddresses -join ', '))
    Write-Host ('서버 키 지문   : {0}' -f $Data.HostKeyFingerprint)
    Write-Host ''
    if ($Data.ReportDelivered) {
        Write-Host '설치가 끝났습니다. 담당자에게 완료되었다고 알려 주세요.' -ForegroundColor Green
    } elseif ($Data.AuditOnly) {
        Write-Host '감사 모드로 실행되어 결과를 저장하지 않았습니다.' -ForegroundColor Yellow
    } else {
        Write-Host '설치가 끝났습니다. 위 내용을 담당자에게 전달해 주세요.' -ForegroundColor Green
    }
    if (-not $Succeeded -and $Data.Error) {
        Write-Host ''
        Write-Host ('오류: {0}' -f $Data.Error) -ForegroundColor Red
    }
    Wait-ForUserClose
}

Write-Host ""
Write-Host "[미리보기 1/2] 결과가 담당자 폴더에 저장된 경우" -ForegroundColor Cyan
Start-Sleep -Milliseconds 400
Show-ResultScreen -Succeeded $true -Data ([ordered]@{ ComputerName=$env:COMPUTERNAME; TargetUser=$me; LanAddresses=$addr; HostKeyFingerprint=$fp; ReportDelivered=$true; AuditOnly=$false; Error=$null })
Write-Host ""
Write-Host "[미리보기 2/2] 폴더에 저장하지 못한 경우" -ForegroundColor Cyan
Start-Sleep -Milliseconds 400
Show-ResultScreen -Succeeded $true -Data ([ordered]@{ ComputerName=$env:COMPUTERNAME; TargetUser=$me; LanAddresses=$addr; HostKeyFingerprint=$fp; ReportDelivered=$false; AuditOnly=$false; Error=$null })
