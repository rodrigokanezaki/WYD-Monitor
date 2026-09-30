function New-AttentionState {
    [pscustomobject]@{Previous=@{};Disconnected=@{};Results=@{}}
}
function Get-CharacterAttention([WydMonitor.CharacterState]$character,[string]$inventoryAlert,$settings,[bool]$disconnected) {
    $result=[pscustomobject]@{Severity=0;Attention='';Buff=$character.XPBuffDetail}
    if($null -ne $script:alertSettings -and -not (Test-CharacterAlertsEnabled $character.Key)){return $result}
    $messages=New-Object 'System.Collections.Generic.List[string]'
    $result.Severity=0
    if($disconnected){$messages.Add('Desconectou após estar online');$result.Severity=3}
    if($character.Status -eq 'Online'){
        if($null -ne $character.HP -and $character.HP -eq 0){$messages.Add('HP zero');$result.Severity=3}
        if($character.Fairy -match 'esgotado'){$messages.Add('Fada: tempo esgotado');$result.Severity=[Math]::Max(2,$result.Severity)}
        elseif($character.Fairy -match '(?:^|\|\s*)00h 0[01]min$'){$messages.Add('Fada próxima de terminar');$result.Severity=[Math]::Max(2,$result.Severity)}
        elseif($character.FairyPresent -ne $false -and $character.Fairy -match 'Sem tempo|Nao confirmada|não confirmada'){$messages.Add('Fada sem tempo identificado');$result.Severity=[Math]::Max(1,$result.Severity)}
        if($inventoryAlert){$messages.Add($inventoryAlert);$result.Severity=[Math]::Max(1,$result.Severity)}
        if($character.Map -in @('-','Nao identificado','Não identificado','')){$messages.Add('Mapa não identificado');$result.Severity=[Math]::Max(1,$result.Severity)}
    }elseif($character.Status -ne 'Offline'){$messages.Add($character.Status+' · leitura indisponível');$result.Severity=[Math]::Max(2,$result.Severity)}
    if($settings -and $character.Status -eq 'Online'){
        if($settings.FairyMissingEnabled -and $settings.FairyMissing.Missing){$messages.Add('Sem Fada equipada');$result.Severity=[Math]::Max(2,$result.Severity)}
        if($settings.XPBuffEnabled -and $settings.XPBuffMissing.Missing){$messages.Add('Sem buff de XP');$result.Severity=[Math]::Max(2,$result.Severity)}
    }
    $result.Attention=$messages -join ' • '
    $result.Buff=$character.XPBuffDetail
    return $result
}
function Update-AttentionState($characterStates=$script:characterStates) {
    if($null -eq $characterStates -or $script:characterStateError){throw 'CharacterState unavailable; Attention evaluation skipped'}
    if($null -eq $script:attentionState){$script:attentionState=New-AttentionState}
    $state=$script:attentionState
    $results=@{}
    foreach($character in $characterStates.Values | Sort-Object Name){
        $key=$character.Key
        if($state.Previous[$key] -eq 'Online' -and $character.Status -eq 'Offline'){$state.Disconnected[$key]=$true}
        if($character.Status -eq 'Online'){$state.Disconnected.Remove($key)}
        $state.Previous[$key]=$character.Status
        $warning=Get-InventoryWarning $character.Key $character.Name
        $settings=if($script:rateTracker){$script:rateTracker.Get($key,$character.Name)}else{$null}
        $results[$key]=Get-CharacterAttention $character $warning $settings ([bool]$state.Disconnected[$key])
    }
    $state.Results=$results
}
function Clear-Attention {
    if($script:attentionState){
        if($null -eq $script:characterStates -or $script:characterStateError){throw 'CharacterState unavailable; Attention clear skipped'}
        $script:attentionState.Disconnected.Clear();Update-AttentionState
    }
}
