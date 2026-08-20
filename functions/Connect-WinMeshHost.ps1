<#
.SYNOPSIS
    Готовит УПРАВЛЯЮЩУЮ сторону к работе с машиной: служба WinRM и TrustedHosts.
.DESCRIPTION
    Настраивает только эту (локальную) машину как клиента:
      * запускает службу WinRM и переводит её в автозапуск;
      * добавляет адрес целевой машины в TrustedHosts.

    TrustedHosts нужен потому, что подключение по IP идёт через NTLM (Kerberos
    по адресу неприменим), а NTLM требует явного списка доверенных хостов —
    даже если управляющая машина в домене.

    Требует прав администратора (правка службы и WSMan). НЕ трогает целевую машину —
    её подготовка делается отдельно, скриптом из New-WinMeshBootstrap.
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
    if (-not $h) { throw "Машины '$Name' нет в конфиге $($Config.Path)." }

    Write-Host "`n=== Подготовка клиента для '$Name' ($($h.Address)) ===" -ForegroundColor Cyan

    # 1. служба WinRM
    $svc = Get-Service WinRM -ErrorAction SilentlyContinue
    if (-not $svc) { throw 'Служба WinRM не найдена на этой машине.' }
    if ($svc.Status -ne 'Running') {
        if ($PSCmdlet.ShouldProcess('WinRM', 'запустить службу')) {
            Start-Service WinRM
            Write-Host '  служба WinRM запущена' -ForegroundColor Green
        }
    } else {
        Write-Host '  служба WinRM уже работает' -ForegroundColor DarkGray
    }
    if ($svc.StartType -ne 'Automatic') {
        if ($PSCmdlet.ShouldProcess('WinRM', 'перевести в автозапуск')) {
            Set-Service WinRM -StartupType Automatic
            Write-Host '  автозапуск включён' -ForegroundColor Green
        }
    }

    # 2. TrustedHosts
    $thPath = 'WSMan:\localhost\Client\TrustedHosts'
    $current = (Get-Item $thPath -ErrorAction SilentlyContinue).Value
    $entries = @($current -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($entries -contains $h.Address -or $current -eq '*') {
        Write-Host "  TrustedHosts уже содержит $($h.Address)" -ForegroundColor DarkGray
    } else {
        if ($PSCmdlet.ShouldProcess($h.Address, 'добавить в TrustedHosts')) {
            Set-Item $thPath -Value $h.Address -Concatenate -Force
            Write-Host "  добавлено в TrustedHosts: $($h.Address)" -ForegroundColor Green
        }
    }

    Write-Host "`nКлиент готов. Проверка: Test-WinMeshHost -Name $Name" -ForegroundColor Cyan
}
