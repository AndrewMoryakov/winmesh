<p align="center">
  <img src="docs/assets/winmesh-hero.png" alt="winmesh: a dispatcher at a desk with an address book sends couriers to Windows machines, each reached by name" width="100%">
</p>

<h1 align="center">winmesh</h1>

<p align="center"><b>Name a machine, run PowerShell on it — over WinRM or SSH, on any network. For admins and devs with a handful of Windows boxes — and the Linux and macOS machines next to them.</b></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-informational.svg"></a>
  <a href="https://learn.microsoft.com/powershell/"><img alt="PowerShell 5.1+ | 7" src="https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207-5391FE.svg?logo=powershell&logoColor=white"></a>
  <a href="#platforms"><img alt="Platform: Windows | Linux | macOS" src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-0078D6.svg"></a>
  <a href="https://learn.microsoft.com/windows/win32/winrm/portal"><img alt="Transport: WinRM | SSH" src="https://img.shields.io/badge/Transport-WinRM%20%7C%20SSH-2E7D57.svg"></a>
  <a href="winmesh.psd1"><img alt="Version" src="https://img.shields.io/badge/version-0.2.1-blue.svg"></a>
</p>

<p align="center"><b>English</b> | <a href="README.ru.md">Русский</a></p>

```powershell
Invoke-WinMeshCommand workstation-01 { hostname; whoami }     # run a command on a host, by name
Test-WinMeshFleet                                             # check every host in the config at once
```

