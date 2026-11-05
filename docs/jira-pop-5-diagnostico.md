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

## Operação correta

Não adicionar as variáveis `JIRA_*` à Railway. Para trocar ou corrigir a conexão, usar **Settings → Issue tracker** no projeto Cezar correspondente e então repetir a leitura de `POP-5`. As automações Jira devem permanecer sujeitas à revisão e ao review gate do Cezar.
