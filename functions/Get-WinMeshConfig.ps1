<#
.SYNOPSIS
    Loads and validates the fleet config.
.DESCRIPTION
    The config is a .psd1 file (not YAML: Windows PowerShell 5.1 has no built-in
    YAML parser, whereas .psd1 is parsed safely via Import-PowerShellDataFile
    without executing code). Default path: $env:WINMESH_CONFIG, otherwise
    config\hosts.psd1 next to the module.
.EXAMPLE
    $cfg = Get-WinMeshConfig
    $cfg.Hosts.Keys
#>
function Get-WinMeshConfig {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if (-not $Path) {
        $Path = $env:WINMESH_CONFIG
    }
    if (-not $Path) {
        $Path = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\hosts.psd1'
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config not found: $Path. Copy config\hosts.example.psd1 to config\hosts.psd1 and fill in your machines."
    }

    $cfg = Import-PowerShellDataFile -LiteralPath $Path

    if (-not $cfg.Hosts -or $cfg.Hosts.Count -eq 0) {
        throw "Config $Path has no machines (the Hosts section is empty)."
    }

    # defaults
    $defaults = @{
        Transport       = 'winrm'
        CredentialStore = (Join-Path $env:USERPROFILE '.winmesh\creds')
        # Subnets allowed to reach the WinRM port (firewall narrowing in the bootstrap).
        # Default is the CGNAT range 100.64.0.0/10, used by both Tailscale and
        # NetBird. For ZeroTier, a plain LAN, or your own addressing, set your own
        # subnets. An empty list means "do not narrow" (e.g. a trusted LAN).
        AllowedSubnets  = @('100.64.0.0/10')
    }
    if ($cfg.Defaults) {
        foreach ($k in $cfg.Defaults.Keys) { $defaults[$k] = $cfg.Defaults[$k] }
    }
    # Backward compatibility with the old TailscaleCidr key.
    if ($cfg.Defaults -and $cfg.Defaults.TailscaleCidr -and -not ($cfg.Defaults.Keys -contains 'AllowedSubnets')) {
        $defaults.AllowedSubnets = @($cfg.Defaults.TailscaleCidr)
    }
    $defaults.AllowedSubnets = @($defaults.AllowedSubnets)

    # expand ~ in the store path
    $defaults.CredentialStore = $defaults.CredentialStore -replace '^~', $env:USERPROFILE

    # validate each host
    foreach ($name in $cfg.Hosts.Keys) {
        $h = $cfg.Hosts[$name]
        if (-not $h.Address)    { throw "Host '$name': Address is missing (overlay/LAN IP or DNS name)." }
        if (-not $h.Credential) { throw "Host '$name': Credential is missing (id of a stored credential)." }
        if (-not $h.Transport)  { $h.Transport = $defaults.Transport }
        if ($h.Transport -ne 'winrm') {
            throw "Host '$name': transport '$($h.Transport)' is not supported yet. This version is winrm only."
        }
    }

    [pscustomobject]@{
        Path     = (Resolve-Path -LiteralPath $Path).Path
        Defaults = $defaults
        Hosts    = $cfg.Hosts
    }
}
