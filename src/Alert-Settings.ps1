# Independent policy; individual RateTracker preferences are never modified.
function Initialize-AlertSettings([string]$path) {
    $script:alertSettings=[pscustomobject]@{Path=$path;Disabled=@{};CanSave=$true;Error=''}
    if(-not (Test-Path -LiteralPath $path)){return}
    try {
        $db=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($db.Version -ne 1 -or $null -eq $db.Characters){throw 'Configuracao de alertas invalida.'}
        foreach($item in $db.Characters){
            if(-not $item.Key -or $item.AlertsEnabled -isnot [bool]){throw 'Politica de personagem invalida.'}
            if(-not $item.AlertsEnabled){$script:alertSettings.Disabled[[string]$item.Key]=$true}
        }
    } catch {$script:alertSettings.Disabled=@{};$script:alertSettings.CanSave=$false;$script:alertSettings.Error=[string]$_.Exception.Message}
}
function Test-CharacterAlertsEnabled([string]$key) {
    return ($null -eq $script:alertSettings -or -not $script:alertSettings.Disabled.ContainsKey($key))
}
function Set-CharacterAlertsEnabled([string[]]$keys,[bool]$enabled) {
    if($null -eq $script:alertSettings -or -not $script:alertSettings.CanSave){throw 'Configuracao de alertas indisponivel; arquivo preservado.'}
    $old=$script:alertSettings.Disabled.Clone()
    try {
        foreach($key in $keys){if($enabled){$script:alertSettings.Disabled.Remove($key)}else{$script:alertSettings.Disabled[$key]=$true}}
        $path=$script:alertSettings.Path;$directory=Split-Path -Parent $path
        if(-not (Test-Path -LiteralPath $directory)){[void][IO.Directory]::CreateDirectory($directory)}
        $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        $items=@($script:alertSettings.Disabled.Keys|Sort-Object|ForEach-Object {[pscustomobject]@{Key=$_;AlertsEnabled=$false}})
        [pscustomobject]@{Version=1;Characters=$items}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,$path+'.bak')}else{[IO.File]::Move($temp,$path)}
    } catch {$script:alertSettings.Disabled=$old;throw}
    finally {if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp}}
}
