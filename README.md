# WYD Monitor

Monitor open source para acompanhar personagens e informações do WYD em Windows.

## Estado do projeto

Versão pública inicial baseada na linha `1.0.0-beta.7`.

O projeto acompanha informações do cliente do jogo e apresenta os dados em uma interface desktop, com recursos adicionais como:

- painel Work e Gamer;
- personagens e status;
- pesquisa de itens;
- alertas configuráveis;
- agenda de eventos;
- conexão entre dois computadores na mesma rede;
- painel de consulta pelo celular.

## Requisitos

- Windows x64
- PowerShell 5.1
- .NET Framework 4.8
- Microsoft Edge WebView2 Runtime

## Código-fonte

A maior parte da implementação está em PowerShell dentro de `src/`.

Principais áreas:

- `WYD-Monitor.ps1` — entrada principal;
- `src/MonitorHost.ps1` — ciclo principal do monitor;
- `src/DesktopShell-View.ps1` — integração da interface desktop;
- `src/Mobile-Panel.ps1` — painel mobile;
- `src/Mobile-Tunnel.ps1` — conexão externa para acesso pelo celular;
- `src/Event-*.ps1` — agenda e runtime de eventos;
- `src/Alert-*.ps1` — alertas e configurações;
- `assets/desktop/` — frontend do painel;
- `mobile/` — frontend mobile.

## Executando pelo código

Mantenha a estrutura de pastas e execute:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\WYD-Monitor.ps1
```

O projeto pode depender de componentes externos do WebView2 que não são versionados no repositório.

## Dados privados

Arquivos locais, senhas, credenciais, logs e configurações pessoais **não devem ser enviados ao GitHub**.

Em especial, nunca publique:

- `Acesso-Celular.txt`
- `Acesso-Celular-Senha.txt`
- arquivos `.env`
- tokens ou chaves privadas
- conteúdo de `%LOCALAPPDATA%\WYDMonitor`

Consulte `PUBLICATION-SAFETY.md`.

## Contribuindo

Issues e Pull Requests são bem-vindos. Ao enviar alterações, descreva claramente o problema, a solução e como ela foi testada.

## Licença

O código original deste projeto é disponibilizado sob a **GNU General Public License v3.0 (GPL-3.0)**.

Componentes de terceiros presentes no repositório continuam sujeitos às suas próprias licenças e avisos.

## Aviso

Este é um projeto independente e não oficial. Marcas e nomes de terceiros pertencem aos respectivos proprietários.
