<p align="center">
  <img src="docs/assets/winmesh-hero.png" alt="winmesh: диспетчер за столом с адресной книгой отправляет курьеров к Windows-машинам, каждая доступна по имени" width="100%">
</p>

<h1 align="center">winmesh</h1>

<p align="center"><b>Назовите машину — и запускайте на ней PowerShell по WinRM или SSH, в любой сети. Для админов и разработчиков, у которых несколько Windows-компьютеров — и Linux- и macOS-машины рядом с ними.</b></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-informational.svg"></a>
  <a href="https://learn.microsoft.com/powershell/"><img alt="PowerShell 5.1+ | 7" src="https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207-5391FE.svg?logo=powershell&logoColor=white"></a>
  <a href="#платформы"><img alt="Platform: Windows | Linux | macOS" src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-0078D6.svg"></a>
  <a href="https://learn.microsoft.com/windows/win32/winrm/portal"><img alt="Transport: WinRM | SSH" src="https://img.shields.io/badge/Transport-WinRM%20%7C%20SSH-2E7D57.svg"></a>
  <a href="winmesh.psd1"><img alt="Version" src="https://img.shields.io/badge/version-0.2.1-blue.svg"></a>
</p>

<p align="center"><a href="README.md">English</a> | <b>Русский</b></p>

```powershell
Invoke-WinMeshCommand workstation-01 { hostname; whoami }     # выполнить команду на хосте по имени
Test-WinMeshFleet                                             # проверить сразу все хосты из конфига
```

