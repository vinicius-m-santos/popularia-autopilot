# Diagnóstico Jira — POP-5

Data da validação: 2026-11-04.

## Causa raiz

`JIRA_BASE_URL`, `JIRA_EMAIL` e `JIRA_API_TOKEN` não estão definidos como variáveis da Railway nem no ambiente do processo. Isso é esperado para a versão atual do Cezar: as credenciais Jira não são lidas por essas variáveis; elas são configuradas por projeto em **Settings → Issue tracker** e persistidas no cofre criptografado do Cezar.

O serviço possui conexões Jira persistidas nos projetos `popularia-backend` e `popularia-mobile`. O projeto `popularia-control` não possui conexão Jira, por ser apenas o projeto de controle.

## Validação

A leitura foi feita pelo endpoint de tracker do Cezar, que usa o adaptador Jira e a rota REST `/rest/api/3/issue/{key}` internamente. Nenhuma escrita, transição, comentário ou alteração de escopo foi executada.

| Projeto | Resultado | Issue | Status retornado |
|---|---:|---|---|
| `popularia-backend` | HTTP `200` | `POP-5` | `Em andamento` |
| `popularia-mobile` | HTTP `200` | `POP-5` | `Em andamento` |

A resposta marcou `available: true` e apontou para o issue Jira esperado. O domínio utilizado foi `viniciusmdoss.atlassian.net`; nenhum e-mail, token ou valor secreto foi registrado.

## Validação de transporte e autorização

A conexão foi testada diretamente a partir do cofre do Cezar, sem revelar o token:

| Transporte | `/myself` | `/rest/api/3/project` | `/rest/api/3/issue/POP-5` |
|---|---:|---:|---:|
| Site `viniciusmdoss.atlassian.net` | `401` | `200` com lista vazia | `404` |
| Gateway Atlassian `api.atlassian.com/ex/jira/{cloudId}` | `200` | `200`, projeto POP encontrado | `200` |

O gateway retornou a conta ativa (`accountId` e nome mascarados), o projeto POP (`id=10000`) e o card com descrição, status `Em andamento` e labels. Portanto, não há evidência de falta de permissão; o 404 era causado pelo transporte/base URL incorreto usado pela chamada direta. O adaptador nativo do Cezar já resolve `/_edge/tenant_info`, obtém o `cloudId` e usa o gateway com fallback controlado.

## Operação correta

Não adicionar as variáveis `JIRA_*` à Railway. Para trocar ou corrigir a conexão, usar **Settings → Issue tracker** no projeto Cezar correspondente e então repetir a leitura de `POP-5`. As automações Jira devem permanecer sujeitas à revisão e ao review gate do Cezar.

## Por que um runner pode receber 404

Uma tarefa criada pelo composer como `quick-task` ou como workflow genérico não recebe as credenciais Jira do projeto. O runner deve consultar somente o contexto do card que o Cezar anexou à tarefa; ele não deve montar `JIRA_BASE_URL`, `JIRA_EMAIL` e `JIRA_API_TOKEN` nem executar `curl` diretamente contra Jira.

## Prompt indevido em automações

O pacote Cezar `0.18.0` também tinha um defeito no template de automações de tracker: ele anexava ao prompt uma instrução para o agente chamar a API Jira diretamente usando `JIRA_*`. Esse texto não vinha do workflow nem do usuário e era incompatível com o cofre/gateway usado por esta instalação. O Dockerfile agora compila o fork fixado do Cezar (`vinicius-m-santos/cezar`, commit `6d280bee`) que usa o fluxo mediado e fornece o comando `node "$CEZ_BIN" tracker read`.

Após o deploy, a imagem foi validada sem expor credenciais: o template não contém mais `JIRA_BASE_URL` e contém a orientação mediada pelo Cezar; `/healthz` retornou sucesso.

Para trabalhar sobre um card Jira, abra o card pela aba **Tracker** do projeto, ou use uma automação Jira em modo Preview, e inicie a tarefa a partir desse contexto. Assim o Cezar encaminha a capability temporária e restrita ao card. O runner pode continuar sem esses nomes de variáveis no ambiente.

A validação feita pelo agente dentro de um shell Codex/Claude não substitui a validação do adaptador: um `GET /rest/api/3/project` vazio ou um `GET /rest/api/3/issue/POP-5` 404 nesse shell indica que a chamada foi feita fora do contexto Jira do Cezar, não que a conexão persistida esteja inválida.
