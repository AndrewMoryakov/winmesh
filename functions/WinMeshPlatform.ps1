<#
.SYNOPSIS
    Platform helpers — not exported.
.DESCRIPTION
    The controller may be Windows, Linux or macOS. The ssh transport works from
    all three; WinRM needs a Windows controller:

      * PowerShell 7 on Linux/macOS has no supported WinRM client — Invoke-Command
        -ComputerName, Test-WSMan and the WSMan: drive are either absent or depend
        on the unmaintained PSWSMan/OMI stack;
      * the credential store is DPAPI, which exists only on Windows. Export-Clixml
        of a PSCredential on Linux/macOS writes the password unencrypted.

    $IsWindows is not used on purpose: it does not exist in Windows PowerShell 5.1,
    where it reads as $null and would classify every 5.1 machine as non-Windows.
#>

function Test-WinMeshWindows {
    $env:OS -eq 'Windows_NT'
}

# Throws a clear error when a WinRM-only operation runs on a non-Windows controller.
function Assert-WinMeshWinRMController {
    param([string]$What = 'The WinRM transport')
    if (-not (Test-WinMeshWindows)) {
        throw "$What needs a Windows controller: PowerShell on Linux/macOS has no supported WinRM client, and the DPAPI credential store exists only on Windows. Use Transport = 'ssh' for this host."
    }
}
