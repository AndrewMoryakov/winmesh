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
    # USERPROFILE is unset outside Windows; fall back to HOME so that merely
    # loading the config does not fail on a non-Windows controller (the ssh
    # transport does not touch the credential store at all).
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

    $defaults = @{
        Transport       = 'winrm'
        CredentialStore = (Join-Path $home_ '.winmesh\creds')
        # Subnets allowed to reach the WinRM port (firewall narrowing in the bootstrap).
        # Default is the CGNAT range 100.64.0.0/10, used by both Tailscale and
        # NetBird. For ZeroTier, a plain LAN, or your own addressing, set your own
        # subnets. An empty list means "do not narrow" (e.g. a trusted LAN).
        AllowedSubnets  = @('100.64.0.0/10')

        # --- ssh transport (Transport = 'ssh') ---
        SshUser     = ''                # remote account; empty = let ssh decide (config/agent/current user)
        SshPort     = 22
        SshShell    = 'powershell'      # 'powershell' (5.1, always present) or 'pwsh'
        SshTimeout  = 15                # seconds, passed as ConnectTimeout
        SshOptions  = @()               # extra -o options, e.g. @('StrictHostKeyChecking=accept-new')
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
    $defaults.CredentialStore = $defaults.CredentialStore -replace '^~', $home_

    # validate each host
    foreach ($name in $cfg.Hosts.Keys) {
        $h = $cfg.Hosts[$name]
        if (-not $h.Address)   { throw "Host '$name': Address is missing (overlay/LAN IP or DNS name)." }
        if (-not $h.Transport) { $h.Transport = $defaults.Transport }
        if ($h.Transport -notin @('winrm', 'ssh')) {
            throw "Host '$name': unknown transport '$($h.Transport)'. Supported: 'winrm', 'ssh'."
        }
        # Only WinRM needs a stored credential. Over ssh the client authenticates
        # on its own — a key, an agent, or the peer identity of an overlay network
        # such as NetBird, whose SSH server authenticates the peer, not the user.
        if ($h.Transport -eq 'winrm' -and -not $h.Credential) {
            throw "Host '$name': Credential is missing (id of a stored credential)."
        }
    }

    [pscustomobject]@{
        Path     = (Resolve-Path -LiteralPath $Path).Path
        Defaults = $defaults
        Hosts    = $cfg.Hosts
    }
}
