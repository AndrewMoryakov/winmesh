<#
.SYNOPSIS
    Generates a one-time prep script for a TARGET machine (run there as admin).
.DESCRIPTION
    This is the answer to the chicken-and-egg problem: enabling remote management
    needs a LOCAL administrator on the target — it cannot be done remotely, the
    channel does not exist yet. No config works around this. The framework only
    GENERATES the script; a human must run it on the target (RDP, console, or GPO
    in a domain).

    The generated script:
      1. enables PowerShell Remoting (Enable-PSRemoting);
      2. NARROWS port 5985 to the allowed subnets — otherwise Enable-PSRemoting
         opens it with RemoteAddress=Any, i.e. for any network with the Private
         profile. This step is easy to forget: skip it once and the port ends up
         wider open than intended. An empty subnet list disables narrowing
         (e.g. a trusted LAN);
      3. grants a full admin token to local accounts in remote sessions
         (LocalAccountTokenFilterPolicy) — needed for non-domain machines and
         non-builtin Administrator;
      4. prints machine facts to fill into the config.
.PARAMETER Name
    Machine name from the config. Optional (used only as a label).
.PARAMETER AllowedSubnets
    Subnets allowed to reach the WinRM port. Taken from the config by default
    (100.64.0.0/10 — the CGNAT range of Tailscale and NetBird). For ZeroTier, a
    plain LAN, or your own addressing, set your own. An empty array = do not narrow.
.PARAMETER OutFile
    Where to save. By default, printed to the console.
.EXAMPLE
    New-WinMeshBootstrap -OutFile .\bootstrap-ws02.ps1
    # then copy the file to the target and run it there as administrator
.EXAMPLE
    New-WinMeshBootstrap -AllowedSubnets '192.168.1.0/24' -OutFile .\bootstrap-lan.ps1
    # narrowing for a plain LAN
#>
function New-WinMeshBootstrap {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string[]]$AllowedSubnets,
        [string]$OutFile
    )

    if (-not $PSBoundParameters.ContainsKey('AllowedSubnets')) {
        try { $AllowedSubnets = (Get-WinMeshConfig).Defaults.AllowedSubnets }
        catch { $AllowedSubnets = @('100.64.0.0/10') }
    }
    $AllowedSubnets = @($AllowedSubnets | Where-Object { $_ })

    $subnetLabel = if ($AllowedSubnets.Count) { $AllowedSubnets -join ', ' } else { 'NONE (empty list)' }
    # PowerShell array literal to substitute into the generated script body.
    $subnetsLiteral = '@(' + (($AllowedSubnets | ForEach-Object { "'$_'" }) -join ',') + ')'

    # Build the body line by line: the target script's own '$' lives inside
    # single-quoted strings, while values computed at generation time
    # ($subnetLabel, $subnetsLiteral) go through normal interpolation. This
    # avoids juggling backticks.
    $lines = @(
        '# =========================================================================='
        '#  winmesh bootstrap - run on the TARGET machine AS ADMINISTRATOR.'
        "#  Subnets allowed to reach the WinRM port: $subnetLabel"
        '# =========================================================================='
        '$ErrorActionPreference = ''Stop'''
        ''
        'Write-Host ''1/4 Enabling remote management...'' -ForegroundColor Cyan'
        '# -SkipNetworkProfileCheck: the overlay adapter is often in the Public'
        '# profile, which makes a plain Enable-PSRemoting refuse to run.'
        'Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null'
        ''
        'Write-Host ''2/4 Narrowing port 5985 to the allowed subnets...'' -ForegroundColor Cyan'
        "`$allowed = $subnetsLiteral"
        '$rules = Get-NetFirewallRule -Direction Inbound -Enabled True | Where-Object {'
        '    ($_ | Get-NetFirewallPortFilter).LocalPort -eq 5985'
        '}'
        'if (-not $rules) {'
        '    Write-Host ''  no rule for 5985 found - check manually'' -ForegroundColor Red'
        '} elseif ($allowed.Count -eq 0) {'
        '    Write-Host ''  subnet list is empty - narrowing skipped (port stays open per network profile)'' -ForegroundColor Yellow'
        '} else {'
        '    $rules | Set-NetFirewallRule -RemoteAddress $allowed'
        '    Write-Host "  rules updated: $(@($rules).Count) -> $($allowed -join '', '')" -ForegroundColor Green'
        '    Write-Host ''  NOTE: WinRM now answers only from these subnets.'' -ForegroundColor Yellow'
        '}'
        ''
        'Write-Host ''3/4 Granting a full admin token to local accounts remotely...'' -ForegroundColor Cyan'
        'New-ItemProperty -Path ''HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'' `'
        '    -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force | Out-Null'
        'Write-Host ''  done'' -ForegroundColor Green'
        ''
        'Write-Host ''4/4 Facts for the winmesh config:'' -ForegroundColor Cyan'
        '$cs = Get-CimInstance Win32_ComputerSystem'
        '[PSCustomObject]@{'
        '    ComputerName = $env:COMPUTERNAME'
        '    Domain       = $cs.Domain'
        '    InDomain     = $cs.PartOfDomain'
        '    User         = $env:USERNAME'
        '    LoginForCred = if ($cs.PartOfDomain) { "$($cs.Domain)\$env:USERNAME" } else { "$env:COMPUTERNAME\$env:USERNAME" }'
        '} | Format-List'
        ''
        'Write-Host ''''''Next, on the CONTROLLER machine:'''''' -ForegroundColor Cyan'
        'Write-Host ''  1) add the machine to config\hosts.psd1 (Address = its network address)'''
        'Write-Host ''  2) Register-WinMeshCredential -Id <id> (login = the LoginForCred value above)'''
        'Write-Host ''  3) Connect-WinMeshHost -Name <name>'''
        'Write-Host ''  4) Test-WinMeshHost   -Name <name>'''
    )
    $script = ($lines -join "`r`n") + "`r`n"

    if ($OutFile) {
        # UTF-8 with BOM so Windows PowerShell 5.1 does not misread it as ANSI
        [IO.File]::WriteAllText($OutFile, $script, (New-Object Text.UTF8Encoding($true)))
        Write-Host "Bootstrap saved: $OutFile" -ForegroundColor Green
        Write-Host 'Copy it to the target machine and run it there as administrator.' -ForegroundColor DarkGray
    } else {
        $script
    }
}
