. (Join-Path $PSScriptRoot 'Monitor-Paths.ps1')
. (Join-Path $PSScriptRoot 'Idle-Limits.ps1')
function Initialize-Counters([string]$path) {
    $script:rateTracker=New-Object WydMonitor.RateTracker
    $script:ratesCanSave=$true
    $script:ratePath=if($path){$path}else{Get-MonitorDataPath 'WYD-Contadores.json'}
    Initialize-IdleLimits ([IO.Path]::ChangeExtension($script:ratePath,'limits.json'))
    if($UiTest -or -not (Test-Path $script:ratePath)){return}
    $script:ratesCanSave=$false
    $db=Get-Content $script:ratePath -Raw | ConvertFrom-Json
    if($db.Version -notin @(1,2,3,4) -or $db.Profile -ne [WydMonitor.Reader]::SupportedHash){throw 'Configuracao incompativel; arquivo preservado.'}
    if($db.Version -lt 4){Copy-Item -LiteralPath $script:ratePath -Destination ($script:ratePath+'.before-alerts-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')+'.bak')}
    if($null -ne $db.IdleMinutes){$script:rateTracker.IdleMinutes=[Math]::Max(0,[Math]::Min(1440,[int]$db.IdleMinutes))}
    if($null -ne $db.XPIdleMinutes){$script:rateTracker.XPIdleMinutes=[Math]::Max(0,[Math]::Min(1440,[int]$db.XPIdleMinutes))}
    foreach($saved in $db.Characters){
        $c=$script:rateTracker.Get($saved.Key,$saved.Name)
        if($db.Version -ge 3){$c.InventoryEnabled=[bool]$saved.InventoryEnabled;$c.XPEnabled=[bool]$saved.XPEnabled}
        if($db.Version -ge 4){$c.FairyMissingEnabled=[bool]$saved.FairyMissingEnabled;$c.XPBuffEnabled=[bool]$saved.XPBuffEnabled;$c.DeathCaptureEnabled=[bool]$saved.DeathCaptureEnabled}
    }
    $script:ratesCanSave=$true
}
function Save-Counters {
    if($UiTest -or -not $script:ratesCanSave -or $null -eq $script:rateTracker){return}
    $chars=@($script:rateTracker.Characters.Values | Select-Object Key,Name,InventoryEnabled,XPEnabled,FairyMissingEnabled,XPBuffEnabled,DeathCaptureEnabled)
    $db=[pscustomobject]@{Version=4;XPIdleMinutes=$script:rateTracker.XPIdleMinutes;IdleMinutes=$script:rateTracker.IdleMinutes;Profile=[WydMonitor.Reader]::SupportedHash;Characters=$chars}
    $temp=$script:ratePath+'.tmp';ConvertTo-Json -InputObject $db -Depth 8 | Set-Content $temp -Encoding UTF8
    if(Test-Path $script:ratePath){[IO.File]::Replace($temp,$script:ratePath,$script:ratePath+'.bak')}else{[IO.File]::Move($temp,$script:ratePath)}
}
function Get-CounterSummary([string]$key,[string]$name) {
    $c=$script:rateTracker.Get($key,$name);$now=[DateTime]::UtcNow
    $policy=($null -eq $script:alertSettings -or (Test-CharacterAlertsEnabled $key))
    [pscustomobject]@{xpAlert=$(if($policy -and $c.XPEnabled){$c.XPInactivity.Warning($script:rateTracker.GetEffectiveXPIdleMinutes($key),$now)}else{''});inventoryAlert=$(if($policy -and $c.InventoryEnabled){$c.Idle.Warning($script:rateTracker.GetEffectiveItemIdleMinutes($key),$now)}else{''});inventoryEnabled=$c.InventoryEnabled;xpEnabled=$c.XPEnabled}
}
function Get-InventoryWarning([string]$key,[string]$name) {
    if($null -eq $script:rateTracker){return ''}
    $c=$script:rateTracker.Get($key,$name);$now=[DateTime]::UtcNow
    $policy=($null -eq $script:alertSettings -or (Test-CharacterAlertsEnabled $key))
    $s=Get-CounterSummary $key $name
    $warnings=@($s.inventoryAlert;$s.xpAlert) | Where-Object {$_}
    if(@($warnings).Count -gt 1){return ('[!] Sem itens {0}m / XP {1}m' -f [int][Math]::Floor($c.Idle.Seconds/60),[int][Math]::Floor($c.XPInactivity.Seconds/60))}
    return ($warnings -join ' | ')
}
function Get-CharacterActiveAlerts($character) {
    $result=[pscustomobject]@{Drop='';XP='';Fairy='';Buff='';Text=''}
    if($character.Status -ne 'Online' -or -not (Test-CharacterAlertsEnabled $character.Key) -or -not $script:rateTracker){return $result}
    $settings=$script:rateTracker.Get($character.Key,$character.Name)
    $summary=Get-CounterSummary $character.Key $character.Name
    $result.Drop=([string]$summary.inventoryAlert).Replace('[!] Sem entrada ha','Sem drop há')
    $result.XP=([string]$summary.xpAlert).Replace('[!] Sem XP ha','Sem XP há')
    if($settings.FairyMissingEnabled){
        if($settings.FairyMissing.Missing){$result.Fairy='Sem fada equipada'}
        elseif($character.Fairy -match 'esgotado'){$result.Fairy='Fada: tempo esgotado'}
        elseif($character.Fairy -match '(?:^|\|\s*)00h 0[01]min$'){$result.Fairy='Fada próxima de terminar'}
    }
    if($settings.XPBuffEnabled -and $settings.XPBuffMissing.Missing){$result.Buff='Sem buff de XP'}
    $result.Text=(@($result.Drop,$result.XP,$result.Fairy,$result.Buff) | Where-Object {$_}) -join ' · '
    return $result
}
function Update-IdleNotifications {
    if($null -eq $script:characterStates -or $script:characterStateError){return}
    if($null -eq $script:idleNotifications){$script:idleNotifications=@{}}
    $next=@{}
    foreach($character in $script:characterStates.Values){
        $alerts=Get-CharacterActiveAlerts $character
        foreach($kind in @('Drop','XP')){
            $key=$character.Key+':'+$kind
            if($alerts.$kind){
                $next[$key]=$true
                if(-not $script:idleNotifications.ContainsKey($key)){Show-FairyAlert ($character.Name+': '+$alerts.$kind)}
            }
        }
    }
    $script:idleNotifications=$next
}
