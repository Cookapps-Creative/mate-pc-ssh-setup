[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'bootstrap.json'),
    [switch]$Elevated,
    [switch]$PwshRelaunched,
    [string]$ContextPath,
    [switch]$AuditOnly,
    [switch]$NoUi
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:BootstrapScriptPath = $PSCommandPath
$script:EmbeddedConfig = @'
{
  "SchemaVersion": 1,
  "RequestId": "",
  "TargetAlias": "mate-pc",
  "PublicKey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK3xL+RpkQ0LLt97n9r9n3w1//HZ9JiF9rRRAnK3H1a3 jmlee1",
  "PublicKeyFingerprint": "SHA256:bnqTzCgJQpM7UjbJCBTh3xNFmWVVTXobJzw8kGEYiz4",
  "ReportUrl": "",
  "ReportExpiresAtUtc": "",
  "ReportDirectory": "\\\\nas\\Cookapps Project\\ON_AIR_UA\\#기타\\Publishing mate-pc SSH\\reports",
  "GateSalt": "6f82e749bbdbf05b",
  "GateHash": "b7a30c6f4e0655e9e085377145141fb4e32896497161839c71102a1fdc2e020a"
}
'@

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function New-UserContext {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $identity.User.Value
    $groups = @($identity.Groups | ForEach-Object { $_.Value })
    return [ordered]@{
        FullName = $identity.Name
        UserName = ($identity.Name -split '\\')[-1]
        SID = $sid
        Profile = [Environment]::GetFolderPath('UserProfile')
        IsAdministratorMember = ($groups -contains 'S-1-5-32-544')
    }
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-PwshPath {
    $candidates = @()
    try {
        $command = Get-Command pwsh.exe -ErrorAction Stop
        if ($command.Source) { $candidates += $command.Source }
    } catch {}
    $candidates += (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe') }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function New-RelaunchArguments {
    param([switch]$ForPwsh)
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevated -ConfigPath "{1}"' -f $script:BootstrapScriptPath, $ConfigPath
    if ($ContextPath) { $arguments += ' -ContextPath "{0}"' -f $ContextPath }
    if ($AuditOnly) { $arguments += ' -AuditOnly' }
    if ($NoUi) { $arguments += ' -NoUi' }
    if ($ForPwsh) { $arguments += ' -PwshRelaunched' }
    return $arguments
}

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

function Initialize-Terminal {
    if ($NoUi) { return }
    try {
        [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        & (Join-Path $env:SystemRoot 'System32\chcp.com') 65001 | Out-Null
    } catch {}
    try {
        $raw = $Host.UI.RawUI
        if ($raw.BufferSize.Width -lt 105) {
            $buffer = $raw.BufferSize
            $buffer.Width = 105
            $raw.BufferSize = $buffer
        }
        if ($raw.WindowSize.Width -lt 100) {
            $window = $raw.WindowSize
            $window.Width = [Math]::Min(100, $raw.MaxPhysicalWindowSize.Width)
            $raw.WindowSize = $window
        }
    } catch {}
    try { $Host.UI.RawUI.WindowTitle = 'COOKAPPS | MATE PC SSH 연결 준비' } catch {}
    Clear-Host
    Show-BrandHeader
    Write-Host ''
    Write-Host 'SSH 연결에 필요한 항목을 확인하고 있습니다.' -ForegroundColor Cyan
    Write-Host '이 창을 닫지 말고 완료 화면이 나올 때까지 기다려 주세요.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-SimpleError {
    param([string]$Message)
    if ($NoUi) { return }
    Clear-Host
    Show-BrandHeader
    Write-Host ''
    Write-Host 'SSH 연결 준비를 시작하지 못했습니다.' -ForegroundColor Red
    Write-Host $Message -ForegroundColor White
    Wait-ForUserClose
}

if (-not $AuditOnly -and -not (Test-Administrator)) {
    try {
        $context = New-UserContext
        $tempContext = Join-Path $env:TEMP ('mate-pc-context-{0}.json' -f [Guid]::NewGuid().ToString('N'))
        Write-Utf8NoBom -Path $tempContext -Text ($context | ConvertTo-Json -Compress)

        Write-Host 'Windows 관리자 권한을 요청합니다. 허용 창에서 예를 눌러 주세요.' -ForegroundColor Cyan
        $ContextPath = $tempContext
        $hostExecutable = Get-PwshPath
        if (-not $hostExecutable) { $hostExecutable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
        $arguments = New-RelaunchArguments
        $process = Start-Process -FilePath $hostExecutable -Verb RunAs -WindowStyle Normal -ArgumentList $arguments -PassThru -Wait
        Remove-Item -LiteralPath $tempContext -Force -ErrorAction SilentlyContinue
        exit $process.ExitCode
    } catch {
        Show-SimpleError '관리자 권한을 받지 못했습니다. 파일을 다시 실행하고 Windows의 허용 버튼을 눌러 주세요.'
        exit 1
    }
}

Initialize-Terminal

$script:Activity = New-Object Collections.ArrayList
$script:Warnings = New-Object Collections.ArrayList
$script:KeyChanged = $false
$script:KeyExisted = $false
$script:KeyPath = $null
$script:KeyBackup = $null
$script:AclBackup = $null
$script:CreatedSshDirectory = $false
$script:FirewallCreated = $false
$script:ReportDelivered = $false
$script:LocalReportPath = $null
$script:ExitCode = 1

function Add-Activity {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    [void]$script:Activity.Add($line)
    if (-not $NoUi) { Write-Host ('  {0}' -f $line) -ForegroundColor DarkGray }
}

function Add-Warning {
    param([string]$Message)
    if (-not $script:Warnings.Contains($Message)) { [void]$script:Warnings.Add($Message) }
}

function Install-PowerShell7 {
    if (-not (Test-Administrator)) { throw 'PowerShell 7 설치에는 관리자 권한이 필요합니다.' }

    Write-Host 'PowerShell 7을 설치하고 있습니다. 잠시 기다려 주세요.' -ForegroundColor Cyan
    $winget = $null
    try { $winget = (Get-Command winget.exe -ErrorAction Stop).Source } catch {}
    if ($winget) {
        & $winget install --id Microsoft.PowerShell --exact --source winget --installer-type wix --scope machine --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        $wingetExitCode = $LASTEXITCODE
        $installed = Get-PwshPath
        if ($wingetExitCode -eq 0 -and $installed) { return $installed }
        Write-Host 'WinGet 설치를 완료하지 못해 Microsoft 서명 MSI로 다시 시도합니다.' -ForegroundColor DarkGray
    }

    $release = '7.6.5'
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $expectedHashes = @{
        x64 = '3A87C24E044EC792047D734C841917EE4323A535E25F645AE6C33141A35FCA8D'
        arm64 = 'A1633B48B8E45C7767902EFC972BFF235B3594C192AD575AF4A4E8EB2EA3BD5A'
    }
    $fileName = 'PowerShell-{0}-win-{1}.msi' -f $release, $architecture
    $downloadUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v{0}/{1}' -f $release, $fileName
    $msiPath = Join-Path $env:TEMP $fileName

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $msiPath -TimeoutSec 180
        $actualHash = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHashes[$architecture]) { throw 'PowerShell MSI의 SHA-256이 공식 배포값과 다릅니다.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $msiPath
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw 'PowerShell MSI의 Microsoft 디지털 서명을 확인하지 못했습니다.'
        }

        $msiArguments = '/i "{0}" /qn /norestart ADD_PATH=1 USE_MU=1 ENABLE_MU=1 REGISTER_MANIFEST=1' -f $msiPath
        $installer = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList $msiArguments -PassThru -Wait
        if ($installer.ExitCode -notin @(0, 1641, 3010)) { throw ('PowerShell MSI 설치가 종료 코드 {0}으로 실패했습니다.' -f $installer.ExitCode) }
    } finally {
        Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
    }

    $installed = Get-PwshPath
    if (-not $installed) { throw '설치 후 pwsh.exe를 찾지 못했습니다.' }
    return $installed
}

function Invoke-Icacls {
    param([string[]]$Arguments)
    & icacls.exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ('파일 권한 설정에 실패했습니다: {0}' -f $Arguments[0]) }
}

function Get-SidValue {
    param([Security.Principal.IdentityReference]$Identity)
    try { return $Identity.Translate([Security.Principal.SecurityIdentifier]).Value } catch { return $Identity.Value }
}

function Assert-KeyAclIsManaged {
    param([string]$Path, [string[]]$AllowedSids)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $acl = Get-Acl -LiteralPath $Path
    if (-not $acl.AreAccessRulesProtected) {
        throw '기존 공개키 파일이 상속 권한을 사용하므로 자동 변경하지 않았습니다.'
    }
    $unexpected = @()
    foreach ($entry in $acl.Access) {
        $sid = Get-SidValue -Identity $entry.IdentityReference
        if ($entry.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $AllowedSids -notcontains $sid) {
            $unexpected += $sid
        }
    }
    if ($unexpected.Count -gt 0) {
        throw ('기존 공개키 파일에 예상하지 않은 권한이 있어 자동 변경하지 않았습니다: {0}' -f (($unexpected | Select-Object -Unique) -join ', '))
    }
}

function Get-PrimaryNetwork {
    $items = @()
    try {
        $configs = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
        foreach ($config in $configs) {
            foreach ($address in @($config.IPv4Address)) {
                if ($address.IPAddress -notlike '127.*' -and $address.IPAddress -notlike '169.254.*' -and $address.IPAddress -notlike '100.*') {
                    $items += ('{0}/{1}' -f $address.IPAddress, $address.PrefixLength)
                }
            }
        }
    } catch {}
    return @($items | Select-Object -Unique)
}

function Get-KeyFingerprint {
    param([string]$SshKeygen, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $output = @(& $SshKeygen -lf $Path 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { return $null }
    $parts = ([string]$output[0]) -split '\s+'
    if ($parts.Count -ge 2) { return $parts[1] }
    return $null
}

function Test-ExistingFirewallAllow {
    try {
        $filters = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction Stop | Get-NetFirewallPortFilter -ErrorAction Stop)
        foreach ($filter in $filters) {
            $protocol = [string]$filter.Protocol
            if (($protocol -eq 'TCP' -or $protocol -eq '6') -and [string]$filter.LocalPort -eq '22') { return $true }
        }
    } catch {}
    return $false
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
        Write-Host '설치 결과를 담당자용 폴더에 저장했습니다. 담당자가 확인합니다.' -ForegroundColor Green
    } elseif ($Data.AuditOnly) {
        Write-Host '감사 모드로 실행되어 결과를 저장하지 않았습니다.' -ForegroundColor Yellow
    } else {
        Write-Host '결과 폴더에 저장하지 못해 이 PC에 결과를 저장했습니다.' -ForegroundColor Yellow
        Write-Host '이 화면을 담당자에게 알려 주세요.' -ForegroundColor White
    }
    if (-not $Succeeded -and $Data.Error) {
        Write-Host ''
        Write-Host ('오류: {0}' -f $Data.Error) -ForegroundColor Red
    }
    Wait-ForUserClose
}

# 공통 패키지(mate.ps1)는 설정을 스크립트 안에 넣어 파일 하나로 배포한다(build-common-package.sh).
if ($script:EmbeddedConfig) {
    $cfg = $script:EmbeddedConfig | ConvertFrom-Json
} elseif (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} else {
    Show-SimpleError 'bootstrap.json 파일을 찾을 수 없습니다. 압축 파일 전체를 풀고 다시 실행해 주세요.'
    exit 1
}
if ($cfg.SchemaVersion -ne 1 -or -not $cfg.PublicKey -or -not $cfg.PublicKeyFingerprint) {
    Show-SimpleError '설치 패키지 설정이 올바르지 않습니다. 새 패키지를 받아 주세요.'
    exit 1
}
if ($cfg.PublicKey -notmatch '^ssh-ed25519\s+([A-Za-z0-9+/]+={0,3})(?:\s+.*)?$') {
    Show-SimpleError '설치 패키지의 공개키 형식이 올바르지 않습니다.'
    exit 1
}
$keyBlob = $Matches[1]

if ($PSVersionTable.PSVersion.Major -lt 7) {
    if ($PwshRelaunched) {
        Show-SimpleError 'PowerShell 7으로 다시 실행하지 못했습니다.'
        exit 1
    }
    try {
        $pwsh = Get-PwshPath
        if (-not $pwsh) {
            if ($AuditOnly) { throw '감사 모드에서는 PowerShell 7을 자동 설치하지 않습니다.' }
            $pwsh = Install-PowerShell7
        }
        Write-Host 'PowerShell 7으로 설치 절차를 이어갑니다.' -ForegroundColor Cyan
        $arguments = New-RelaunchArguments -ForPwsh
        $process = Start-Process -FilePath $pwsh -ArgumentList $arguments -NoNewWindow -PassThru -Wait
        exit $process.ExitCode
    } catch {
        Show-SimpleError ('PowerShell 7을 준비하지 못했습니다. {0}' -f $_.Exception.Message)
        exit 1
    }
}

if ($ContextPath -and (Test-Path -LiteralPath $ContextPath)) {
    $target = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
    Remove-Item -LiteralPath $ContextPath -Force -ErrorAction SilentlyContinue
} else {
    $target = New-UserContext
}

# 설치 암호 확인 — 공유 위치(공개 저장소 등)에 두더라도 암호 없이는 설치되지 않게 한다.
# 설정의 salt·hash는 공개돼도 되는 값이고, 평문 암호는 어디에도 저장하지 않는다. 암호는 준비한 사람이 따로 알려 준다.
if (-not $AuditOnly -and [string]$cfg.GateHash) {
    $gateSalt = [string]$cfg.GateSalt
    $gateHash = ([string]$cfg.GateHash).ToLowerInvariant()
    $gateTries = 0
    while ($true) {
        $sec = Read-Host '설치 암호를 입력하세요' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $got = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($gateSalt + $pw)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
        $pw = $null
        if ($got -eq $gateHash) { break }
        $gateTries++
        if ($gateTries -ge 3) { Show-SimpleError '설치 암호가 올바르지 않습니다. 준비한 사람에게 암호를 확인해 주세요.'; exit 1 }
        Write-Host '암호가 올바르지 않습니다. 다시 시도해 주세요.' -ForegroundColor Yellow
    }
}

$requestId = [string]$cfg.RequestId
if (-not $requestId) { $requestId = ('offline-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$targetAlias = [string]$cfg.TargetAlias
if (-not $targetAlias) { $targetAlias = 'new-mate-pc' }

$reportRoot = if ($AuditOnly) { Join-Path $env:TEMP 'Cookapps-SSH-Audit' } else { Join-Path $env:ProgramData 'Cookapps-SSH' }
$backupRoot = Join-Path $reportRoot 'backups'
$reportsRoot = Join-Path $reportRoot 'reports'
New-Item -ItemType Directory -Path $backupRoot, $reportsRoot -Force | Out-Null
$logPath = Join-Path $reportRoot ('bootstrap-{0}.log' -f $requestId)

$report = [ordered]@{
    SchemaVersion = 1
    RequestId = $requestId
    TargetAlias = $targetAlias
    Status = 'RUNNING'
    StartedAtUtc = [DateTime]::UtcNow.ToString('o')
    FinishedAtUtc = $null
    ComputerName = $env:COMPUTERNAME
    TargetUser = [string]$target.FullName
    TargetUserName = [string]$target.UserName
    TargetProfile = [string]$target.Profile
    TargetSid = [string]$target.SID
    AdministratorMember = [bool]$target.IsAdministratorMember
    AdminSharedKey = $false
    PostConnectReviewRequired = $false
    Windows = $null
    PowerShell = $PSVersionTable.PSVersion.ToString()
    OpenSshCapability = $null
    SshdStatus = $null
    SshdStartType = $null
    Firewall = $null
    AuthorizedKeysPath = $null
    AccessKeyFingerprint = [string]$cfg.PublicKeyFingerprint
    HostKeyFingerprint = $null
    LanAddresses = @()
    AuditOnly = [bool]$AuditOnly
    ReportDelivered = $false
    LocalReportPath = $null
    Warnings = @()
    Error = $null
    Activity = @()
}

try {
    if (-not $AuditOnly -and -not (Test-Administrator)) { throw '관리자 권한을 받지 못했습니다.' }
    Add-Activity 'Windows와 현재 로그인 사용자를 확인했습니다.'

    $os = Get-CimInstance Win32_OperatingSystem
    $report.Windows = ('{0} (build {1})' -f $os.Caption, $os.BuildNumber)
    if ([int]$os.BuildNumber -lt 22000) { throw '이 도구는 Windows 11용입니다.' }
    if ([string]$target.FullName -match '^AzureAD\\') { throw 'Microsoft Entra ID 계정은 이 자동 등록 절차에서 지원하지 않습니다.' }
    if (-not $target.Profile -or -not (Test-Path -LiteralPath $target.Profile)) { throw '현재 로그인 사용자의 프로필 폴더를 찾지 못했습니다.' }

    $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if (-not $capability) { throw 'Windows OpenSSH Server 기능을 찾지 못했습니다.' }
    $report.OpenSshCapability = [string]$capability.State

    if (-not $AuditOnly -and $capability.State -ne 'Installed') {
        Add-Activity 'Windows OpenSSH Server를 설치합니다.'
        Add-WindowsCapability -Online -Name $capability.Name | Out-Null
        $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
        if ($capability.State -ne 'Installed') { throw 'Windows OpenSSH Server 설치를 완료하지 못했습니다.' }
        $report.OpenSshCapability = [string]$capability.State
    }

    if ($capability.State -ne 'Installed') {
        if ($AuditOnly) { throw '감사 모드: OpenSSH Server가 설치되어 있지 않습니다.' }
        throw 'OpenSSH Server가 설치되어 있지 않습니다.'
    }

    if (-not $AuditOnly) {
        Set-Service -Name sshd -StartupType Automatic
        if ((Get-Service -Name sshd).Status -ne 'Running') { Start-Service -Name sshd }
    }
    $service = Get-CimInstance Win32_Service -Filter "Name='sshd'"
    $report.SshdStatus = [string]$service.State
    $report.SshdStartType = [string]$service.StartMode
    if ($service.State -ne 'Running' -and -not $AuditOnly) { throw 'sshd 서비스를 시작하지 못했습니다.' }
    Add-Activity 'sshd 서비스 상태를 확인했습니다.'

    $sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
    $sshKeygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
    $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (-not (Test-Path -LiteralPath $sshdExe) -or -not (Test-Path -LiteralPath $sshKeygen)) { throw 'Windows OpenSSH 실행 파일을 찾지 못했습니다.' }
    if (-not (Test-Path -LiteralPath $sshdConfig)) { throw 'sshd_config가 생성되지 않았습니다.' }
    & $sshdExe -t -f $sshdConfig
    if ($LASTEXITCODE -ne 0) { throw '기존 sshd_config 문법이 올바르지 않아 자동 변경하지 않았습니다.' }

    $effective = @(& $sshdExe -T -f $sshdConfig -C ('user={0},host={1},addr=127.0.0.1' -f $target.UserName, $env:COMPUTERNAME) 2>&1)
    if ($LASTEXITCODE -ne 0) { throw '현재 사용자에게 적용되는 SSH 공개키 경로를 확인하지 못했습니다.' }
    $authLine = @($effective | Where-Object { [string]$_ -match '^authorizedkeysfile\s+' } | Select-Object -First 1)
    if ($authLine.Count -eq 0) { throw 'sshd의 AuthorizedKeysFile 적용값을 찾지 못했습니다.' }
    $effectiveKeyValue = (([string]$authLine[0]) -replace '^authorizedkeysfile\s+', '').Trim().Trim('"').Replace('\','/').ToLowerInvariant()

    if ([bool]$target.IsAdministratorMember) {
        $expectedValues = @('__programdata__/ssh/administrators_authorized_keys', (Join-Path $env:ProgramData 'ssh\administrators_authorized_keys').Replace('\','/').ToLowerInvariant())
        if ($expectedValues -notcontains $effectiveKeyValue) {
            throw ('관리자 계정의 공개키 경로가 Windows 기본값과 다릅니다. 적용값: {0}' -f $effectiveKeyValue)
        }
        $script:KeyPath = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
        $report.AdminSharedKey = $true
        $report.PostConnectReviewRequired = $true
        Add-Warning '관리자 공용 공개키 파일을 사용합니다. 연결 후 공유 범위를 검토해야 합니다.'
    } else {
        if ($effectiveKeyValue -ne '.ssh/authorized_keys') {
            throw ('일반 사용자 공개키 경로가 Windows 기본값과 다릅니다. 적용값: {0}' -f $effectiveKeyValue)
        }
        $sshDirectory = Join-Path $target.Profile '.ssh'
        $script:KeyPath = Join-Path $sshDirectory 'authorized_keys'
        if (-not (Test-Path -LiteralPath $sshDirectory)) {
            if (-not $AuditOnly) {
                New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
                $script:CreatedSshDirectory = $true
                Invoke-Icacls -Arguments @($sshDirectory, '/inheritance:r', '/grant:r', ('*{0}:(OI)(CI)F' -f $target.SID), '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
            }
        }
    }
    $report.AuthorizedKeysPath = $script:KeyPath
    Add-Activity ('공개키 적용 경로를 확인했습니다: {0}' -f $script:KeyPath)

    $allowedSids = @('S-1-5-18', 'S-1-5-32-544')
    if (-not [bool]$target.IsAdministratorMember) { $allowedSids += [string]$target.SID }
    Assert-KeyAclIsManaged -Path $script:KeyPath -AllowedSids $allowedSids

    $script:KeyExisted = Test-Path -LiteralPath $script:KeyPath
    $existingLines = @()
    if ($script:KeyExisted) { $existingLines = @(Get-Content -LiteralPath $script:KeyPath) }
    $sameKeyLines = @($existingLines | Where-Object { [string]$_ -match ('(?<!\S)ssh-ed25519\s+{0}(?:\s|$)' -f [regex]::Escape($keyBlob)) })

    if ($sameKeyLines.Count -gt 0) {
        if (@($sameKeyLines | Where-Object { $_ -match '(^|,|\s)(restrict|no-port-forwarding)(,|\s)' }).Count -gt 0) {
            $report.PostConnectReviewRequired = $true
            Add-Warning '기존 공개키에 포트 연결 제한이 있습니다. SSH 연결 후 OAuth/웹 터널 사용 전에 검토해야 합니다.'
        }
        if (@($sameKeyLines | Where-Object { $_ -match '(^|,)from=' }).Count -gt 0) {
            $report.PostConnectReviewRequired = $true
            Add-Warning '기존 공개키에 접속 출발지 제한이 있습니다. marketing-pc 게이트웨이 경로와 대체 경로를 각각 검증해야 합니다.'
        }
        Add-Activity '같은 공개키가 이미 있어 중복 추가하지 않았습니다.'
    } elseif (-not $AuditOnly) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        if ($script:KeyExisted) {
            $script:KeyBackup = Join-Path $backupRoot ('authorized_keys-{0}-{1}.bak' -f $requestId, $timestamp)
            Copy-Item -LiteralPath $script:KeyPath -Destination $script:KeyBackup -Force
            $script:AclBackup = Join-Path $backupRoot ('authorized_keys-{0}-{1}.acl.xml' -f $requestId, $timestamp)
            Get-Acl -LiteralPath $script:KeyPath | Export-Clixml -LiteralPath $script:AclBackup
        }
        $newLines = @($existingLines)
        $newLines += [string]$cfg.PublicKey
        Write-Utf8NoBom -Path $script:KeyPath -Text (($newLines -join "`r`n").TrimEnd() + "`r`n")
        $script:KeyChanged = $true
        Add-Activity '기존 키를 보존하고 Cookapps 원격 접속 공개키를 추가했습니다.'
    }

    if (-not $AuditOnly -and $script:KeyChanged) {
        if ([bool]$target.IsAdministratorMember) {
            Invoke-Icacls -Arguments @($script:KeyPath, '/inheritance:r', '/grant:r', '*S-1-5-18:F', '*S-1-5-32-544:F')
        } else {
            Invoke-Icacls -Arguments @($script:KeyPath, '/inheritance:r', '/grant:r', ('*{0}:F' -f $target.SID), '*S-1-5-18:F', '*S-1-5-32-544:F')
        }
    }

    if (-not $AuditOnly -and -not (Test-ExistingFirewallAllow)) {
        New-NetFirewallRule -Name 'Cookapps-Mate-SSH-In-TCP' -DisplayName 'Cookapps mate PC SSH (TCP 22)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
        $script:FirewallCreated = $true
        Add-Activity '기존 규칙을 변경하지 않고 TCP 22 허용 규칙을 추가했습니다.'
    } else {
        Add-Activity '기존 TCP 22 허용 방화벽 규칙을 보존했습니다.'
    }
    $report.Firewall = $(if (Test-ExistingFirewallAllow) { 'ALLOW_TCP_22_FOUND' } else { 'ALLOW_TCP_22_NOT_FOUND' })
    if (-not $AuditOnly -and $report.Firewall -ne 'ALLOW_TCP_22_FOUND') { throw 'TCP 22 인바운드 허용 규칙을 확인하지 못했습니다.' }

    $report.LanAddresses = @(Get-PrimaryNetwork)
    if ($report.LanAddresses.Count -eq 0) { Add-Warning '기본 게이트웨이가 있는 사무실 LAN 주소를 자동으로 찾지 못했습니다.' }
    if (@($report.LanAddresses | Where-Object { $_ -match '^192\.168\.[0-3]\.' }).Count -eq 0) {
        $report.PostConnectReviewRequired = $true
        Add-Warning '현재 주소가 사무실 LAN(192.168.0.0/22) 밖에 있어 marketing-pc 게이트웨이에서 닿지 않을 수 있습니다. 네트워크 경로를 확인해야 합니다.'
    }

    $hostPublicKey = Join-Path $env:ProgramData 'ssh\ssh_host_ed25519_key.pub'
    $report.HostKeyFingerprint = Get-KeyFingerprint -SshKeygen $sshKeygen -Path $hostPublicKey
    if (-not $report.HostKeyFingerprint) { throw 'ED25519 SSH 서버 키 지문을 확인하지 못했습니다.' }

    if (-not $AuditOnly) {
        $listener = Get-NetTCPConnection -State Listen -LocalPort 22 -ErrorAction SilentlyContinue
        if (-not $listener) { throw 'sshd가 TCP 22에서 수신 중이지 않습니다.' }
    }

    $report.Status = $(if ($AuditOnly) { 'AUDIT_OK' } else { 'READY_FOR_MAC_VERIFICATION' })
    $script:ExitCode = 0
    Add-Activity '로컬 준비 절차를 완료했습니다.'
} catch {
    $report.Status = 'FAILED'
    $report.Error = $_.Exception.Message
    Add-Activity ('실패: {0}' -f $_.Exception.Message)
    if ($script:KeyChanged -and -not $AuditOnly) {
        try {
            if ($script:KeyExisted -and $script:KeyBackup) {
                Copy-Item -LiteralPath $script:KeyBackup -Destination $script:KeyPath -Force
                if ($script:AclBackup) { Set-Acl -LiteralPath $script:KeyPath -AclObject (Import-Clixml -LiteralPath $script:AclBackup) }
            } elseif (Test-Path -LiteralPath $script:KeyPath) {
                Remove-Item -LiteralPath $script:KeyPath -Force
            }
            Add-Activity '공개키 파일 변경을 되돌렸습니다.'
        } catch {
            Add-Warning '공개키 파일 자동 복구에 실패했습니다. 백업 폴더를 확인해야 합니다.'
        }
    }
    if ($script:FirewallCreated -and -not $AuditOnly) {
        try {
            Get-NetFirewallRule -Name 'Cookapps-Mate-SSH-In-TCP' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
            Add-Activity '이번 실행에서 만든 방화벽 규칙을 되돌렸습니다.'
        } catch {
            Add-Warning '이번 실행에서 만든 방화벽 규칙을 자동 제거하지 못했습니다.'
        }
    }
    if ($script:CreatedSshDirectory -and -not $AuditOnly) {
        try {
            if ((Test-Path -LiteralPath $sshDirectory) -and @(Get-ChildItem -LiteralPath $sshDirectory -Force).Count -eq 0) {
                Remove-Item -LiteralPath $sshDirectory -Force
            }
        } catch {}
    }
} finally {
    $report.FinishedAtUtc = [DateTime]::UtcNow.ToString('o')
    $report.Warnings = @($script:Warnings)
    $report.Activity = @($script:Activity)
    $script:LocalReportPath = Join-Path $reportsRoot ('{0}-{1}.json' -f $requestId, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $report.LocalReportPath = $script:LocalReportPath

    $json = $report | ConvertTo-Json -Depth 6
    Write-Utf8NoBom -Path $script:LocalReportPath -Text $json
    Write-Utf8NoBom -Path $logPath -Text (($script:Activity -join "`r`n") + "`r`n")

    if ($cfg.ReportUrl) {
        try {
            if ($cfg.ReportExpiresAtUtc -and [DateTime]::UtcNow -gt [DateTime]::Parse([string]$cfg.ReportExpiresAtUtc).ToUniversalTime()) {
                throw 'report window expired'
            }
            Invoke-WebRequest -UseBasicParsing -Uri ([string]$cfg.ReportUrl) -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 12 | Out-Null
            $script:ReportDelivered = $true
        } catch {
            Add-Warning '자동 결과 전송에 실패했습니다. 바탕 화면의 결과 파일을 사용해야 합니다.'
        }
    } elseif ($cfg.ReportDirectory) {
        # 공통 패키지: 지정한 공유 폴더에 PC 이름별 결과 파일을 남긴다.
        try {
            $sharedReport = Join-Path ([string]$cfg.ReportDirectory) ('{0}-{1}.json' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Write-Utf8NoBom -Path $sharedReport -Text $json
            $script:ReportDelivered = $true
        } catch {
            Add-Warning '공유 폴더에 결과를 저장하지 못했습니다. 바탕 화면의 결과 파일을 사용해야 합니다.'
        }
    } else {
        Add-Warning '이 패키지는 자동 결과 전송 없이 만들어졌습니다.'
    }

    $report.ReportDelivered = $script:ReportDelivered
    $report.Warnings = @($script:Warnings)
    $json = $report | ConvertTo-Json -Depth 6
    Write-Utf8NoBom -Path $script:LocalReportPath -Text $json

    try {
        if ($AuditOnly -or $script:ReportDelivered) { throw 'AUDIT_ONLY_SKIP_DESKTOP' }
        $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
        if (-not $publicDesktop) { $publicDesktop = Join-Path $env:PUBLIC 'Desktop' }
        $desktopReport = Join-Path $publicDesktop ('COOKAPPS SSH 연결 결과 - {0}.txt' -f $env:COMPUTERNAME)
        $summary = @(
            'COOKAPPS SSH 연결 결과',
            ('상태: {0}' -f $report.Status),
            ('PC: {0}' -f $report.ComputerName),
            ('Windows 사용자: {0}' -f $report.TargetUser),
            ('주소: {0}' -f ($report.LanAddresses -join ', ')),
            ('서버 키 지문: {0}' -f $report.HostKeyFingerprint),
            ('자동 전송: {0}' -f $(if ($report.ReportDelivered) { '완료' } else { '실패 또는 미설정' })),
            ('상세 보고서: {0}' -f $script:LocalReportPath),
            ('오류: {0}' -f $report.Error)
        ) -join "`r`n"
        Write-Utf8NoBom -Path $desktopReport -Text ($summary + "`r`n")
    } catch {
        if ($_.Exception.Message -ne 'AUDIT_ONLY_SKIP_DESKTOP') {}
    }

    Show-ResultScreen -Succeeded ($script:ExitCode -eq 0) -Data $report
}

exit $script:ExitCode
