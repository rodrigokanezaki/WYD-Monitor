function Convert-FinanceItems($items) {
    return ,([WydMonitor.FinanceItemAdapter]::Copy($items))
}
function Get-FinancialProjection($states=$script:characterStates) {
    if($null -eq $states -or $script:characterStateError){throw 'CharacterState unavailable; finance projection skipped'}
    $characters=@{}
    $results=New-Object 'System.Collections.Generic.List[WydMonitor.CharacterFinanceResult]'
    foreach($record in $states.Values | Sort-Object Name){
        $inputData=New-Object WydMonitor.CharacterFinanceInput
        $inputData.Gold=$record.Gold; $inputData.ChestGold=$record.ChestGold
        $inputData.GoldFresh=$record.GoldFresh; $inputData.ChestGoldFresh=$record.ChestGoldFresh; $inputData.InventoryFresh=$record.InventoryFresh
        $inputData.HasInventoryReading=[bool]$record.InventoryAt
        $inputData.Inventory=(Convert-FinanceItems $record.Inventory); $inputData.AllSlots=(Convert-FinanceItems $record.AllSlots)
        $result=[WydMonitor.FinanceProjection]::Project($inputData)
        $characters[$record.Key]=$result
        $results.Add($result)
    }
    $summary=[WydMonitor.FinanceProjection]::Summarize($results)
    $prefix=if($summary.Complete){'Gold total'}else{'Gold parcial'}
    [pscustomobject]@{
        Characters=$characters
        Summary=$summary
        Total=$summary.Total.ToString('N0',[Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
        Coverage="${prefix}: mochila + bau + moedas | $($summary.CompleteCount)/$($summary.CharacterCount) contas | 1 moeda = 1kk"
    }
}
