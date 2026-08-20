# winmesh

[![License: MIT](https://img.shields.io/badge/License-MIT-informational.svg)](LICENSE)
[![PowerShell 5.1+ | 7](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207-5391FE.svg?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-0078D6.svg?logo=windows&logoColor=white)](https://github.com/AndrewMoryakov/winmesh)
[![Transport: WinRM | SSH](https://img.shields.io/badge/Transport-WinRM%20%7C%20SSH-2E7D57.svg)](https://learn.microsoft.com/windows/win32/winrm/portal)
[![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)](winmesh.psd1)

A thin layer for linking Windows machines over PowerShell Remoting **or SSH**. Name a host, run commands on it. Windows only.

**Not tied to any specific network.** Machines only need stable, mutually reachable addresses — provided by an overlay network (**Tailscale, NetBird, ZeroTier**), a plain **LAN**, or anything else. winmesh is about the addresses and WinRM, not how you obtain them.

This is not a new protocol. Under the hood it is stock WinRM and `Invoke-Command`, or stock `ssh` — you pick per host with one config field. The value is the opinionated bundle: name-based addressing from a config file, a firewall narrowed to trusted subnets, a local credential store, one-command channel checks, and a set of gotchas you would otherwise learn the hard way. Aimed at a handful of machines, where Ansible is overkill.

---

## Concepts in 30 seconds

- **Controller** — the machine you run winmesh *from* (your laptop). It holds the config and the credential store.
- **Target** — a machine you want to reach. It runs the WinRM listener.
- **Config** (`config/hosts.psd1`) — the list of targets: a short name, an address, a credential id.
- **Credential store** — encrypted per-target credentials, kept locally (never in git). WinRM only.
- **Transport** — `winrm` (default) or `ssh`, set per host. Everything above the transport is identical: same names, same commands, same object results.

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
in your mesh needs no key at all. Steps 3 and 4 of the setup simply do not apply.

You still get objects back, not text. The scriptblock and its arguments are
base64-packed into `powershell -EncodedCommand`, and the result is serialized on
the far side with the same CliXml engine remoting uses, then rehydrated here.

**SSH options** — per host or in `Defaults`:

| Key | Default | Meaning |
|---|---|---|
| `SshUser` | *(empty)* | remote account; empty means let `ssh` decide |
| `SshPort` | `22` | |
| `SshShell` | `powershell` | `powershell` (5.1, always present) or `pwsh` |
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

## Commands

| Command | What it does | Runs on | Admin |
|---|---|---|---|
| `Get-WinMeshConfig` | load and validate the config | controller | no |
| `Register-WinMeshCredential` | save a target's credentials (DPAPI) — *winrm only* | controller | no |
| `Connect-WinMeshHost` | set up the client: WinRM + TrustedHosts — *winrm only* | controller | **yes** |
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
- **Does not install an SSH server for you.** Unlike WinRM there is no bootstrap for it: either the overlay VPN already provides one (NetBird does), or you install Windows OpenSSH Server yourself, once.

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

---

## Requirements

Windows PowerShell 5.1 or PowerShell 7. A network giving machines stable, mutually reachable addresses — overlay (Tailscale, NetBird, ZeroTier) or plain LAN. Administrator rights only for `Connect-WinMeshHost` on the controller and the bootstrap on each target — neither applies to ssh hosts. For the ssh transport, an `ssh` client on the controller (built into Windows 10/11 and Server 2019+) and an SSH server on the target.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for scope, conventions, and how to test. The project stays deliberately small and dependency-free.

## License

MIT — see [LICENSE](LICENSE).
