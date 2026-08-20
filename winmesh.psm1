# winmesh — module loader.
# Each function lives in its own file under functions/ and is dot-sourced here.
# Works in both Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'

# Auto-loading the CIM/network modules under -WhatIf pollutes output with
# "What if: Set Alias" lines — preload them with the preference temporarily off.
$savedWhatIf = $WhatIfPreference
$WhatIfPreference = $false
Import-Module CimCmdlets, NetTCPIP -ErrorAction SilentlyContinue
$WhatIfPreference = $savedWhatIf

foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'functions') -Filter '*.ps1' -ErrorAction SilentlyContinue) {
    . $file.FullName
}
