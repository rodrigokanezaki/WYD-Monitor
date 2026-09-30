# WYD Monitor

![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

**WYD Monitor** é um projeto open source para acompanhar personagens e informações do WYD em Windows por meio de um painel desktop, com visualização complementar pelo celular.

> Projeto independente e não oficial. WYD e demais marcas pertencem aos seus respectivos proprietários.

## ✨ Recursos

- Dashboard com modos **Work** e **Gamer**
- Monitoramento de personagens e status
- Pesquisa de itens entre personagens
- Alertas configuráveis
- Agenda e acompanhamento de eventos
- Painel mobile para consulta pelo celular
- Conexão entre dois computadores na mesma rede
- Estrutura modular em PowerShell
- Interface desktop baseada em WebView2

## 🚧 Estado do projeto

A versão pública atual está na linha **v1.0.0-beta.7**.

O projeto está em desenvolvimento e pode sofrer alterações de estrutura, interface e compatibilidade.

## 🖥️ Requisitos

- Windows x64
- PowerShell 5.1 ou superior
- .NET Framework 4.8
- Microsoft Edge WebView2 Runtime
- Cliente compatível do jogo em execução para os recursos que dependem de leitura local

## 🚀 Executando pelo código-fonte

Clone o repositório:

```powershell
git clone https://github.com/rodrigokanezaki/WYD-Monitor.git
cd WYD-Monitor
```

Execute:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\WYD-Monitor.ps1
```

Também existem scripts `.bat` na raiz para facilitar a inicialização no Windows.

> Algumas dependências binárias não são versionadas no repositório. Consulte os arquivos de instruções antes de executar uma cópia recém-clonada.

## 📁 Estrutura

```text
WYD-Monitor/
├── assets/             # interface e recursos do desktop
├── mobile/             # frontend do painel mobile
├── src/                # módulos principais em PowerShell
├── bin/                # avisos/licenças de dependências
├── tools/              # avisos/licenças de ferramentas
├── WYD-Monitor.ps1     # entrada principal
├── COMECE-AQUI.txt
├── GUIA-DOIS-PCS.txt
└── README.md
```

Alguns módulos importantes:

- `src/MonitorHost.ps1` — ciclo principal
- `src/DesktopShell-View.ps1` — integração da interface desktop
- `src/Mobile-Panel.ps1` — painel mobile
- `src/Mobile-Tunnel.ps1` — acesso externo/mobile
- `src/Event-*.ps1` — agenda e runtime de eventos
- `src/Alert-*.ps1` — sistema de alertas

## 📱 Acesso pelo celular

O projeto possui painel mobile e scripts próprios para iniciar e encerrar o acesso.

Credenciais de acesso são dados locais e **não devem ser commitadas no GitHub**.

Consulte `COMECE-AQUI.txt` para instruções de utilização.

## 🔐 Segurança e privacidade

Nunca publique:

- `Acesso-Celular.txt`
- `Acesso-Celular-Senha.txt`
- arquivos `.env`
- tokens ou chaves privadas
- logs contendo informações sensíveis
- conteúdo pessoal de `%LOCALAPPDATA%\WYDMonitor`

Veja também [PUBLICATION-SAFETY.md](PUBLICATION-SAFETY.md).

## 🤝 Contribuindo

Contribuições são bem-vindas.

Você pode abrir uma **Issue** para relatar bugs ou sugerir funcionalidades e enviar um **Pull Request** para propor alterações no código.

Ao contribuir, informe o que foi alterado e como a mudança foi testada.

## 📦 Releases

O código-fonte permanece disponível neste repositório. Pacotes prontos para usuários finais podem ser disponibilizados na seção **Releases** do GitHub.

## 📄 Licença

O código original do WYD Monitor é disponibilizado sob a **GNU General Public License v3.0 (GPL-3.0)**.

Componentes e ferramentas de terceiros permanecem sujeitos às suas respectivas licenças.

---

Feito para a comunidade, com desenvolvimento aberto e colaboração via GitHub.
