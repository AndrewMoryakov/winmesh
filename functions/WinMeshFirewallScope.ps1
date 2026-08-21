<#
.SYNOPSIS
    View and change which source networks may reach a host's WinRM port.
.DESCRIPTION
    The bootstrap narrows the WinRM firewall rule to Defaults.AllowedSubnets. These
    commands make that scope visible and changeable after the fact, driven by the
    same config value — so "which networks can reach this machine" is configuration,
    not a firewall command you have to remember.

    WinRM only. Over ssh the port and its firewall are a different concern.

    A host may override the global Defaults.AllowedSubnets with its own AllowedSubnets
    (e.g. a machine reachable through a different overlay than the rest of the fleet).
#>

# IPv4 CIDR containment. Private. 'Any'/'*' matches everything; a bare IP is /32.
function Test-WinMeshCidr {
    param([Parameter(Mandatory)][string]$Address, [Parameter(Mandatory)][string]$Cidr)
    if ($Cidr -in @('Any', '*')) { return $true }
    $parts = $Cidr -split '/'
    $net  = $parts[0]
    $bits = if ($parts.Count -gt 1) { [int]$parts[1] } else { 32 }
    try {
        $a = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
        $n = [System.Net.IPAddress]::Parse($net).GetAddressBytes()
    } catch { return $false }
    if ($a.Length -ne 4 -or $n.Length -ne 4) { return $false }   # IPv4 only
    if ($bits -le 0)  { return $true }
    if ($bits -gt 32) { return $false }
    [array]::Reverse($a); [array]::Reverse($n)
    $ai = [BitConverter]::ToUInt32($a, 0)
    $ni = [BitConverter]::ToUInt32($n, 0)
    $mask = [uint32](([long]0xFFFFFFFF -shl (32 - $bits)) -band 0xFFFFFFFFL)
    ($ai -band $mask) -eq ($ni -band $mask)
}

# Effective allowed subnets for a host: its own override, else the global default.
function Get-WinMeshEffectiveSubnets {
    param([Parameter(Mandatory)]$HostEntry, [Parameter(Mandatory)]$Defaults)
    $s = if ($null -ne $HostEntry.AllowedSubnets) { $HostEntry.AllowedSubnets } else { $Defaults.AllowedSubnets }
    @($s | Where-Object { $_ })
}

<#
.SYNOPSIS
    Shows a host's current WinRM firewall scope and whether it matches the config.
.EXAMPLE
    Get-WinMeshFirewallScope -Name workstation-01
#>
function Get-WinMeshFirewallScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [object]$Config
    )
    if (-not $Config) { $Config = Get-WinMeshConfig }
    $h = $Config.Hosts[$Name]
    if (-not $h) { throw "Host '$Name' is not in config $($Config.Path)." }
    if ($h.Transport -eq 'ssh') { throw "Host '$Name' uses ssh; firewall scope is a WinRM concern only." }

    $current = @(Invoke-WinMeshCommand -Name $Name -Config $Config -ScriptBlock {
        $rule = Get-NetFirewallRule -Direction Inbound -Enabled True |
            Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -eq 5985 } | Select-Object -First 1
        if ($rule) { @(($rule | Get-NetFirewallAddressFilter).RemoteAddress) } else { @() }
    })

    $configured = Get-WinMeshEffectiveSubnets -HostEntry $h -Defaults $Config.Defaults
    $wantAny = ($configured.Count -eq 0)
    # Compare as sets of strings; the live rule stores CIDR as address/mask, so also
    # accept the /prefix form matching (a light check — exact drift is what matters).
    $inSync = if ($wantAny) { $current -contains 'Any' } else {
        # every configured subnet appears (by network prefix) in the live scope
        -not ($configured | Where-Object { $c = $_; -not ($current | Where-Object { $_ -like ($c -replace '/.*','') + '*' }) })
    }

    [pscustomobject]@{
        Host       = $Name
        Current    = $current
        Configured = if ($wantAny) { @('Any (empty AllowedSubnets)') } else { $configured }
        InSync     = [bool]$inSync
    }
}

<#
.SYNOPSIS
    Applies the config's AllowedSubnets to a host's WinRM firewall rule.
.DESCRIPTION
    Refuses if it would cut the caller's own live session — no established WinRM
    connection would fall inside the new ranges — unless -Force is given. An empty
    AllowedSubnets means 'Any' (do not narrow).
.EXAMPLE
    Set-WinMeshFirewallScope -Name workstation-01 -WhatIf
    Set-WinMeshFirewallScope -Name workstation-01
#>
function Set-WinMeshFirewallScope {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [object]$Config,
        [switch]$Force
    )
    if (-not $Config) { $Config = Get-WinMeshConfig }
    $h = $Config.Hosts[$Name]
    if (-not $h) { throw "Host '$Name' is not in config $($Config.Path)." }
    if ($h.Transport -eq 'ssh') { throw "Host '$Name' uses ssh; firewall scope is a WinRM concern only." }

    $subnets = Get-WinMeshEffectiveSubnets -HostEntry $h -Defaults $Config.Defaults
    $wantAny = ($subnets.Count -eq 0)
    $target  = if ($wantAny) { 'Any' } else { $subnets }

    Write-Host "`n=== $Name -> WinRM allowed source: $(if ($wantAny) { 'Any (not narrowed)' } else { $subnets -join ', ' }) ===" -ForegroundColor Cyan

    # Lock-out guard: look at who is connected on 5985 right now. If we are about to
    # narrow and none of the live sources falls inside the new ranges, applying would
    # cut the current session (this one included). Refuse unless forced.
    if (-not $wantAny) {
        $live = @(Invoke-WinMeshCommand -Name $Name -Config $Config -ScriptBlock {
            @((Get-NetTCPConnection -LocalPort 5985 -State Established -ErrorAction SilentlyContinue).RemoteAddress) | Where-Object { $_ }
        })
        $kept = @($live | Where-Object { $addr = $_; $subnets | Where-Object { Test-WinMeshCidr -Address $addr -Cidr $_ } })
        $cut  = @($live | Where-Object { $_ -notin $kept })
        if ($live.Count -gt 0) {
            Write-Host "  live WinRM sources: $($live -join ', ')" -ForegroundColor DarkGray
            if ($cut.Count)  { Write-Host "  would be cut off:   $($cut -join ', ')" -ForegroundColor Yellow }
        }
        if ($live.Count -gt 0 -and $kept.Count -eq 0 -and -not $Force) {
            throw "Refusing: no live WinRM source falls inside the new ranges — this would lock you out. Add your source subnet, or pass -Force if you are on the console."
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$Name WinRM firewall rule", "set allowed source to $(if ($wantAny) {'Any'} else {$subnets -join ', '})")) {
        Write-Host 'Preview only — nothing changed.' -ForegroundColor Yellow
        return
    }

    $applied = @(Invoke-WinMeshCommand -Name $Name -Config $Config -ArgumentList (,$target) -ScriptBlock {
        param($scope)
        $rules = Get-NetFirewallRule -Direction Inbound -Enabled True |
            Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -eq 5985 }
        if (-not $rules) { throw 'no inbound WinRM (5985) rule found on the target' }
        $rules | Set-NetFirewallRule -RemoteAddress $scope
        @((($rules | Select-Object -First 1) | Get-NetFirewallAddressFilter).RemoteAddress)
    })

    Write-Host "  applied. WinRM now accepts from: $($applied -join ', ')" -ForegroundColor Green
    [pscustomobject]@{ Host = $Name; RemoteAddress = $applied }
}
