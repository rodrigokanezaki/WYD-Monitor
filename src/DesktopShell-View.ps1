# Presentation bridge: published local state and validated LAN snapshots stay separate.
function Read-DesktopPreferences {
    $path=Join-Path $script:hostRoot 'config/ui-preferences.json'
    $result=[pscustomobject]@{Path=$path;Mode='Gamer';Appearance='dark';Density='normal';SoundEnabled=[bool]$script:SoundEnabled;CanSave=$true;Error=''}
    if(Test-Path -LiteralPath $path){
        try {
            $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if($saved.Version -ne 1 -or $saved.Mode -notin @('Work','Gamer') -or $saved.SoundEnabled -isnot [bool]){throw 'Preferências de interface inválidas; arquivo preservado.'}
            $result.Mode=[string]$saved.Mode;$result.SoundEnabled=[bool]$saved.SoundEnabled
            if($saved.PSObject.Properties['Appearance']){if($saved.Appearance -notin @('dark','light','system')){throw 'Aparência inválida.'};$result.Appearance=$saved.Appearance}
            if($saved.PSObject.Properties['Density']){if($saved.Density -notin @('normal','compact')){throw 'Espaçamento inválido.'};$result.Density=$saved.Density}
        } catch {$result.CanSave=$false;$result.Error=$_.Exception.Message}
    }
    $script:desktopPreferences=$result
    return $result
}
function Save-DesktopPreferences([string]$mode,[bool]$soundEnabled,[string]$appearance='',[string]$density='') {
    if($mode -notin @('Work','Gamer')){throw 'Modo de interface inválido.'}
    if(-not $script:desktopPreferences -or -not $script:desktopPreferences.CanSave){throw 'Preferências indisponíveis; arquivo preservado.'}
    if(-not $appearance){$appearance=$script:desktopPreferences.Appearance};if(-not $density){$density=$script:desktopPreferences.Density}
    if($appearance -notin @('dark','light','system') -or $density -notin @('normal','compact')){throw 'Aparência inválida.'}
    $path=$script:desktopPreferences.Path;$temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [pscustomobject]@{Version=1;Mode=$mode;SoundEnabled=$soundEnabled;Appearance=$appearance;Density=$density}|ConvertTo-Json|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,$path+'.bak')}else{[IO.File]::Move($temp,$path)}
        $script:desktopPreferences.Mode=$mode;$script:desktopPreferences.SoundEnabled=$soundEnabled
        $script:desktopPreferences.Appearance=$appearance;$script:desktopPreferences.Density=$density
    } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Format-DesktopEffect($state,[bool]$xp,[datetime]$now) {
    if($state.Status -ne 'Online'){return 'Não confirmado'}
    $present=if($xp){$state.XPBuffPresent}else{$state.FairyPresent}
    if($present -eq $false){return 'Ausente'}
    $seconds=if($xp){$state.XPBuffSeconds}elseif($null -ne $state.FairyMinutes){[long]$state.FairyMinutes*60}else{$null}
    if($present -ne $true -or $null -eq $seconds){return 'Não confirmado'}
    if($null -ne $state.ObservedAt -and $state.ObservedAt.Kind -eq [DateTimeKind]::Utc -and $state.ObservedAt -ne [datetime]::MinValue){
        $seconds=[math]::Max(0,$seconds-[math]::Floor([math]::Max(0,($now-$state.ObservedAt).TotalSeconds)))
    }
    return (Format-DesktopDuration $seconds)
}
function Format-DesktopDuration($seconds) {
    if($null -eq $seconds){return 'Não confirmado'}
    $duration=[timespan]::FromSeconds([math]::Max(0,[long]$seconds))
    return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($duration.TotalHours),$duration.Minutes,$duration.Seconds)
}
function Get-DesktopItems($states,[string]$query) {
    $query=$query.Trim()
    $compare=[Globalization.CultureInfo]::GetCultureInfo('pt-BR').CompareInfo
    $options=[Globalization.CompareOptions]::IgnoreCase -bor [Globalization.CompareOptions]::IgnoreNonSpace
    foreach($state in $states.Values | Sort-Object Name){
        # The existing inventory projection preserves unknown quantities and prior readings.
        foreach($match in @(Find-GlobalItems @($state) ([string]$state.Name) | Sort-Object Item,Area)){
            $itemName=([string]$match.Item).Replace('_',' ')
            $haystack=$itemName+' '+$match.Character+' '+$match.Area+' '+$match.ItemId
            if($query -and $compare.IndexOf($haystack,$query,$options) -lt 0){continue}
            $item=New-Object WydMonitor.DesktopItem
            $item.Key=$script:desktopLocalHostId+':'+$match.Key
            $item.CharacterKey=$script:desktopLocalHostId+':'+$state.Key
            $item.Character=[string]$match.Character;$item.Item=$itemName;$item.ItemId=[string]$match.ItemId;$item.Area=[string]$match.Area
            $item.Quantity=if($match.Known){([long]$match.Quantity).ToString('N0',[Globalization.CultureInfo]::GetCultureInfo('pt-BR'))}else{'?'}
            $item.Fresh=if($match.Fresh -and $state.Status -eq 'Online'){'Atual'}else{'Anterior'}
            $readAt=[datetime]::MinValue
            $item.Time=if([datetime]::TryParse([string]$match.Time,[ref]$readAt)){$readAt.ToString('dd/MM HH:mm')}else{[string]$match.Time}
            $item.Origin='Este PC'
            $item
        }
    }
}
function New-DesktopSnapshot {
    $now=[datetime]::UtcNow
    $data=New-Object WydMonitor.DesktopSnapshot
    $data.SoundEnabled=[bool]$script:SoundEnabled
    $data.PeerConfigured=([bool]$script:peerLink -or -not [string]::IsNullOrWhiteSpace([string]$script:peerAddress))
    $remote=$script:peerRemote
    if($remote -and (-not $script:peerReceived -or ($now-$script:peerReceived).TotalSeconds -gt 10 -or ($now-$script:peerReceived).TotalSeconds -lt 0)){$remote=$null}
    if($remote -and $remote.HostId -eq $script:desktopLocalHostId){$remote=$null}
    $data.RemoteAvailable=($null -ne $remote)
    $data.RemoteStatus=if($remote){'Conectado a '+$remote.HostName}elseif($data.PeerConfigured){'Outro PC indisponível. Totais parciais.'}else{'Outro PC ainda não conectado.'}
    if($script:desktopIdentityError){$data.PeerConfigured=$true;$data.RemoteStatus=$script:desktopIdentityError}
    $localAvailable=($null -ne $script:characterStates -and -not $script:characterStateError)
    $data.LocalAvailable=$localAvailable
    $data.LocalStatus=if(-not $localAvailable){'Leitura local indisponível. Totais parciais.'}elseif($script:hostRunning){'Monitorando este PC'}else{'Monitor local pronto'}
    if($script:desktopPreferences -and $script:desktopPreferences.Error){$data.LocalStatus+=' | '+$script:desktopPreferences.Error}
    $problems=@()
    $readFailures=@($script:characterStates.Values | Where-Object {$_.Status -in @('Sem acesso','Incompativel','Leitura indisponivel')})
    if($readFailures.Count){
        $data.LocalStatus+=' | '+$readFailures.Count+' cliente(s) sem leitura. Veja os avisos.'
        foreach($failure in $readFailures){
            $reason=if($failure.Status -eq 'Sem acesso'){'O Windows negou acesso. Abra o Monitor como administrador se o jogo estiver elevado.'}else{[string]$failure.Detail}
            $problems+=([string]$failure.Name+': '+[string]$failure.Status+'. '+$reason)
        }
    }
    $readProblemCount=$problems.Count
    if(-not $script:ratesCanSave){$problems+='Configuração dos contadores indisponível; arquivo preservado.'}
    if($script:idleLimits -and $script:idleLimits.Error){$problems+='Limites de aviso: '+$script:idleLimits.Error}
    if($script:alertSettings -and $script:alertSettings.Error){$problems+='Seleção de avisos: '+$script:alertSettings.Error}
    if(-not $script:historyLoaded){$problems+='Histórico indisponível; arquivo preservado.'}
    if($problems.Count -gt $readProblemCount){$data.LocalStatus+=' | Configurações precisam de atenção.'}
    if($localAvailable){
        $finance=Get-FinancialProjection $script:characterStates
        foreach($state in $script:characterStates.Values | Sort-Object Name){
            $row=New-Object WydMonitor.DesktopCharacter
            $row.LocalKey=[string]$state.Key;$row.HostId=$script:desktopLocalHostId;$row.Key=$row.HostId+':'+$row.LocalKey
            $row.Name=[string]$state.Name;$row.Origin='Este PC';$row.IsRemote=$false;$row.Status=[string]$state.Status;$row.Online=($state.Status -eq 'Online')
            $row.Detail=[string]$state.Detail
            $row.ActiveAlerts=(Get-CharacterActiveAlerts $state).Text
            $row.Level=if($null -ne $state.Level){[string]$state.Level}else{'?'}
            $row.Server=[string]$state.Server;$row.Map=[string]$state.Map
            $row.HPKnown=($row.Online -and $null -ne $state.HP -and $null -ne $state.MaxHP -and $state.MaxHP -gt 0)
            if($row.HPKnown){$row.HPPercent=[int][math]::Max(0,[math]::Min(100,[math]::Round(100.0*$state.HP/$state.MaxHP)))}
            $row.Fairy=Format-DesktopEffect $state $false $now;$row.XP=Format-DesktopEffect $state $true $now
            $f=$finance.Characters[$state.Key]
            $row.CashPartial=$true;$row.CoinsPartial=$true;$row.WealthPartial=$true
            if($row.Online -and $f){
                if($f.GoldEligible){$row.Cash+=[long]$f.Gold};if($f.ChestGoldEligible){$row.Cash+=[long]$f.ChestGold}
                if($f.SilverCoinsEligible){$row.Coins+=[long]$f.SilverCoins};if($f.ChestSilverCoinsEligible){$row.Coins+=[long]$f.ChestSilverCoins}
                $row.Wealth=[long]$f.Wealth
                $row.CashPartial=(-not $f.GoldEligible -or -not $f.ChestGoldEligible)
                $row.CoinsPartial=(-not $f.SilverCoinsEligible -or -not $f.ChestSilverCoinsEligible);$row.WealthPartial=(-not $f.Complete)
            }
            $settings=$script:rateTracker.Get($state.Key,$state.Name);$limits=Get-CharacterIdleLimits $state.Key
            $row.Monitor=Test-CharacterAlertsEnabled $state.Key
            $row.DropMinutes=$limits.ItemEffective;$row.XPMinutes=$limits.XPEffective
            $row.DropAlert=($settings.InventoryEnabled -and $row.DropMinutes -gt 0);$row.XPAlert=($settings.XPEnabled -and $row.XPMinutes -gt 0)
            $row.FairyAlert=$settings.FairyMissingEnabled;$row.DeathCapture=$settings.DeathCaptureEnabled;$row.BuffAlert=$settings.XPBuffEnabled
            $data.Characters.Add($row)
        }
        foreach($item in @(Get-DesktopItems $script:characterStates ([string]$script:desktopItemQuery))){$data.Items.Add($item)}
    }
    if($remote){
        foreach($state in $remote.Characters | Sort-Object Name){
            $row=New-Object WydMonitor.DesktopCharacter
            $row.HostId=[string]$remote.HostId;$row.LocalKey=[string]$state.Key;$row.Key=$row.HostId+':'+$row.LocalKey
            $row.Name=[string]$state.Name;$row.Origin=[string]$remote.HostName;$row.IsRemote=$true;$row.Status=[string]$state.Status;$row.Online=($state.Status -eq 'Online')
            $row.ActiveAlerts=if($row.Online){[string]$state.ActiveAlerts}else{''}
            $row.Level=if($null -ne $state.Level){[string]$state.Level}else{'?'}
            $row.Server=[string]$state.Server;$row.Map=[string]$state.Map
            $row.HPKnown=($row.Online -and $null -ne $state.HP -and $null -ne $state.MaxHP -and $state.MaxHP -gt 0)
            if($row.HPKnown){$row.HPPercent=[int][math]::Max(0,[math]::Min(100,[math]::Round(100.0*$state.HP/$state.MaxHP)))}
            $row.Fairy=if($row.Online){[string]$state.Fairy}else{'Não confirmado'};$row.XP=if($row.Online){[string]$state.XP}else{'Não confirmado'}
            $row.CashPartial=$true;$row.CoinsPartial=$true;$row.WealthPartial=$true
            if($row.Online){
                $row.Cash=[long]$state.Gold+[long]$state.ChestGold;$row.Coins=[long]$state.Coins+[long]$state.ChestCoins;$row.Wealth=[long]$state.Wealth
                $row.CashPartial=($null -eq $state.Gold -or $null -eq $state.ChestGold);$row.CoinsPartial=(-not $state.CoinsComplete);$row.WealthPartial=(-not $state.Complete)
            }
            $data.Characters.Add($row)
        }
    }
    $data.ItemStatus=if($localAvailable){'Leituras anteriores estão identificadas; ? indica quantidade não confirmada.'}else{'Leitura local indisponível. Aguarde a próxima leitura.'}
    $events=@()
    if($script:eventSchedule){
        if($script:eventSchedule.Error){$events+=[string]$script:eventSchedule.Error}
        foreach($event in @(Get-UpcomingEvents $script:eventSchedule ([datetimeoffset]$now) | Select-Object -First 6)){
            $remaining=Format-DesktopDuration ([long][math]::Max(0,($event.Utc.UtcDateTime-$now).TotalSeconds))
            $events+=('{0} | {1} ({2}) | Faltam {3}' -f $event.Name,$event.Official.ToString('dd/MM HH:mm'),$event.TimeZone,$remaining)
        }
    }
    $data.EventText=if($events.Count){$events -join "`r`n"}else{'Nenhum evento futuro configurado.'}
    $activity=if($script:alertStore){@($script:alertStore.Snapshot(8))}else{@()}
    if($script:lastError){$problems+='Último erro: '+[string]$script:lastError}
    $activity=@($problems)+@($activity)
    $data.ActivityText=if($activity.Count){$activity -join "`r`n"}else{'Nenhum aviso nesta sessão.'}
    $peerDetails=Get-DesktopPeerDetails
    foreach($field in @('HostName','Addresses','Address','State','Active','Connected','IdentityAvailable')){$data.Peer.$field=$peerDetails.$field}
    if($script:desktopIdentityError){$data.Peer.State=$script:desktopIdentityError;$data.Peer.IdentityAvailable=$false}
    if($script:eventSchedule){
        $data.EventsWritable=$script:eventSchedule.CanSave
        foreach($definition in $script:eventSchedule.Events){
            $entry=New-Object WydMonitor.DesktopEvent
            foreach($field in @('Id','Name','TimeZone','RecurrenceType','SpecificDate','Notes','Enabled','Times','DaysOfWeek','ReminderOffsets','DayOfMonth')){$entry.$field=$definition.$field}
            $data.Events.Add($entry)
        }
    }
    return $data
}
function Update-DesktopShell([switch]$Force) {
    if(-not $script:desktopShell -or $script:desktopShell.IsDisposed){return}
    $now=[datetime]::UtcNow
    if(-not $Force -and $script:desktopLastUpdate -and ($now-$script:desktopLastUpdate).TotalSeconds -lt 1){return}
    $script:desktopLastUpdate=$now
    $script:desktopShell.Publish((New-DesktopSnapshot))
}
function Get-DesktopLocalCharacter([string]$key) {
    if(-not $key -or $null -eq $script:characterStates -or $script:characterStateError){throw 'Personagem local indisponível.'}
    $prefix=$script:desktopLocalHostId+':'
    if(-not $key.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Configure os avisos e o inventário deste personagem no PC de origem.'}
    $localKey=$key.Substring($prefix.Length)
    if(-not $script:characterStates.ContainsKey($localKey)){throw 'Personagem não encontrado neste PC.'}
    return $script:characterStates[$localKey]
}
function Invoke-DesktopCommand($commandArgs) {
    switch([string]$commandArgs.Command){
        'mode' {Save-DesktopPreferences $commandArgs.Value ([bool]$script:SoundEnabled);$script:desktopShell.SetMode($script:desktopPreferences.Mode);return}
        'appearance' {Save-DesktopPreferences $script:desktopPreferences.Mode ([bool]$script:SoundEnabled) $commandArgs.Value $script:desktopPreferences.Density;$script:desktopShell.SetAppearance($script:desktopPreferences.Appearance,$script:desktopPreferences.Density);return}
        'density' {Save-DesktopPreferences $script:desktopPreferences.Mode ([bool]$script:SoundEnabled) $script:desktopPreferences.Appearance $commandArgs.Value;$script:desktopShell.SetAppearance($script:desktopPreferences.Appearance,$script:desktopPreferences.Density);return}
        'sound' {Save-DesktopPreferences $script:desktopPreferences.Mode ([bool]$commandArgs.Enabled);$script:SoundEnabled=[bool]$commandArgs.Enabled;Update-DesktopShell -Force;return}
        'item-search' {$script:desktopItemQuery=[string]$commandArgs.Value;Update-DesktopShell -Force;return}
        'peers' {$script:desktopShell.Navigate('connections');return}
        'events' {$script:desktopShell.Navigate('events');return}
        'peer-generate' {$script:desktopShell.SendPeerKey([WydMonitor.PeerLink]::NewKey());return}
        'peer-connect' {
            if($script:desktopIdentityError){throw $script:desktopIdentityError}
            $connection=[string]$commandArgs.Value|ConvertFrom-Json -ErrorAction Stop
            Start-DesktopPeer ([string]$connection.address) ([string]$connection.key)
            Update-DesktopShell -Force;return
        }
        'peer-disconnect' {Stop-PeerMonitor;Update-DesktopShell -Force;return}
        'event-save' {
            $definition=[string]$commandArgs.Value|ConvertFrom-Json -ErrorAction Stop
            if(-not $definition.Id){$definition|Add-Member NoteProperty Id ('custom-'+[guid]::NewGuid().ToString('N')) -Force}
            if($definition.Name -isnot [string] -or $definition.Name.Length -gt 80 -or $definition.Name -match '[\x00-\x1f]' -or ([string]$definition.Notes).Length -gt 500){throw 'Revise o nome e a observação do evento.'}
            Set-ScheduledEvent $script:eventSchedule $definition
            Update-DesktopShell -Force;return
        }
        'event-toggle' {
            $definition=@($script:eventSchedule.Events|Where-Object Id -EQ $commandArgs.Key|Select-Object -First 1)[0]
            if(-not $definition){throw 'Evento não encontrado.'}
            $updated=$definition|ConvertTo-Json -Depth 5|ConvertFrom-Json
            $updated.Enabled=[bool]$commandArgs.Enabled
            Set-ScheduledEvent $script:eventSchedule $updated
            Update-DesktopShell -Force;return
        }
        'event-delete' {Remove-ScheduledEvent $script:eventSchedule ([string]$commandArgs.Key);Update-DesktopShell -Force;return}
        'refresh' {$script:nextRead=[datetime]::UtcNow;Update-DesktopShell -Force;return}
        'about' {$script:desktopShell.Navigate('settings');return}
        'test-alert' {Show-FairyAlert 'Teste: este e o aviso de fim da Fada.';return}
        'clear-alerts' {Clear-AlertMessages;Update-DesktopShell -Force;return}
        'fullscreen' {
            if($form.FormBorderStyle -eq 'None'){$form.FormBorderStyle='Sizable';$form.WindowState='Normal'}else{$form.FormBorderStyle='None';$form.WindowState='Maximized'}
            return
        }
    }
    $state=Get-DesktopLocalCharacter ([string]$commandArgs.Key)
    $key=$state.Key;$settings=$script:rateTracker.Get($key,$state.Name)
    switch([string]$commandArgs.Command){
        'open-character' {
            if(-not $UiTest -and $state.Status -eq 'Online' -and $state.Pid -gt 0){
                $process=Get-Process -Id $state.Pid -ErrorAction SilentlyContinue
                if($process -and $process.StartTime.ToUniversalTime().Ticks -eq $state.Session -and $process.MainWindowHandle -ne [IntPtr]::Zero){[WydMonitor.DesktopShell]::FocusGameWindow($process.MainWindowHandle)}
            }
            return
        }
        'inventory' {$script:desktopItemQuery=$state.Name;$script:desktopShell.Navigate('items');$script:desktopShell.SetItemQuery($state.Name);Update-DesktopShell -Force;return}
        'monitor' {Set-CharacterAlertsEnabled @($key) ([bool]$commandArgs.Enabled)}
        {$_ -in @('drop-minutes','xp-minutes')} {
            $limits=Get-CharacterIdleLimits $key
            if($_ -eq 'drop-minutes'){Set-CharacterIdleLimits $key $state.Name $commandArgs.Minutes $limits.XPOverride}
            else{Set-CharacterIdleLimits $key $state.Name $limits.ItemOverride $commandArgs.Minutes}
        }
        {$_ -in @('drop','xp','fairy','death','buff')} {
            if(-not $script:ratesCanSave){throw 'Configuração de avisos indisponível; arquivo preservado.'}
            $fields=@{drop='InventoryEnabled';xp='XPEnabled';fairy='FairyMissingEnabled';death='DeathCaptureEnabled';buff='XPBuffEnabled'}
            $field=$fields[$_];$previous=$settings.$field;$limits=Get-CharacterIdleLimits $key;$changedLimit=$false
            try {
                if($commandArgs.Enabled -and $_ -eq 'drop' -and $limits.ItemEffective -eq 0){$minutes=if($limits.ItemGlobal -gt 0){$limits.ItemGlobal}else{20};Set-CharacterIdleLimits $key $state.Name $minutes $limits.XPOverride;$changedLimit=$true}
                if($commandArgs.Enabled -and $_ -eq 'xp' -and $limits.XPEffective -eq 0){$minutes=if($limits.XPGlobal -gt 0){$limits.XPGlobal}else{10};Set-CharacterIdleLimits $key $state.Name $limits.ItemOverride $minutes;$changedLimit=$true}
                $settings.$field=[bool]$commandArgs.Enabled;Save-Counters
            } catch {
                $settings.$field=$previous
                if($changedLimit){Set-CharacterIdleLimits $key $state.Name $limits.ItemOverride $limits.XPOverride}
                throw
            }
            switch($_){'drop'{$settings.Idle.Reset()};'xp'{$settings.XPInactivity.Reset()};'fairy'{$settings.FairyMissing.Reset()};'buff'{$settings.XPBuffMissing.Reset()}}
        }
        default {throw 'Ação de interface desconhecida.'}
    }
    Update-AttentionState
    Update-DesktopShell -Force
}
function Initialize-DesktopShell {
    [void](Read-DesktopPreferences)
    $script:SoundEnabled=$script:desktopPreferences.SoundEnabled
    $script:desktopIdentityError=''
    $previousPeerHostId=$script:peerHostId
    try {Initialize-PeerIdentity;$script:desktopLocalHostId=[string]$script:peerHostId}
    catch {
        $script:peerHostId=$previousPeerHostId
        $script:desktopLocalHostId='session-'+[guid]::NewGuid().ToString('N')
        $script:desktopIdentityError='Identidade de rede indisponível; monitor local ativo. Corrija config/peer-id.txt na pasta de dados e reinicie. Arquivo preservado.'
    }
    $script:desktopItemQuery='';$script:desktopLastUpdate=$null
    $script:desktopShell=New-Object WydMonitor.DesktopShell
    $script:desktopShell.Dock='Fill';$script:desktopShell.SetMode($script:desktopPreferences.Mode)
    $script:desktopShell.SetAppearance($script:desktopPreferences.Appearance,$script:desktopPreferences.Density)
    $script:desktopShell.Configure((Join-Path $script:desktopAppRoot 'assets/desktop'),(Join-Path $script:hostRoot 'WebView2'))
    $script:desktopShell.Add_Command({
        param($sender,$commandArgs)
        try {Invoke-DesktopCommand $commandArgs}
        catch {
            $script:lastError=$_.Exception.Message
            $script:desktopShell.SetMode($script:desktopPreferences.Mode)
            Protect-Action {Update-DesktopShell -Force}
            $script:desktopShell.ReportError($script:lastError)
        }
    })
    $form.Controls.Add($script:desktopShell)
    $script:desktopShell.BringToFront()
    Update-DesktopShell -Force
}
