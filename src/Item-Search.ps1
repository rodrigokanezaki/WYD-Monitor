function Find-GlobalItems($characters,[string]$query) {
    $query=$query.Trim();if(-not $query){return}
    foreach($record in $characters){
        $groups=@{}
        foreach($item in $record.AllSlots){
            if($item.ItemId -le 0){continue}
            if($record.Name.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0 -and $item.Name.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0 -and [string]$item.ItemId -ne $query){continue}
            $key=$item.Section+':'+$item.ItemId
            if(-not $groups.ContainsKey($key)){
                $groups[$key]=[pscustomobject]@{Key=$record.Key+':'+$key;Character=$record.Name;Item=$item.Name;ItemId=$item.ItemId;Area=$item.Section;Quantity=0L;Known=$true;Slots=@();Fresh=[bool]$record.InventoryFresh;Time=$record.InventoryAt}
            }
            $found=$groups[$key]
            if($null -eq $item.Quantity){$found.Known=$false}else{$found.Quantity+=$item.Quantity}
            $found.Slots+=$item.Slot
        }
        foreach($found in $groups.Values){if(-not $found.Known){$found.Quantity=$null};$found}
    }
}
function Get-ItemSearchResult($characters,[string]$query) {
    $matches=@(Find-GlobalItems $characters $query | Sort-Object Character,Item,Area)
    [long]$total=0;$uncertain=0
    foreach($match in $matches){
        if($match.Fresh -and $match.Known){$total+=$match.Quantity}else{$uncertain++}
    }
    $unavailable=@($characters | Where-Object {-not $_.InventoryFresh -or $_.AllSlots.Count -ne 223}).Count
    [pscustomobject]@{Matches=$matches;Total=$total;Uncertain=$uncertain;Unavailable=$unavailable}
}
