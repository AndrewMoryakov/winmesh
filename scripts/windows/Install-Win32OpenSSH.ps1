#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    # Exact GitHub release tag, as shown on the releases page. Do not use an
    # implicit 'latest' release. Note the prefix varies: '10.0.0.0p2-Preview'
    # has none, older tags such as 'v9.8.3.0p2-Preview' start with 'v'.
    [Parameter(Mandatory)]
    [string]$Version,

    # Only these source addresses may reach TCP/22.
    [Parameter(Mandatory)]
    [string[]]$AllowedRemoteAddress,

    # Optional SHA-256 of OpenSSH-Win64.zip, obtained independently before install.
    [string]$ExpectedSha256,

    [switch]$ForceUpgrade
)

$ErrorActionPreference = 'Stop'

$openSshDirectory = Join-Path $env:ProgramFiles 'OpenSSH'
$sshdPath = Join-Path $openSshDirectory 'sshd.exe'
$zipName = 'OpenSSH-Win64.zip'
$releaseUri = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/$Version/$zipName"

if ((-not (Test-Path -LiteralPath $sshdPath -PathType Leaf)) -or $ForceUpgrade) {
    $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("winmesh-openssh-" + [Guid]::NewGuid())
    try {
        New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
        $archivePath = Join-Path $temporaryDirectory $zipName
        Invoke-WebRequest -Uri $releaseUri -OutFile $archivePath -UseBasicParsing

        if ($ExpectedSha256) {
            $actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
            if ($actualSha256 -ne $ExpectedSha256.ToUpperInvariant()) {
                throw "Downloaded archive SHA-256 does not match ExpectedSha256. Actual: $actualSha256"
            }
        }

        $extractPath = Join-Path $temporaryDirectory 'extract'
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
        $payloadDirectory = Get-ChildItem -LiteralPath $extractPath -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'sshd.exe') -PathType Leaf } |
            Select-Object -First 1
        if ($null -eq $payloadDirectory) {
            throw "The GitHub archive does not contain a directory with sshd.exe: $releaseUri"
        }

        if (Test-Path -LiteralPath $openSshDirectory) {
            if (-not $ForceUpgrade) {
                throw "OpenSSH directory already exists: $openSshDirectory. Use -ForceUpgrade only after stopping dependent sessions."
            }
            $existingService = Get-Service -Name sshd -ErrorAction SilentlyContinue
            if ($existingService -and $existingService.Status -eq 'Running') {
                Stop-Service -Name sshd
            }
            Remove-Item -LiteralPath $openSshDirectory -Recurse -Force
        }
        Move-Item -LiteralPath $payloadDirectory.FullName -Destination $openSshDirectory
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $sshdPath -PathType Leaf)) {
    throw "sshd.exe was not found after installation: $sshdPath"
}

& (Join-Path $openSshDirectory 'ssh-keygen.exe') -A
if ($LASTEXITCODE -ne 0) { throw "ssh-keygen -A failed with exit code $LASTEXITCODE." }

& $sshdPath -t
if ($LASTEXITCODE -ne 0) { throw "sshd.exe -t failed with exit code $LASTEXITCODE." }

if ($null -eq (Get-Service -Name sshd -ErrorAction SilentlyContinue)) {
    New-Service -Name sshd -BinaryPathName ('"{0}"' -f $sshdPath) `
        -DisplayName 'OpenSSH SSH Server' -StartupType Automatic | Out-Null
}
else {
    & sc.exe config sshd binPath= ('"{0}"' -f $sshdPath) start= auto | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sc.exe config sshd failed with exit code $LASTEXITCODE." }
}

$ruleName = 'winmesh-sshd'
if ($null -eq (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName 'winmesh OpenSSH Server (TCP 22)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
        -RemoteAddress $AllowedRemoteAddress | Out-Null
}
else {
    Set-NetFirewallRule -Name $ruleName -Enabled True | Out-Null
    Set-NetFirewallAddressFilter -AssociatedNetFirewallRule (Get-NetFirewallRule -Name $ruleName) `
        -RemoteAddress $AllowedRemoteAddress | Out-Null
}

# Allow rules add up: any other enabled inbound allow rule for TCP/22 - such as
# the stock OpenSSH-Server-In-TCP with RemoteAddress Any - would keep the port
# open to everyone next to winmesh-sshd. Disable them (reversible with
# Enable-NetFirewallRule) rather than delete. Rules pushed by Group Policy are
# not in the local store and cannot be changed here; review those separately.
$otherSshRules = @(Get-NetFirewallPortFilter -All |
    Where-Object { $_.Protocol -eq 'TCP' -and @($_.LocalPort) -contains '22' } |
    Get-NetFirewallRule |
    Where-Object {
        $_.Name -ne $ruleName -and $_.Enabled -eq 'True' -and
        $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow'
    })
foreach ($rule in $otherSshRules) {
    Disable-NetFirewallRule -Name $rule.Name
    Write-Host "Disabled the broader firewall rule for TCP/22: $($rule.Name) ($($rule.DisplayName))"
}

$service = Get-Service -Name sshd
if ($service.Status -ne 'Running') { Start-Service -Name sshd }

$isListening = @(Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue).Count -gt 0
if (-not $isListening) { throw 'The sshd service started but TCP port 22 is not listening.' }

$serviceConfig = Get-CimInstance Win32_Service -Filter "Name='sshd'"
[pscustomobject]@{
    SshdPath            = $sshdPath
    SshdStatus          = (Get-Service -Name sshd).Status
    StartupType         = $serviceConfig.StartMode
    AllowedRemoteAddress = $AllowedRemoteAddress -join ', '
    DisabledRules       = ($otherSshRules | ForEach-Object Name) -join ', '
    Port22Listening     = $isListening
}
