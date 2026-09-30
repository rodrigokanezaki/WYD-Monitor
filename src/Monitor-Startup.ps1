function Assert-MonitorPanelOwner($Status,[string]$AppRoot) {
    $ownerId=[int]$Status.monitorPid
    if($ownerId -le 0){throw 'Monitor identity unavailable'}
    $process=Get-Process -Id $ownerId -ErrorAction Stop
    if($process.StartTime.ToUniversalTime().Ticks -ne [long]$Status.monitorSession){throw 'Monitor session changed'}
    $listeners=@(Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction Stop)
    if(-not @($listeners | Where-Object OwningProcess -eq $ownerId).Count){throw 'Port belongs to another process'}
    $info=Get-CimInstance Win32_Process -Filter "ProcessId=$ownerId"
    $expected=Join-Path $AppRoot 'WYD-Monitor.ps1'
    if(-not $info.CommandLine){throw 'O Windows nao permitiu identificar o Monitor aberto. Execute o acesso celular como administrador e confirme a permissao.'}
    if($info.Name -ne 'powershell.exe' -or $info.CommandLine -notmatch ('(?i)-File\s+"'+[regex]::Escape($expected)+'"(?:\s|$)')){throw 'O Monitor aberto pertence a outra pasta. Feche a janela do Monitor antigo e abra WYD Monitor.exe e Iniciar-Acesso-Celular.bat da mesma pasta.'}
}
function Stop-PreviousMonitor([string]$root) {
    $password=(Get-Content -LiteralPath (Join-Path $root 'Acesso-Celular-Senha.txt') -Raw).Trim()
    $headers=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('wyd:'+$password))}
    $status=Invoke-RestMethod 'http://127.0.0.1:8765/api/status' -Headers $headers -TimeoutSec 4
    $ownerId=[int]$status.monitorPid
    if($ownerId -le 0 -or $ownerId -eq $PID){throw 'Identidade do monitor anterior indisponivel.'}
    $listener=Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction Stop
    if(@($listener | Where-Object OwningProcess -eq $ownerId).Count -eq 0){throw 'A porta pertence a outro processo.'}
    $process=Get-Process -Id $ownerId -ErrorAction Stop
    if($process.StartTime.ToUniversalTime().Ticks -ne [long]$status.monitorSession){throw 'A instancia anterior mudou; tente novamente.'}
    $info=Get-CimInstance Win32_Process -Filter "ProcessId=$ownerId"
    $expected=Join-Path $root 'WYD-Monitor.ps1'
    if($info.Name -ne 'powershell.exe' -or -not $info.CommandLine -or $info.CommandLine -notmatch ('(?i)-File\s+"'+[regex]::Escape($expected)+'"(?:\s|$)')){throw 'Nao foi possivel confirmar o monitor anterior. Abra como administrador para verificar.'}
    if($process.MainWindowHandle -ne 0){
        [void]$process.CloseMainWindow()
        if(-not $process.WaitForExit(5000)){throw 'O monitor anterior ainda esta encerrando. Aguarde e tente novamente.'}
    }else{
        # Instancia sem janela, autenticada e confirmada por PID, inicio e script.
        Stop-Process -Id $ownerId -ErrorAction Stop
        if(-not $process.WaitForExit(5000)){throw 'O monitor anterior nao encerrou.'}
    }
}
function Show-ExistingMonitor([string]$root,[string]$DataRoot=$root) {
    $password=(Get-Content -LiteralPath (Join-Path $DataRoot 'Acesso-Celular-Senha.txt') -Raw).Trim()
    $headers=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('wyd:'+$password))}
    $status=Invoke-RestMethod 'http://127.0.0.1:8765/api/status' -Headers $headers -TimeoutSec 4
    Assert-MonitorPanelOwner $status $root
    $process=Get-Process -Id ([int]$status.monitorPid) -ErrorAction Stop
    if($process.StartTime.ToUniversalTime().Ticks -ne [long]$status.monitorSession){throw 'Instancia mudou.'}
    if(-not ('WydMonitor.WindowActivation' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace WydMonitor {
 public static class WindowActivation {
  delegate bool EnumProc(IntPtr h,IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder text,int count);
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h,int cmd);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  public static bool Show(int pid){bool found=false;EnumWindows(delegate(IntPtr h,IntPtr p){uint owner;GetWindowThreadProcessId(h,out owner);if(owner!=pid)return true;var title=new StringBuilder(256);GetWindowText(h,title,256);if(!title.ToString().StartsWith("WYD Monitor ",StringComparison.Ordinal))return true;ShowWindowAsync(h,9);SetForegroundWindow(h);found=true;return false;},IntPtr.Zero);return found;}
 }
}
"@
    }
    if(-not [WydMonitor.WindowActivation]::Show($process.Id)){throw 'A janela do monitor ainda nao esta pronta. Aguarde alguns segundos.'}
}
