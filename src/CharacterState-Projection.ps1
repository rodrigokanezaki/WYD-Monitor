if(-not ('WydMonitor.CharacterState' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Monitor.CharacterState.cs')}
function Convert-CharacterItems($items) {
    if($null -eq $items){return $null}
    # CLR item collections use the C# bridge; dynamic/scalar inputs keep legacy binding.
    if($items -is [System.Collections.IList]){
        $typedCopy=$null
        if([WydMonitor.CharacterItemAdapter]::TryCopy($items,[ref]$typedCopy)){return ,$typedCopy}
    }
    $copy=New-Object 'System.Collections.Generic.List[WydMonitor.CharacterItemData]'
    foreach($item in $items){
        if($null -eq $item){$copy.Add($null);continue}
        $d=New-Object WydMonitor.CharacterItemData
        foreach($field in @('Slot','Position','ItemId','Quantity')){$d.$field=$item.$field}
        # Fresh typed DTO strings default to null. Assign only non-null values:
        # PowerShell converts null to empty when assigning a C# string property.
        foreach($field in @('Section','RawHex','Bag','Name')){if($null -ne $item.$field){$d.$field=$item.$field}}
        $copy.Add($d)
    }
    return ,$copy.ToArray()
}
function New-CharacterState($record,$observation,$previous) {
    $d=New-Object WydMonitor.CharacterStateData
    foreach($field in @('X','Y','FairyPresent','XPBuffPresent','Pid','Session','HP','MaxHP','Experience','Gold','GoldFresh','ChestGold','ChestGoldFresh','InventoryFresh')){$d.$field=$record.$field}
    # Preserve the fresh DTO's null rather than passing it through string binding.
    foreach($field in @('Key','Name','Status','Server','Map','Fairy','XPBuffDetail','LastSeen','Detail','InventoryAt','InventoryDetail')){if($null -ne $record.$field){$d.$field=$record.$field}}
    $d.HistoryLevel=$record.Level
    if($null -ne $record.Level){$d.LevelText=[string]$record.Level}
    [int]$levelNumber=0
    if([int]::TryParse($d.LevelText,[ref]$levelNumber)){$d.Level=$levelNumber}
    $d.Inventory=Convert-CharacterItems $record.Inventory
    $d.AllSlots=Convert-CharacterItems $record.AllSlots
    if($null -ne $observation){
        # TimeUtc is observation evidence, not the time the projection happens to run.
        if($observation.TimeUtc.Kind -eq [DateTimeKind]::Utc -and $observation.TimeUtc -ne [datetime]::MinValue){$d.ObservedAt=$observation.TimeUtc}
        $d.FairyMinutes=$observation.FairyMinutes;$d.FairyItem=$observation.FairyItem
        $d.XPBuffSlot=$observation.XPBuffSlot;$d.XPBuffSeconds=$observation.XPBuffSeconds
        $d.Accepted['Name']=[bool]$observation.Name
        $d.Accepted['Level']=($null -ne $observation.Level)
        foreach($field in @('Server','Map','X','Y','LastSeen')){$d.Accepted[$field]=($observation.Status -eq 'Online')}
        foreach($field in @('HP','MaxHP','Experience')){$d.Accepted[$field]=($null -ne $observation.$field)}
        $d.Accepted['Gold']=[bool]$record.GoldFresh;$d.Accepted['ChestGold']=[bool]$record.ChestGoldFresh
        $d.Accepted['InventoryAt']=[bool]$record.InventoryFresh
    }
    return New-Object WydMonitor.CharacterState -ArgumentList $d,$previous
}
function Publish-CharacterStates {
    # Shadow path only: errors must not enter the legacy read/merge invalidation path.
    try {
        $next=@{}
        foreach($record in $script:records.Values){
            $reading=if($script:characterObservations){$script:characterObservations[$record.Key]}else{$null}
            $previous=if($script:characterStates){$script:characterStates[$record.Key]}else{$null}
            $next[$record.Key]=New-CharacterState $record $reading $previous
        }
        $script:characterStates=$next
        $script:characterStateError=''
    } catch {
        $script:characterStateError=[string]$_
        Write-Error -ErrorRecord $_ -ErrorAction Continue
    }
}
