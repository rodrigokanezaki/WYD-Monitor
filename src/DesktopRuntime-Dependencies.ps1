# The renderer uses the same Chromium engine as the approved HTML previews.
# Only the packaged SDK is loaded; no machine-wide installation is performed here.
function Initialize-DesktopRuntimeDependencies([string]$AppRoot) {
    if(Test-Path -LiteralPath (Join-Path $AppRoot 'RELEASE_PACKAGE.json')){
        $managed=Join-Path $AppRoot 'bin';$loader=$managed
    } else {
        $sdk=Join-Path $AppRoot 'build-tools/webview2-1.0.4191.47'
        $managed=Join-Path $sdk 'lib/net462';$loader=Join-Path $sdk 'runtimes/win-x64/native'
    }
    $references=@((Join-Path $managed 'Microsoft.Web.WebView2.Core.dll'),(Join-Path $managed 'Microsoft.Web.WebView2.WinForms.dll'))
    foreach($path in @($references)+@((Join-Path $loader 'WebView2Loader.dll'))){
        if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw ('Componente de interface ausente: '+$path+'. Mantenha todos os arquivos do pacote juntos.')}
    }
    foreach($assembly in $references){Add-Type -Path $assembly}
    [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath($loader)
    [pscustomobject]@{References=[string[]]$references;LoaderDirectory=$loader}
}
