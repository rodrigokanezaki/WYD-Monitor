function Invoke-AlertEffect([string]$name,[scriptblock]$action) {
    try {& $action; if($script:alertEffectErrors){$script:alertEffectErrors.Remove($name)}}
    catch {
        if($null -eq $script:alertEffectErrors){$script:alertEffectErrors=@{}}
        $script:alertEffectErrors[$name]=[string]$_
    }
}
