<#
.SYNOPSIS
    Сохраняет учётные данные машины в зашифрованный файл (DPAPI).
.DESCRIPTION
    Пароль шифруется через Export-Clixml/DPAPI: файл расшифровывается ТОЛЬКО той
    учётной записью и ТОЛЬКО на той машине, где создан. Скопированный в другое
    место он бесполезен — поэтому хранилище по своей природе локально и в git
    попадать не должно.

    Имя пользователя для НЕ доменной целевой машины задаётся как
    ИМЯ-КОМПЬЮТЕРА\логин — часть до \ направляет проверку в локальную базу той машины.
.PARAMETER Id
    Идентификатор записи. На него ссылается поле Credential в конфиге.
.EXAMPLE
    Register-WinMeshCredential -Id 'admin@workstation-01'
    # откроется запрос логина/пароля; логин: workstation-01\admin
#>
function Register-WinMeshCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Id,
        [pscredential]$Credential,
        [string]$Store
    )

    if (-not $Store) {
        $cfg = Get-WinMeshConfig
        $Store = $cfg.Defaults.CredentialStore
    }
    if (-not (Test-Path -LiteralPath $Store)) {
        New-Item -ItemType Directory -Path $Store -Force | Out-Null
    }

    if (-not $Credential) {
        # GUI-окно всплывает не всегда (встроенные оболочки) — тогда просим в консоли
        $Credential = Get-Credential -Message "Учётные данные для '$Id' (логин вида КОМП\пользователь)"
        if (-not $Credential) {
            $user = Read-Host 'Логин (КОМП\пользователь)'
            $pass = Read-Host 'Пароль' -AsSecureString
            $Credential = New-Object System.Management.Automation.PSCredential($user, $pass)
        }
    }

    $file = Join-Path $Store ((($Id -replace '[^\w.@-]', '_')) + '.cred.xml')
    $Credential | Export-Clixml -LiteralPath $file
    Write-Host "Сохранено: $file  (пользователь $($Credential.UserName))" -ForegroundColor Green
    Write-Host 'Файл зашифрован DPAPI — читается только этой учёткой на этой машине.' -ForegroundColor DarkGray
}

# Внутренний резолвер — не экспортируется.
function Get-WinMeshCredential {
    param([Parameter(Mandatory)] [string]$Id, [Parameter(Mandatory)] [string]$Store)
    $file = Join-Path $Store ((($Id -replace '[^\w.@-]', '_')) + '.cred.xml')
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Нет учётных данных '$Id'. Создайте: Register-WinMeshCredential -Id '$Id'"
    }
    Import-Clixml -LiteralPath $file
}
