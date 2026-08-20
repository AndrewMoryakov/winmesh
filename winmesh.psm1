# winmesh — загрузчик модуля.
# Все функции лежат отдельными файлами в functions/ и подключаются здесь.
# Модуль работает и в Windows PowerShell 5.1, и в PowerShell 7.

$ErrorActionPreference = 'Stop'

# Автозагрузка модулей CIM/сеть при -WhatIf засоряет вывод «What if: Set Alias» —
# подгружаем заранее при временно сброшенной преференции.
$savedWhatIf = $WhatIfPreference
$WhatIfPreference = $false
Import-Module CimCmdlets, NetTCPIP -ErrorAction SilentlyContinue
$WhatIfPreference = $savedWhatIf

foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'functions') -Filter '*.ps1' -ErrorAction SilentlyContinue) {
    . $file.FullName
}
