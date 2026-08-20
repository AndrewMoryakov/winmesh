<#
.SYNOPSIS
    Выполняет команду на машине парка по имени из конфига.
.DESCRIPTION
    Резолвит адрес и учётные данные из конфига и вызывает Invoke-Command.
    Это замена ручного «импортировать cred + помнить IP» на «назвать машину».
.PARAMETER Name
    Имя машины из конфига.
.PARAMETER ScriptBlock
    Что выполнить на той стороне.
.PARAMETER ArgumentList
    Аргументы, пробрасываемые в ScriptBlock (через param в блоке).
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
    if (-not $h) { throw "Машины '$Name' нет в конфиге $($Config.Path)." }

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
