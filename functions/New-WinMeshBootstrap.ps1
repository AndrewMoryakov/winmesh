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
      2. СУЖАЕТ порт 5985 до диапазона mesh-VPN — иначе Enable-PSRemoting откроет его
         с RemoteAddress=Any, то есть для любой сети с профилем «Частная». Это тот шаг,
         который легко забыть: в первом развёртывании его пропустили и порт оказался
         открыт шире, чем предполагалось;
      3. выдаёт локальной учётке полный админ-токен в удалённой сессии
         (LocalAccountTokenFilterPolicy) — нужно для НЕ доменных машин и не встроенного
         Администратора;
      4. печатает факты о машине, чтобы вписать её в конфиг.
.PARAMETER Name
    Имя машины из конфига (для подстановки её адреса в комментарии). Необязательно.
.PARAMETER TailscaleCidr
    Диапазон mesh-VPN, которым ограничивается порт. По умолчанию Tailscale CGNAT.
.PARAMETER OutFile
    Куда сохранить. По умолчанию — вывести в консоль.
.EXAMPLE
    New-WinMeshBootstrap -OutFile .\bootstrap-workstation-02.ps1
    # затем скопировать файл на целевую машину и запустить там от администратора
#>
function New-WinMeshBootstrap {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$TailscaleCidr = '100.64.0.0/10',
        [string]$OutFile
    )

    if ($Name) {
        try {
            $cfg = Get-WinMeshConfig
            if ($cfg.Hosts[$Name]) { $TailscaleCidr = $cfg.Defaults.TailscaleCidr }
        } catch { }
    }

    $script = @"
# ==========================================================================
#  winmesh bootstrap — запустить на ЦЕЛЕВОЙ машине ОТ АДМИНИСТРАТОРА.
#  Открывает удалённое управление только для mesh-VPN ($TailscaleCidr).
# ==========================================================================
`$ErrorActionPreference = 'Stop'

Write-Host '1/4 Включаю удалённое управление...' -ForegroundColor Cyan
# -SkipNetworkProfileCheck: адаптер mesh-VPN нередко в профиле «Общедоступная»,
# из-за чего обычный Enable-PSRemoting отказывается работать.
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null

Write-Host '2/4 Сужаю порт 5985 до mesh-VPN...' -ForegroundColor Cyan
`$rules = Get-NetFirewallRule -Direction Inbound -Enabled True | Where-Object {
    (`$_ | Get-NetFirewallPortFilter).LocalPort -eq 5985
}
if (`$rules) {
    `$rules | Set-NetFirewallRule -RemoteAddress '$TailscaleCidr'
    Write-Host "  правил обновлено: `$(@(`$rules).Count) -> RemoteAddress=$TailscaleCidr" -ForegroundColor Green
    Write-Host '  ВНИМАНИЕ: WinRM больше не отвечает из локальной сети, только через mesh-VPN.' -ForegroundColor Yellow
} else {
    Write-Host '  правило для 5985 не найдено — проверьте вручную' -ForegroundColor Red
}

Write-Host '3/4 Разрешаю полный админ-токен локальным учёткам удалённо...' -ForegroundColor Cyan
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' ``
    -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host '  готово' -ForegroundColor Green

Write-Host '4/4 Факты для конфига winmesh:' -ForegroundColor Cyan
`$cs = Get-CimInstance Win32_ComputerSystem
[PSCustomObject]@{
    ИмяКомпьютера = `$env:COMPUTERNAME
    Домен         = `$cs.Domain
    ВДомене       = `$cs.PartOfDomain
    Пользователь  = `$env:USERNAME
    ЛогинДляCred  = if (`$cs.PartOfDomain) { "`$(`$cs.Domain)\`$env:USERNAME" } else { "`$env:COMPUTERNAME\`$env:USERNAME" }
} | Format-List

Write-Host ''
Write-Host 'Дальше на УПРАВЛЯЮЩЕЙ машине:' -ForegroundColor Cyan
Write-Host '  1) впишите машину в config\hosts.psd1 (Address = её mesh-VPN адрес)'
Write-Host '  2) Register-WinMeshCredential -Id <ид> (логин — строка ЛогинДляCred выше)'
Write-Host '  3) Connect-WinMeshHost -Name <имя>'
Write-Host '  4) Test-WinMeshHost   -Name <имя>'
"@

    if ($OutFile) {
        # UTF-8 с BOM — иначе Windows PowerShell 5.1 не прочитает кириллицу
        [IO.File]::WriteAllText($OutFile, $script, (New-Object Text.UTF8Encoding($true)))
        Write-Host "Bootstrap сохранён: $OutFile" -ForegroundColor Green
        Write-Host 'Скопируйте его на целевую машину и запустите там от администратора.' -ForegroundColor DarkGray
    } else {
        $script
    }
}
