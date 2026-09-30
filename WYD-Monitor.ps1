# WYD Monitor desktop: the approved Work/Gamer HTML is the only application interface.
param([switch]$VerifyOnly,[switch]$UiTest)
$ErrorActionPreference='Stop'
if($UiTest -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'tests/Invoke-MonitorUiFixture.ps1') -PathType Leaf)){
    throw 'Modo UiTest requer as fixtures de QA, ausentes no pacote de distribuicao.'
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions
. (Join-Path $PSScriptRoot 'src/DesktopRuntime-Dependencies.ps1')
$desktopDependencies=Initialize-DesktopRuntimeDependencies $PSScriptRoot
$runtimePath=Join-Path $PSScriptRoot 'bin/WydMonitor.Runtime.dll'
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'RELEASE_PACKAGE.json')){
    if(-not (Test-Path -LiteralPath $runtimePath)){throw 'Pacote incompleto: WydMonitor.Runtime.dll ausente.'}
    Add-Type -Path $runtimePath
}else{
    Add-Type -Path @((Join-Path $PSScriptRoot 'src/Monitor.Core.cs'),(Join-Path $PSScriptRoot 'src/Monitor.Rates.cs'),(Join-Path $PSScriptRoot 'src/Monitor.Finance.cs'),(Join-Path $PSScriptRoot 'src/Monitor.CharacterState.cs'),(Join-Path $PSScriptRoot 'src/Monitor.FinanceAdapter.cs'))
    foreach($name in @('Monitor.Alerts.cs','Monitor.Mobile.cs','Monitor.Peer.cs','Monitor.Capture.cs')){Add-Type -Path (Join-Path $PSScriptRoot ('src/'+$name))}
    $rendererReferences=@('System.dll','System.Core.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Web.Extensions.dll')+@($desktopDependencies.References)
    Add-Type -Path (Join-Path $PSScriptRoot 'src/Monitor.DesktopShell.cs') -ReferencedAssemblies $rendererReferences
}
foreach($name in @('Monitor-Paths.ps1','Alert-Messages.ps1','Alert-Effects.ps1','Attention-Service.ps1','Finance-Projection.ps1','MonitorHost.ps1','Item-Search.ps1','Peer-Service.ps1','DesktopShell-View.ps1')){
    . (Join-Path $PSScriptRoot ('src/'+$name))
}
if($VerifyOnly){'Compilacao OK';return}
$script:desktopAppRoot=$PSScriptRoot
$script:hostRoot=if($UiTest){Join-Path ([IO.Path]::GetTempPath()) ('wyd-uitest-'+[guid]::NewGuid().ToString('N'))}else{Get-MonitorUserRoot}
Initialize-MonitorDataDirectory $script:hostRoot
$script:instanceLock=$null;$script:desktopShell=$null
$form=$null;$tray=$null;$timer=$null;$initialized=$false
try {
    if(-not $UiTest){
        try {$script:instanceLock=[IO.File]::Open((Join-Path $script:hostRoot '.WYD-Monitor.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException] {
            . (Join-Path $PSScriptRoot 'src/Monitor-Startup.ps1')
            try {Show-ExistingMonitor $PSScriptRoot -DataRoot $script:hostRoot}
            catch {[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'WYD Monitor')}
            return
        }
        $probe=New-Object Net.Sockets.TcpClient
        try {$probe.Connect('127.0.0.1',8765);$occupied=$true}catch{$occupied=$false}finally{$probe.Dispose()}
        if($occupied){
            [void][Windows.Forms.MessageBox]::Show('A porta 8765 esta ocupada. Feche a outra instancia do Monitor antes de iniciar esta versao.','WYD Monitor')
            return
        }
    }
    [Windows.Forms.Application]::EnableVisualStyles()
    Initialize-MonitorHost -Root $script:hostRoot -TestMode:$UiTest
    $initialized=$true
    $form=New-Object Windows.Forms.Form
    $form.Text='WYD Monitor '+[WydMonitor.DesktopShell]::AppVersion
    $form.ClientSize=New-Object Drawing.Size(1280,800)
    $form.MinimumSize=New-Object Drawing.Size(900,680)
    $form.StartPosition='CenterScreen'
    $form.BackColor=[Drawing.ColorTranslator]::FromHtml('#00101F')
    $tray=New-Object Windows.Forms.NotifyIcon
    $tray.Icon=[Drawing.SystemIcons]::Information;$tray.Text='WYD Monitor';$tray.Visible=(-not $UiTest)
    $tray.Add_DoubleClick({if($form -and -not $form.IsDisposed){$form.Show();$form.WindowState='Normal';$form.Activate()}})
    $script:hostRender={Update-DesktopShell -Force}
    $script:hostStatus={Update-DesktopShell}
    $script:hostDesktopAlert={param($line,$message) Invoke-AlertDesktopEffects $line $message}
    $script:alertProjection={param($append,$clear) Update-DesktopShell -Force}
    Initialize-DesktopShell
    Add-AlertMessage 'Mantenha o Monitor aberto para acompanhar seus personagens e avisos.' -Append
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=250
    $timer.Add_Tick({Update-MonitorHost;Protect-Action {Update-PeerMonitor};Protect-Action {Update-DesktopShell}})
    $form.Add_Shown({if(-not $UiTest){Protect-Action {Start-MonitorHost;$timer.Start()}}})
    $form.Add_FormClosing({$timer.Stop()})
    if($UiTest){
        $script:uiTestAppRoot=$PSScriptRoot
        . (Join-Path $PSScriptRoot 'tests/Invoke-MonitorUiFixture.ps1')
        return
    }
    [void]$form.ShowDialog()
} finally {
    if($timer){$timer.Stop();$timer.Dispose()}
    Stop-PeerMonitor
    if($initialized){Stop-MonitorHost}
    if($tray){$tray.Visible=$false;$tray.Dispose()}
    if($form){$form.Dispose()}
    if($script:instanceLock){$script:instanceLock.Dispose();$script:instanceLock=$null}
}
