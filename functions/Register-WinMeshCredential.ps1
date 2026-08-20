<#
.SYNOPSIS
    Saves a machine's credentials to an encrypted file (DPAPI).
.DESCRIPTION
    The password is encrypted with Export-Clixml/DPAPI: the file can only be
    decrypted by the same account on the same machine where it was created.
    Copied elsewhere it is useless — so the store is inherently local and must
    never end up in git.

    For a non-domain target, give the username as COMPUTERNAME\user — the part
    before the backslash directs authentication to that machine's local database.
.PARAMETER Id
    Credential id. The Credential field in the config refers to it.
.EXAMPLE
    Register-WinMeshCredential -Id 'admin@workstation-01'
    # a login/password prompt appears; login: workstation-01\admin
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
        # the GUI prompt does not always appear (e.g. embedded hosts) — fall back to console input
        $Credential = Get-Credential -Message "Credentials for '$Id' (login like COMPUTER\user)"
        if (-not $Credential) {
            $user = Read-Host 'Login (COMPUTER\user)'
            $pass = Read-Host 'Password' -AsSecureString
            $Credential = New-Object System.Management.Automation.PSCredential($user, $pass)
        }
    }

    $file = Join-Path $Store ((($Id -replace '[^\w.@-]', '_')) + '.cred.xml')
    $Credential | Export-Clixml -LiteralPath $file
    Write-Host "Saved: $file  (user $($Credential.UserName))" -ForegroundColor Green
    Write-Host 'The file is DPAPI-encrypted — readable only by this account on this machine.' -ForegroundColor DarkGray
}

# Internal resolver — not exported.
function Get-WinMeshCredential {
    param([Parameter(Mandatory)] [string]$Id, [Parameter(Mandatory)] [string]$Store)
    $file = Join-Path $Store ((($Id -replace '[^\w.@-]', '_')) + '.cred.xml')
    if (-not (Test-Path -LiteralPath $file)) {
        throw "No credential '$Id'. Create it: Register-WinMeshCredential -Id '$Id'"
    }
    Import-Clixml -LiteralPath $file
}
