. (Join-Path $PSScriptRoot 'Monitor-Paths.ps1')
function Start-MobilePanel([string]$DataRoot=(Get-MonitorUserRoot)) {
    $passwordPath=Join-Path $DataRoot 'Acesso-Celular-Senha.txt'
    if(-not (Test-Path -LiteralPath $passwordPath)){
        $bytes=New-Object byte[] 24;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
        [Convert]::ToBase64String($bytes) | Set-Content -LiteralPath $passwordPath -Encoding ASCII
    }
    $password=(Get-Content -LiteralPath $passwordPath -Raw).Trim()
    $script:mobileServer=New-Object WydMonitor.MobileServer -ArgumentList (Join-Path $PSScriptRoot '../mobile/index.html'),8765,$password
}
function Publish-MobilePanel() {
    if($null -eq $script:mobileServer){return}
    # Do not publish retained states after a projection error or fall back to records.
    if($null -eq $script:characterStates -or $script:characterStateError){throw 'CharacterState unavailable; mobile publication skipped'}
    $states=$script:characterStates
    $financialProjection=Get-FinancialProjection $states
    $characters=@(foreach($r in $states.Values | Sort-Object Name){
        $finance=$financialProjection.Characters[$r.Key]
        [pscustomobject]@{counters=(Get-CounterSummary $r.Key $r.Name);hp=$r.HP;maxHP=$r.MaxHP;name=$r.Name;status=$r.Status;level=$(if($null -ne $r.Level){$r.Level}elseif($r.LevelText){$r.LevelText}else{$null});server=$r.Server;map=$r.Map;x=$r.X;y=$r.Y;fairy=$r.Fairy;xpBuff=$r.XPBuffDetail;gold=$finance.Gold;chestGold=$finance.ChestGold;coins=$finance.SilverCoins;chestCoins=$finance.ChestSilverCoins;fresh=($r.GoldFresh -and $r.ChestGoldFresh -and $r.InventoryFresh);inventoryFresh=$r.InventoryFresh;lastSeen=$r.LastSeen;items=@(foreach($i in $r.AllSlots){if($i.ItemId -gt 0){[pscustomobject]@{name=$i.Name;id=$i.ItemId;quantity=$i.Quantity;area=$i.Section;slot=$i.Slot}}})}
    })
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $snapshot=[pscustomobject]@{monitorPid=$PID;monitorSession=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks;administrator=$isAdmin;updatedAt=[DateTime]::UtcNow.ToString('o');characters=$characters;total=$financialProjection.Total;coverage=$financialProjection.Coverage;alerts=@($script:alertStore.Snapshot(30))}
    $script:mobileServer.Publish((ConvertTo-Json -InputObject $snapshot -Depth 7 -Compress))
}
