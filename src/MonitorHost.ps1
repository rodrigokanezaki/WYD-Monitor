# Single-runspace application host. No visual component is required.
foreach($dependency in @('Catalogo-Itens.ps1','Counter-Service.ps1','Finance-Projection.ps1','Mobile-Panel.ps1','Effect-Boundary.ps1','Alert-Messages.ps1','Attention-Service.ps1','CharacterState-Projection.ps1','Alert-Settings.ps1','Event-Schedule.ps1','Event-Runtime.ps1')){
    . (Join-Path $PSScriptRoot $dependency)
}
function Protect-Action([scriptblock]$action){
    try { & $action } catch { $script:lastError=[string]$_; Write-Error -ErrorRecord $_ -ErrorAction Continue }
}
function Read-MonitorMapRegions([string]$path) {
    $json=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    if(-not $json -or -not $json.TrimStart().StartsWith('[')){throw 'Mapas.json deve conter uma lista de regioes.'}
    $regions=New-Object 'System.Collections.Generic.List[WydMonitor.MapRegion]'
    foreach($entry in ($json | ConvertFrom-Json -ErrorAction Stop)){
        if($entry.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Name) -or $entry.Name.Length -gt 80 -or $entry.Name -match '[\x00-\x1f]'){throw 'Regiao de mapa com nome invalido.'}
        foreach($field in @('MinX','MaxX','MinY','MaxY')){
            $coordinate=0
            if(-not [int]::TryParse([string]$entry.$field,[ref]$coordinate) -or $coordinate -lt 0 -or $coordinate -ge 4096){throw 'Regiao de mapa com coordenadas invalidas.'}
        }
        if([int]$entry.MinX -gt [int]$entry.MaxX -or [int]$entry.MinY -gt [int]$entry.MaxY){throw 'Regiao de mapa com limites invertidos.'}
        $region=New-Object WydMonitor.MapRegion
        $region.Name=$entry.Name;$region.MinX=$entry.MinX;$region.MaxX=$entry.MaxX;$region.MinY=$entry.MinY;$region.MaxY=$entry.MaxY
        $regions.Add($region)
    }
    return ,$regions.ToArray()
}
function Update-MapCatalog([string]$path) {
    if($null -eq $script:characterStates -or $script:characterStateError){throw 'CharacterState unavailable; map update skipped'}
    $nextRegions=Read-MonitorMapRegions $path
    $nextReader=New-Object WydMonitor.Reader -ArgumentList (,([WydMonitor.MapRegion[]]$nextRegions))
    $script:regions=$nextRegions;$script:reader=$nextReader;$script:mapCatalogError=''
    # records remains the transitional builder; published CharacterState is immutable.
    foreach($character in $script:characterStates.Values){
        if($null -ne $character.X -and $null -ne $character.Y){
            $script:records[$character.Key].Map=[WydMonitor.Rules]::FindMap($character.X,$character.Y,[WydMonitor.MapRegion[]]$script:regions)
        }
    }
    Publish-CharacterStates
    $script:nextRead=[DateTime]::UtcNow;Update-MonitorConsumers
}
function Save-History {
    Save-Counters
    $script:lastSaved=[DateTime]::UtcNow
    if(-not $script:historyLoaded){return}
    if($null -eq $script:characterStates -or $script:characterStateError){throw 'CharacterState unavailable; history save skipped'}
    $history=@($script:characterStates.Values | Where-Object {$_.Key -notlike 'pid:*'} | Select-Object Key,Name,@{Name='Level';Expression={$_.HistoryLevel}},Server,Map,X,Y,LastSeen)
    ConvertTo-Json -InputObject $history -Depth 4 | Set-Content -LiteralPath ($script:statePath+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($script:statePath+'.tmp') -Destination $script:statePath -Force
    $script:lastSaved=[DateTime]::UtcNow
}
function Show-FairyAlert([string]$message){
    $line=('{0:HH:mm:ss}  {1}' -f (Get-Date),$message)
    Add-AlertMessage $line
    Invoke-AlertEffect 'Desktop' {if($script:hostDesktopAlert){& $script:hostDesktopAlert $line $message}}
}
function Update-MonitorConsumers {
    Protect-Action {Update-AttentionState}
    Protect-Action {Update-IdleNotifications}
    if(-not $UiTest -and $null -ne $script:mobileServer){
        try {Publish-MobilePanel; $script:lastMobileError=''}
        catch {
            $message=[string]$_
            $changed=($script:lastMobileError -cne $message)
            $script:lastMobileError=$message
            if($changed){Write-Error -ErrorRecord $_ -ErrorAction Continue}
        }
    }
    if($script:hostRender){Protect-Action {& $script:hostRender}}
}
function Merge-Readings($readings){
    $script:characterObservations=@{}
    if($null -eq $script:identityConflicts){$script:identityConflicts=New-Object 'System.Collections.Generic.HashSet[string]'}
    $seen=@{}
    foreach($r in [WydMonitor.ReadingIdentity]::Filter([WydMonitor.Reading[]]$readings,$script:identityConflicts)){
        $existing=$script:records.Values | Where-Object {$_.Pid -eq $r.Pid -and $_.Session -eq $r.Session} | Select-Object -First 1
        $key=if($r.Name){$r.Name.ToLowerInvariant()}elseif($existing){$existing.Key}else{'pid:'+$r.Pid+':'+$r.Session}
        $seen[$key]=$true
        if($existing -and $existing.Key -ne $key -and $existing.Key -like 'pid:*'){$script:records.Remove($existing.Key)}
        if(-not $script:records.ContainsKey($key)){
            $script:records[$key]=[pscustomobject]@{Key=$key;Name=('PID '+$r.Pid);Status='Desconhecido';Level='-';Server='-';Map='-';X=$null;Y=$null;Fairy='Nao confirmada';FairyPresent=$null;XPBuffPresent=$null;XPBuffDetail='Buff XP nao confirmado';Pid=$r.Pid;Session=$r.Session;LastSeen='-';Detail='';HP=$null;MaxHP=$null;Experience=$null;Gold=$null;GoldFresh=$false;ChestGold=$null;ChestGoldFresh=$false;AllSlots=@();Inventory=@();InventoryAt='';InventoryFresh=$false;InventoryDetail='Inventario ainda nao lido'}
        }
        $record=$script:records[$key]
        if($r.Status -eq [WydMonitor.ReadingIdentity]::ConflictStatus){
            # Do not retain values that may already have belonged to another namesake.
            $record.Level='-';$record.Server='-';$record.Map='-';$record.X=$null;$record.Y=$null;$record.LastSeen='-'
            $record.Gold=$null;$record.ChestGold=$null;$record.Inventory=$null;$record.AllSlots=$null;$record.InventoryAt=''
        }
        if($r.Name){$record.Name=$r.Name}; if($null -ne $r.Level){$record.Level=$r.Level}
        $settings=if($script:rateTracker){$script:rateTracker.Get($key,$record.Name)}else{$null}
        $record.FairyPresent=if($r.Status -eq 'Online'){$r.FairyPresent}else{$null};$record.XPBuffPresent=if($r.Status -eq 'Online'){$r.XPBuffPresent}else{$null};$record.XPBuffDetail=if($r.Status -eq 'Online'){$r.XPBuffDetail}else{'Buff XP nao confirmado'}
        if($settings){
            $alertsEnabled=($null -eq $script:alertSettings -or (Test-CharacterAlertsEnabled $key))
            if($settings.FairyMissing.Update(($settings.FairyMissingEnabled -and $alertsEnabled),$record.FairyPresent,$r.Session,$r.TimeUtc)){Show-FairyAlert ($record.Name+': sem Fada equipada.')}
            if($settings.XPBuffMissing.Update(($settings.XPBuffEnabled -and $alertsEnabled),$record.XPBuffPresent,$r.Session,$r.TimeUtc)){Show-FairyAlert ($record.Name+': sem buff de XP (Bonus EXP).')}
        }
        $record.Pid=$r.Pid; $record.Session=$r.Session; $record.Status=$r.Status; $record.Detail=$r.Detail
        if($r.Status -eq 'Online'){
            $record.Server=$r.Server; $record.Map=$r.Map; $record.X=$r.X; $record.Y=$r.Y
            if($script:regions -and $null -ne $r.X -and $null -ne $r.Y){$record.Map=[WydMonitor.Rules]::FindMap($r.X,$r.Y,[WydMonitor.MapRegion[]]$script:regions)}
            $record.LastSeen=$r.TimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
        }
        $record.HP=$r.HP;$record.MaxHP=$r.MaxHP
        if(-not $script:deathAlarms){$script:deathAlarms=@{}}
        if(-not $script:deathAlarms.ContainsKey($key)){$script:deathAlarms[$key]=New-Object WydMonitor.DeathAlarm}
        if(($script:deathAlarms[$key].Update($r)) -and ($null -eq $script:alertSettings -or (Test-CharacterAlertsEnabled $key))){
            Show-FairyAlert ($record.Name+': morte detectada (HP 0). Autor nao identificado.')
            if(-not $UiTest -and $settings -and $settings.DeathCaptureEnabled){[void]$script:deathCaptures.Add([pscustomobject]@{Name=$record.Name;Task=[WydMonitor.DeathCapture]::CaptureAsync($r.Pid,$r.Session,$record.Name,(Join-Path $script:hostRoot 'Capturas-Mortes'))})}
        }
        $record.Experience=$r.Experience
        $record.GoldFresh=($r.Status -eq 'Online' -and $null -ne $r.Gold)
        if($record.GoldFresh){$record.Gold=$r.Gold}
        $record.ChestGoldFresh=($r.Status -eq 'Online' -and $null -ne $r.ChestGold)
        if($record.ChestGoldFresh){$record.ChestGold=$r.ChestGold}
        $record.Fairy=if($r.Status -eq 'Online'){$r.Fairy}else{'Nao confirmada'}
        if($r.Status -eq 'Online' -and $null -ne $r.Inventory){
            $record.Inventory=@($r.Inventory)
            $record.AllSlots=if($null -ne $r.AllSlots){@($r.AllSlots)}else{@($r.Inventory)}
            $record.InventoryAt=$r.TimeUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
            $record.InventoryFresh=$true; $record.InventoryDetail=$r.InventoryDetail
        }else{
            $record.InventoryFresh=$false
            $record.InventoryDetail=if($r.InventoryDetail){$r.InventoryDetail}else{$r.Detail}
        }
        if(-not $script:alarms.ContainsKey($key)){$script:alarms[$key]=New-Object WydMonitor.FairyAlarm}
        if(($script:alarms[$key].Update($r)) -and ($null -eq $script:alertSettings -or (Test-CharacterAlertsEnabled $key))){Show-FairyAlert ($record.Name+': a Fada terminou ou foi retirada no fim do tempo.')}
        $script:characterObservations[$key]=$r
    }
    foreach($record in @($script:records.Values)){
        if(-not $seen.ContainsKey($record.Key)){
            $record.HP=$null;$record.MaxHP=$null;if($script:deathAlarms){$script:deathAlarms.Remove($record.Key)}
            $record.FairyPresent=$null;$record.XPBuffPresent=$null;$record.XPBuffDetail='Buff XP nao confirmado';if($script:rateTracker){$c=$script:rateTracker.Get($record.Key,$record.Name);$c.FairyMissing.Reset();$c.XPBuffMissing.Reset()}
            $record.Status='Offline'; $record.Fairy='Nao confirmada'; $record.Detail='Personagem ausente; dados da ultima leitura'
            $record.GoldFresh=$false;$record.ChestGoldFresh=$false; $record.InventoryFresh=$false; $record.InventoryDetail='Personagem offline; mostrando somente a ultima leitura'
            $record.Pid=0; $record.Session=0; $script:alarms.Remove($record.Key)
            if($record.Key -like 'pid:*'){$script:records.Remove($record.Key)}
        }
    }
    if(Get-Command Publish-CharacterStates -ErrorAction SilentlyContinue){Publish-CharacterStates}
}

function Initialize-MonitorHost([string]$Root,[switch]$TestMode) {
    $script:hostRoot=$Root
    $script:alertSettings=$null;$script:eventSchedule=$null
    if(-not $TestMode){
        Initialize-AlertSettings (Join-Path $Root 'config/alert-settings.json')
        Initialize-EventRuntime (Join-Path $Root 'config/events.json')
    }
    $script:characterStates=@{};$script:characterObservations=@{};$script:characterStateError=''
    $script:identityConflicts=New-Object 'System.Collections.Generic.HashSet[string]'
    $script:UiTest=[bool]$TestMode
    $script:hostRunning=$false;$script:hostStopped=$false;$script:hostPolling=$false
    $script:hostRender=$null;$script:hostStatus=$null;$script:hostDesktopAlert=$null
$script:alertStore=New-Object WydMonitor.AlertStore
$script:attentionState=New-AttentionState
$script:idleNotifications=@{}
$script:SoundEnabled=$true
$script:alertEffectErrors=@{}
$script:mobileServer=$null
$script:deathCaptures=New-Object System.Collections.ArrayList
$script:records=@{}; $script:deathAlarms=@{}; $script:alarms=@{}; $script:job=$null
$script:cancel=New-Object Threading.CancellationTokenSource
$script:nextRead=[DateTime]::UtcNow
$script:lastSaved=[DateTime]::UtcNow
$script:lastError=''
$script:lastUiError=''
$script:lastMobileError=''
$script:historyLoaded=$true
$script:statePath=Join-Path $script:hostRoot 'WYD-Monitor-Estado.json'
Protect-Action {Initialize-Counters (Join-Path $script:hostRoot 'WYD-Contadores.json')}
if(-not $UiTest){Protect-Action {Start-MobilePanel -DataRoot $script:hostRoot}}
if(-not $UiTest -and (Test-Path -LiteralPath $script:statePath)){ Protect-Action {
    $script:historyLoaded=$false
    foreach($saved in (Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json)){
        if(-not $saved.Name -or -not $saved.Key){throw 'Historico invalido; arquivo preservado para recuperacao'}
        $script:records[$saved.Key]=[pscustomobject]@{Key=$saved.Key;Name=$saved.Name;Status='Offline';Level=$saved.Level;Server=$saved.Server;Map=$saved.Map;X=$saved.X;Y=$saved.Y;Fairy='Nao confirmada';FairyPresent=$null;XPBuffPresent=$null;XPBuffDetail='Buff XP nao confirmado';Pid=0;Session=0;LastSeen=$saved.LastSeen;Detail='Historico; aguardando deteccao';HP=$null;MaxHP=$null;Experience=$null;Gold=$null;GoldFresh=$false;ChestGold=$null;ChestGoldFresh=$false;AllSlots=@();Inventory=@();InventoryAt='';InventoryFresh=$false;InventoryDetail='Inventario ainda nao lido nesta sessao'}
    }
    $script:historyLoaded=$true
} }
$script:regions=@();$script:mapCatalogError=''
try {$script:regions=Read-MonitorMapRegions (Join-Path $script:hostRoot 'Mapas.json')}
catch {
    $script:mapCatalogError='Mapas.json invalido ou indisponivel; arquivo preservado. Monitor iniciado sem mapas personalizados. Corrija ou restaure o arquivo e reinicie o Monitor.'
    Show-FairyAlert $script:mapCatalogError
}
$script:reader=New-Object WydMonitor.Reader -ArgumentList (,([WydMonitor.MapRegion[]]$regions))
Publish-CharacterStates

}
function Start-MonitorHost {
    if($script:hostStopped){throw 'Host encerrado; inicialize uma nova sessao antes de iniciar.'}
    if($script:hostRunning){return}
    $script:hostRunning=$true
    Update-MonitorConsumers
}
function Update-MonitorHost {
    if(-not $script:hostRunning -or $script:hostPolling){return}
    $script:hostPolling=$true
    try {
Protect-Action {
    foreach($capture in @($script:deathCaptures.ToArray())){
        if($capture.Task.IsCompleted){
            try{$path=$capture.Task.GetAwaiter().GetResult();Show-FairyAlert ($capture.Name+': screenshot salvo em '+$path)}
            catch{Show-FairyAlert ($capture.Name+': falha no screenshot: '+$_.Exception.Message)}
            [void]$script:deathCaptures.Remove($capture)
        }
    }
    if($null -ne $script:job -and $script:job.IsCompleted){
        try {
            $readings=$script:job.GetAwaiter().GetResult()
            # Uma falha do banco nao deve invalidar a leitura do jogo.
            Protect-Action {Update-ItemDatabase $readings (Join-Path $script:hostRoot 'Banco-Itens.json')}
            $script:rateTracker.Observe([WydMonitor.Reading[]]$readings)
            Merge-Readings $readings
        }
        catch {
            foreach($record in $script:records.Values){$record.GoldFresh=$false;$record.ChestGoldFresh=$false;$record.HP=$null;$record.MaxHP=$null;$script:deathAlarms.Clear();$record.FairyPresent=$null;$record.XPBuffPresent=$null;$record.XPBuffDetail='Buff XP nao confirmado';$c=$script:rateTracker.Get($record.Key,$record.Name);$c.FairyMissing.Reset();$c.XPBuffMissing.Reset();$record.Status='Leitura indisponivel';$record.Fairy='Nao confirmada';$record.Detail='Falha no ciclo de leitura; dados anteriores';$record.InventoryFresh=$false;$record.InventoryDetail=$record.Detail}
            $script:alarms.Clear(); $script:rateTracker.Observe([WydMonitor.Reading[]]@()); $script:characterObservations=@{}; if(Get-Command Publish-CharacterStates -ErrorAction SilentlyContinue){Publish-CharacterStates}; Update-MonitorConsumers; throw
        }
        finally {$script:job=$null; $script:nextRead=[DateTime]::UtcNow.AddSeconds(2)}
        Update-MonitorConsumers
    }
    if($null -eq $script:job -and [DateTime]::UtcNow -ge $script:nextRead){$script:job=$reader.ReadAsync($script:cancel.Token)}
    if($script:eventSchedule){Protect-Action {Update-EventRuntime ([datetimeoffset]::UtcNow)}}
    if($script:hostStatus){Protect-Action {& $script:hostStatus}}
    if(([DateTime]::UtcNow-$script:lastSaved).TotalSeconds -ge 30){Save-History}
}
    } finally {$script:hostPolling=$false}
}
function Stop-MonitorHost {
    if($script:hostStopped){return}
    $script:hostStopped=$true;$script:hostRunning=$false
    $script:cancel.Cancel()
    if($script:mobileServer){$script:mobileServer.Dispose()}
    if(-not $UiTest){Protect-Action {Save-History}}
    if($null -ne $script:job){try{[void]$script:job.GetAwaiter().GetResult()}catch{}}
    $script:job=$null
    $script:cancel.Dispose()
}
function Run-MonitorHost {
    Start-MonitorHost
    try {while($script:hostRunning){Update-MonitorHost;Start-Sleep -Milliseconds 250}}
    finally {Stop-MonitorHost}
}
