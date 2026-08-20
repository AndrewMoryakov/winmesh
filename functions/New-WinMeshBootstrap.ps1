<#
.SYNOPSIS
    Генерирует скрипт для разовой подготовки ЦЕЛЕВОЙ машины (запускается там с админом).
.DESCRIPTION
    Это ответ на проблему курицы и яйца: чтобы включить удалённое управление, нужен
    администратор ЛОКАЛЬНО на целевой машине — удалённо это сделать нельзя, канала ещё
    нет. Никакой конфиг это не обходит. Фреймворк лишь ГЕНЕРИРУЕТ скрипт, а запустить
    его у цели должен человек (RDP, консоль, а в домене — через GPO).

    Сгенерированный скрипт:
      1. включает удалённое управление (Enable-PSRemoting);
      2. СУЖАЕТ порт 5985 до разрешённых подсетей — иначе Enable-PSRemoting откроет его
         с RemoteAddress=Any, то есть для любой сети с профилем «Частная». Это тот шаг,
         который легко забыть: в одном развёртывании его пропустили и порт оказался
         открыт шире, чем предполагалось. Пустой список подсетей отключает сужение
         (например, доверенная локальная сеть);
      3. выдаёт локальной учётке полный админ-токен в удалённой сессии
         (LocalAccountTokenFilterPolicy) — нужно для НЕ доменных машин и не встроенного
         Администратора;
      4. печатает факты о машине, чтобы вписать её в конфиг.
.PARAMETER Name
    Имя машины из конфига. Необязательно (используется только для метки).
.PARAMETER AllowedSubnets
    Подсети, которым разрешается порт WinRM. По умолчанию берутся из конфига
    (100.64.0.0/10 — CGNAT-диапазон Tailscale и NetBird). Для ZeroTier, обычной
    локальной сети или своей адресации задайте свои. Пустой массив — не сужать порт.
.PARAMETER OutFile
    Куда сохранить. По умолчанию — вывести в консоль.
.EXAMPLE
    New-WinMeshBootstrap -OutFile .\bootstrap-ws02.ps1
    # затем скопировать файл на целевую машину и запустить там от администратора
.EXAMPLE
    New-WinMeshBootstrap -AllowedSubnets '192.168.1.0/24' -OutFile .\bootstrap-lan.ps1
    # сужение под обычную локальную сеть
#>
function New-WinMeshBootstrap {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string[]]$AllowedSubnets,
        [string]$OutFile
    )

    if (-not $PSBoundParameters.ContainsKey('AllowedSubnets')) {
        try { $AllowedSubnets = (Get-WinMeshConfig).Defaults.AllowedSubnets }
        catch { $AllowedSubnets = @('100.64.0.0/10') }
    }
    $AllowedSubnets = @($AllowedSubnets | Where-Object { $_ })

    $subnetLabel = if ($AllowedSubnets.Count) { $AllowedSubnets -join ', ' } else { 'НЕ СУЖАЕТСЯ (пустой список)' }
    # Литерал массива PowerShell для подстановки в тело генерируемого скрипта.
    $subnetsLiteral = '@(' + (($AllowedSubnets | ForEach-Object { "'$_'" }) -join ',') + ')'

    # Тело собираем построчно: символ '$' целевого скрипта пишем как одинарные строки,
    # а вычисляемые на этапе генерации значения ($subnetLabel, $subnetsLiteral) —
    # через обычную интерполяцию. Так не приходится жонглировать обратными кавычками.
    $lines = @(
        '# =========================================================================='
        '#  winmesh bootstrap — запустить на ЦЕЛЕВОЙ машине ОТ АДМИНИСТРАТОРА.'
        "#  Разрешённые подсети для порта WinRM: $subnetLabel"
        '# =========================================================================='
        '$ErrorActionPreference = ''Stop'''
        ''
        'Write-Host ''1/4 Включаю удалённое управление...'' -ForegroundColor Cyan'
        '# -SkipNetworkProfileCheck: адаптер оверлейной сети нередко в профиле'
        '# «Общедоступная», из-за чего обычный Enable-PSRemoting отказывается работать.'
        'Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null'
        ''
        'Write-Host ''2/4 Сужаю порт 5985 до разрешённых подсетей...'' -ForegroundColor Cyan'
        "`$allowed = $subnetsLiteral"
        '$rules = Get-NetFirewallRule -Direction Inbound -Enabled True | Where-Object {'
        '    ($_ | Get-NetFirewallPortFilter).LocalPort -eq 5985'
        '}'
        'if (-not $rules) {'
        '    Write-Host ''  правило для 5985 не найдено — проверьте вручную'' -ForegroundColor Red'
        '} elseif ($allowed.Count -eq 0) {'
        '    Write-Host ''  список подсетей пуст — сужение пропущено (порт открыт по профилю сети)'' -ForegroundColor Yellow'
        '} else {'
        '    $rules | Set-NetFirewallRule -RemoteAddress $allowed'
        '    Write-Host "  правил обновлено: $(@($rules).Count) -> $($allowed -join '', '')" -ForegroundColor Green'
        '    Write-Host ''  ВНИМАНИЕ: WinRM теперь отвечает только из этих подсетей.'' -ForegroundColor Yellow'
        '}'
        ''
        'Write-Host ''3/4 Разрешаю полный админ-токен локальным учёткам удалённо...'' -ForegroundColor Cyan'
        'New-ItemProperty -Path ''HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'' `'
        '    -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force | Out-Null'
        'Write-Host ''  готово'' -ForegroundColor Green'
        ''
        'Write-Host ''4/4 Факты для конфига winmesh:'' -ForegroundColor Cyan'
        '$cs = Get-CimInstance Win32_ComputerSystem'
        '[PSCustomObject]@{'
        '    ИмяКомпьютера = $env:COMPUTERNAME'
        '    Домен         = $cs.Domain'
        '    ВДомене       = $cs.PartOfDomain'
        '    Пользователь  = $env:USERNAME'
        '    ЛогинДляCred  = if ($cs.PartOfDomain) { "$($cs.Domain)\$env:USERNAME" } else { "$env:COMPUTERNAME\$env:USERNAME" }'
        '} | Format-List'
        ''
        'Write-Host ''''''Дальше на УПРАВЛЯЮЩЕЙ машине:'''''' -ForegroundColor Cyan'
        'Write-Host ''  1) впишите машину в config\hosts.psd1 (Address = её адрес в сети)'''
        'Write-Host ''  2) Register-WinMeshCredential -Id <ид> (логин — строка ЛогинДляCred выше)'''
        'Write-Host ''  3) Connect-WinMeshHost -Name <имя>'''
        'Write-Host ''  4) Test-WinMeshHost   -Name <имя>'''
    )
    $script = ($lines -join "`r`n") + "`r`n"

    if ($OutFile) {
        # UTF-8 с BOM — иначе Windows PowerShell 5.1 читает кириллицу как ANSI
        [IO.File]::WriteAllText($OutFile, $script, (New-Object Text.UTF8Encoding($true)))
        Write-Host "Bootstrap сохранён: $OutFile" -ForegroundColor Green
        Write-Host 'Скопируйте его на целевую машину и запустите там от администратора.' -ForegroundColor DarkGray
    } else {
        $script
    }
}
