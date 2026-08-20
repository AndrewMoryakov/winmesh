<#
.SYNOPSIS
    Runs a command on a fleet machine by its config name.
.DESCRIPTION
    Resolves the address and credentials from the config and calls Invoke-Command.
    Replaces the manual "import cred + remember the IP" with "name the machine".

    Hosts with Transport = 'ssh' go through the ssh transport instead. Either way
    the return value is real objects, not text.
.PARAMETER Name
    Machine name from the config.
.PARAMETER ScriptBlock
    What to run on the other side.
.PARAMETER ArgumentList
    Arguments passed into the ScriptBlock (via param in the block).
.EXAMPLE
    Invoke-WinMeshCommand workstation-01 { hostname; whoami }
.EXAMPLE
    Invoke-WinMeshCommand workstation-01 { param($p) Test-Path $p } -ArgumentList 'C:\Windows'
#>
function Invoke-WinMeshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory, Position = 1)] [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [object]$Config
    )

    if (-not $Config) { $Config = Get-WinMeshConfig }
    $h = $Config.Hosts[$Name]
    if (-not $h) { throw "Host '$Name' is not in config $($Config.Path)." }

    if ($h.Transport -eq 'ssh') {
        return Invoke-WinMeshSsh -HostEntry $h -Defaults $Config.Defaults `
            -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }

    $cred = Get-WinMeshCredential -Id $h.Credential -Store $Config.Defaults.CredentialStore

    $params = @{
        ComputerName = $h.Address
        Credential   = $cred
        ScriptBlock  = $ScriptBlock
        ErrorAction  = 'Stop'
    }
    if ($ArgumentList) { $params.ArgumentList = $ArgumentList }

    Invoke-Command @params
}
