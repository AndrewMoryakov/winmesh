<#
.SYNOPSIS
    Проверяет канал до всех машин парка разом.
.DESCRIPTION
    Прогоняет Test-WinMeshHost по каждой машине конфига и печатает сводку.
    Код возврата процесса не ставит (это функция) — используйте поле Ok в результате.
.EXAMPLE
    Test-WinMeshFleet
.EXAMPLE
    if ((Test-WinMeshFleet).Where({ -not $_.Ok })) { 'есть недоступные машины' }
#>
function Test-WinMeshFleet {
    [CmdletBinding()]
    param(
        [object]$Config,
        [switch]$Quiet
    )

    if (-not $Config) { $Config = Get-WinMeshConfig }

    $results = foreach ($name in $Config.Hosts.Keys) {
        Test-WinMeshHost -Name $name -Config $Config -Quiet:$Quiet
    }

    if (-not $Quiet) {
        Write-Host "`n=== Сводка по парку ===" -ForegroundColor Cyan
        foreach ($r in $results) {
            $mark  = if ($r.Ok) { '  OK  ' } else { ' FAIL ' }
            $color = if ($r.Ok) { 'Green' } else { 'Red' }
            $failed = ($r.Checks | Where-Object { -not $_.Ok } | ForEach-Object { $_.Check }) -join ', '
            Write-Host $mark -NoNewline -ForegroundColor $color
            Write-Host (" {0,-24} {1}" -f $r.Host, $r.Address) -NoNewline
            if ($failed) { Write-Host "  — не пройдено: $failed" -ForegroundColor DarkGray } else { Write-Host '' }
        }
        $bad = @($results | Where-Object { -not $_.Ok }).Count
        Write-Host ''
        if ($bad -eq 0) { Write-Host 'Все машины доступны.' -ForegroundColor Green }
        else { Write-Host "Недоступны: $bad из $($results.Count)" -ForegroundColor Yellow }
    }

    $results
}
