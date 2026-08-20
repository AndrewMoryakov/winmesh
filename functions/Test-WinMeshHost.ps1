<#
.SYNOPSIS
    Checks that the channel to one fleet machine is ready.
.DESCRIPTION
    Checks the whole chain and returns a structured result (suitable for
    automation), and prints a readable report unless -Quiet is set:
      * WinRM port reachable over the network;
      * WS-Management responds from the other side;
      * credentials present and readable;
      * a command actually runs, and the privilege level.
.PARAMETER Quiet
    Do not print; return the object only.
.EXAMPLE
    Test-WinMeshHost -Name workstation-01
#>
function Test-WinMeshHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [object]$Config,
        [switch]$Quiet
    )

    if (-not $Config) { $Config = Get-WinMeshConfig }
    $h = $Config.Hosts[$Name]
    if (-not $h) { throw "Host '$Name' is not in config $($Config.Path)." }

    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check($label, $ok, $detail) {
        $checks.Add([pscustomobject]@{ Check = $label; Ok = [bool]$ok; Detail = "$detail" })
    }

    # 1. port
    $port = Test-NetConnection -ComputerName $h.Address -Port 5985 -WarningAction SilentlyContinue
    Add-Check 'WinRM port 5985' $port.TcpTestSucceeded $(if ($port.TcpTestSucceeded) { $h.Address } else { 'no connection' })

    # 2. WS-Management
    $wsman = $false
    if ($port.TcpTestSucceeded) {
        try { Test-WSMan -ComputerName $h.Address -ErrorAction Stop | Out-Null; $wsman = $true } catch { }
    }
    Add-Check 'WS-Management responds' $wsman $(if ($wsman) { 'responds' } else { 'no response' })

    # 3. credentials
    $cred = $null
    try { $cred = Get-WinMeshCredential -Id $h.Credential -Store $Config.Defaults.CredentialStore } catch { }
    Add-Check 'credentials' ([bool]$cred) $(if ($cred) { $cred.UserName } else { "no entry '$($h.Credential)'" })

    # 4. actually run a command
    if ($cred -and $wsman) {
        try {
            $r = Invoke-Command -ComputerName $h.Address -Credential $cred -ErrorAction Stop -ScriptBlock {
                [PSCustomObject]@{
                    Host  = $env:COMPUTERNAME
                    User  = whoami
                    Admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
                }
            }
            Add-Check 'command runs' $true "$($r.Host) / $($r.User)"
            Add-Check 'full admin token' $r.Admin $(if ($r.Admin) { 'yes' } else { 'reduced (set LocalAccountTokenFilterPolicy on the target)' })
        } catch {
            Add-Check 'command runs' $false (($_.Exception.Message -split "`n")[0])
        }
    }

    $allOk = -not ($checks | Where-Object { -not $_.Ok })

    if (-not $Quiet) {
        Write-Host "`n=== $Name ($($h.Address)) ===" -ForegroundColor Cyan
        foreach ($c in $checks) {
            $mark  = if ($c.Ok) { '  OK  ' } else { ' FAIL ' }
            $color = if ($c.Ok) { 'Green' } else { 'Red' }
            Write-Host $mark -NoNewline -ForegroundColor $color
            Write-Host " $($c.Check)" -NoNewline
            if ($c.Detail) { Write-Host "  - $($c.Detail)" -ForegroundColor DarkGray } else { Write-Host '' }
        }
    }

    [pscustomobject]@{
        Host   = $Name
        Address = $h.Address
        Ok     = $allOk
        Checks = $checks
    }
}
