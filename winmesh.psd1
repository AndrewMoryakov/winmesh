@{
    RootModule        = 'winmesh.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b8f1e6a2-3c4d-4e5f-9a0b-1c2d3e4f5a6b'
    Author            = 'yourname'
    Description       = 'Тонкий opinionated-слой для связывания Windows-машин по WinRM: адресация по имени из конфига, проверка канала, генератор bootstrap. Работает поверх любой сети со стабильными адресами — оверлейной (Tailscale, NetBird, ZeroTier) или локальной. Только Windows.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-WinMeshConfig',
        'Register-WinMeshCredential',
        'Connect-WinMeshHost',
        'Invoke-WinMeshCommand',
        'Test-WinMeshHost',
        'Test-WinMeshFleet',
        'New-WinMeshBootstrap'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            LicenseUri = 'https://github.com/AndrewMoryakov/winmesh/blob/main/LICENSE'
            ProjectUri = 'https://github.com/AndrewMoryakov/winmesh'
            Tags       = @('Windows', 'WinRM', 'PSRemoting', 'remote-management', 'mesh-vpn', 'Tailscale', 'NetBird', 'ZeroTier', 'LAN')
        }
    }
}
