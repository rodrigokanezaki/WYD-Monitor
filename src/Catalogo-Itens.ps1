# Catalogo local por perfil do cliente. Sem gravacoes na memoria do jogo.
function Update-ItemDatabase($readings,[string]$path) {
    $catalog=@{};$dirty=$false
    if(Test-Path -LiteralPath $path){
        $db=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if($db.Version -ne 1 -or $db.Profile -ne [WydMonitor.Reader]::SupportedHash){throw 'Banco de itens incompativel; arquivo preservado.'}
        foreach($item in $db.Items){$catalog[[string]$item.Id]=$item}
    }
    foreach($reading in $readings){
        if($reading.Status -ne 'Online' -or $null -eq $reading.AllSlots){continue}
        foreach($slot in $reading.AllSlots){
            if($slot.ItemId -eq 0){continue}
            $key=[string]$slot.ItemId
            $resolved=$slot.Name -and $slot.Name -notlike 'Item #*'
            $location=$slot.Section+'/'+$slot.Bag
            if(-not $catalog.ContainsKey($key)){
                $catalog[$key]=[pscustomobject]@{Id=$slot.ItemId;Name=$slot.Name;NameConfirmed=[bool]$resolved;FirstSeenUtc=$reading.TimeUtc.ToString('o');UpdatedUtc=$reading.TimeUtc.ToString('o');Locations=@($location);SampleRawHex=$slot.RawHex}
                $dirty=$true
            }else{
                $item=$catalog[$key]
                if($resolved -and (-not $item.NameConfirmed -or $item.Name -ne $slot.Name)){$item.Name=$slot.Name;$item.NameConfirmed=$true;$item.UpdatedUtc=$reading.TimeUtc.ToString('o');$dirty=$true}
                if($item.Locations -notcontains $location){$item.Locations=@($item.Locations)+$location;$item.UpdatedUtc=$reading.TimeUtc.ToString('o');$dirty=$true}
                if(-not $resolved -and $item.NameConfirmed){$slot.Name=$item.Name}
            }
        }
    }
    if($dirty){
        $db=[pscustomobject]@{Version=1;Profile=[WydMonitor.Reader]::SupportedHash;Items=@($catalog.Values | Sort-Object Id)}
        $temporary=$path+'.tmp'
        ConvertTo-Json -InputObject $db -Depth 6 | Set-Content -LiteralPath $temporary -Encoding UTF8
        if(Test-Path -LiteralPath $path){[IO.File]::Replace($temporary,$path,$path+'.bak')}else{[IO.File]::Move($temporary,$path)}
    }
}
