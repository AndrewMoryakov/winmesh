<#
.SYNOPSIS
    SSH transport internals — not exported.
.DESCRIPTION
    Runs a scriptblock on a target over `ssh` and brings real objects back,
    keeping the same contract as the WinRM path (Invoke-Command returns objects,
    not text).

    Three problems have to be solved to make text-only SSH behave like remoting;
    each is handled below, and each is a gotcha in its own right:

      1. Quoting. The remote shell behind Windows OpenSSH is cmd.exe by default,
         but may be PowerShell if DefaultShell was changed. Nothing that survives
         both reliably can be written by hand. So the payload travels as a single
         base64 token in `powershell -EncodedCommand`, which both shells pass
         through untouched.
      2. Encoding. -EncodedCommand expects base64 of UTF-16LE, not UTF-8. Encode
         the payload as UTF-8 and PowerShell reads garbage or refuses to parse.
      3. Objects. The channel carries text, so the result is serialized on the
         far side with PSSerializer (the CliXml engine remoting itself uses) and
         rehydrated here. ConvertTo-CliXml does not exist in Windows PowerShell
         5.1 — PSSerializer does, in both 5.1 and 7.

    Arguments and the scriptblock body are themselves base64 inside the payload,
    so no quoting of user content is ever needed.
#>

# Marker lines the remote payload prints. Anything else the remote writes
# (Write-Host, native command output) is passed through to the caller's host.
$script:WinMeshSshOk  = '@@WINMESH-OK@@'
$script:WinMeshSshErr = '@@WINMESH-ERR@@'

function ConvertTo-WinMeshB64 {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function ConvertFrom-WinMeshB64 {
    param([Parameter(Mandatory)] [string]$B64)
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64))
}

# Builds the script that will run on the target.
function New-WinMeshSshPayload {
    param(
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList
    )

    $sbB64   = ConvertTo-WinMeshB64 -Text $ScriptBlock.ToString()
    # No args must mean no positional argument, not an explicit $null (that would
    # override a scriptblock's defaulted parameter). Normalise null to an empty list.
    $argList = if ($null -eq $ArgumentList) { @() } else { @($ArgumentList) }
    $argsB64 = ConvertTo-WinMeshB64 -Text ([System.Management.Automation.PSSerializer]::Serialize($argList))

    @"
`$ErrorActionPreference = 'Stop'
try {
    `$__args = [System.Management.Automation.PSSerializer]::Deserialize(
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$argsB64')))
    `$__sb = [scriptblock]::Create(
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$sbB64')))
    `$__r = & `$__sb @__args
    `$__x = [System.Management.Automation.PSSerializer]::Serialize(`$__r)
    [Console]::Out.WriteLine('$($script:WinMeshSshOk)' +
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$__x)))
} catch {
    `$__x = [System.Management.Automation.PSSerializer]::Serialize(`$_.ToString())
    [Console]::Out.WriteLine('$($script:WinMeshSshErr)' +
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$__x)))
}
"@
}

# Assembles the ssh argument vector for one host entry.
function New-WinMeshSshArgs {
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] $Defaults,
        [Parameter(Mandatory)] [string]$RemoteCommand
    )

    $port    = if ($HostEntry.SshPort)    { $HostEntry.SshPort }    else { $Defaults.SshPort }
    $user    = if ($HostEntry.SshUser)    { $HostEntry.SshUser }    else { $Defaults.SshUser }
    $shell   = if ($HostEntry.SshShell)   { $HostEntry.SshShell }   else { $Defaults.SshShell }
    $timeout = if ($HostEntry.SshTimeout) { $HostEntry.SshTimeout } else { $Defaults.SshTimeout }
    $extra   = @(if ($null -ne $HostEntry.SshOptions) { $HostEntry.SshOptions } else { $Defaults.SshOptions })

    $target = if ($user) { "$user@$($HostEntry.Address)" } else { $HostEntry.Address }

    $a = @('-o', 'BatchMode=yes', '-o', "ConnectTimeout=$timeout")
    if ($port -and $port -ne 22) { $a += @('-p', "$port") }
    foreach ($o in $extra) { if ($o) { $a += @('-o', "$o") } }
    $a += $target
    $a += "$shell -NoProfile -NonInteractive -EncodedCommand $RemoteCommand"
    , $a
}

# Runs a scriptblock on a host over ssh and returns the deserialized result.
function Invoke-WinMeshSsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] $Defaults,
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList
    )

    $payload = New-WinMeshSshPayload -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    # -EncodedCommand takes base64 of UTF-16LE. This is the step that is easy to get wrong.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $sshArgs = New-WinMeshSshArgs -HostEntry $HostEntry -Defaults $Defaults -RemoteCommand $encoded

    Write-Verbose "ssh $($sshArgs -join ' ')"

    # A native command writing to stderr must not become a terminating error here —
    # ssh uses stderr for ordinary notices, and we need its exit code instead.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & ssh @sshArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }

    $marker = $null
    $noise  = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($raw)) {
        $text = "$line"
        if ($text.StartsWith($script:WinMeshSshOk) -or $text.StartsWith($script:WinMeshSshErr)) {
            $marker = $text
        } elseif ($text.Trim()) {
            $noise.Add($text)
        }
    }

    if (-not $marker) {
        $detail = if ($noise.Count) { ($noise -join '; ') } else { "ssh exited with code $code" }
        throw "winmesh(ssh) $($HostEntry.Address): no response from the target — $detail"
    }

    # Remote output that was not the result (Write-Host, native stdout) is not
    # swallowed: it goes to the host stream, as it would under WinRM.
    foreach ($n in $noise) { Write-Host $n }

    if ($marker.StartsWith($script:WinMeshSshErr)) {
        $msg = [System.Management.Automation.PSSerializer]::Deserialize(
            (ConvertFrom-WinMeshB64 -B64 $marker.Substring($script:WinMeshSshErr.Length)))
        throw "winmesh(ssh) $($HostEntry.Address): $msg"
    }

    [System.Management.Automation.PSSerializer]::Deserialize(
        (ConvertFrom-WinMeshB64 -B64 $marker.Substring($script:WinMeshSshOk.Length)))
}

# TCP reachability without Test-NetConnection (Windows-only) — and it reads the
# banner, which tells you *which* SSH server answered. On an overlay network that
# matters: NetBird ships its own SSH server and it may be the one on port 22,
# not the Windows OpenSSH service you think you configured.
function Test-WinMeshSshPort {
    param(
        [Parameter(Mandatory)] [string]$Address,
        [int]$Port = 22,
        [int]$TimeoutMs = 5000
    )

    $result = [pscustomobject]@{ Ok = $false; Banner = ''; Detail = '' }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        if (-not $client.ConnectAsync($Address, $Port).Wait($TimeoutMs)) {
            $result.Detail = 'no connection'
            return $result
        }
        $result.Ok = $true
        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMs
        $buffer = New-Object byte[] 255
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -gt 0) {
            $result.Banner = ([Text.Encoding]::ASCII.GetString($buffer, 0, $read)).Trim()
        }
        $result.Detail = if ($result.Banner) { $result.Banner } else { "${Address}:$Port" }
    } catch {
        $result.Detail = ($_.Exception.Message -split "`n")[0]
    } finally {
        $client.Dispose()
    }
    $result
}
