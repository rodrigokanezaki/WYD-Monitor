# Independent schedule service. All evaluation accepts an absolute, injectable clock.
function Resolve-EventTimeZone([string]$id) {
    $aliases=@{'America/Sao_Paulo'='E. South America Standard Time';'Europe/Dublin'='GMT Standard Time';'Etc/UTC'='UTC'}
    try {return [TimeZoneInfo]::FindSystemTimeZoneById($id)} catch {
        if($aliases.ContainsKey($id)){return [TimeZoneInfo]::FindSystemTimeZoneById($aliases[$id])}
        throw "Fuso desconhecido: $id. Use um identificador suportado pelo Windows."
    }
}
function ConvertTo-EventDefinition($event) {
    if(-not $event.Id -or -not $event.Name){throw 'Evento precisa de Id e nome.'}
    $zone=Resolve-EventTimeZone ([string]$event.TimeZone)
    $kind=([string]$event.RecurrenceType).ToUpperInvariant()
    if($kind -notin @('DAILY','WEEKLY','MONTHLY','ONCE')){throw 'Recorrencia invalida.'}
    $times=@(@(foreach($time in $event.Times){
        $parsed=[datetime]::MinValue
        if(-not [datetime]::TryParseExact([string]$time,'HH:mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)){throw "Horario invalido: $time"}
        $parsed.ToString('HH:mm')
    }) | Sort-Object -Unique)
    if(-not $times.Count){throw 'Informe pelo menos um horario.'}
    $days=@(@(foreach($day in $event.DaysOfWeek){
        if([string]$day -notmatch '^[0-6]$'){throw 'Dias da semana: 0=domingo ate 6=sabado.'};[int]$day
    }) | Sort-Object -Unique)
    if($kind -eq 'WEEKLY' -and -not $days.Count){throw 'Selecione dias da semana.'}
    $monthDay=0
    if($kind -eq 'MONTHLY'){
        if([string]$event.DayOfMonth -notmatch '^([1-9]|[12][0-9]|3[01])$'){throw 'Dia do mes invalido.'};$monthDay=[int]$event.DayOfMonth
    }
    $date=''
    if($kind -eq 'ONCE'){
        $parsed=[datetime]::MinValue
        if(-not [datetime]::TryParseExact([string]$event.SpecificDate,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)){throw 'Data invalida: use yyyy-MM-dd.'}
        $date=$parsed.ToString('yyyy-MM-dd')
    }
    $reminders=@(@(foreach($offset in $event.ReminderOffsets){
        if([string]$offset -notmatch '^\d+$' -or [long]$offset -gt 10080){throw 'Aviso deve ser de 0 a 10080 minutos.'};[int]$offset
    }) | Sort-Object -Unique)
    if($event.Enabled -isnot [bool]){throw 'Enabled deve ser booleano.'}
    [pscustomobject]@{Id=[string]$event.Id;Name=[string]$event.Name;Enabled=[bool]$event.Enabled;TimeZone=[string]$event.TimeZone;RecurrenceType=$kind;Times=$times;DaysOfWeek=$days;DayOfMonth=$monthDay;SpecificDate=$date;ReminderOffsets=$reminders;Notes=[string]$event.Notes}
}
function New-EventSchedule([string]$path) {
    [pscustomobject]@{Path=$path;Events=@();Sent=@{};LastCheck=$null;CanSave=$true;Error=''}
}
function Get-DefaultEvents {
    foreach($pair in @(@('arena','Arena',@('11:00','17:00','19:00','22:00')),@('king-tauron','King of Tauron',@('11:30','14:30','17:30','20:30')),@('tower-war','Guerra de torre',@('21:30')),@('king-tower','King Tower',@('21:45')))){
        ConvertTo-EventDefinition ([pscustomobject]@{Id=$pair[0];Name=$pair[1];Enabled=$true;TimeZone='America/Sao_Paulo';RecurrenceType='DAILY';Times=$pair[2];DaysOfWeek=@();DayOfMonth=0;SpecificDate='';ReminderOffsets=@(15,5,0);Notes=$(if($pair[0] -eq 'tower-war'){'No TS'}else{''})})
    }
    ConvertTo-EventDefinition ([pscustomobject]@{Id='kefra';Name='Kefra';Enabled=$true;TimeZone='America/Sao_Paulo';RecurrenceType='WEEKLY';Times=@('20:00');DaysOfWeek=@(3);DayOfMonth=0;SpecificDate='';ReminderOffsets=@(15,5,0);Notes=''})
}
function Import-EventSchedule($service) {
    try {
        if(-not (Test-Path -LiteralPath $service.Path)){$service.Events=@(Get-DefaultEvents);return}
        $db=Get-Content -LiteralPath $service.Path -Raw | ConvertFrom-Json
        if($db.Version -ne 1 -or $null -eq $db.Events){throw 'Agenda invalida ou versao desconhecida.'}
        $events=@(foreach($item in $db.Events){ConvertTo-EventDefinition $item})
        if(@($events.Id|Sort-Object -Unique).Count -ne $events.Count){throw 'Ids duplicados.'}
        $service.Events=$events;$service.CanSave=$true;$service.Error=''
    } catch {$service.Events=@();$service.CanSave=$false;$service.Error=[string]$_.Exception.Message}
}
function Save-EventSchedule($service) {
    if(-not $service.CanSave){throw 'Agenda invalida preservada; corrija o arquivo antes de salvar.'}
    $parent=Split-Path -Parent $service.Path
    if($parent -and -not (Test-Path -LiteralPath $parent)){[void][IO.Directory]::CreateDirectory($parent)}
    $temp=$service.Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [pscustomobject]@{Version=1;Events=@($service.Events)}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $service.Path){[IO.File]::Replace($temp,$service.Path,$service.Path+'.bak')}else{[IO.File]::Move($temp,$service.Path)}
    } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Set-ScheduledEvent($service,$event) {
    $normalized=ConvertTo-EventDefinition $event
    $old=$service.Events
    try {$service.Events=@($old|Where-Object Id -NE $normalized.Id)+@($normalized);Save-EventSchedule $service}
    catch {$service.Events=$old;throw}
}
function Remove-ScheduledEvent($service,[string]$id) {
    $old=$service.Events
    try {$service.Events=@($old|Where-Object Id -NE $id);Save-EventSchedule $service}
    catch {$service.Events=$old;throw}
}
function Get-NextOccurrence($event,[datetimeoffset]$now,[TimeZoneInfo]$localZone=[TimeZoneInfo]::Local) {
    if(-not $event.Enabled){return $null}
    $zone=Resolve-EventTimeZone $event.TimeZone
    $start=[TimeZoneInfo]::ConvertTime($now,$zone).Date
    $dates=@()
    switch($event.RecurrenceType){
        'DAILY' {$dates=@($start,$start.AddDays(1),$start.AddDays(2))}
        'WEEKLY' {$dates=@(0..8|ForEach-Object {$d=$start.AddDays($_);if([int]$d.DayOfWeek -in $event.DaysOfWeek){$d}})}
        'MONTHLY' {$first=New-Object datetime($start.Year,$start.Month,1);$dates=@(0..24|ForEach-Object {$m=$first.AddMonths($_);if($event.DayOfMonth -le [datetime]::DaysInMonth($m.Year,$m.Month)){$m.AddDays($event.DayOfMonth-1)}})}
        'ONCE' {$dates=@([datetime]::ParseExact($event.SpecificDate,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture))}
    }
    foreach($date in $dates){foreach($time in $event.Times){
        $wall=[datetime]::SpecifyKind($date.Add([timespan]::ParseExact($time,'hh\:mm',[Globalization.CultureInfo]::InvariantCulture)),[DateTimeKind]::Unspecified)
        # Nonexistent DST wall times are skipped. Ambiguous times fire once, at the earlier instant.
        if($zone.IsInvalidTime($wall)){continue}
        $offset=if($zone.IsAmbiguousTime($wall)){@($zone.GetAmbiguousTimeOffsets($wall)|Sort-Object -Descending)[0]}else{$zone.GetUtcOffset($wall)}
        $instant=New-Object datetimeoffset($wall,$offset)
        if($instant -lt $now){continue}
        return [pscustomobject]@{EventId=$event.Id;Name=$event.Name;Utc=$instant.ToUniversalTime();Official=$instant;Local=[TimeZoneInfo]::ConvertTime($instant,$localZone);Remaining=($instant-$now);TimeZone=$event.TimeZone}
    }}
    return $null
}
function Get-UpcomingEvents($service,[datetimeoffset]$now,[TimeZoneInfo]$localZone=[TimeZoneInfo]::Local) {
    @(foreach($event in $service.Events){$next=Get-NextOccurrence $event $now $localZone;if($next){$next}})|Sort-Object Utc,EventId
}
function Get-DueEventReminders($service,[datetimeoffset]$now,[TimeZoneInfo]$localZone=[TimeZoneInfo]::Local) {
    # On startup/resume, do not flood the user with old reminders. Maximum catch-up: one minute.
    $from=$now.AddMinutes(-1)
    if($null -ne $service.LastCheck -and $service.LastCheck -gt $from){$from=$service.LastCheck}
    if($from -gt $now){$from=$now}
    $service.LastCheck=$now
    foreach($key in @($service.Sent.Keys)){if($service.Sent[$key] -lt $now.AddDays(-1)){$service.Sent.Remove($key)}}
    foreach($event in $service.Events){foreach($offset in $event.ReminderOffsets){
        $cursor=$from.AddMinutes($offset)
        while($true){
        $next=Get-NextOccurrence $event $cursor $localZone
        if(-not $next){break}
        $due=$next.Utc.AddMinutes(-$offset)
        if($due -gt $now){break}
        $cursor=$next.Utc.AddTicks(1)
        $key=$event.Id+'|'+$next.Utc.UtcTicks+'|'+$offset
        if($due -lt $from -or $service.Sent.ContainsKey($key)){continue}
        $service.Sent[$key]=$next.Utc
        [pscustomobject]@{EventId=$event.Id;Occurrence=$next;Offset=$offset;Message=('{0} {1} · {2:dd/MM HH:mm} oficial / {3:dd/MM HH:mm} local' -f $event.Name,$(if($offset -eq 0){'comeca agora'}else{"comeca em $offset minutos"}),$next.Official,$next.Local)}
    }}}
}
