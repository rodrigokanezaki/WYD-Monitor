param([switch]$ElevationAttempt)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'src/Mobile-Tunnel.ps1')
$elevatedExit=Invoke-MobileElevation $PSCommandPath -AlreadyAttempted:$ElevationAttempt
if($null -ne $elevatedExit){exit $elevatedExit}
. (Join-Path $PSScriptRoot 'src/Monitor-Paths.ps1')
$dataRoot=Get-MonitorUserRoot
Initialize-MonitorDataDirectory $dataRoot
Set-Location $PSScriptRoot
. (Join-Path $PSScriptRoot 'src/Monitor-Startup.ps1')
. (Join-Path $PSScriptRoot 'src/Mobile-Tunnel.ps1')
$operationLock=Enter-MobileTunnelLock $dataRoot
try {
[void](Get-VerifiedMobileConnector $PSScriptRoot)
function Local-PanelReady {
 $passwordPath=Join-Path $dataRoot 'Acesso-Celular-Senha.txt'
 if(-not (Test-Path -LiteralPath $passwordPath)){return $false}
 $r=[Net.HttpWebRequest]::Create('http://127.0.0.1:8765/api/status');$r.Timeout=2000
 $r.Headers['Authorization']='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('wyd:'+(Get-Content $passwordPath -Raw).Trim()))
 try{$response=$r.GetResponse();$reader=New-Object IO.StreamReader($response.GetResponseStream());$data=$reader.ReadToEnd() | ConvertFrom-Json;$script:panelData=$data;return ($null -ne $data.updatedAt)}catch{return $false}finally{if($response){$response.Close()}}
}
$panelReady=Local-PanelReady
if($panelReady){Assert-MonitorPanelOwner $script:panelData $PSScriptRoot}
$requiresElevation=$panelReady -and -not $script:panelData.administrator -and @($script:panelData.characters | Where-Object status -eq 'Sem acesso').Count -gt 0
if($requiresElevation){
 # Fecha somente o monitor deste projeto que possui a porta; nunca encerra o jogo.
 $ownerId=if($script:panelData.monitorPid){[int]$script:panelData.monitorPid}else{[int](Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction Stop | Select-Object -First 1).OwningProcess}
 $owner=Get-CimInstance Win32_Process -Filter ("ProcessId="+$ownerId)
 $monitorPath=Join-Path $PSScriptRoot 'WYD-Monitor.ps1'
 if(-not $owner -or $owner.Name -ne 'powershell.exe' -or $owner.CommandLine.IndexOf($monitorPath,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Feche o monitor antigo manualmente e tente novamente; nao foi possivel validar a instancia.'}
 $process=Get-Process -Id $ownerId
 if($process.MainWindowHandle -eq [IntPtr]::Zero){Stop-Process -Id $ownerId -ErrorAction Stop;[void]$process.WaitForExit(10000)}
 elseif(-not $process.CloseMainWindow() -or -not $process.WaitForExit(10000)){throw 'Feche a janela antiga do monitor e tente novamente.'}
 $panelReady=$false
}
if(-not $panelReady){
 $probe=New-Object Net.Sockets.TcpClient
 try{$probe.Connect('127.0.0.1',8765);$occupied=$true}catch{$occupied=$false}finally{$probe.Dispose()}
 if($occupied){throw 'A porta 8765 esta ocupada. Encerre a outra instancia manualmente.'}
 $monitor=Join-Path $PSScriptRoot 'WYD-Monitor.ps1'
 Write-Output 'O Windows pedira permissao de administrador para ler todas as contas.'
 Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "'+$monitor+'"') -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
 $ready=$false
 for($i=0;$i -lt 25;$i++){Start-Sleep -Seconds 1;if(Local-PanelReady){$ready=$true;break}}
 if(-not $ready){throw 'O painel local nao respondeu. Feche monitores antigos e abra novamente.'}
}
Assert-MonitorPanelOwner $script:panelData $PSScriptRoot
$url=Start-UserMobileTunnel $PSScriptRoot $dataRoot $script:panelData
Write-Output ('Acesso criado: '+$url)
Write-Output ('Usuario e senha estao em: '+(Join-Path $dataRoot 'Acesso-Celular.txt'))
} finally {$operationLock.Dispose()}
