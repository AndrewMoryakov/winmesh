@{
    # Defaults for every host. Any of these can be overridden per host.
    Defaults = @{
        Transport       = 'winrm'                       # only 'winrm' in this version

        CredentialStore = '~\.winmesh\creds'            # where encrypted credentials are stored

        # Subnets allowed to reach the WinRM port (the bootstrap narrows the
        # firewall to these). Choose the value that matches how your machines
        # are linked:
        #   Tailscale / NetBird  -> '100.64.0.0/10'  (CGNAT range, the default)
        #   ZeroTier             -> your network subnet, e.g. '10.147.17.0/24'
        #   plain LAN            -> e.g. '192.168.1.0/24'
        #   several at once      -> @('192.168.1.0/24','100.64.0.0/10')
        #   do not narrow (trusted LAN) -> @()
        AllowedSubnets  = @('100.64.0.0/10')
    }

    # Your fleet. The key is a short name you will use to refer to the machine.
    # Address is its address on your network (overlay IP, LAN address, or DNS name).
    Hosts = @{
        'workstation-01' = @{
            Address    = '100.100.10.11'                # address or DNS name
            Credential = 'admin@workstation-01'         # id of the stored credential
            Note       = 'example: a workstation'       # optional free-text note
        }

        # 'nas-lan' = @{
        #     Address    = '192.168.1.50'               # example: a machine on the LAN
        #     Credential = 'admin@nas-lan'
        # }
    }
}
