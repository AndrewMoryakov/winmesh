<#
.SYNOPSIS
    Prepares the CONTROLLER side to talk to a host: WinRM service and TrustedHosts.
.DESCRIPTION
    Configures only this (local) machine as a client:
      * starts the WinRM service and sets it to Automatic;
      * adds the target's address to TrustedHosts.

    TrustedHosts is required because connecting by IP uses NTLM (Kerberos does
    not apply to a bare address), and NTLM needs an explicit trusted-hosts list —
    even when the controller is domain-joined.

    Requires administrator rights (service and WSMan changes). Does NOT touch the
    target — prepare that separately with the script from New-WinMeshBootstrap.
.EXAMPLE
    Connect-WinMeshHost -Name workstation-01 -WhatIf
    Connect-WinMeshHost -Name workstation-01
#>
function Connect-WinMeshHost {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [object]$Config
    )

    if (-not $Config) { $Config = Get-WinMeshConfig }
    $h = $Config.Hosts[$Name]
    if (-not $h) { throw "Host '$Name' is not in config $($Config.Path)." }

    Write-Host "`n=== Preparing client for '$Name' ($($h.Address)) ===" -ForegroundColor Cyan

    # 1. WinRM service
    $svc = Get-Service WinRM -ErrorAction SilentlyContinue
    if (-not $svc) { throw 'The WinRM service was not found on this machine.' }
    if ($svc.Status -ne 'Running') {
        if ($PSCmdlet.ShouldProcess('WinRM', 'start service')) {
            Start-Service WinRM
            Write-Host '  WinRM service started' -ForegroundColor Green
        }
    } else {
        Write-Host '  WinRM service already running' -ForegroundColor DarkGray
    }
    if ($svc.StartType -ne 'Automatic') {
        if ($PSCmdlet.ShouldProcess('WinRM', 'set to Automatic')) {
            Set-Service WinRM -StartupType Automatic
            Write-Host '  set to Automatic startup' -ForegroundColor Green
        }
    }

    # 2. TrustedHosts
    $thPath = 'WSMan:\localhost\Client\TrustedHosts'
    $current = (Get-Item $thPath -ErrorAction SilentlyContinue).Value
    $entries = @($current -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($entries -contains $h.Address -or $current -eq '*') {
        Write-Host "  TrustedHosts already contains $($h.Address)" -ForegroundColor DarkGray
    } else {
        if ($PSCmdlet.ShouldProcess($h.Address, 'add to TrustedHosts')) {
            Set-Item $thPath -Value $h.Address -Concatenate -Force
            Write-Host "  added to TrustedHosts: $($h.Address)" -ForegroundColor Green
        }
    }

    Write-Host "`nClient ready. Verify: Test-WinMeshHost -Name $Name" -ForegroundColor Cyan
}
