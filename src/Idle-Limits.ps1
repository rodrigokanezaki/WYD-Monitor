# Optional limits use the existing tracker/detectors; legacy counter JSON stays unchanged.
function ConvertTo-IdleOverride($value) {
    if($null -eq $value){return $null}
    if([string]$value -notmatch '^\d+$' -or [long]$value -gt 1440){throw 'Limite deve ser inteiro de 0 a 1440 minutos.'}
    return [int]$value
}
function Initialize-IdleLimits([string]$path) {
    $script:idleLimits=[pscustomobject]@{Path=$path;CanSave=$true;Error=''}
    if($UiTest -or -not (Test-Path -LiteralPath $path)){return}
    try {
        $db=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($db.Version -ne 1 -or $null -eq $db.Characters){throw 'Configuracao de limites invalida.'}
        $validated=@();$keys=@{}
        foreach($item in $db.Characters){
            if(-not $item.Key -or $keys.ContainsKey([string]$item.Key)){throw 'Chave ausente ou duplicada.'}
            $keys[[string]$item.Key]=$true
            $validated+= [pscustomobject]@{Key=[string]$item.Key;Item=(ConvertTo-IdleOverride $item.ItemIdleOverrideMinutes);XP=(ConvertTo-IdleOverride $item.XPIdleOverrideMinutes)}
        }
        foreach($item in $validated){$c=$script:rateTracker.Get($item.Key,$item.Key);$c.ItemIdleOverrideMinutes=$item.Item;$c.XPIdleOverrideMinutes=$item.XP}
    } catch {$script:idleLimits.CanSave=$false;$script:idleLimits.Error=[string]$_.Exception.Message}
}
function Get-CharacterIdleLimits([string]$key) {
    $c=$script:rateTracker.Characters[$key]
    [pscustomobject]@{ItemOverride=$(if($c){$c.ItemIdleOverrideMinutes}else{$null});XPOverride=$(if($c){$c.XPIdleOverrideMinutes}else{$null});ItemGlobal=$script:rateTracker.IdleMinutes;XPGlobal=$script:rateTracker.XPIdleMinutes;ItemEffective=$script:rateTracker.GetEffectiveItemIdleMinutes($key);XPEffective=$script:rateTracker.GetEffectiveXPIdleMinutes($key)}
}
function Set-CharacterIdleLimits([string]$key,[string]$name,$itemOverride,$xpOverride) {
    if(-not $key){throw 'Personagem nao identificado.'}
    $item=ConvertTo-IdleOverride $itemOverride;$xp=ConvertTo-IdleOverride $xpOverride
    if(-not $script:idleLimits -or -not $script:idleLimits.CanSave){throw 'Arquivo de limites indisponivel; configuracao preservada.'}
    $c=$script:rateTracker.Get($key,$name);$oldItem=$c.ItemIdleOverrideMinutes;$oldXP=$c.XPIdleOverrideMinutes
    $before=Get-CharacterIdleLimits $key
    try {
        $c.ItemIdleOverrideMinutes=$item;$c.XPIdleOverrideMinutes=$xp
        $path=$script:idleLimits.Path;$parent=Split-Path -Parent $path
        if(-not (Test-Path -LiteralPath $parent)){[void][IO.Directory]::CreateDirectory($parent)}
        $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        $entries=@($script:rateTracker.Characters.Values|Where-Object {$null -ne $_.ItemIdleOverrideMinutes -or $null -ne $_.XPIdleOverrideMinutes}|Sort-Object Key|Select-Object Key,ItemIdleOverrideMinutes,XPIdleOverrideMinutes)
        [pscustomobject]@{Version=1;Characters=$entries}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,$path+'.bak')}else{[IO.File]::Move($temp,$path)}
    } catch {$c.ItemIdleOverrideMinutes=$oldItem;$c.XPIdleOverrideMinutes=$oldXP;throw}
    finally {if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp}}
    $after=Get-CharacterIdleLimits $key
    # Crossing disabled/enabled starts a new baseline; positive limit edits preserve elapsed observation.
    if(($before.ItemEffective -eq 0) -ne ($after.ItemEffective -eq 0)){$c.Idle.Reset()}
    if(($before.XPEffective -eq 0) -ne ($after.XPEffective -eq 0)){$c.XPInactivity.Reset()}
}
