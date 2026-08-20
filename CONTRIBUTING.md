# Contributing to winmesh

Thanks for considering a contribution. winmesh is deliberately small — a thin, opinionated layer over WinRM and SSH. The goal is to keep it that way: easy to read in one sitting, no external dependencies, no surprises.

## Scope

In scope:

- Making the existing WinRM or SSH flow more robust or clearer.
- New helper commands that fit the "name a host, act on it" model.
- Keeping the two transports interchangeable: anything a user writes above the transport should behave the same on both.
- Documentation and examples.

Out of scope (by design):

- Turning this into a full configuration-management tool. If you need that, use Ansible or DSC.
- Anything that bypasses the one-time local admin step on a target — it cannot be done and we will not pretend otherwise.
- Storing credentials anywhere but the local DPAPI store.
- Handling secrets on the SSH path at all — no key generation, no passphrase prompts, no `sshpass`. Authentication over ssh is whatever the client already negotiates, and per-host detail belongs in `~/.ssh/config`, which we do not duplicate.
- Installing an SSH server on a target. Either the overlay VPN provides one or the user installs OpenSSH Server once, by hand.

If unsure whether something fits, open an issue before writing code.

## Development setup

```powershell
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
Import-Module .\winmesh.psd1 -Force      # re-run after every edit
```

There are no build steps and no packages to install. The module is plain `.ps1`/`.psd1`.

## Coding conventions

These are not style preferences — each one prevents a bug we have already hit:

- **Support both Windows PowerShell 5.1 and PowerShell 7.** Test in both. They differ in real ways (default encodings, `-match` on arrays, `ConfirmImpact` behavior).
- **Save every `.ps1`/`.psd1` as UTF-8 *with BOM*.** Without the BOM, Windows PowerShell 5.1 reads non-ASCII as ANSI and fails to parse the file.
- **No external dependencies.** Standard cmdlets only. The config is `.psd1`, not YAML, precisely because 5.1 has no YAML parser.
- **Destructive commands use `SupportsShouldProcess` and honor `-WhatIf`.** Do *not* set `ConfirmImpact = 'High'` on anything meant to run via `Invoke-Command` — under a non-interactive host `ShouldProcess` throws instead of prompting.
- **Never name a function parameter `$Pid`.** It is a read-only automatic variable; shadowing it fails silently and the function returns nothing.
- **`Import-Module` has no `-WhatIf`.** To preload a module quietly under `-WhatIf`, toggle `$WhatIfPreference` around the call (see `winmesh.psm1`).
- **`curl.exe` and many native tools return an *array of lines*.** `-join "`n"` before `-match`, or use `[regex]::Match`; a bare `-match` on an array does not populate `$Matches`.

Specific to the SSH transport (`functions/Invoke-WinMeshSsh.ps1`):

- **Never hand-quote a command for the remote shell.** Windows OpenSSH runs `cmd.exe` by default but PowerShell if `DefaultShell` was changed, and the two disagree about quoting. Send one base64 token and the question disappears. Anything user-supplied — a scriptblock body, an argument — is base64 *inside* the payload for the same reason.
- **`-EncodedCommand` takes base64 of UTF-16LE.** Use `[Text.Encoding]::Unicode`, not `::UTF8`; the UTF-8 version parses as garbage or not at all.
- **Use `[System.Management.Automation.PSSerializer]` for the object round-trip.** `ConvertTo-CliXml` / `ConvertFrom-CliXml` do not exist in Windows PowerShell 5.1. Keeping this serialization is what makes ssh hosts return objects rather than text — do not "simplify" it into string output.
- **Keep the ssh path free of Windows-only cmdlets.** `Test-NetConnection` is why the port probe uses `System.Net.Sockets.TcpClient` instead. A controller-side ssh call should not fail for reasons unrelated to the target.
- **A native command writing to stderr must not become a terminating error.** `ssh` uses stderr for ordinary notices; set `$ErrorActionPreference = 'Continue'` around the call and read `$LASTEXITCODE`.

## Testing

Before opening a PR, run these on your changes:

```powershell
# 1. Every file parses (catches BOM/encoding and syntax issues)
Get-ChildItem -Recurse -Include *.ps1,*.psd1 | ForEach-Object {
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e)
    if ($e) { "FAIL: $($_.Name) - $($e[0].Message)" }
}

# 2. Manifest is valid
Test-ModuleManifest .\winmesh.psd1

# 3. Every fix-style / destructive command still no-ops under -WhatIf

# 4. A real smoke test against a host you control:
#    Test-WinMeshHost -Name <yourhost>   -> all green
```

If your change touches the SSH transport, smoke-test it against a real target — the
interesting failures are all on the wire, not in the parser:

```powershell
# objects, not text
Invoke-WinMeshCommand <sshhost> { Get-Service } | Where-Object Status -eq 'Running'
# arguments survive a quote-hostile string
Invoke-WinMeshCommand <sshhost> { param($s) $s } -ArgumentList 'a b "c" ; d \ % ^ &'
# a remote failure surfaces locally
try { Invoke-WinMeshCommand <sshhost> { throw 'boom' } } catch { $_.Exception.Message }
```

Note that `Test-WinMeshHost` may report `full admin token: reduced` on a host that
is otherwise working — some SSH servers, including the one NetBird ships, hand out
a non-elevated session even for an administrator account. That is a property of the
target, not a regression.

If your change touches the generated bootstrap, confirm the *output* still parses:

```powershell
$bs = New-WinMeshBootstrap -AllowedSubnets '192.168.1.0/24'
$e = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($bs, [ref]$null, [ref]$e)
if ($e) { 'generated script does not parse' }
```

## Commits and pull requests

- One logical change per PR; keep the diff readable.
- Write commit messages in the imperative mood ("Add …", "Fix …").
- Explain *why* in the body when the change is not obvious.
- Never commit a real `config/hosts.psd1`, a `.cred.xml`, or a generated `bootstrap-*.ps1` — `.gitignore` already excludes them, but double-check `git status` before pushing.
- Do not put real hostnames, IPs, or overlay addresses in examples. Use the placeholder names (`workstation-01`, `100.100.10.11`).

## Reporting bugs

Open an issue with: PowerShell edition and version (`$PSVersionTable`), the transport (`winrm` or `ssh`), the network type (Tailscale / NetBird / ZeroTier / LAN), what you ran, what you expected, and what happened. A failing `Test-WinMeshHost` report is the ideal starting point — for ssh it includes the server banner, which is often the whole answer.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
