# Contribuindo com o WYD Monitor

Obrigado pelo interesse em melhorar o WYD Monitor. Este projeto é aberto a correções, melhorias de interface, documentação e novas funcionalidades.

## Antes de começar

- Não publique senhas, tokens, credenciais, dados pessoais ou arquivos gerados localmente.
- Verifique as Issues existentes antes de iniciar uma alteração grande.
- Para mudanças importantes, prefira abrir uma Issue primeiro para documentar a proposta.
- Preserve funcionalidades existentes que não façam parte da alteração.

## Preparando o projeto

Faça um fork no GitHub ou clone o repositório:

```powershell
git clone https://github.com/rodrigokanezaki/WYD-Monitor.git
cd WYD-Monitor
```

Crie uma branch:

```powershell
git checkout -b feature/minha-melhoria
```

Use nomes objetivos, por exemplo:

- `fix/mobile-reconnect`
- `feature/event-alerts`
- `ui/dashboard-cleanup`
- `docs/install-guide`

## Estrutura principal

- `WYD-Monitor.ps1` — entrada principal
- `src/` — módulos PowerShell
- `assets/desktop/` — interface desktop
- `mobile/` — interface mobile
- `src/MonitorHost.ps1` — ciclo principal
- `src/DesktopShell-View.ps1` — integração desktop
- `src/Mobile-Panel.ps1` — painel mobile
- `src/Mobile-Tunnel.ps1` — acesso mobile
- `src/Event-*.ps1` — eventos
- `src/Alert-*.ps1` — alertas

## Trabalhando com ChatGPT ou Codex

Ferramentas de IA podem ajudar a analisar e modificar o projeto, mas revise as alterações antes de enviá-las.

Um bom prompt inicial:

```text
Analise o projeto antes de editar.

Objetivo:
[DESCREVA A ALTERAÇÃO]

Regras:
- identifique os arquivos envolvidos antes de modificar;
- preserve comportamentos existentes fora do escopo;
- faça a menor alteração segura possível;
- não introduza senhas, tokens ou caminhos pessoais;
- depois informe os arquivos alterados;
- explique como testar a mudança.
```

Para mudanças maiores, divida o trabalho em etapas pequenas e faça checkpoints com Git.

## Testes

Antes de abrir um Pull Request, teste as áreas afetadas.

Dependendo da alteração, confira:

- inicialização do monitor;
- captura e atualização dos personagens;
- dashboard Gamer e Work;
- pesquisa de itens;
- alertas;
- eventos;
- painel mobile;
- reconexão/acesso pelo celular;
- conexão entre computadores;
- comportamento quando um personagem fica offline.

Evite misturar correções não relacionadas no mesmo Pull Request.

## Commit

Use mensagens curtas e descritivas:

```text
fix: correct mobile reconnect state
feat: add event countdown
ui: improve character cards
docs: update installation guide
```

Antes do commit:

```powershell
git status
git diff
```

## Enviando a alteração

```powershell
git add .
git commit -m "feat: describe your change"
git push -u origin feature/minha-melhoria
```

Depois abra um Pull Request para a branch `main`.

No Pull Request, explique:

1. O problema ou objetivo.
2. O que foi alterado.
3. Como foi testado.
4. Prints, quando houver mudança visual.
5. Limitações ou pontos que ainda precisam ser verificados.

## Segurança

Nunca envie ao repositório:

- `Acesso-Celular.txt`
- `Acesso-Celular-Senha.txt`
- arquivos `.env`
- tokens ou chaves
- credenciais
- logs com dados sensíveis
- conteúdo pessoal de `%LOCALAPPDATA%\WYDMonitor`

Consulte também `PUBLICATION-SAFETY.md`.

## Licença

Ao contribuir com código para este repositório, sua contribuição será disponibilizada sob a licença GPL-3.0 utilizada pelo projeto.
