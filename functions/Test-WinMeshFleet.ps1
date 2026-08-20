<#
.SYNOPSIS
    Checks the channel to every machine in the fleet at once.
.DESCRIPTION
    Runs Test-WinMeshHost for each machine in the config and prints a summary.
    Does not set a process exit code (it is a function) — use the Ok field in the result.
.EXAMPLE
    Test-WinMeshFleet
.EXAMPLE
    if ((Test-WinMeshFleet).Where({ -not $_.Ok })) { 'some machines are unreachable' }
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
        Write-Host "`n=== Fleet summary ===" -ForegroundColor Cyan
        foreach ($r in $results) {
            $mark  = if ($r.Ok) { '  OK  ' } else { ' FAIL ' }
            $color = if ($r.Ok) { 'Green' } else { 'Red' }
            $failed = ($r.Checks | Where-Object { -not $_.Ok } | ForEach-Object { $_.Check }) -join ', '
            Write-Host $mark -NoNewline -ForegroundColor $color
            Write-Host (" {0,-24} {1}" -f $r.Host, $r.Address) -NoNewline
            if ($failed) { Write-Host "  - failed: $failed" -ForegroundColor DarkGray } else { Write-Host '' }
        }
        $bad = @($results | Where-Object { -not $_.Ok }).Count
        Write-Host ''
        if ($bad -eq 0) { Write-Host 'All machines reachable.' -ForegroundColor Green }
        else { Write-Host "Unreachable: $bad of $($results.Count)" -ForegroundColor Yellow }
    }

    $results
}
