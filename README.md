# winmesh

[![License: MIT](https://img.shields.io/badge/License-MIT-informational.svg)](LICENSE)
[![PowerShell 5.1+ | 7](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207-5391FE.svg?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-0078D6.svg?logo=windows&logoColor=white)](https://github.com/AndrewMoryakov/winmesh)
[![Transport: WinRM](https://img.shields.io/badge/Transport-WinRM-2E7D57.svg)](https://learn.microsoft.com/windows/win32/winrm/portal)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](winmesh.psd1)

Тонкий слой для связывания Windows-машин по PowerShell Remoting. Называешь машину по имени — выполняешь на ней команды. Только Windows.

Не привязан к конкретной сети. Машинам нужны лишь стабильные, взаимно достижимые адреса — их даёт оверлейная сеть (**Tailscale, NetBird, ZeroTier**), обычная **локальная сеть** или что угодно ещё. winmesh про адреса и WinRM, а не про способ их получить.

Это не новый протокол. Под капотом — штатные WinRM и `Invoke-Command`. Ценность в собранном мнении: адресация по имени из конфига, суженный до доверенных подсетей брандмауэр, локальное хранилище секретов, проверка канала одной командой и набор ловушек, которые иначе выясняются на своей шкуре. Для парка в несколько машин, где Ansible — из пушки по воробьям.

## Быстрый старт

```powershell
Import-Module .\winmesh.psd1

# 1. конфиг парка
Copy-Item .\config\hosts.example.psd1 .\config\hosts.psd1
#    впишите свои машины: короткое имя, адрес (оверлей/LAN/DNS), ид учётки

# 2. учётные данные (шифруются DPAPI, лежат вне git)
Register-WinMeshCredential -Id 'admin@workstation-01'   # логин: workstation-01\admin

# 3. подготовить эту (управляющую) машину — нужен админ
Connect-WinMeshHost -Name workstation-01

# 4. проверить канал
Test-WinMeshHost -Name workstation-01

# 5. работать
Invoke-WinMeshCommand workstation-01 { hostname; whoami }
Test-WinMeshFleet
```

## Новая машина, у которой WinRM ещё выключен

Здесь вступает проблема курицы и яйца: включить удалённое управление нужно **администратором на самой машине** — удалённо нельзя, канала ещё нет. Конфигом это не обходится. Поэтому:

```powershell
# на управляющей — сгенерировать скрипт подготовки
New-WinMeshBootstrap -OutFile .\bootstrap-newpc.ps1
```

Скопируйте `bootstrap-newpc.ps1` на новую машину (RDP, флешка, в домене — GPO) и запустите там **от администратора**. Он включит WinRM, сузит порт до разрешённых подсетей, разрешит админ-токен и напечатает факты для конфига. Дальше — обычные шаги 1–5.

## Как задать разрешённые подсети под свою сеть

Порт WinRM сужается до `Defaults.AllowedSubnets` из конфига. Значение зависит от того, как связаны машины:

| Сеть | AllowedSubnets |
|---|---|
| Tailscale / NetBird | `@('100.64.0.0/10')` — диапазон CGNAT (по умолчанию) |
| ZeroTier | подсеть вашей сети, например `@('10.147.17.0/24')` |
| Обычная локальная сеть | например `@('192.168.1.0/24')` |
| Несколько сразу | `@('192.168.1.0/24','100.64.0.0/10')` |
| Не сужать (доверенный LAN) | `@()` |

То же значение можно передать напрямую: `New-WinMeshBootstrap -AllowedSubnets '192.168.1.0/24'`.

## Команды

| Команда | Что делает | Где | Админ |
|---|---|---|---|
| `Get-WinMeshConfig` | загрузить и проверить конфиг | управляющая | нет |
| `Register-WinMeshCredential` | сохранить учётку машины (DPAPI) | управляющая | нет |
| `Connect-WinMeshHost` | настроить клиента: WinRM + TrustedHosts | управляющая | **да** |
| `Test-WinMeshHost` / `Test-WinMeshFleet` | проверить канал | управляющая | нет |
| `Invoke-WinMeshCommand` | выполнить команду на машине | управляющая | нет |
| `New-WinMeshBootstrap` | сгенерировать скрипт подготовки цели | управляющая | нет |
| *(bootstrap на цели)* | включить WinRM, сузить порт | **целевая** | **да** |

## Что осознанно не делает

- **Не обходит первичный админ на цели.** Это невозможно в принципе; фреймворк лишь генерирует скрипт.
- **Не переносит учётные данные между управляющими машинами.** DPAPI-файл расшифровывается только там, где создан. Хранилище локально.
- **Не поддерживает не-Windows и SSH-транспорт.** Пока только WinRM. Задел под `Transport` в конфиге есть, реализации нет.

## Ловушки, кодифицированные здесь

Собраны из реальной отладки, каждая стоила времени:

- **`Set-Item WSMan:...` жалуется на удалённый узел, когда виновата локальная служба WinRM.** Если она остановлена, обращение к диску `WSMan:` падает с ошибкой про недоступность цели. `Connect-WinMeshHost` сначала поднимает службу.
- **`Enable-PSRemoting` открывает порт с `RemoteAddress=Any`.** Сужение до доверенных подсетей — обязательный шаг, встроен в bootstrap. Однажды его забыли, и порт был открыт шире, чем думали.
- **TrustedHosts нужен даже в домене**, если подключаться по IP: Kerberos неприменим, аутентификация уходит в NTLM.
- **Скрипты в UTF-8 с BOM.** Без BOM Windows PowerShell 5.1 читает кириллицу как ANSI и не парсит файл.

## Требования

Windows PowerShell 5.1 или PowerShell 7. Сеть, дающая машинам стабильные взаимно достижимые адреса — оверлейная (Tailscale, NetBird, ZeroTier) или обычная локальная. Права администратора — только на два шага: `Connect-WinMeshHost` на управляющей и bootstrap на целевой.
