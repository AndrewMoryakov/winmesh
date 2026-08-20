# Contributing to winmesh

Thanks for considering a contribution. winmesh is deliberately small — a thin, opinionated layer over WinRM. The goal is to keep it that way: easy to read in one sitting, no external dependencies, no surprises.

## Scope

In scope:

- Making the existing WinRM flow more robust or clearer.
- New helper commands that fit the "name a host, act on it" model.
- The planned SSH transport (`Transport = 'ssh'`) for mixed fleets.
- Documentation and examples.

Out of scope (by design):

- Turning this into a full configuration-management tool. If you need that, use Ansible or DSC.
- Anything that bypasses the one-time local admin step on a target — it cannot be done and we will not pretend otherwise.
- Storing credentials anywhere but the local DPAPI store.

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

Open an issue with: PowerShell edition and version (`$PSVersionTable`), the network type (Tailscale / NetBird / ZeroTier / LAN), what you ran, what you expected, and what happened. A failing `Test-WinMeshHost` report is the ideal starting point.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
