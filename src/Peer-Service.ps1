# Read-only LAN service. No UI controls, forms, or remote commands belong here.
# Remote snapshots never enter local character state, history or alert configuration.
function New-PeerSnapshot {
    if($null -eq $script:characterStates -or $script:characterStateError){throw 'Leitura local indisponivel'}
    $finance=Get-FinancialProjection $script:characterStates
    $rows=@(foreach($state in $script:characterStates.Values){
        $f=$finance.Characters[$state.Key]
        $active=if(Get-Command Get-CharacterActiveAlerts -ErrorAction SilentlyContinue){(Get-CharacterActiveAlerts $state).Text}else{''}
        [pscustomobject]@{ActiveAlerts=[string]$active;Key=[string]$state.Key;Name=[string]$state.Name;Status=[string]$state.Status;Level=$state.Level;Server=[string]$state.Server;Map=[string]$state.Map;HP=$state.HP;MaxHP=$state.MaxHP;Fairy=[string]$state.Fairy;XP=[string]$state.XPBuffDetail;Gold=$(if($f.GoldEligible){$f.Gold});ChestGold=$(if($f.ChestGoldEligible){$f.ChestGold});Wealth=$f.Wealth;Complete=[bool]$f.Complete;Coins=$(if($f.SilverCoinsEligible){$f.SilverCoins});ChestCoins=$(if($f.ChestSilverCoinsEligible){$f.ChestSilverCoins});CoinsComplete=([bool]$f.SilverCoinsEligible -and [bool]$f.ChestSilverCoinsEligible)}
    })
    [pscustomobject]@{Schema=1;HostId=$script:peerHostId;HostName=[Environment]::MachineName;UpdatedUtc=[datetime]::UtcNow.ToString('o');Characters=$rows}
}
function ConvertFrom-PeerSnapshot([string]$json,[datetime]$now=[datetime]::UtcNow) {
    if($json.Length -gt 1048576){throw 'Resposta muito grande'}
    $data=$json|ConvertFrom-Json -ErrorAction Stop
    $id=[guid]::Empty;$stamp=[datetimeoffset]::MinValue
    if($data.Schema -ne 1 -or -not [guid]::TryParse([string]$data.HostId,[ref]$id) -or $id -eq [guid]::Empty){throw 'Identidade do outro Monitor invalida'}
    if(-not [datetimeoffset]::TryParse([string]$data.UpdatedUtc,[ref]$stamp) -or ($now-$stamp.UtcDateTime).TotalSeconds -gt 15 -or ($stamp.UtcDateTime-$now).TotalSeconds -gt 15){throw 'Dados antigos ou relogios dos PCs fora de sincronia'}
    if($data.Characters -isnot [array] -or $data.Characters.Count -gt 128){throw 'Lista de personagens invalida'}
    if([string]::IsNullOrWhiteSpace([string]$data.HostName) -or ([string]$data.HostName).Length -gt 100 -or $data.HostName -match '[\x00-\x1f]'){throw 'Nome do PC invalido'}
    $keys=@{}
    foreach($row in $data.Characters){
        foreach($field in @('Key','Name','Status','Server','Map','Fairy','XP')){
            if($row.$field -isnot [string] -or $row.$field.Length -gt 256 -or $row.$field -match '[\x00-\x1f]'){throw 'Texto de personagem invalido'}
        }
        if($null -ne $row.ActiveAlerts -and ($row.ActiveAlerts -isnot [string] -or $row.ActiveAlerts.Length -gt 1024 -or $row.ActiveAlerts -match '[\x00-\x1f]')){throw 'Avisos do outro PC invalidos'}
        if(-not $row.Key -or $keys.ContainsKey($row.Key)){throw 'Personagem duplicado na origem'};$keys[$row.Key]=$true
        foreach($field in @('HP','MaxHP','Level','Gold','ChestGold','Wealth','Coins','ChestCoins')){
            if($null -ne $row.$field){$value=0L;if(-not [long]::TryParse([string]$row.$field,[ref]$value) -or $value -lt 0 -or $value -gt 1000000000000000L){throw 'Valor numerico invalido'}}
        }
        if($row.Complete -isnot [bool] -or $row.CoinsComplete -isnot [bool]){throw 'Cobertura invalida'}
    }
    return $data
}
function Get-PeerSummary($local,$remote) {
    $wealth=[decimal]0;$cash=[decimal]0;$coins=[decimal]0;$online=0;$partial=($null -eq $local -or $null -eq $remote);$coinsPartial=$partial;$cashPartial=$partial
    foreach($snapshot in @($local,$remote)){
        if(-not $snapshot){continue}
        foreach($row in $snapshot.Characters){
            if($row.Status -ne 'Online'){continue}
            $online++;$wealth+=[decimal]$row.Wealth;$coins+=[decimal]$row.Coins+[decimal]$row.ChestCoins
            $cash+=[decimal]$row.Gold+[decimal]$row.ChestGold
            if($null -eq $row.Gold -or $null -eq $row.ChestGold){$cashPartial=$true}
            if(-not $row.Complete){$partial=$true};if(-not $row.CoinsComplete){$coinsPartial=$true}
        }
    }
    [pscustomobject]@{Online=$online;Wealth=$wealth;Cash=$cash;CashPartial=$cashPartial;Coins=$coins;Partial=$partial;CoinsPartial=$coinsPartial}
}
function Stop-PeerMonitor {
    if($script:peerLink){$script:peerLink.Dispose();$script:peerLink=$null}
    if($script:peerTask){[WydMonitor.PeerLink]::Observe($script:peerTask)}
    $script:peerTask=$null;$script:peerRemote=$null;$script:peerLocal=$null;$script:peerReceived=$null;$script:peerState='Desconectado'
}
function Update-PeerMonitor {
    if(-not $script:peerLink){return}
    $now=[datetime]::UtcNow
    if($script:peerTask -and $script:peerTask.IsCompleted){
        try{
            $remote=ConvertFrom-PeerSnapshot ($script:peerTask.GetAwaiter().GetResult()) $now
            if($remote.HostId -eq $script:peerHostId){throw 'Este endereco aponta para o proprio Monitor'}
            $script:peerRemote=$remote;$script:peerReceived=$now;$script:peerState='Conectado a '+$remote.HostName
        }catch{$script:peerRemote=$null;$script:peerState='Outro PC indisponivel: '+$_.Exception.GetBaseException().Message}
        finally{$script:peerTask=$null}
    }
    if($script:peerRemote -and (-not $script:peerReceived -or ($now-$script:peerReceived).TotalSeconds -gt 10 -or ($now-$script:peerReceived).TotalSeconds -lt 0)){$script:peerRemote=$null;$script:peerState='Conexao sem atualizacao; totais parciais'}
    if($now -lt $script:peerNext){return}
    $script:peerNext=$now.AddSeconds(2)
    try{$script:peerLocal=New-PeerSnapshot;$script:peerLink.Publish(($script:peerLocal|ConvertTo-Json -Depth 6 -Compress))}
    catch{$script:peerLocal=$null;$script:peerLink.Publish('{}');$script:peerState='Leitura local indisponivel'}
    if(-not $script:peerTask){$script:peerTask=$script:peerLink.FetchAsync($script:peerAddress,8766)}
}
function Initialize-PeerIdentity {
    $id=[guid]::Empty
    if($script:peerHostId){
        if(-not [guid]::TryParse([string]$script:peerHostId,[ref]$id) -or $id -eq [guid]::Empty){throw 'Identidade deste Monitor invalida; conexao indisponivel.'}
        return
    }
    $path=Join-Path $script:hostRoot 'config/peer-id.txt'
    if(Test-Path -LiteralPath $path){
        $text=([IO.File]::ReadAllText($path)).Trim()
        if(-not [guid]::TryParse($text,[ref]$id) -or $id -eq [guid]::Empty){throw 'Identidade deste Monitor invalida; peer-id.txt preservado. Corrija ou restaure o arquivo e reinicie.'}
    }else{
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        $id=[guid]::NewGuid()
        $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$bytes=[Text.Encoding]::ASCII.GetBytes($id.ToString());$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }
    $script:peerHostId=$id.ToString()
}
function Start-DesktopPeer([string]$address,[string]$key) {
    $target=$address.Trim();$sharedKey=$key.Trim()
    if(-not [WydMonitor.PeerLink]::IsLanAddress($target)){throw 'Informe o IPv4 privado do outro PC, por exemplo 192.168.1.20.'}
    $secret=$null
    try {
        if($sharedKey.Length -ne 44){throw 'Invalid key'}
        $secret=[Convert]::FromBase64String($sharedKey)
        if($secret.Length -ne 32){throw 'Invalid key'}
    }catch{throw 'Use a chave gerada pelo Monitor; copie a mesma chave nos dois PCs.'}
    finally{if($secret){[Array]::Clear($secret,0,$secret.Length)}}
    # Invalid input or identity must not tear down a working session.
    Initialize-PeerIdentity
    Stop-PeerMonitor
    $script:peerAddress=$target
    try {
        $script:peerLink=New-Object WydMonitor.PeerLink -ArgumentList $sharedKey,8766,$false
        $script:peerState='Aguardando outro PC';$script:peerNext=[datetime]::MinValue
        Update-PeerMonitor
    }catch{
        Stop-PeerMonitor
        $script:peerState='Nao foi possivel conectar: '+$_.Exception.GetBaseException().Message
        throw
    }
}
function Get-DesktopPeerDetails {
    $now=[datetime]::UtcNow
    if(-not $script:peerAddressesChecked -or ($now-$script:peerAddressesChecked).TotalSeconds -ge 30 -or ($now-$script:peerAddressesChecked).TotalSeconds -lt 0){
        $addresses=@()
        try {
            foreach($network in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()){
                if($network.OperationalStatus -ne [Net.NetworkInformation.OperationalStatus]::Up){continue}
                foreach($unicast in $network.GetIPProperties().UnicastAddresses){
                    $ip=$unicast.Address
                    if($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and -not [Net.IPAddress]::IsLoopback($ip) -and [WydMonitor.PeerLink]::IsLanAddress($ip.ToString())){$addresses+=$ip.ToString()}
                }
            }
        }catch{$addresses=@()}
        $script:peerAddresses=@($addresses | Sort-Object -Unique);$script:peerAddressesChecked=$now
    }
    $id=[guid]::Empty
    $identityAvailable=([guid]::TryParse([string]$script:peerHostId,[ref]$id) -and $id -ne [guid]::Empty)
    $freshRemote=($null -ne $script:peerRemote -and $script:peerReceived -and ($now-$script:peerReceived).TotalSeconds -ge 0 -and ($now-$script:peerReceived).TotalSeconds -le 10)
    [pscustomobject]@{HostName=[Environment]::MachineName;Addresses=@($script:peerAddresses);Address=[string]$script:peerAddress;State=$(if($script:peerState){[string]$script:peerState}else{'Desconectado'});Active=[bool]$script:peerLink;Connected=([bool]$script:peerLink -and [bool]$freshRemote);IdentityAvailable=$identityAvailable}
}
