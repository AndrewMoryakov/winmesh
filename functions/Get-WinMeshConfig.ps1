<#
.SYNOPSIS
    Загружает и проверяет конфиг парка машин.
.DESCRIPTION
    Конфиг — файл .psd1 (не YAML: у Windows PowerShell 5.1 нет встроенного парсера
    YAML, а .psd1 читается безопасно через Import-PowerShellDataFile без выполнения кода).
    Путь по умолчанию: $env:WINMESH_CONFIG, иначе config\hosts.psd1 рядом с модулем.
.EXAMPLE
    $cfg = Get-WinMeshConfig
    $cfg.Hosts.Keys
#>
function Get-WinMeshConfig {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if (-not $Path) {
        $Path = $env:WINMESH_CONFIG
    }
    if (-not $Path) {
        $Path = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\hosts.psd1'
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Конфиг не найден: $Path. Скопируйте config\hosts.example.psd1 в config\hosts.psd1 и впишите свои машины."
    }

    $cfg = Import-PowerShellDataFile -LiteralPath $Path

    if (-not $cfg.Hosts -or $cfg.Hosts.Count -eq 0) {
        throw "В конфиге $Path нет ни одной машины (секция Hosts пуста)."
    }

    # значения по умолчанию
    $defaults = @{
        Transport       = 'winrm'
        CredentialStore = (Join-Path $env:USERPROFILE '.winmesh\creds')
        # Подсети, которым разрешён порт WinRM (сужение брандмауэра в bootstrap).
        # По умолчанию — диапазон CGNAT 100.64.0.0/10: его используют и Tailscale,
        # и NetBird. Для ZeroTier, обычной локальной сети или своей адресации
        # укажите свои подсети. Пустой список = не сужать (например, доверенный LAN).
        AllowedSubnets  = @('100.64.0.0/10')
    }
    if ($cfg.Defaults) {
        foreach ($k in $cfg.Defaults.Keys) { $defaults[$k] = $cfg.Defaults[$k] }
    }
    # Обратная совместимость со старым ключом TailscaleCidr.
    if ($cfg.Defaults -and $cfg.Defaults.TailscaleCidr -and -not ($cfg.Defaults.Keys -contains 'AllowedSubnets')) {
        $defaults.AllowedSubnets = @($cfg.Defaults.TailscaleCidr)
    }
    $defaults.AllowedSubnets = @($defaults.AllowedSubnets)

    # раскрыть ~ в пути к хранилищу
    $defaults.CredentialStore = $defaults.CredentialStore -replace '^~', $env:USERPROFILE

    # проверка каждой машины
    foreach ($name in $cfg.Hosts.Keys) {
        $h = $cfg.Hosts[$name]
        if (-not $h.Address)    { throw "Машина '$name': не задан Address (IP в оверлейной сети/LAN или DNS-имя)." }
        if (-not $h.Credential) { throw "Машина '$name': не задан Credential (идентификатор записи в хранилище)." }
        if (-not $h.Transport)  { $h.Transport = $defaults.Transport }
        if ($h.Transport -ne 'winrm') {
            throw "Машина '$name': транспорт '$($h.Transport)' пока не поддерживается. В этой версии только winrm."
        }
    }

    [pscustomobject]@{
        Path     = (Resolve-Path -LiteralPath $Path).Path
        Defaults = $defaults
        Hosts    = $cfg.Hosts
    }
}
