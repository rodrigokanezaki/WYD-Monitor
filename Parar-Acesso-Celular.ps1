param([switch]$ElevationAttempt)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'src/Mobile-Tunnel.ps1')
$elevatedExit=Invoke-MobileElevation $PSCommandPath -AlreadyAttempted:$ElevationAttempt
if($null -ne $elevatedExit){exit $elevatedExit}
. (Join-Path $PSScriptRoot 'src/Monitor-Paths.ps1')
. (Join-Path $PSScriptRoot 'src/Mobile-Tunnel.ps1')
$dataRoot=Get-MonitorUserRoot
Initialize-MonitorDataDirectory $dataRoot
$operationLock=Enter-MobileTunnelLock $dataRoot
try {
    Stop-UserMobileTunnel $PSScriptRoot $dataRoot
    'Acesso externo encerrado ou ja inativo. O monitor local continua funcionando.'
}finally{$operationLock.Dispose()}
