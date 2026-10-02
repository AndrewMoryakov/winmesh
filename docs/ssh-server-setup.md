# SSH server setup

These scripts prepare a target for winmesh's `Transport = 'ssh'`. They do not
create an account or add a public key. Add the key before depending on remote
access, and keep an active console/RDP session until the first SSH login works.

Both scripts close TCP/22 to every source outside the ranges you pass, including
broad rules that existed before. Include the network you will connect from, or
new SSH connections from it will be refused.

## Windows: Win32-OpenSSH

Check first whether the target already runs an SSH server. `OpenSSH.Server :
NotPresent` from `Get-WindowsCapability` describes only Windows' inbox optional
feature; a manually installed Win32-OpenSSH can be running all the same. Look at
the service, the binary it starts, and what listens on TCP/22:

```powershell
Get-Service sshd
(Get-CimInstance Win32_Service -Filter "Name='sshd'").PathName
Get-NetTCPConnection -LocalPort 22 -State Listen
```

An empty `Get-NetTCPConnection` result does not prove that nothing answers on
port 22 of an overlay address: NetBird's own SSH server was not listed there on
a host where it demonstrably answered. The installer below recognises an
existing installation only at `C:\Program Files\OpenSSH\sshd.exe`; an `sshd`
service that starts a binary from any other path is not treated as one.

Run PowerShell as Administrator on the target. Pick an explicit release tag
from [Win32-OpenSSH releases](https://github.com/PowerShell/Win32-OpenSSH/releases).
The project currently labels its newest release as a preview, so the installer
intentionally has no automatic `latest` default. Copy the tag exactly as the
releases page shows it: `10.0.0.0p2-Preview` has no prefix, while older tags
such as `v9.8.3.0p2-Preview` start with `v`.

```powershell
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\Install-Win32OpenSSH.ps1 `
  -Version '10.0.0.0p2-Preview' `
  -AllowedRemoteAddress '100.64.0.0/10'
```

Pass every trusted network with repeated values, for example:

```powershell
-AllowedRemoteAddress '100.64.0.0/10','192.168.1.0/24'
```

The script downloads `OpenSSH-Win64.zip` from the selected GitHub tag only when
`C:\Program Files\OpenSSH\sshd.exe` is absent. It generates host keys, validates
`sshd_config`, creates or repairs the `sshd` service, makes it automatic, and
creates a `winmesh-sshd` firewall rule for TCP/22 restricted to the supplied
source ranges. Firewall allow rules add up, so it then disables every other
enabled inbound allow rule for TCP/22 (for example the stock
`OpenSSH-Server-In-TCP`, open to any address) and lists them in its output;
`Enable-NetFirewallRule -Name <name>` brings one back. Rules pushed by Group
Policy cannot be changed locally, so review those yourself. Use
`-ExpectedSha256` when you have independently verified the archive checksum.
An existing installation at that path is left in place; `-ForceUpgrade`
replaces it and stops the service, so use it only from a local console.

Verify on the target:

```powershell
Get-Service sshd
Get-NetTCPConnection -LocalPort 22 -State Listen
```

## Linux

Run on the target as root or through `sudo`:

```bash
git clone https://github.com/AndrewMoryakov/winmesh.git
cd winmesh
sudo ./scripts/linux/install-openssh-server.sh --allowed-cidr 100.64.0.0/10
```

Repeat `--allowed-cidr` for each permitted source range. The script supports
`apt`, `dnf`, `yum`, and `pacman`; enables the installed `ssh` or `sshd` systemd
unit; generates any missing host keys and validates the configuration; and adds
restricted rules only when active UFW or firewalld is detected. It then removes
the broad allowances that would keep TCP/22 open to everyone next to them: UFW
rules `OpenSSH`, `ssh`, `22/tcp` or `22` from Anywhere, and the `ssh` service or
port `22/tcp` in the default and active firewalld zones. If neither is active,
it does not invent firewall rules and exits successfully after printing a
reminder to review the host's firewall.

Verify:

```bash
systemctl status ssh || systemctl status sshd
ss -ltn | grep ':22'
```

winmesh runs your scriptblock in PowerShell on the target, so a Linux target
also needs [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux)
(`pwsh`). The script above installs only the SSH server. Confirm with
`command -v pwsh`.

## Add the host to winmesh

On the controller, add an SSH transport host to `config/hosts.psd1`:

```powershell
'linux-01' = @{
    Address   = '100.100.10.21'     # its overlay/LAN address or DNS name
    Transport = 'ssh'
    SshUser   = 'admin'             # the account whose key you added
    SshShell  = 'pwsh'              # a Linux target has no 'powershell'
}
```

A Windows target needs no `SshShell`: the default `powershell` is always there.

Then establish public-key authentication with the account named by `SshUser` and
run `Test-WinMeshHost -Name linux-01` from the controller.
