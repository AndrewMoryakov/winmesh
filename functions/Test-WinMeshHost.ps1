<#
.SYNOPSIS
    Проверяет готовность канала до одной машины парка.
.DESCRIPTION
    Проверяет всю цепочку и возвращает структурированный результат (пригодный для
    автоматики), плюс печатает читаемый отчёт, если не задан -Quiet:
      * достижимость порта WinRM поверх mesh-VPN;
      * ответ WS-Management с той стороны;
      * наличие и читаемость учётных данных;
      * фактическое выполнение команды и уровень прав.
.PARAMETER Quiet
    Не печатать, только вернуть объект.
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
    if (-not $h) { throw "Машины '$Name' нет в конфиге $($Config.Path)." }

    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check($label, $ok, $detail) {
        $checks.Add([pscustomobject]@{ Check = $label; Ok = [bool]$ok; Detail = "$detail" })
    }

    # 1. порт
    $port = Test-NetConnection -ComputerName $h.Address -Port 5985 -WarningAction SilentlyContinue
    Add-Check 'порт WinRM 5985' $port.TcpTestSucceeded $(if ($port.TcpTestSucceeded) { $h.Address } else { 'нет соединения' })

    # 2. WS-Management
    $wsman = $false
    if ($port.TcpTestSucceeded) {
        try { Test-WSMan -ComputerName $h.Address -ErrorAction Stop | Out-Null; $wsman = $true } catch { }
    }
    Add-Check 'ответ WS-Management' $wsman $(if ($wsman) { 'отвечает' } else { 'нет ответа' })

    # 3. учётные данные
    $cred = $null
    try { $cred = Get-WinMeshCredential -Id $h.Credential -Store $Config.Defaults.CredentialStore } catch { }
    Add-Check 'учётные данные' ([bool]$cred) $(if ($cred) { $cred.UserName } else { "нет записи '$($h.Credential)'" })

    # 4. выполнение боем
    if ($cred -and $wsman) {
        try {
            $r = Invoke-Command -ComputerName $h.Address -Credential $cred -ErrorAction Stop -ScriptBlock {
                [PSCustomObject]@{
                    Host  = $env:COMPUTERNAME
                    User  = whoami
                    Admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
                }
            }
            Add-Check 'команда выполняется' $true "$($r.Host) / $($r.User)"
            Add-Check 'полный админ-токен' $r.Admin $(if ($r.Admin) { 'да' } else { 'урезан (LocalAccountTokenFilterPolicy на цели)' })
        } catch {
            Add-Check 'команда выполняется' $false (($_.Exception.Message -split "`n")[0])
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
            if ($c.Detail) { Write-Host "  — $($c.Detail)" -ForegroundColor DarkGray } else { Write-Host '' }
        }
    }

    [pscustomobject]@{
        Host   = $Name
        Address = $h.Address
        Ok     = $allOk
        Checks = $checks
    }
}
