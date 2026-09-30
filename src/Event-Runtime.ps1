function Initialize-EventRuntime([string]$path) {
    $script:eventSchedule=New-EventSchedule $path
    Import-EventSchedule $script:eventSchedule
    $statePath=$path+'.reminders.json'
    if(Test-Path -LiteralPath $statePath){
        try {
            foreach($entry in @(Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json)){
                $script:eventSchedule.Sent[[string]$entry.Key]=[datetimeoffset]::Parse([string]$entry.Occurrence,[Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {$script:eventSchedule.Error='Historico de avisos invalido; avisos de eventos pausados.';$script:eventSchedule.CanSave=$false}
    }
    if($script:eventSchedule.CanSave -and -not (Test-Path -LiteralPath $path)){
        try {Save-EventSchedule $script:eventSchedule}
        catch {$script:eventSchedule.Error=[string]$_.Exception.Message;$script:eventSchedule.CanSave=$false}
    }
    $script:eventNextEvaluation=[datetimeoffset]::MinValue
    $script:upcomingEvents=@()
}
function Update-EventRuntime([datetimeoffset]$now) {
    if(-not $script:eventSchedule -or $now -lt $script:eventNextEvaluation){return}
    $script:eventNextEvaluation=$now.AddSeconds(1)
    if($script:eventSchedule.CanSave){
        # Evaluation mutates Sent and LastCheck. Roll back only if disk commit fails.
        # The existing one-minute catch-up window bounds retries of old reminders.
        $previousSent=$script:eventSchedule.Sent.Clone();$previousCheck=$script:eventSchedule.LastCheck
        $reminders=@(Get-DueEventReminders $script:eventSchedule $now)
        if($reminders.Count){
            # Persist deduplication before publishing: avoid repeats on restart.
            # A crash between these operations can omit an alert, never duplicate it.
            $path=$script:eventSchedule.Path+'.reminders.json';$temp=$path+'.tmp'
            $committed=$false
            try {
                $state=@(foreach($key in $script:eventSchedule.Sent.Keys){[pscustomobject]@{Key=$key;Occurrence=$script:eventSchedule.Sent[$key].ToString('o')}})
                ConvertTo-Json -InputObject $state -Depth 4|Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
                if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,$path+'.bak')}else{[IO.File]::Move($temp,$path)}
                $committed=$true;$script:eventSchedule.Error=''
                foreach($reminder in $reminders){Show-FairyAlert $reminder.Message}
            } catch {
                if(-not $committed){$script:eventSchedule.Sent=$previousSent;$script:eventSchedule.LastCheck=$previousCheck}
                $script:eventSchedule.Error='Nao foi possivel registrar ou apresentar o aviso da agenda: '+$_.Exception.Message
                throw
            }
            finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue}}
        }
    }
    $script:upcomingEvents=@(Get-UpcomingEvents $script:eventSchedule $now)
}
