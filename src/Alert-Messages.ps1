function Add-AlertMessage([string]$line,[switch]$Append,[switch]$Unbounded) {
    if($Append){$script:alertStore.Append($line)}else{$script:alertStore.InsertFirst($line,(-not $Unbounded))}
    Invoke-AlertEffect 'ListBox' {if($script:alertProjection){& $script:alertProjection ([bool]$Append) $false}}
}
function Clear-AlertMessages {
    $script:alertStore.Clear()
    if($script:attentionState){Clear-Attention}
    Invoke-AlertEffect 'ListBox' {if($script:alertProjection){& $script:alertProjection $false $true}}
}
