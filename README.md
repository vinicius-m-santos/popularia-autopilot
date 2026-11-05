# Popularia Autopilot — Cezar na Railway

Deploy endurecido do [Cezar](https://cezar.run/) para orquestrar até dois agentes de IA em paralelo, com Claude Code, Codex e OpenCode + DeepSeek. O Cezar fornece fila, worktrees isoladas, workflows, integração com GitHub/Jira e review gate; este repositório acrescenta apenas o empacotamento necessário para Railway (volume, proxy autenticado e healthcheck).

O serviço Railway existente é `popularia-autopilot`, no projeto `welcoming-serenity` / ambiente `production`.

## Arquitetura

```text
Internet → Railway HTTPS → nginx :$PORT (Basic Auth)
                              ├─ /healthz → Cezar /api/v1/health (sem credencial)
                              └─ demais rotas → Cezar 127.0.0.1:4321

Volume /data
├─ cezar/       estado global, fila, cofre e maxParallel=2
├─ home/        logins persistentes de Claude/Codex/OpenCode/gh
└─ workspaces/  clones, projetos e worktrees isoladas
```

O Cezar não tem autenticação HTTP própria e não deve ser exposto diretamente. O nginx exige `DASHBOARD_USERNAME` e `DASHBOARD_PASSWORD` e repassa WebSocket/SSE. O terminal web fica desativado. As automações de Jira/GitHub começam desativadas por `CEZ_AUTOMATIONS=0`; habilite-as somente depois dos testes manuais.

## Versões fixadas

- Node.js `22.21.1`
- `cezar-run` `0.18.0`
- OpenCode `1.19.5` (a integração do Cezar usa o protocolo 1.x)
- Codex CLI `0.166.0`
- Claude Code `2.1.318`

Atualize deliberadamente os `ARG` do [Dockerfile](Dockerfile), confira os changelogs oficiais e rode o smoke test antes de publicar.

## Variáveis da Railway

Obrigatórias:

| Variável | Uso |
|---|---|
| `DASHBOARD_USERNAME` | Usuário do Basic Auth; use apenas letras, números, `.`, `_` ou `-`. |
| `DASHBOARD_PASSWORD` | Senha forte do dashboard (mínimo de 16 caracteres). |

Integrações:

| Variável | Uso |
|---|---|
| `GITHUB_TOKEN` | Token fine-grained do GitHub. Dê somente acesso aos repositórios Popularia, leitura de Issues/Metadata e escrita de Contents/Pull requests para branches e draft PRs. Não conceda merge administrativo. |
| `DEEPSEEK_API_KEY` | Credencial usada pelo backend OpenCode. O Cezar encaminha a família `DEEPSEEK_*` ao OpenCode, mas não aos runners Claude/Codex. |
| `ANTHROPIC_API_KEY` | Opcional. Use somente se quiser cobrança por API em vez do login persistente do Claude Code. |
| `OPENAI_API_KEY` | Opcional. Use somente se quiser cobrança por API em vez do login persistente do Codex. |
| `GH_HOST` | Opcional para GitHub Enterprise. |

Não crie variáveis `JIRA_BASE_URL`, `JIRA_EMAIL` ou `JIRA_API_TOKEN`: versões atuais do Cezar não as leem. Configure Jira em **Project Settings → Issue tracker**; o Cezar grava URL, e-mail e token no cofre criptografado persistido em `CEZ_HOME`.

Variáveis de política já definidas na imagem:

- `CEZ_AUTOMATIONS=0`: impede polling/execução de cards até o go-live manual.
- `CEZ_AUTONOMOUS_DEFAULT=0`: tarefas novas não começam autônomas por padrão.
- `CEZ_REVIEW_GATE=1`: alterações param para revisão humana; nada é mesclado automaticamente.
- `CEZ_WORKTREE_DEFAULT=1`: cada tarefa elegível usa uma worktree própria.
- `CEZ_TERMINAL=0`: remove o shell interativo do dashboard remoto.
- `CEZ_TELEMETRY=0`: bloqueia telemetria.
- `CEZ_REMOTE_AGENT_ACCOUNTS=1`: permite visualizar/configurar contas de agentes atrás do proxy autenticado.

Não habilite `CEZ_AGENT_ENV_FULL=1`. Ele entregaria todos os segredos do container a cada agente.

## Deploy

1. No serviço `popularia-autopilot`, monte um volume Railway em `/data`. Mantenha uma única réplica: serviços com volume não devem escalar horizontalmente.
2. Cadastre as duas variáveis obrigatórias e, quando disponíveis, `GITHUB_TOKEN` e `DEEPSEEK_API_KEY` como secrets no painel Railway.
3. O [.railway/railway.ts](.railway/railway.ts) usa o IaC nativo da Railway para selecionar o Dockerfile, preservar o volume `/data` e configurar `/healthz`, timeout, réplica e política de restart. As variáveis permanecem fora do IaC para não versionar segredos.
4. Faça o deploy pelo repositório conectado ou localmente:

   ```bash
   railway up --ci -m "Configure Cezar production runtime"
   ```

5. Gere um domínio Railway e abra-o. `/healthz` deve responder sem autenticação; `/` deve responder `401` sem credencial e carregar o cockpit com Basic Auth.

O entrypoint falha fechado se usuário/senha estiverem ausentes ou fracos. Em um volume novo, ele cria `/data/workspaces/popularia-control`, instala os workflows deste repositório e grava `resources.maxParallel: 2` no arquivo global do Cezar. Reinícios preservam logins, projetos, fila e worktrees.

## Login dos agentes

O volume persiste `$HOME`, portanto logins feitos uma vez sobrevivem a redeploys. Abra um shell no serviço:

```bash
railway ssh --service popularia-autopilot --environment production
```

Então autentique apenas os runners desejados:

```bash
claude login
codex login
gh auth login
opencode auth list
```

Para DeepSeek, a opção mais simples na Railway é `DEEPSEEK_API_KEY`. Não imprima a chave nem a passe em argumento de linha de comando. Depois do redeploy, confirme no dashboard do Cezar que OpenCode está conectado e selecione um modelo `deepseek/...` oferecido pelo próprio `opencode models`; o projeto não fixa um identificador de modelo que pode ficar obsoleto.

## Projetos backend e mobile

No cockpit, use **Add project → Clone from GitHub** para clonar separadamente:

- backend Symfony em `/data/workspaces/<backend>`;
- mobile React Native em `/data/workspaces/<mobile>`.

O Cezar registra os dois projetos no mesmo cockpit e o semáforo global limita a duas tarefas ativas. Cada tarefa recebe sua própria worktree e seu próprio diretório temporário. Adicione a tag `popularia` aos dois projetos para agrupá-los no dashboard global.

Uma execução do Cezar é sempre vinculada a um projeto/repositório. Para um card Jira que exige Symfony e React Native ao mesmo tempo, abra o mesmo card em cada projeto com instruções específicas (`contrato/backend` e `consumo/mobile`) e inicie as duas tarefas; elas ocupam exatamente os dois slots. Use o mesmo identificador do card nos títulos e faça a revisão conjunta dos dois draft PRs. O dispatch nativo cria filhos apenas dentro do projeto pai, portanto não deve ser tratado como dispatch cross-repository.

Copie os workflows apropriados de `.ai/cezar/workflows/` para cada repositório e ajuste somente os comandos de teste aos scripts reais do projeto. Os workflows incluídos usam Claude ou Codex para planejar, OpenCode para implementar e um runner diferente para revisar; `git diff --check` é o gate portátil mínimo.

## Jira

O diagnóstico e a validação de leitura do card `POP-5` estão documentados em [docs/jira-pop-5-diagnostico.md](docs/jira-pop-5-diagnostico.md).

Para cada projeto Cezar:

1. Abra **Settings → Issue tracker → Configure Jira credentials**.
2. Informe a URL `https://<site>.atlassian.net`, e-mail da conta técnica e API token restrito.
3. Use inicialmente apenas leitura (`read:jira-work`; automações também precisam `read:jira-user`) e **Browse/Connect** no projeto correto.
4. Não conceda escrita de comentários/transições até ela ser necessária e revisada.
5. Mantenha `CEZ_AUTOMATIONS=0` durante o smoke test. Para o go-live, remova ou altere a variável, redeploye, crie a automação pausada, execute **Preview**, revise os matches e só então habilite.

O Cezar nunca entrega o token Jira aos agentes; automações recebem uma capability temporária e restrita ao card vinculado.

Para executar trabalho sobre um card, inicie a tarefa pela aba **Tracker** do projeto ou por uma automação Jira em Preview. Não peça ao runner para ler `JIRA_*` ou chamar Jira com `curl`: tarefas genéricas não recebem essas credenciais por segurança, e o contexto do card é fornecido pelo próprio Cezar.

## Workflows e merge

Os workflows são arquivos YAML nativos do Cezar. Nenhum deles executa `git merge`, `gh pr merge` ou habilita merge automático. Draft PRs continuam sujeitos à revisão humana e às proteções do GitHub.

- `claude-plan-opencode.yml`: Claude planeja, OpenCode implementa, Codex revisa.
- `codex-plan-opencode.yml`: Codex planeja, OpenCode implementa, Claude revisa.

O OpenCode é marcado como experimental pelo Cezar e autoaprova suas ferramentas. Use-o somente em worktrees e repositórios dedicados, com tokens de menor privilégio.

## Validação local

Validação estática:

```bash
./scripts/validate.sh
```

Smoke test completo (build Docker, Cezar em `CEZ_DRY_RUN=1`, healthcheck e Basic Auth):

```bash
./scripts/smoke-test.sh
```

O smoke test usa credenciais descartáveis e não chama Claude, Codex, OpenCode, Jira, GitHub ou DeepSeek.

## Operação e recuperação

- Logs: `railway logs --service popularia-autopilot --lines 200 --json`.
- Métricas: `railway metrics --service popularia-autopilot --since 1h --json`.
- Health: `GET /healthz`.
- Estado persistente: todo o conteúdo relevante fica em `/data`; mantenha uma única réplica.
- Rotação de senha: substitua `DASHBOARD_PASSWORD`; a alteração provoca redeploy e recria o htpasswd.
- Rotação Jira: use **Replace credentials** no Cezar e reconecte o escopo.
- Rotação GitHub/DeepSeek: altere o secret Railway e redeploye.

## Referências oficiais

- [Cezar — repositório](https://github.com/open-mercato/cezar)
- [Referência do Cezar](https://github.com/open-mercato/cezar/blob/main/docs/reference.md)
- [Jira no Cezar](https://github.com/open-mercato/cezar/blob/main/docs/issue-trackers.md)
- [Providers do OpenCode](https://opencode.ai/docs/providers/)
- [Deploy com Dockerfile na Railway](https://docs.railway.com/builds/dockerfiles)
- [Volumes da Railway](https://docs.railway.com/reference/volumes)
