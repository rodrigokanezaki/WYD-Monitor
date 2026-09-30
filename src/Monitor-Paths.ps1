# Paths only: never migrates developer data or loads personal configuration.
function Get-MonitorUserRoot {
    $base=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if(-not $base){throw 'LocalApplicationData unavailable'}
    Join-Path $base 'WYDMonitor'
}
function Initialize-MonitorDataDirectory([string]$Root) {
    if(-not [IO.Path]::IsPathRooted($Root)){throw 'Data root must be absolute'}
    [void][IO.Directory]::CreateDirectory($Root)
    [void][IO.Directory]::CreateDirectory((Join-Path $Root 'config'))
    $maps=Join-Path $Root 'Mapas.json'
    # CreateNew keeps concurrent starts from overwriting an existing map file.
    if(-not (Test-Path -LiteralPath $maps)){
        try{$stream=[IO.File]::Open($maps,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)}
        catch [IO.IOException]{if(Test-Path -LiteralPath $maps){return};throw}
        try{$bytes=[Text.Encoding]::UTF8.GetBytes('[]');$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }
}
function Get-MonitorDataPath([string]$Name) {
    $root=if($script:hostRoot){$script:hostRoot}else{Get-MonitorUserRoot}
    Join-Path $root $Name
}
