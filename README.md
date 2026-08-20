# winmesh

[![License: MIT](https://img.shields.io/badge/License-MIT-informational.svg)](LICENSE)
[![PowerShell 5.1+ | 7](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207-5391FE.svg?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-0078D6.svg?logo=windows&logoColor=white)](https://github.com/AndrewMoryakov/winmesh)
[![Transport: WinRM](https://img.shields.io/badge/Transport-WinRM-2E7D57.svg)](https://learn.microsoft.com/windows/win32/winrm/portal)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](winmesh.psd1)

A thin layer for linking Windows machines over PowerShell Remoting. Name a host, run commands on it. Windows only.

**Not tied to any specific network.** Machines only need stable, mutually reachable addresses — provided by an overlay network (**Tailscale, NetBird, ZeroTier**), a plain **LAN**, or anything else. winmesh is about the addresses and WinRM, not how you obtain them.

This is not a new protocol. Under the hood it is stock WinRM and `Invoke-Command`. The value is the opinionated bundle: name-based addressing from a config file, a firewall narrowed to trusted subnets, a local credential store, one-command channel checks, and a set of gotchas you would otherwise learn the hard way. Aimed at a handful of machines, where Ansible is overkill.

---

## Concepts in 30 seconds

- **Controller** — the machine you run winmesh *from* (your laptop). It holds the config and the credential store.
- **Target** — a machine you want to reach. It runs the WinRM listener.
- **Config** (`config/hosts.psd1`) — the list of targets: a short name, an address, a credential id.
- **Credential store** — encrypted per-target credentials, kept locally (never in git).

You do a one-time setup per machine, then day-to-day you just call `Invoke-WinMeshCommand <name> { ... }`.

---

## Prerequisites

- Windows PowerShell 5.1 **or** PowerShell 7, on both controller and targets.
- A network that gives the machines stable, mutually reachable addresses (Tailscale / NetBird / ZeroTier / LAN).
- Administrator rights for exactly two steps: `Connect-WinMeshHost` on the controller, and the bootstrap script on each target.

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

> If the target is already reachable by WinRM, skip this step.

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

## Commands

| Command | What it does | Runs on | Admin |
|---|---|---|---|
| `Get-WinMeshConfig` | load and validate the config | controller | no |
| `Register-WinMeshCredential` | save a target's credentials (DPAPI) | controller | no |
| `Connect-WinMeshHost` | set up the client: WinRM + TrustedHosts | controller | **yes** |
| `Test-WinMeshHost` / `Test-WinMeshFleet` | check the channel | controller | no |
| `Invoke-WinMeshCommand` | run a command on a host | controller | no |
| `New-WinMeshBootstrap` | generate the target-prep script | controller | no |
| *(bootstrap on target)* | enable WinRM, narrow the port | **target** | **yes** |

---

## Config reference

`config/hosts.psd1` is a PowerShell data file (`.psd1`, not YAML — Windows PowerShell 5.1 has no built-in YAML parser, and `.psd1` is parsed safely without executing code).

```powershell
@{
    Defaults = @{
        Transport       = 'winrm'                  # only 'winrm' in this version
        CredentialStore = '~\.winmesh\creds'       # where encrypted credentials live
        AllowedSubnets  = @('100.64.0.0/10')       # subnets allowed to reach WinRM
    }
    Hosts = @{
        'workstation-01' = @{
            Address    = '100.100.10.11'
            Credential = 'admin@workstation-01'
            Note       = 'optional free-text note'
        }
    }
}
```

Point winmesh at a different config with `$env:WINMESH_CONFIG` or `-Config`/`-Path` parameters.

---

## What it deliberately does *not* do

- **Does not bypass the first admin step on a target.** That is impossible in principle; the module only generates the script.
- **Does not move credentials between controllers.** A DPAPI file decrypts only where it was created. The store is local by design.
- **Does not support non-Windows or SSH transport.** WinRM only for now. The `Transport` field is a placeholder for future work.

---

## Gotchas baked in

Collected from real debugging — each one cost time:

- **`Set-Item WSMan:...` blames the remote host when the local WinRM service is actually the problem.** If it is stopped, touching the `WSMan:` drive fails with an error about the target being unreachable. `Connect-WinMeshHost` starts the service first.
- **`Enable-PSRemoting` opens the port with `RemoteAddress=Any`.** Narrowing it to trusted subnets is a mandatory step, built into the bootstrap. Skip it once and the port ends up wider open than you think.
- **TrustedHosts is required even in a domain** when connecting by IP: Kerberos does not apply, so auth falls back to NTLM.
- **Scripts are UTF-8 with BOM.** Without the BOM, Windows PowerShell 5.1 reads non-ASCII as ANSI and fails to parse the file.

---

## Requirements

Windows PowerShell 5.1 or PowerShell 7. A network giving machines stable, mutually reachable addresses — overlay (Tailscale, NetBird, ZeroTier) or plain LAN. Administrator rights only for `Connect-WinMeshHost` on the controller and the bootstrap on each target.

## License

MIT — see [LICENSE](LICENSE).
