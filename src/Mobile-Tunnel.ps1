function Test-MobileAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
}
function Invoke-MobileElevation([string]$ScriptPath,[switch]$AlreadyAttempted) {
    if(Test-MobileAdministrator){return $null}
    if($AlreadyAttempted){throw 'A permissao de administrador nao foi concedida. Abra o acesso celular como administrador.'}
    Write-Host 'Confirme a permissao do Windows para conectar ao Monitor aberto.'
    $shell=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    try{
        $child=Start-Process -FilePath $shell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$ScriptPath+'" -ElevationAttempt') -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        # Wait only for the launcher, not its long-running monitor/tunnel descendants.
        $child.WaitForExit()
    }catch{throw 'O Windows nao autorizou o acesso celular. Tente novamente e confirme Sim na solicitacao de permissao.'}
    if($child.ExitCode -ne 0){throw 'Nao foi possivel concluir o acesso celular. Feche o Monitor antigo e abra o Monitor e o acesso celular da mesma pasta. Para ver o detalhe, execute este atalho como administrador.'}
    return [int]$child.ExitCode
}
function Get-VerifiedMobileConnector([string]$AppRoot) {
    $exe=Join-Path $AppRoot 'tools/cloudflared.exe'
    $lockPath=Join-Path $AppRoot 'tools/cloudflared.lock.json'
    if(-not (Test-Path -LiteralPath $exe -PathType Leaf) -or -not (Test-Path -LiteralPath $lockPath -PathType Leaf)){
        throw 'O conector de acesso celular esta ausente ou o ZIP foi extraido parcialmente. Extraia o pacote completo com acesso celular, incluindo a pasta tools, e tente novamente.'
    }
    try{$lock=Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop}
    catch{throw 'O arquivo de verificacao do conector esta danificado. Extraia novamente o pacote completo com acesso celular.'}
    if($lock.SHA256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'O arquivo de verificacao do conector e invalido. Extraia novamente o pacote completo com acesso celular.'}
    if((Get-FileHash -LiteralPath $exe).Hash -ne $lock.SHA256){throw 'Hash do conector nao confere com esta versao.'}
    $signature=Get-AuthenticodeSignature -LiteralPath $exe
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Cloudflare, Inc.*'){throw 'Assinatura do conector nao validada.'}
    return $exe
}
function Enter-MobileTunnelLock([string]$DataRoot) {
    try{return [IO.File]::Open((Join-Path $DataRoot '.mobile-tunnel.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch [IO.IOException]{throw 'Outra operacao de acesso celular esta em andamento.'}
}
function Get-OwnedMobileTunnel($Saved,[string]$Executable) {
    if([int]$Saved.Pid -le 0 -or [long]$Saved.StartTicks -le 0){throw 'Estado do tunel invalido; nenhum processo foi encerrado.'}
    $process=Get-Process -Id ([int]$Saved.Pid) -ErrorAction SilentlyContinue
    if(-not $process){return $null}
    if($process.StartTime.ToUniversalTime().Ticks -ne [long]$Saved.StartTicks -or $process.Path -ne $Executable){throw 'A identidade do processo nao confere. Nenhum processo foi encerrado.'}
    return $process
}
function New-MobileTunnelStartInfo([string]$Executable,[string]$SessionRoot) {
    [void][IO.Directory]::CreateDirectory($SessionRoot)
    $config=Join-Path $SessionRoot 'quick-tunnel.yml'
    [IO.File]::WriteAllText($config,'{}',[Text.UTF8Encoding]::new($false))
    $log=Join-Path $SessionRoot 'connector.log'
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Executable;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.WorkingDirectory=$SessionRoot
    $info.Arguments='tunnel --config "'+$config+'" --no-autoupdate --url http://127.0.0.1:8765 --protocol http2 --metrics 127.0.0.1:0 --logfile "'+$log+'" --origincert "'+(Join-Path $SessionRoot 'unused-cert.pem')+'"'
    # Change only the child environment, never the user's Windows configuration.
    foreach($key in @($info.EnvironmentVariables.Keys)){
        if($key -match '^(TUNNEL_|CLOUDFLARED_|CF_)'){$info.EnvironmentVariables.Remove($key)}
    }
    foreach($key in @('USERPROFILE','HOME','APPDATA','LOCALAPPDATA')){$info.EnvironmentVariables[$key]=$SessionRoot}
    $info.EnvironmentVariables['HOMEDRIVE']=[IO.Path]::GetPathRoot($SessionRoot).TrimEnd('\')
    $info.EnvironmentVariables['HOMEPATH']=$SessionRoot.Substring([IO.Path]::GetPathRoot($SessionRoot).Length-1)
    return $info
}
function Start-MobileTunnelProcess($StartInfo) {return [Diagnostics.Process]::Start($StartInfo)}
function Stop-OwnedMobileTunnel($Process) {
    if(-not $Process.HasExited){$Process.Kill();if(-not $Process.WaitForExit(5000)){throw 'Conector ainda nao encerrou.'}}
}
function Write-MobileAccessInfo([string]$DataRoot,[string]$Url) {
    if($Url -notmatch '^https://[a-z0-9-]+\.trycloudflare\.com$'){throw 'Endereco inesperado do tunel.'}
    $password=(Get-Content -LiteralPath (Join-Path $DataRoot 'Acesso-Celular-Senha.txt') -Raw).Trim()
    if($password.Length -lt 20){throw 'Senha local invalida. Verifique a configuracao do painel.'}
    $text="WYD MONITOR - CONSULTA PELO CELULAR`r`nEndereco: $Url`r`nUsuario: wyd`r`nSenha: $password`r`n`r`nNao compartilhe este arquivo. O endereco muda ao reiniciar o tunel.`r`nMantenha o Monitor aberto. Para desligar: Parar-Acesso-Celular.bat"
    [IO.File]::WriteAllText((Join-Path $DataRoot 'Acesso-Celular.txt'),$text,[Text.UTF8Encoding]::new($true))
}
function Start-UserMobileTunnel([string]$AppRoot,[string]$DataRoot,$Panel) {
    $exe=Get-VerifiedMobileConnector $AppRoot
    $statePath=Join-Path $DataRoot 'Acesso-Celular-Tunel.json'
    if(Test-Path -LiteralPath $statePath){
        $saved=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
        $running=Get-OwnedMobileTunnel $saved $exe
        if($running){
            if($saved.MonitorPid -eq $Panel.monitorPid -and $saved.MonitorSession -eq $Panel.monitorSession -and $saved.Url -match '^https://[a-z0-9-]+\.trycloudflare\.com$'){
                Write-MobileAccessInfo $DataRoot $saved.Url
                return $saved.Url
            }
            Stop-OwnedMobileTunnel $running
        }
        Remove-Item -LiteralPath $statePath
        $oldInfo=Join-Path $DataRoot 'Acesso-Celular.txt';if(Test-Path $oldInfo){Remove-Item -LiteralPath $oldInfo}
    }
    $session=Join-Path (Join-Path $DataRoot 'mobile-sessions') ([guid]::NewGuid().ToString('N'))
    $info=New-MobileTunnelStartInfo $exe $session
    $process=Start-MobileTunnelProcess $info
    try{
        $log=Join-Path $session 'connector.log';$url=$null
        # Persist ownership before waiting so an interrupted connection can be stopped/recovered.
        [pscustomobject]@{Pid=$process.Id;StartTicks=$process.StartTime.ToUniversalTime().Ticks;Url=$null;Log=$log;MonitorPid=$Panel.monitorPid;MonitorSession=$Panel.monitorSession}|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
        for($i=0;$i -lt 40;$i++){
            Start-Sleep -Seconds 1
            if($process.HasExited){throw 'Conector encerrou; consulte o log da sessao mobile.'}
            if(Test-Path $log){$content=Get-Content $log -Raw;$match=[regex]::Match($content,'https://[a-z0-9-]+\.trycloudflare\.com');if($match.Success -and $content -match 'Registered tunnel connection'){$url=$match.Value;break}}
        }
        if(-not $url){throw 'Nao foi possivel obter endereco externo em 40 segundos.'}
        [pscustomobject]@{Pid=$process.Id;StartTicks=$process.StartTime.ToUniversalTime().Ticks;Url=$url;Log=$log;MonitorPid=$Panel.monitorPid;MonitorSession=$Panel.monitorSession}|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
        Write-MobileAccessInfo $DataRoot $url
        return $url
    }catch{
        Stop-OwnedMobileTunnel $process
        foreach($file in @($statePath,(Join-Path $DataRoot 'Acesso-Celular.txt'))){if(Test-Path $file){Remove-Item -LiteralPath $file}}
        throw
    }
}
function Stop-UserMobileTunnel([string]$AppRoot,[string]$DataRoot) {
    $statePath=Join-Path $DataRoot 'Acesso-Celular-Tunel.json'
    if(Test-Path -LiteralPath $statePath){
        $saved=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
        $process=Get-OwnedMobileTunnel $saved (Join-Path $AppRoot 'tools/cloudflared.exe')
        if($process){Stop-OwnedMobileTunnel $process}
        Remove-Item -LiteralPath $statePath
    }
    $info=Join-Path $DataRoot 'Acesso-Celular.txt';if(Test-Path $info){Remove-Item -LiteralPath $info}
}