winmesh — тонкий слой для связи Windows-машин по PowerShell Remoting **или SSH**. Назовите хост, запустите на нём команду, получите обратно настоящие объекты. Контроллер и цели могут быть на Windows, Linux или macOS: WinRM — между Windows-машинами, SSH — везде; см. [Платформы](#платформы).

## Зачем нужен winmesh?

- **Если** у вас несколько Windows-машин (рабочие станции, NAS, лабораторные стенды) и вы хотите запускать на них PowerShell по имени, **то** после разовой настройки каждой машины вы получаете `Invoke-WinMeshCommand <имя> { ... }`.
- **Если** Ansible для пары-тройки машин — это перебор, **то** winmesh намеренно маленький: один конфиг, штатный WinRM или `ssh`, без агентов и лишних зависимостей.
- **Если** машины связаны Tailscale, NetBird, ZeroTier или обычной LAN, **то** всё работает одинаково: winmesh нужны лишь стабильные, взаимно достижимые адреса, а не какая-то конкретная сеть. **Не привязан ни к какой конкретной сети.**
- **Если** вы не хотите набивать шишки на подводных камнях WinRM, файрвола и SSH-квотирования, **то** [грабли](#встроенные-грабли) уже учтены.

Это не новый протокол. Под капотом — штатные WinRM и `Invoke-Command` либо штатный `ssh`; выбор делается для каждого хоста одним полем конфига. Ценность — в продуманном наборе, описанном ниже. winmesh **не** предназначен для больших парков машин и управления конфигурацией — см. [чего он намеренно не делает](#чего-он-намеренно-не-делает).

## Возможности

- **Адресация по имени** — хосты описаны в одном `config/hosts.psd1`; вы пишете `workstation-01`, а не IP.
- **Два транспорта, один интерфейс** — `winrm` (по умолчанию) или `ssh`, на каждый хост отдельно. Те же имена, те же команды, те же объекты в ответе.
- **Настоящие объекты, а не текст** — результат можно передавать по конвейеру как любой вывод PowerShell, в обоих транспортах.
- **Файрвол сужен до доверенных подсетей** — bootstrap ограничивает порт WinRM значением `AllowedSubnets`; позже посмотреть или применить заново можно через `Get-`/`Set-WinMeshFirewallScope`.
- **Локальное хранилище учётных данных** — учётки для каждой цели шифруются DPAPI и никогда не попадают в git (WinRM).
- **Проверка канала одной командой** — `Test-WinMeshHost` и `Test-WinMeshFleet`.
- **Грабли учтены заранее** — уроки реальной отладки встроены в скрипты и [записаны](#встроенные-грабли).

## Как это работает

<p align="center">
  <img src="docs/assets/winmesh-how-it-works.png" alt="winmesh: контроллер находит имя хоста в конфиге и обращается к машине по WinRM или SSH" width="100%">
</p>

1. **Назовите машины.** Опишите каждую цель — короткое имя, адрес, id учётных данных — в `config/hosts.psd1`.
2. **Подготовьте один раз.** Запустите сгенерированный bootstrap-скрипт на каждой цели (включает WinRM, сужает файрвол) и `Connect-WinMeshHost` на контроллере.
3. **Запускайте по имени.** `Invoke-WinMeshCommand <имя> { ... }` выбирает транспорт хоста — `winrm` или `ssh` — и выполняет там ваш scriptblock.
4. **Получайте объекты.** Результат возвращается как объекты PowerShell, которые можно передавать дальше по конвейеру.

## Быстрый старт

Из клона этого репозитория на **контроллере** (вашем ноутбуке). Права администратора нужны только для bootstrap на цели и для `Connect-WinMeshHost`. Каждый шаг подробно описан в разделе [Настройка — шаг за шагом](#настройка--шаг-за-шагом).

```powershell
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
Import-Module .\winmesh.psd1

Copy-Item .\config\hosts.example.psd1 .\config\hosts.psd1
notepad .\config\hosts.psd1                       # добавьте свою машину (Address + Credential) и задайте AllowedSubnets

New-WinMeshBootstrap -OutFile .\bootstrap.ps1     # берёт AllowedSubnets из конфига; скопируйте на цель и запустите там один раз от имени администратора

Register-WinMeshCredential -Id 'admin@workstation-01'   # логин — ровно так, как его напечатал bootstrap
Connect-WinMeshHost -Name workstation-01                # настройка контроллера (админ, один раз)
Test-WinMeshHost    -Name workstation-01                # пять зелёных проверок = успех

Invoke-WinMeshCommand workstation-01 { hostname; whoami }
```

Создайте конфиг **до** генерации bootstrap-скрипта: `New-WinMeshBootstrap` берёт область файрвола из `AllowedSubnets` в `config\hosts.psd1`, а без конфига подставляет `100.64.0.0/10` (диапазон Tailscale/NetBird) — и контроллер в обычной LAN или ZeroTier окажется отрезан. Либо передайте `-AllowedSubnets` явно — см. [Выбор разрешённых подсетей](#выбор-разрешённых-подсетей).

Цели, доступные по **SSH**, полностью пропускают bootstrap, учётные данные и `Connect-WinMeshHost` — изменения WinRM им не нужны. См. [SSH вместо WinRM](#ssh-вместо-winrm).

---

## Концепции за 30 секунд

- **Контроллер** — машина, с которой вы запускаете winmesh (ваш ноутбук). Здесь лежат конфиг и хранилище учётных данных.
- **Цель** — машина, до которой нужно достучаться. На ней работает WinRM-listener или SSH-сервер.
- **Конфиг** (`config/hosts.psd1`) — список целей: короткое имя, адрес, id учётных данных.
- **Хранилище учётных данных** — зашифрованные учётки для каждой цели, хранятся локально (никогда не в git). Только для WinRM.
- **Транспорт** — `winrm` (по умолчанию) или `ssh`, задаётся для каждого хоста. Всё поверх транспорта одинаково: те же имена, те же команды, те же объекты в ответе.

Один раз настраиваете каждую машину, а дальше просто вызываете `Invoke-WinMeshCommand <имя> { ... }`.

---

## Требования для старта

- Windows PowerShell 5.1 **или** PowerShell 7 на Windows-машинах; PowerShell 7 (`pwsh`) на Linux и macOS — и на контроллере, и на целях. См. [Платформы](#платформы).
- Сеть, дающая машинам стабильные, взаимно достижимые адреса (Tailscale / NetBird / ZeroTier / LAN).
- Права администратора нужны ровно для двух шагов: `Connect-WinMeshHost` на контроллере и bootstrap-скрипт на каждой цели.

---

## Платформы

ssh-транспорт работает в любом направлении; WinRM требует Windows на обоих концах.

| Контроллер ↓ · Цель → | Windows | Linux / macOS |
|---|---|---|
| **Windows** (PowerShell 5.1 или 7) | `winrm` или `ssh` | `ssh` |
| **Linux / macOS** (PowerShell 7) | `ssh` | `ssh` |

**Почему WinRM остаётся Windows-к-Windows.** У PowerShell 7 на Linux/macOS нет
поддерживаемого WinRM-клиента (`Invoke-Command -ComputerName`, `Test-WSMan` и диск
`WSMan:` отсутствуют или зависят от заброшенного стека PSWSMan/OMI), а хранилище
учётных данных — это DPAPI, который есть только в Windows: вне Windows
`Export-Clixml` записывает пароль простым hex. Поэтому на Linux/macOS-контроллере
`Register-WinMeshCredential`, `Connect-WinMeshHost`, `Invoke-WinMeshCommand` и
команды области файрвола отказываются работать с WinRM-хостом с понятным
сообщением, а `Test-WinMeshHost` / `Test-WinMeshFleet` показывают его как
проваленную проверку `WinRM client`, не прерываясь, — ssh-хосты смешанного парка
всё равно проверяются.

**Контроллер на Linux или macOS.** Установите [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
и пользуйтесь модулем так же, как в Windows. Путь к конфигу, `$env:WINMESH_CONFIG`
и `~/.ssh/config` работают как обычно; `CredentialStore` принимает любой разделитель.

```bash
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
cp config/hosts.example.psd1 config/hosts.psd1     # хосты с Transport = 'ssh'
pwsh -c 'Import-Module ./winmesh.psd1; Test-WinMeshFleet'
```

**Цель на Linux или macOS.** Нужны SSH-сервер и PowerShell 7 — scriptblock
выполняется там в `pwsh`, и результаты по-прежнему приходят объектами. Задайте
хосту `SshShell = 'pwsh'`: значение по умолчанию `powershell` есть только в Windows.

```powershell
'linux-01' = @{
    Address   = '100.100.10.21'
    Transport = 'ssh'
    SshUser   = 'admin'
    SshShell  = 'pwsh'          # или полный путь, если PATH ssh-сессии его не видит
}
```

- **Linux:** установите `openssh-server` и [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux) из пакетов дистрибутива или Microsoft.
- **macOS:** включите *Удалённый вход* (Системные настройки → Основные → Общий доступ, или `sudo systemsetup -setremotelogin on`) и установите [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-macos).
- Неинтерактивная ssh-команда не читает login-профили, поэтому её `PATH` может отличаться от вашего терминала. Если winmesh сообщает, что PowerShell не найден, укажите в `SshShell` полный путь, который печатает `command -v pwsh` на цели.

У Linux/macOS-цели в `Test-WinMeshHost` нет проверки *full admin token*: обычный
вход там — это норма, а root получают через `sudo`. Строка *command runs* говорит,
что именно, — например, `linux-01 / admin (Linux), not root`.

---

## Настройка — шаг за шагом

### Шаг 0 · Установите модуль (контроллер)

```powershell
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
Import-Module .\winmesh.psd1
```

### Шаг 1 · Подготовьте каждую цель (выполняется НА цели, один раз, от администратора)

Цель становится доступной только после включения на ней WinRM, а для этого нужен **локальный администратор этой машины**. Удалённо обойти это невозможно: канала ещё не существует. Это единственный ручной шаг.

На **контроллере** сгенерируйте bootstrap-скрипт:

```powershell
New-WinMeshBootstrap -OutFile .\bootstrap.ps1
```

Скопируйте `bootstrap.ps1` на цель (RDP, флешка или GPO в домене) и запустите там **от имени администратора**. Скрипт:

1. включает PowerShell Remoting (`Enable-PSRemoting`);
2. сужает правило файрвола WinRM до ваших доверенных подсетей (см. [Выбор разрешённых подсетей](#выбор-разрешённых-подсетей));
3. выдаёт полный админ-токен локальным учётным записям в удалённых сессиях;
4. печатает данные о машине, нужные для конфига (имя компьютера, домен, точная строка логина).

Запомните напечатанное значение **LoginForCred** — оно понадобится на шаге 3.

> Bootstrap берёт `AllowedSubnets` из `config\hosts.psd1`. Если конфига ещё нет, он подставит `100.64.0.0/10` — сначала выполните шаг 2 или передайте `-AllowedSubnets` явно (см. [Выбор разрешённых подсетей](#выбор-разрешённых-подсетей)).
>
> Если цель уже доступна по WinRM или будет подключаться по SSH, пропустите этот шаг.

### Шаг 2 · Добавьте цель в конфиг (контроллер)

```powershell
Copy-Item .\config\hosts.example.psd1 .\config\hosts.psd1
notepad .\config\hosts.psd1
```

Заполните по одной записи на каждую машину:

```powershell
Hosts = @{
    'workstation-01' = @{
        Address    = '100.100.10.11'          # её адрес в оверлее/LAN или DNS-имя
        Credential = 'admin@workstation-01'   # любой id; используется на шаге 3
    }
}
```

### Шаг 3 · Сохраните учётные данные (контроллер)

```powershell
Register-WinMeshCredential -Id 'admin@workstation-01'
```

Появится запрос. Введите логин ровно в том виде, как его напечатал bootstrap:

- доменная машина → `DOMAIN\user`
- рабочая группа / отдельная машина → `COMPUTERNAME\user` (например, `workstation-01\admin`)

Пароль шифруется DPAPI — файл может прочитать только *ваша* учётная запись на *этом* контроллере. Если его скопировать в другое место, он бесполезен.

### Шаг 4 · Подготовьте контроллер (нужен админ, один раз)

```powershell
Connect-WinMeshHost -Name workstation-01
```

Команда запускает службу WinRM на контроллере и добавляет цель в `TrustedHosts` (нужно для аутентификации по IP). Выполняется один раз для каждого нового адреса цели.

### Шаг 5 · Проверьте

```powershell
Test-WinMeshHost -Name workstation-01
```

Ожидайте пять зелёных проверок: порт, WS-Management, учётные данные, команда выполняется, полный админ-токен.

### Шаг 6 · Пользуйтесь

```powershell
Invoke-WinMeshCommand workstation-01 { hostname; whoami }
Invoke-WinMeshCommand workstation-01 { param($p) Test-Path $p } -ArgumentList 'C:\Windows'
Test-WinMeshFleet          # проверить все хосты из конфига сразу
```

---

## Примеры использования

Всё ниже предполагает, что хост `workstation-01` настроен (шаги 1–5).

**Выполнить команду и прочитать результат.** `Invoke-WinMeshCommand` возвращает настоящие объекты, а не текст — передавайте их по конвейеру как обычно:

```powershell
Invoke-WinMeshCommand workstation-01 { Get-Service } |
    Where-Object Status -eq 'Running' |
    Measure-Object
```

**Передать аргументы.** Используйте `param()` в блоке и `-ArgumentList`:

```powershell
Invoke-WinMeshCommand workstation-01 {
    param($name, $days)
    Get-EventLog -LogName System -After (Get-Date).AddDays(-$days) -EntryType Error |
        Where-Object Source -like "*$name*"
} -ArgumentList 'disk', 7
```

**Сделать одно и то же на каждой машине парка.** Пройдитесь циклом по конфигу:

```powershell
$cfg = Get-WinMeshConfig
foreach ($name in $cfg.Hosts.Keys) {
    $free = Invoke-WinMeshCommand $name {
        (Get-PSDrive C).Free / 1GB
    }
    "{0,-20} {1,6:N1} GB free on C:" -f $name, $free
}
```

**Запускать скрипт только при здоровом канале.** `Test-WinMeshHost -Quiet` возвращает объект с полем `Ok` и ничего не печатает — удобно для автоматизации:

```powershell
if (-not (Test-WinMeshHost -Name workstation-01 -Quiet).Ok) {
    throw 'workstation-01 is unreachable — aborting'
}
# ... продолжаем, зная, что канал работает
```

**Проверять весь парк в запланированной задаче:**

```powershell
$down = (Test-WinMeshFleet -Quiet) | Where-Object { -not $_.Ok }
if ($down) {
    "$($down.Count) machine(s) down: $($down.Host -join ', ')" | Send-Alert   # ваш уведомитель
}
```

**Копировать файлы на хост или с него.** Для передачи файлов нужна живая сессия; откройте её с сохранёнными учётными данными:

```powershell
$cfg  = Get-WinMeshConfig
$h    = $cfg.Hosts['workstation-01']
$cred = Import-Clixml (Join-Path $cfg.Defaults.CredentialStore "$($h.Credential -replace '[^\w.@-]','_').cred.xml")

$s = New-PSSession -ComputerName $h.Address -Credential $cred
Copy-Item .\report.csv -Destination 'C:\Temp\' -ToSession $s
Copy-Item 'C:\Temp\log.txt' -Destination .\ -FromSession $s
Remove-PSSession $s
```

**Использовать другой файл конфигурации** (например, staging и production):

```powershell
$env:WINMESH_CONFIG = 'C:\fleets\staging.psd1'
Test-WinMeshFleet
# или для отдельного вызова:
Invoke-WinMeshCommand nas-lan { hostname } -Config (Get-WinMeshConfig -Path .\lan.psd1)
```

---

## SSH вместо WinRM

WinRM используется по умолчанию: он родной для Windows и возвращает объекты. SSH лучше
в двух случаях: машины уже связаны оверлейной VPN со своим SSH-сервером (у NetBird он
есть) либо WinRM вам недоступен — заблокирован политикой или порт закрыт и открыть его
нельзя.

Переключение хоста — одно поле. В ваших скриптах больше ничего не меняется:

```powershell
Hosts = @{
    'workstation-02' = @{
        Address   = 'workstation-02'      # имя в оверлее или IP
        Transport = 'ssh'
        SshUser   = 'Administrator'
    }
}
```

```powershell
Test-WinMeshHost    -Name workstation-02
Invoke-WinMeshCommand workstation-02 { Get-Service } | Where-Object Status -eq 'Running'
```

**Поля `Credential` нет, и шага `Connect-WinMeshHost` нет.** По ssh клиент
аутентифицируется сам — ключом, агентом или, в оверлейной сети, идентичностью пира:
SSH-сервер NetBird аутентифицирует *пира*, поэтому машине, уже входящей в вашу сеть,
ключ вообще не нужен. Шаги 1, 3 и 4 настройки (bootstrap, учётные данные, `Connect-WinMeshHost`) к ней просто не относятся.

Объекты вы по-прежнему получаете, а не текст. Scriptblock и его аргументы упаковываются
в base64 и передаются через `powershell -EncodedCommand` (`pwsh` на Linux/macOS), а результат сериализуется на
удалённой стороне тем же движком CliXml, что использует remoting, и здесь восстанавливается.

**Опции SSH** — для хоста или в `Defaults`:

| Ключ | По умолчанию | Значение |
|---|---|---|
| `SshUser` | *(пусто)* | удалённая учётная запись; пусто — пусть решает `ssh` |
| `SshPort` | `22` | |
| `SshShell` | `powershell` | `powershell` (5.1, в Windows есть всегда) или `pwsh`; Linux/macOS-целям нужен `pwsh` или полный путь к нему |
| `SshTimeout` | `15` | секунды, превращается в `ConnectTimeout` |
| `SshOptions` | `@()` | дополнительные опции `-o`, например `@('StrictHostKeyChecking=accept-new')` |

Всё более специфичное — jump-хосты, ключи для отдельных хостов, алиасы — относится в
ваш `~/.ssh/config`, который `ssh` читает как обычно. winmesh это не дублирует.

### Если вы используете оверлейную VPN

`AllowedSubnets` (применяется bootstrap-скриптом WinRM) действует только на WinRM. Если
вы обслуживаете SSH через Windows OpenSSH, а не через собственный сервер VPN, сузьте
порт 22 самостоятельно:

```powershell
Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -RemoteAddress '100.64.0.0/10'
```

---

## Добавление машин

Повторите **шаги 1–5** для каждой новой цели. В повседневной работе помнить нужно только короткое имя хоста.

```powershell
Test-WinMeshFleet          # состояние всего парка
```

---

## Выбор разрешённых подсетей

Bootstrap сужает порт WinRM до `Defaults.AllowedSubnets` из вашего конфига. Выберите значение, соответствующее тому, как связаны ваши машины:

| Сеть | AllowedSubnets |
|---|---|
| Tailscale / NetBird | `@('100.64.0.0/10')` — диапазон CGNAT (по умолчанию) |
| ZeroTier | подсеть вашей сети, например `@('10.147.17.0/24')` |
| Обычная LAN | например `@('192.168.1.0/24')` |
| Несколько сразу | `@('192.168.1.0/24','100.64.0.0/10')` |
| Не сужать (доверенная LAN) | `@()` |

Можно также передать значение напрямую, игнорируя умолчание из конфига:

```powershell
New-WinMeshBootstrap -AllowedSubnets '192.168.1.0/24' -OutFile .\bootstrap-lan.ps1
```

---

## Просмотр и изменение того, каким сетям разрешено подключаться

`AllowedSubnets` — единственное место, которое решает, каким исходным сетям разрешён
доступ к порту WinRM хоста. Оно применяется при bootstrap; посмотреть или применить
его заново позже можно, не вспоминая команды файрвола:

```powershell
Get-WinMeshFirewallScope -Name workstation-01            # текущая область + совпадает ли она с конфигом
Set-WinMeshFirewallScope -Name workstation-01 -WhatIf    # предпросмотр
Set-WinMeshFirewallScope -Name workstation-01            # применить AllowedSubnets из конфига
```

`Set-WinMeshFirewallScope` откажется работать, если сужение отрежет вашу собственную
живую сессию (ни один подключённый источник не попадает в новые диапазоны) — передавайте
`-Force` только сидя за консолью. Хост может переопределить глобальное значение своим
`AllowedSubnets` (например, машина, доступная через другой оверлей):

```powershell
Hosts = @{
    'nas-zt' = @{
        Address        = '10.147.17.20'
        Credential     = 'admin@nas-zt'
        AllowedSubnets = @('10.147.17.0/24')   # только для этого хоста; переопределяет Defaults
    }
}
```

## Подключение из другой сети

Для доступа к хосту должны выполняться оба условия: источник должен уметь
*маршрутизироваться* до машины, а его адрес — попадать в `AllowedSubnets`.

- **Вы физически в другом месте (офис, отель, дом).** Менять ничего не нужно —
  Tailscale/NetBird работает поверх любого доступного интернета, вы остаётесь в
  оверлее, и хост достижим по своему оверлейному адресу. Обычный случай.
- **Добавить ещё один оверлей (например, ZeroTier).** Подключите к нему обе машины,
  добавьте его подсеть в `AllowedSubnets` (ZeroTier не входит в диапазон CGNAT
  `100.64.0.0/10`), выполните `Set-WinMeshFirewallScope` и добавьте новый адрес хоста
  в `TrustedHosts` на контроллере.
- **Конкретная доверенная LAN без оверлея.** Добавьте эту подсеть — как можно уже
  (`/24` или один `/32`), помня, что после этого любой в ней сможет достучаться до WinRM.

## Заметки по безопасности

- **Границей лучше считать членство в оверлее.** Чтобы достучаться до хоста, нужно быть
  в его оверлее, а для этого нужна ваша аутентификация в Tailscale/NetBird. Диапазон
  файрвола — второй слой, отсекающий физическую LAN и публичные адреса.
- **Не открывайте WinRM для всей корпоративной или публичной подсети.** Вместо этого
  заходите на хост через оверлей из той сети; оверлей туннелируется через любой интернет.
- **`AllowedSubnets` заменяет, а не дополняет.** Перечисляйте сразу все нужные сети;
  пустой список (`@()`) означает «не сужать» (`Any`) — только для доверенной LAN.
- **WinRM 5985 шифруется Negotiate/Kerberos**, это не открытый текст, но всё равно
  админ-канал — держите исходный диапазон настолько узким, насколько позволяет настройка.
- **Профиль правила по-прежнему важен.** Оно применяется к Domain+Private; если
  оверлейный адаптер отнесён к Public, правило его не покроет. Держите оверлейные
  адаптеры Private либо расширьте профиль правила после того, как задан исходный диапазон.

## Команды

| Команда | Что делает | Где выполняется | Админ |
|---|---|---|---|
| `Get-WinMeshConfig` | загрузить и проверить конфиг | контроллер | нет |
| `Register-WinMeshCredential` | сохранить учётные данные цели (DPAPI) — *только winrm, Windows-контроллер* | контроллер | нет |
| `Connect-WinMeshHost` | настроить клиент: WinRM + TrustedHosts — *только winrm, Windows-контроллер* | контроллер | **да** |
| `Test-WinMeshHost` / `Test-WinMeshFleet` | проверить канал | контроллер | нет |
| `Invoke-WinMeshCommand` | выполнить команду на хосте | контроллер | нет |
| `New-WinMeshBootstrap` | сгенерировать скрипт подготовки цели | контроллер | нет |
| *(bootstrap на цели)* | включить WinRM, сузить порт — *только winrm* | **цель** | **да** |

---

## Справочник по конфигу

`config/hosts.psd1` — файл данных PowerShell (`.psd1`, не YAML: во встроенном Windows PowerShell 5.1 нет парсера YAML, а `.psd1` разбирается безопасно, без выполнения кода).

```powershell
@{
    Defaults = @{
        Transport       = 'winrm'                  # 'winrm' или 'ssh'
        CredentialStore = '~\.winmesh\creds'       # где лежат зашифрованные учётные данные
        AllowedSubnets  = @('100.64.0.0/10')       # подсети, которым разрешён доступ к WinRM
    }
    Hosts = @{
        'workstation-01' = @{
            Address    = '100.100.10.11'
            Credential = 'admin@workstation-01'
            Note       = 'необязательная заметка'
        }
        'workstation-02' = @{
            Address    = 'workstation-02'          # тот же парк, но ssh вместо WinRM
            Transport  = 'ssh'
            SshUser    = 'Administrator'           # без Credential: см. «SSH вместо WinRM»
        }
    }
}
```

Указать winmesh другой конфиг можно через `$env:WINMESH_CONFIG` или параметры `-Config`/`-Path`.

---

## Чего он намеренно не делает

- **Не обходит первый админ-шаг на цели.** В принципе невозможно; модуль лишь генерирует скрипт.
- **Не переносит учётные данные между контроллерами.** Файл DPAPI расшифровывается только там, где создан. Хранилище локально намеренно.
- **Не управляет SSH-ключами и паролями.** По ssh аутентификация — это то, о чём договорится ваш `ssh`-клиент: ключ, агент или идентичность пира оверлейной сети. winmesh для ssh-пути никогда не запрашивает, не хранит и не пересылает секреты.
- **Не устанавливает SSH-сервер за вас.** В отличие от WinRM, bootstrap для него нет: либо оверлейная VPN уже предоставляет сервер (NetBird), либо вы один раз сами ставите OpenSSH-сервер (а на Linux/macOS-цель — ещё и PowerShell 7).

---

## Встроенные грабли

Собрано из реальной отладки — каждая стоила времени:

- **`Set-Item WSMan:...` винит удалённый хост, когда на самом деле проблема в локальной службе WinRM.** Если она остановлена, обращение к диску `WSMan:` падает с ошибкой о недоступности цели. `Connect-WinMeshHost` сначала запускает службу.
- **`Enable-PSRemoting` открывает порт с `RemoteAddress=Any`.** Сужение до доверенных подсетей — обязательный шаг, встроенный в bootstrap. Пропустите его — и порт окажется открыт шире, чем вы думаете.
- **TrustedHosts нужен даже в домене** при подключении по IP: Kerberos не применяется, и аутентификация откатывается на NTLM.
- **Скрипты — UTF-8 с BOM.** Без BOM Windows PowerShell 5.1 читает не-ASCII как ANSI и не может разобрать файл.

Именно про SSH:

- **`-EncodedCommand` ждёт base64 от UTF-16LE, а не UTF-8.** Закодируйте нагрузку как UTF-8 — и PowerShell либо прочитает мусор, либо откажется разбирать. Поэтому транспорт кодирует через `[Text.Encoding]::Unicode`.
- **Нельзя вручную заквотировать команду для удалённой оболочки.** Windows OpenSSH по умолчанию запускает `cmd.exe`, а PowerShell — если изменён `DefaultShell`, и они по-разному трактуют кавычки. Один base64-токен вообще снимает вопрос, и одна и та же строка работает в любой оболочке.
- **`ConvertTo-CliXml` не существует в Windows PowerShell 5.1.** Используйте `[System.Management.Automation.PSSerializer]::Serialize()` / `::Deserialize()`, которые есть и в 5.1, и в 7.
- **В оверлейной сети порт 22 может отвечать не тот сервер, что вы настроили.** NetBird поставляет собственный SSH-сервер и занимает порт на оверлейном адресе, так что настроенная вами служба Windows OpenSSH может простаивать. `Test-WinMeshHost` печатает SSH-баннер именно поэтому — читайте его.
- **Сессия, открытая SSH-сервером оверлея, может не нести полный админ-токен,** даже для учётки администратора. `Test-WinMeshHost` сообщает об этом отдельной проверкой, а не даёт проявиться позже запутанным access-denied.

На **неанглийской Windows** или на доменной машине с недоступным DC:

- **`IsInRole('Administrators')` ненадёжен на локализованной Windows — может
  бросить исключение или вернуть неверное `$false`.** Встроенная группа может быть
  локализована (`BUILTIN\Администраторы` на русской установке), а строковая перегрузка
  разрешает по *имени*. Измерено в обе стороны: на русской установке с локализованной
  группой английский литерал вызвал `MethodInvocationException`; на другой машине
  неразрешимое имя просто вернуло `$false` (и в 5.1, и в 7). Локализованное имя,
  перечисление `[WindowsBuiltInRole]::Administrator` и сырой SID вернули верный ответ.
  В любом случае исправный канал отображается как `command runs: False` — исключение
  роняет весь вызов изнутри удалённого scriptblock, а неверное `$false` просто неверно.
  Всегда используйте перечисление или `S-1-5-32-544`, но не английское имя.
- **`icacls` и `Add-LocalGroupMember` ломаются так же, но по другой причине.**
  Передача имени `"Administrators"` заставляет Windows его разрешать, а на доменной
  машине этот запрос уходит на контроллер домена — так что при недоступном DC вы
  получаете *«could not establish trust relationship with the primary domain»* при
  совершенно локальной операции. Известным SID поиск не нужен:
  `icacls f /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F"` и
  `Add-LocalGroupMember -Group (Get-LocalGroup -SID S-1-5-32-544)`.
- **Доменная учётка может пройти publickey-аутентификацию и всё равно не открыть сессию.**
  В логе OpenSSH видно `Accepted publickey for <user>`, затем клиент получает
  `Connection reset by peer` — и **дальше ничего не логируется**, потому что сбой
  происходит за пределами логирования sshd. Вход по ключу строит токен пользователя
  через S4U, а для доменной учётки это требует живого DC; ваша интерактивная сессия
  работает лишь потому, что использует кэшированные учётные данные, недоступные sshd.
  Исправление — не в настройке sshd: используйте **локальную** учётную запись. На
  доменной машине `Get-LocalGroupMember -SID S-1-5-32-544` обычно показывает такую.
- **Вставка ключа в консоль может его разорвать, а sshd вам об этом не скажет.**
  Длинная строка `$key = 'ssh-ed25519 …'` переносится по ширине консоли, перевод
  строки оказывается *внутри* строки, и `authorized_keys` получает два фрагмента.
  Некорректные строки молча пропускаются, так что симптом — обычный
  `Permission denied` при выглядящем корректно файле. Проверяйте длинами, а не на глаз —
  валидная строка ed25519 — это одна строка примерно в 110 символов:
  `Get-Content $f | ForEach-Object { $_.Length }`.
- **Админские ключи лежат совсем в другом месте.** Для любой учётки из группы
  администраторов стандартный `sshd_config` содержит
  `Match Group administrators` → `__PROGRAMDATA__/ssh/administrators_authorized_keys`.
  Ключ, положенный в `C:\Users\<name>\.ssh\authorized_keys`, игнорируется — как и
  этот общий файл, если его ACL шире, чем SYSTEM + Administrators.
- **Правило, стоящее за первыми двумя: на локализованной Windows всё, что
  разрешается или форматируется через системную локаль, — ошибка переносимости.**
  За час на одной машине нашлись два примера — `IsInRole('Administrators')`,
  бросающий исключение, и отдельный CLI, у которого `toLocaleString()` печатал `1 401`
  там, где `en-US` печатает `1,401`, ломая собственный разбор вывода. Оба выглядят
  корректно на английской машине, и ни один не ловится прогоном тестов под Linux.
  Фиксируйте локаль (`toLocaleString('en-US')`) и обращайтесь к принципалам по SID.

### Linux и macOS

- **`$IsWindows` не существует в Windows PowerShell 5.1.** Там он равен `$null`,
  и `if ($IsWindows)` молча считает любую машину с 5.1 не-Windows. Scriptblock,
  который может выполниться на цели с 5.1, проверяет `$env:OS -eq 'Windows_NT'`.
- **`WindowsIdentity` вне Windows бросает исключение.** Проверка админа, работающая
  на любой Windows-цели, на Linux/macOS даёт `PlatformNotSupportedException`; там
  вопрос решает `id -u` — и «не root» это норма, а не сбой.
- **Обратный слэш в Linux/macOS — обычный символ имени файла.** `Join-Path $dir 'config\hosts.psd1'`
  даёт один файл с именем `config\hosts.psd1`. Соединяйте сегменты по отдельности.
- **Вне Windows `Export-Clixml` не шифрует учётные данные.** Пароль хранится как
  hex от UTF-16 — его прочитает любой, кто может прочитать файл. Поэтому хранилище
  учётных данных (а с ним и WinRM) — только для Windows.

### Управление целью из скрипта

- **Не встраивайте не-ASCII литералы в передаваемый скрипт.** `.ps1` с кириллицей
  после `scp` оказался испорчен, и PowerShell 5.1 не смог его разобрать — это тот же
  случай с BOM, пришедший другим путём. Получайте локализованную строку во время
  выполнения — тогда литерал вообще не нужен:
  `([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value`.
- **Не квотируйте вручную и разовую команду.** Транспорт избегает этого упаковкой в
  base64 (см. выше), но в консоли та же ловушка срабатывает: разовая
  `powershell -Command "... try { } catch { } ..."` через `ssh` потеряла фигурные
  скобки на двух слоях квотирования и упала с `MissingCatchOrFinally`. Запишите файл и
  запустите `powershell -File` — ровно так, как фактически делает транспорт.
- **Большая загрузка, запущенная *на* цели, может не удаться там, где отправка с
  контроллера проходит.** `Invoke-WebRequest` прервался с `IOException` на середине
  файла в 100 МБ, а возобновление через `curl.exe -C -` не смогло даже открыть
  частичный файл в каталоге, доказанно доступном для записи за минуты до этого. `scp`
  тех же байтов с контроллера сработал с первого раза. Причина не установлена —
  защитное ПО очевидный подозреваемый, но это не подтверждено. Полезно знать как
  обходной путь, а не как объяснение.

---

## Требования

Windows PowerShell 5.1 или PowerShell 7 в Windows; PowerShell 7 в Linux и macOS (см. [Платформы](#платформы)). Сеть, дающая машинам стабильные, взаимно достижимые адреса — оверлей (Tailscale, NetBird, ZeroTier) или обычная LAN. Права администратора нужны только для `Connect-WinMeshHost` на контроллере и bootstrap на каждой цели — к ssh-хостам ни то ни другое не относится. Для ssh-транспорта нужны `ssh`-клиент на контроллере (встроен в Windows 10/11, Server 2019+, Linux и macOS) и SSH-сервер на цели — а если цель на Linux или macOS, то и PowerShell 7 на ней.

## Участие в разработке

Вклад приветствуется — область, соглашения и способы тестирования описаны в [CONTRIBUTING.md](CONTRIBUTING.md). Проект намеренно остаётся маленьким и без зависимостей.

## Лицензия

MIT — см. [LICENSE](LICENSE).
