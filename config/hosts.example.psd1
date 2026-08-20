@{
    # Значения по умолчанию для всех машин. Любое переопределяется в самой машине.
    Defaults = @{
        Transport       = 'winrm'                       # в этой версии только winrm
        CredentialStore = '~\.winmesh\creds'            # где лежат зашифрованные учётки
        TailscaleCidr   = '100.64.0.0/10'               # диапазон mesh-VPN для сужения порта
    }

    # Машины парка. Ключ — короткое имя, которым вы будете называть машину.
    Hosts = @{
        'workstation-01' = @{
            Address    = '100.100.10.11'                 # Tailscale-адрес или MagicDNS-имя
            Credential = 'admin@workstation-01'         # ид записи в хранилище
            Note       = 'пример: рабочая станция'
        }

        # 'workstation-02' = @{
        #     Address    = '100.100.10.12'
        #     Credential = 'admin@workstation-02'
        #     Note       = 'WinRM пока не включён — сначала New-WinMeshBootstrap'
        # }
    }
}