winmesh is a thin layer for linking Windows machines over PowerShell Remoting **or SSH**. Name a host, run commands on it, get real objects back. The controller and the targets can be Windows, Linux or macOS: WinRM between Windows machines, SSH everywhere — see [Platforms](#platforms).

## Why winmesh?

- **If** you have a few Windows machines (workstations, a NAS, lab boxes) and want to run PowerShell on them by name, **then** winmesh gives you `Invoke-WinMeshCommand <name> { ... }` after a one-time setup per machine.
- **If** Ansible feels like overkill for a handful of machines, **then** winmesh is deliberately small: one config file, stock WinRM or `ssh`, no agents, no extra dependencies.
- **If** your machines are linked by Tailscale, NetBird, ZeroTier or a plain LAN, **then** it works the same — winmesh only needs stable, mutually reachable addresses, not any particular network. **Not tied to any specific network.**
- **If** you would rather not learn the WinRM, firewall and SSH-quoting pitfalls the hard way, **then** the [gotchas](#gotchas-baked-in) are already baked in.

This is not a new protocol. Under the hood it is stock WinRM and `Invoke-Command`, or stock `ssh` — you pick per host with one config field. The value is the opinionated bundle described below. It is **not** for large fleets or configuration management — see [what it deliberately does not do](#what-it-deliberately-does-not-do).

## Features

- **Name-based addressing** — hosts live in one `config/hosts.psd1`; you type `workstation-01`, not an IP.
- **Two transports, one interface** — `winrm` (default) or `ssh`, chosen per host. Same names, same commands, same object results.
- **Real objects, not text** — pipe results like any PowerShell output, over either transport.
- **Firewall narrowed to trusted subnets** — the bootstrap restricts the WinRM port to `AllowedSubnets`; view or re-apply it later with `Get-`/`Set-WinMeshFirewallScope`.
- **Local credential store** — per-target credentials encrypted with DPAPI, never in git (WinRM).
- **One-command channel checks** — `Test-WinMeshHost` and `Test-WinMeshFleet`.
- **Gotchas baked in** — lessons from real debugging, built into the scripts and [written down](#gotchas-baked-in).

## How it works

<p align="center">
  <img src="docs/assets/winmesh-how-it-works.png" alt="winmesh: a controller looks up a host name in the config and reaches the machine over WinRM or SSH" width="100%">
</p>

1. **Name your machines.** List each target — a short name, an address, a credential id — in `config/hosts.psd1`.
2. **Prepare once.** Run the generated bootstrap script on each target (enables WinRM, narrows the firewall), and `Connect-WinMeshHost` on the controller.
3. **Run by name.** `Invoke-WinMeshCommand <name> { ... }` picks the host's transport — `winrm` or `ssh` — and runs your scriptblock there.
4. **Get objects back.** Results come back as PowerShell objects you can pipe on.

## Quick start

From a clone of this repo on the **controller** (your laptop). Admin rights are needed only for the bootstrap on the target and for `Connect-WinMeshHost`. Each step is explained in [Setup — step by step](#setup--step-by-step).

```powershell
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
Import-Module .\winmesh.psd1

Copy-Item .\config\hosts.example.psd1 .\config\hosts.psd1
notepad .\config\hosts.psd1                       # add your machine (Address + Credential) and set AllowedSubnets

New-WinMeshBootstrap -OutFile .\bootstrap.ps1     # takes AllowedSubnets from the config; copy to the target, run there once as Administrator

Register-WinMeshCredential -Id 'admin@workstation-01'   # login exactly as the bootstrap printed it
Connect-WinMeshHost -Name workstation-01                # controller-side setup (admin, once)
Test-WinMeshHost    -Name workstation-01                # five green checks = success

Invoke-WinMeshCommand workstation-01 { hostname; whoami }
```

Create the config **before** generating the bootstrap: `New-WinMeshBootstrap` takes the firewall scope from `AllowedSubnets` in `config\hosts.psd1`, and without a config it falls back to `100.64.0.0/10` (the Tailscale/NetBird range) — a controller on a plain LAN or ZeroTier would then be locked out. Or pass `-AllowedSubnets` explicitly — see [Choosing allowed subnets](#choosing-allowed-subnets).

Targets reached over **SSH** skip the bootstrap, the credential and the `Connect-WinMeshHost` steps entirely — they need none of the WinRM changes. See [Over SSH instead of WinRM](#over-ssh-instead-of-winrm).

---

## Concepts in 30 seconds

- **Controller** — the machine you run winmesh *from* (your laptop). It holds the config and the credential store.
- **Target** — a machine you want to reach. It runs the WinRM listener or an SSH server.
- **Config** (`config/hosts.psd1`) — the list of targets: a short name, an address, a credential id.
- **Credential store** — encrypted per-target credentials, kept locally (never in git). WinRM only.
- **Transport** — `winrm` (default) or `ssh`, set per host. Everything above the transport is identical: same names, same commands, same object results.

You do a one-time setup per machine, then day-to-day you just call `Invoke-WinMeshCommand <name> { ... }`.

---

## Prerequisites

- Windows PowerShell 5.1 **or** PowerShell 7 on Windows machines; PowerShell 7 (`pwsh`) on Linux and macOS machines — controller and targets alike. See [Platforms](#platforms).
- A network that gives the machines stable, mutually reachable addresses (Tailscale / NetBird / ZeroTier / LAN).
- Administrator rights for exactly two steps: `Connect-WinMeshHost` on the controller, and the bootstrap script on each target.

---

## Platforms

The ssh transport works in every direction; WinRM needs Windows on both ends.

| Controller ↓ · Target → | Windows | Linux / macOS |
|---|---|---|
| **Windows** (PowerShell 5.1 or 7) | `winrm` or `ssh` | `ssh` |
| **Linux / macOS** (PowerShell 7) | `ssh` | `ssh` |

**Why WinRM stays Windows-to-Windows.** PowerShell 7 on Linux/macOS has no
supported WinRM client (`Invoke-Command -ComputerName`, `Test-WSMan` and the
`WSMan:` drive are missing or depend on the third-party PSWSMan/OMI stack), and
the credential store is DPAPI, which exists only on Windows — off Windows,
`Export-Clixml` writes a password as plain hex. So on a Linux/macOS controller
`Register-WinMeshCredential`, `Connect-WinMeshHost`, `Invoke-WinMeshCommand` and
the firewall-scope commands refuse a WinRM host with a clear message, and
`Test-WinMeshHost` / `Test-WinMeshFleet` report it as a failed `WinRM client`
check instead of stopping — the ssh hosts of a mixed fleet are still checked.

**A Linux or macOS controller.** Install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell),
then use the module exactly as on Windows. The config path, `$env:WINMESH_CONFIG`
and `~/.ssh/config` work as usual; `CredentialStore` accepts either separator.

```bash
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
cp config/hosts.example.psd1 config/hosts.psd1     # hosts with Transport = 'ssh'
pwsh -c 'Import-Module ./winmesh.psd1; Test-WinMeshFleet'
```

**A Linux or macOS target.** It needs an SSH server and PowerShell 7 — the
scriptblock runs in `pwsh` there, and results still come back as objects. Set
`SshShell = 'pwsh'` for the host; the default `powershell` exists only on Windows.

```powershell
'linux-01' = @{
    Address   = '100.100.10.21'
    Transport = 'ssh'
    SshUser   = 'admin'
    SshShell  = 'pwsh'          # or its full path, if the ssh session's PATH misses it
}
```

- **Linux:** install `openssh-server` and [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux) from your distribution's or Microsoft's packages.
- **macOS:** turn on *Remote Login* (System Settings → General → Sharing) and install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-macos).
- A non-interactive ssh command skips login profiles, so its `PATH` can differ from your terminal's. If winmesh reports that PowerShell was not found, set `SshShell` to the full path printed by `command -v pwsh` on the target.

On a Linux/macOS target `Test-WinMeshHost` has no *full admin token* check: an
ordinary login is healthy there, and root comes through `sudo`. The *command runs*
line says which it is — e.g. `linux-01 / admin (Linux), not root`.

---

## Setup — step by step

### Step 0 · Install the module (controller)

```powershell
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
Import-Module .\winmesh.psd1
```

### Step 1 · Prepare each target (run ON the target, once, as admin)

A target can only be reached after WinRM is enabled on it — and enabling it needs a **local administrator on that machine**. There is no way around this remotely: the channel does not exist yet. This is the one manual step.

On the **controller**, generate the bootstrap script:

```powershell
New-WinMeshBootstrap -OutFile .\bootstrap.ps1
```

Copy `bootstrap.ps1` to the target (RDP, USB stick, or GPO in a domain) and run it there **as Administrator**. It will:

1. enable PowerShell Remoting (`Enable-PSRemoting`);
2. narrow the WinRM firewall rule to your trusted subnets (see [Choosing subnets](#choosing-allowed-subnets));
3. grant a full admin token to local accounts in remote sessions;
4. print the machine facts you need for the config (computer name, domain, the exact login string).

Note the printed **LoginForCred** value — you will use it in Step 3.

> The bootstrap takes `AllowedSubnets` from `config\hosts.psd1`. If the config does not exist yet, it falls back to `100.64.0.0/10` — do Step 2 first, or pass `-AllowedSubnets` explicitly (see [Choosing allowed subnets](#choosing-allowed-subnets)).
>
> If the target is already reachable by WinRM, or will be reached over SSH, skip this step.

### Step 2 · Add the target to your config (controller)

```powershell
Copy-Item .\config\hosts.example.psd1 .\config\hosts.psd1
notepad .\config\hosts.psd1
```

Fill in one entry per machine:

```powershell
Hosts = @{
    'workstation-01' = @{
        Address    = '100.100.10.11'          # its overlay/LAN address or DNS name
        Credential = 'admin@workstation-01'   # any id you like; used in Step 3
    }
}
```

### Step 3 · Save the credentials (controller)

```powershell
Register-WinMeshCredential -Id 'admin@workstation-01'
```

A prompt appears. Enter the login exactly as the bootstrap printed it:

- domain machine → `DOMAIN\user`
- workgroup / standalone → `COMPUTERNAME\user` (e.g. `workstation-01\admin`)

The password is encrypted with DPAPI — the file can only be read by *your* account on *this* controller. Copied elsewhere, it is useless.

### Step 4 · Prepare the controller (needs admin, once)

```powershell
Connect-WinMeshHost -Name workstation-01
```

This starts the WinRM service on the controller and adds the target to `TrustedHosts` (required for IP-based auth). Run once per new target address.

### Step 5 · Verify

```powershell
Test-WinMeshHost -Name workstation-01
```

Expect five green checks: port, WS-Management, credentials, command runs, full admin token.

### Step 6 · Use it

```powershell
Invoke-WinMeshCommand workstation-01 { hostname; whoami }
Invoke-WinMeshCommand workstation-01 { param($p) Test-Path $p } -ArgumentList 'C:\Windows'
Test-WinMeshFleet          # check every host in the config at once
```

---

## Usage examples

Everything below assumes the host `workstation-01` is set up (Steps 1–5).

**Run a command and read the result.** `Invoke-WinMeshCommand` returns real objects, not text — pipe them like anything else:

```powershell
Invoke-WinMeshCommand workstation-01 { Get-Service } |
    Where-Object Status -eq 'Running' |
    Measure-Object
```

**Pass arguments in.** Use `param()` in the block and `-ArgumentList`:

```powershell
Invoke-WinMeshCommand workstation-01 {
    param($name, $days)
    Get-EventLog -LogName System -After (Get-Date).AddDays(-$days) -EntryType Error |
        Where-Object Source -like "*$name*"
} -ArgumentList 'disk', 7
```

**Do the same thing on every machine in the fleet.** Loop over the config:

```powershell
$cfg = Get-WinMeshConfig
foreach ($name in $cfg.Hosts.Keys) {
    $free = Invoke-WinMeshCommand $name {
        (Get-PSDrive C).Free / 1GB
    }
    "{0,-20} {1,6:N1} GB free on C:" -f $name, $free
}
```

**Gate a script on channel health.** `Test-WinMeshHost -Quiet` returns an object with an `Ok` field and no output — good for automation:

```powershell
if (-not (Test-WinMeshHost -Name workstation-01 -Quiet).Ok) {
    throw 'workstation-01 is unreachable — aborting'
}
# ... proceed knowing the channel works
```

**Check the whole fleet in a scheduled job:**

```powershell
$down = (Test-WinMeshFleet -Quiet) | Where-Object { -not $_.Ok }
if ($down) {
    "$($down.Count) machine(s) down: $($down.Host -join ', ')" | Send-Alert   # your notifier
}
```

**Copy files to or from a host.** File transfer needs a live session; open one with the stored credential:

```powershell
$cfg  = Get-WinMeshConfig
$h    = $cfg.Hosts['workstation-01']
$cred = Import-Clixml (Join-Path $cfg.Defaults.CredentialStore "$($h.Credential -replace '[^\w.@-]','_').cred.xml")

$s = New-PSSession -ComputerName $h.Address -Credential $cred
Copy-Item .\report.csv -Destination 'C:\Temp\' -ToSession $s
Copy-Item 'C:\Temp\log.txt' -Destination .\ -FromSession $s
Remove-PSSession $s
```

**Use a different config file** (e.g. staging vs production):

```powershell
$env:WINMESH_CONFIG = 'C:\fleets\staging.psd1'
Test-WinMeshFleet
# or per-call:
Invoke-WinMeshCommand nas-lan { hostname } -Config (Get-WinMeshConfig -Path .\lan.psd1)
```


---

## Over SSH instead of WinRM

WinRM is the default because it is native and returns objects. SSH is the better
choice in two cases: the machines are already joined by an overlay VPN that ships
its own SSH server (NetBird does), or WinRM is unavailable to you — blocked by
policy, or the port is closed and you cannot open it.

Switching a host is one field. Nothing else in your scripts changes:

```powershell
Hosts = @{
    'workstation-02' = @{
        Address   = 'workstation-02'      # overlay name or IP
        Transport = 'ssh'
        SshUser   = 'Administrator'
    }
}
```

```powershell
Test-WinMeshHost    -Name workstation-02
Invoke-WinMeshCommand workstation-02 { Get-Service } | Where-Object Status -eq 'Running'
```

**There is no `Credential` field and no `Connect-WinMeshHost` step.** Over ssh the
client authenticates on its own — a key, an agent, or, on an overlay network, the
peer identity: NetBird's SSH server authenticates the *peer*, so a machine already
in your mesh needs no key at all. Steps 1, 3 and 4 of the setup (bootstrap, credential, `Connect-WinMeshHost`) simply do not apply.

You still get objects back, not text. The scriptblock and its arguments are
base64-packed into `powershell -EncodedCommand` (`pwsh` on Linux/macOS), and the result is serialized on
the far side with the same CliXml engine remoting uses, then rehydrated here.

**SSH options** — per host or in `Defaults`:

| Key | Default | Meaning |
|---|---|---|
| `SshUser` | *(empty)* | remote account; empty means let `ssh` decide |
| `SshPort` | `22` | |
| `SshShell` | `powershell` | `powershell` (5.1, always present on Windows) or `pwsh`; Linux/macOS targets need `pwsh` or its full path |
| `SshTimeout` | `15` | seconds, becomes `ConnectTimeout` |
| `SshOptions` | `@()` | extra `-o` options, e.g. `@('StrictHostKeyChecking=accept-new')` |

Anything more specific — jump hosts, per-host keys, aliases — belongs in your
`~/.ssh/config`, which `ssh` reads as usual. winmesh does not duplicate it.

### If you use an overlay VPN

`AllowedSubnets` (used by the WinRM bootstrap) applies to WinRM only. If you serve
SSH from Windows OpenSSH rather than the VPN's own server, narrow port 22 yourself:

```powershell
Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -RemoteAddress '100.64.0.0/10'
```

---

## Adding more machines

Repeat **Steps 1–5** for each new target. Day-to-day there is nothing to remember beyond the host's short name.

```powershell
Test-WinMeshFleet          # health of the whole fleet
```

---

## Choosing allowed subnets

The bootstrap narrows the WinRM port to `Defaults.AllowedSubnets` from your config. Pick the value that matches how your machines are linked:

| Network | AllowedSubnets |
|---|---|
| Tailscale / NetBird | `@('100.64.0.0/10')` — the CGNAT range (default) |
| ZeroTier | your network's subnet, e.g. `@('10.147.17.0/24')` |
| Plain LAN | e.g. `@('192.168.1.0/24')` |
| Several at once | `@('192.168.1.0/24','100.64.0.0/10')` |
| Do not narrow (trusted LAN) | `@()` |

You can also pass it directly, ignoring the config default:

```powershell
New-WinMeshBootstrap -AllowedSubnets '192.168.1.0/24' -OutFile .\bootstrap-lan.ps1
```

---

## Seeing and changing which networks may connect

`AllowedSubnets` is the single place that decides which source networks may reach
a host's WinRM port. It is applied at bootstrap; view or re-apply it later without
remembering firewall commands:

```powershell
Get-WinMeshFirewallScope -Name workstation-01            # current scope + whether it matches the config
Set-WinMeshFirewallScope -Name workstation-01 -WhatIf    # preview
Set-WinMeshFirewallScope -Name workstation-01            # apply the config's AllowedSubnets
```

`Set-WinMeshFirewallScope` refuses if narrowing would cut your own live session
(no connected source falls inside the new ranges) — pass `-Force` only at the
console. A host may override the global default with its own `AllowedSubnets`
(e.g. a machine reachable through a different overlay):

```powershell
Hosts = @{
    'nas-zt' = @{
        Address        = '10.147.17.20'
        Credential     = 'admin@nas-zt'
        AllowedSubnets = @('10.147.17.0/24')   # this host only; overrides Defaults
    }
}
```

## Connecting from another network

Two things must both hold to reach a host: the source must be able to *route* to
the machine, and its address must fall inside `AllowedSubnets`.

- **You are physically elsewhere (corporate, hotel, home).** Nothing to change —
  Tailscale/NetBird runs over whatever internet you have, so you stay on the
  overlay and the host is reachable at its overlay address. The usual case.
- **Add another overlay (e.g. ZeroTier).** Join both machines to it, add its
  subnet to `AllowedSubnets` (ZeroTier is not in the `100.64.0.0/10` CGNAT range),
  run `Set-WinMeshFirewallScope`, and add the host's new address to `TrustedHosts`
  on the controller.
- **A specific trusted LAN, no overlay.** Add that subnet — as narrow as possible
  (a `/24`, or a single `/32`) — weighing that anything on it can then reach WinRM.

## Security notes

- **Prefer overlay membership as the boundary.** Reaching a host means being on
  its overlay, which requires your Tailscale/NetBird auth. The firewall range is a
  second layer that rejects the physical LAN and public addresses.
- **Do not open a whole corporate or public subnet to WinRM.** Reach the host over
  the overlay from that network instead; the overlay tunnels over any internet.
- **`AllowedSubnets` replaces, never appends.** List every network you want at once;
  an empty list (`@()`) means "do not narrow" (`Any`) — only for a trusted LAN.
- **WinRM 5985 is Negotiate/Kerberos-encrypted**, not plaintext, but it is still an
  admin channel — keep the source range as tight as the setup allows.
- **The rule's profile still matters.** It applies to Domain+Private; if an overlay
  adapter is categorized Public the rule will not cover it. Keep overlay adapters
  Private, or widen the rule's profile once the source range is set.
## Commands

| Command | What it does | Runs on | Admin |
|---|---|---|---|
| `Get-WinMeshConfig` | load and validate the config | controller | no |
| `Register-WinMeshCredential` | save a target's credentials (DPAPI) — *winrm only, Windows controller* | controller | no |
| `Connect-WinMeshHost` | set up the client: WinRM + TrustedHosts — *winrm only, Windows controller* | controller | **yes** |
| `Test-WinMeshHost` / `Test-WinMeshFleet` | check the channel | controller | no |
| `Invoke-WinMeshCommand` | run a command on a host | controller | no |
| `New-WinMeshBootstrap` | generate the target-prep script | controller | no |
| *(bootstrap on target)* | enable WinRM, narrow the port — *winrm only* | **target** | **yes** |

---

## Config reference

`config/hosts.psd1` is a PowerShell data file (`.psd1`, not YAML — Windows PowerShell 5.1 has no built-in YAML parser, and `.psd1` is parsed safely without executing code).

```powershell
@{
    Defaults = @{
        Transport       = 'winrm'                  # 'winrm' or 'ssh'
        CredentialStore = '~\.winmesh\creds'       # where encrypted credentials live
        AllowedSubnets  = @('100.64.0.0/10')       # subnets allowed to reach WinRM
    }
    Hosts = @{
        'workstation-01' = @{
            Address    = '100.100.10.11'
            Credential = 'admin@workstation-01'
            Note       = 'optional free-text note'
        }
        'workstation-02' = @{
            Address    = 'workstation-02'          # same fleet, ssh instead of WinRM
            Transport  = 'ssh'
            SshUser    = 'Administrator'           # no Credential: see "Over SSH instead of WinRM"
        }
    }
}
```

Point winmesh at a different config with `$env:WINMESH_CONFIG` or `-Config`/`-Path` parameters.

---

## What it deliberately does *not* do

- **Does not bypass the first admin step on a target.** That is impossible in principle; the module only generates the script.
- **Does not move credentials between controllers.** A DPAPI file decrypts only where it was created. The store is local by design.
- **Does not manage SSH keys or passwords.** Over ssh, authentication is whatever your `ssh` client already negotiates — a key, an agent, or an overlay network's peer identity. winmesh never prompts, stores, or forwards a secret for the ssh path.
- **Does not install an SSH server for you.** Unlike WinRM there is no bootstrap for it: either the overlay VPN already provides one (NetBird does), or you install an OpenSSH server yourself, once (plus PowerShell 7 on a Linux/macOS target).

---

## Gotchas baked in

Collected from real debugging — each one cost time:

- **`Set-Item WSMan:...` blames the remote host when the local WinRM service is actually the problem.** If it is stopped, touching the `WSMan:` drive fails with an error about the target being unreachable. `Connect-WinMeshHost` starts the service first.
- **`Enable-PSRemoting` opens the port with `RemoteAddress=Any`.** Narrowing it to trusted subnets is a mandatory step, built into the bootstrap. Skip it once and the port ends up wider open than you think.
- **TrustedHosts is required even in a domain** when connecting by IP: Kerberos does not apply, so auth falls back to NTLM.
- **Scripts are UTF-8 with BOM.** Without the BOM, Windows PowerShell 5.1 reads non-ASCII as ANSI and fails to parse the file.

Over SSH specifically:

- **`-EncodedCommand` wants base64 of UTF-16LE, not UTF-8.** Encode the payload as UTF-8 and PowerShell either reads garbage or refuses to parse. This is why the transport encodes with `[Text.Encoding]::Unicode`.
- **You cannot hand-quote a command for the remote shell.** Windows OpenSSH runs `cmd.exe` by default, but PowerShell if `DefaultShell` was changed — and the two disagree about quoting. Sending one base64 token sidesteps the question entirely, and the same string works under either shell.
- **`ConvertTo-CliXml` does not exist in Windows PowerShell 5.1.** Use `[System.Management.Automation.PSSerializer]::Serialize()` / `::Deserialize()`, which exist in both 5.1 and 7.
- **On an overlay network, the server answering port 22 may not be the one you configured.** NetBird ships its own SSH server and takes the port on the overlay address, so the Windows OpenSSH service you set up can sit there unused. `Test-WinMeshHost` prints the SSH banner for exactly this reason — read it.
- **A session opened by an overlay's SSH server may not carry a full admin token,** even for an Administrator account. `Test-WinMeshHost` reports this as a separate check rather than letting it surface later as a confusing access-denied.

On a **non-English Windows**, or a domain-joined machine whose DC is unreachable:

- **`IsInRole('Administrators')` is unreliable on a localized Windows — it may
  throw, or return a wrong `$false`.** The built-in group can be localized
  (`BUILTIN\Администраторы` on a Russian install), and the string overload
  resolves by *name*. Measured both ways: on a Russian install where the group
  was localized, the English literal raised `MethodInvocationException`; on
  another box an unmappable name simply returned `$false` (5.1 and 7 alike). The
  localized name, the `[WindowsBuiltInRole]::Administrator` enum, and the raw SID
  all returned the right answer. Either way a healthy channel gets reported as
  `command runs: False` — a throw fails the whole call from *inside* the remote
  scriptblock, and a wrong `$false` is just wrong. Always use the enum or
  `S-1-5-32-544`, never the English name.
- **`icacls` and `Add-LocalGroupMember` fail the same way, for a different
  reason.** Passing the name `"Administrators"` makes Windows resolve it, and on
  a domain-joined machine that query goes to a domain controller — so with the
  DC unreachable you get *"could not establish trust relationship with the
  primary domain"* while doing something entirely local. Well-known SIDs need no
  lookup: `icacls f /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F"`, and
  `Add-LocalGroupMember -Group (Get-LocalGroup -SID S-1-5-32-544)`.
- **A domain account can pass publickey auth and still fail to open a session.**
  The OpenSSH log shows `Accepted publickey for <user>`, then the client sees
  `Connection reset by peer` — and **nothing further is logged**, because the
  failure is past sshd's logging. Key-based logon builds the user's token via
  S4U, which for a domain account needs a live DC; your own interactive session
  works only because it runs on cached credentials, which sshd cannot use. The
  fix is not an sshd setting — use a **local** account. On a domain-joined
  machine, `Get-LocalGroupMember -SID S-1-5-32-544` usually reveals one already.
- **Pasting a key into a console can split it, and sshd will not tell you.** A
  long `$key = 'ssh-ed25519 …'` line wraps at the console width, the newline
  lands *inside* the string, and `authorized_keys` receives two fragments.
  Malformed lines are skipped silently, so the symptom is a plain
  `Permission denied` with a correct-looking file. Verify with lengths, not by
  eye — a valid ed25519 line is a single ~110-character row:
  `Get-Content $f | ForEach-Object { $_.Length }`.
- **Admin keys live somewhere else entirely.** For any account in the
  administrators group, stock `sshd_config` carries
  `Match Group administrators` → `__PROGRAMDATA__/ssh/administrators_authorized_keys`.
  A key placed in `C:\Users\<name>\.ssh\authorized_keys` is ignored, and so is
  that shared file if its ACL is wider than SYSTEM + Administrators.
- **The rule behind the first two: on a localized Windows, anything that
  resolves or formats through the system locale is a portability bug.** Two
  instances turned up within an hour on the same box — `IsInRole('Administrators')`
  throwing, and a separate CLI whose `toLocaleString()` printed `1 401` where
  `en-US` prints `1,401`, breaking its own output parser. Both look correct on
  an English machine and neither is caught by a Linux test run. Pin the locale
  (`toLocaleString('en-US')`) and address principals by SID.

### Linux and macOS

- **`$IsWindows` does not exist in Windows PowerShell 5.1.** It reads as `$null`,
  so `if ($IsWindows)` quietly classifies every 5.1 machine as non-Windows. A
  scriptblock that may run on a 5.1 target tests `$env:OS -eq 'Windows_NT'`.
- **`WindowsIdentity` throws off Windows.** The admin check that works on every
  Windows target is `PlatformNotSupportedException` on Linux/macOS; there the
  question is `id -u` — and "not root" is normal, not a failure.
- **A backslash is a file-name character on Linux/macOS.** `Join-Path $dir 'config\hosts.psd1'`
  names one file called `config\hosts.psd1`. Join each segment separately.
- **Off Windows, `Export-Clixml` does not encrypt a credential.** The password is
  stored as hex-encoded UTF-16 — readable by anyone who can read the file. That is
  why the credential store (and with it WinRM) is Windows-only.

### Driving a target from a script

- **Do not embed non-ASCII literals in a script you transfer.** A `.ps1`
  carrying Cyrillic came out mangled after `scp`, and PowerShell 5.1 failed to
  parse it — the BOM gotcha above, arriving through a different door. Derive the
  localized string at run time instead, which needs no literal at all:
  `([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value`.
- **Do not hand-quote an ad-hoc command either.** The transport avoids this by
  base64-packing (see above), but the same trap catches you at the console: a
  one-off `powershell -Command "... try { } catch { } ..."` over `ssh` lost its
  braces to two layers of quoting and died with `MissingCatchOrFinally`. Write a
  file and run `powershell -File`, exactly as the transport effectively does.
- **A large download initiated *on* the target may fail where a push from the
  controller succeeds.** `Invoke-WebRequest` aborted with `IOException` partway
  through a 100 MB file, and a `curl.exe -C -` resume then could not even open
  the partial file, in a directory proven writable moments earlier. `scp` of the
  same bytes from the controller worked first time. Cause not established —
  security software is the obvious suspect, but it was not confirmed. Worth
  knowing as a fallback rather than as an explanation.

---

## Requirements

Windows PowerShell 5.1 or PowerShell 7 on Windows; PowerShell 7 on Linux and macOS (see [Platforms](#platforms)). A network giving machines stable, mutually reachable addresses — overlay (Tailscale, NetBird, ZeroTier) or plain LAN. Administrator rights only for `Connect-WinMeshHost` on the controller and the bootstrap on each target — neither applies to ssh hosts. For the ssh transport, an `ssh` client on the controller (built into Windows 10/11, Server 2019+, Linux and macOS) and an SSH server on the target — plus PowerShell 7 there if the target is Linux or macOS.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for scope, conventions, and how to test. The project stays deliberately small and dependency-free.

## License

MIT — see [LICENSE](LICENSE).
