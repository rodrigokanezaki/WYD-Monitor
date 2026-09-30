. (Join-Path $PSScriptRoot 'Monitor-Paths.ps1')
. (Join-Path $PSScriptRoot 'Effect-Boundary.ps1')
function Play-AlertSound { [System.Media.SystemSounds]::Exclamation.Play() }
function Invoke-AlertDesktopEffects([string]$line,[string]$message) {
    Invoke-AlertEffect 'Tray' {$tray.ShowBalloonTip(10000,'WYD - Aviso',$message,[Windows.Forms.ToolTipIcon]::Warning)}
    if($script:SoundEnabled){Invoke-AlertEffect 'Sound' {Play-AlertSound}}
    Invoke-AlertEffect 'Log' {Add-Content -LiteralPath (Get-MonitorDataPath 'WYD-Monitor-Alertas.log') -Value $line -Encoding UTF8}
}
