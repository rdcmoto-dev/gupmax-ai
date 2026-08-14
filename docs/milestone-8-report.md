# Milestone 8 — Frontend MVP

## Etapa 8.1 — Fundação Flutter + Autenticação Real

## Resultado

A Etapa 8.1 cria a fundação do frontend GUPMAX AI em Flutter, com Material 3, arquitetura feature-first e autenticação conectada aos contratos existentes do backend. O escopo está limitado a splash, login, cadastro, restauração de sessão, dashboard de identidade e logout. Prompt Engine, IA, wallet, billing, pagamentos, administração, recuperação de senha e deploy não fazem parte desta etapa.

## Stack

- Flutter com Dart null safety e Material 3.
- `go_router` para navegação declarativa e proteção de rotas.
- `dio` para HTTP e interceptors.
- `flutter_riverpod` para estado e injeção de dependências.
- `flutter_secure_storage` para persistência exclusiva do refresh token.
- Modelos Dart manuais; `freezed` e `json_serializable` não foram adicionados porque os contratos desta etapa são pequenos e estáveis.
- Nenhum Firebase, Supabase ou SDK de provider financeiro foi adicionado.

## Arquitetura

O frontend usa organização feature-first:

- `lib/app`: aplicação Material e composição raiz.
- `lib/core/config`: configuração por `--dart-define`.
- `lib/core/network`: Dio, interceptor, coordenação de refresh e expiração global.
- `lib/core/storage`: contrato de sessão e implementação segura.
- `lib/core/routing`: rotas e redirects de autenticação.
- `lib/core/theme`: tema Material 3.
- `lib/core/errors`: falhas sanitizadas para a interface.
- `lib/features/auth`: modelos, repositório, controller, validações e telas.
- `lib/features/dashboard`: dashboard autenticado mínimo.
- `test`: testes de controller, refresh, formulários, widgets, rotas, contrato e segurança.

## Contratos backend utilizados

Os payloads e status codes foram auditados diretamente no backend antes da implementação:

| Endpoint | Request | Resposta | Status |
| --- | --- | --- | --- |
| `POST /api/v1/auth/register` | `email`, `full_name`, `password` | `access_token`, `refresh_token`, `token_type`, `user` | 201 |
| `POST /api/v1/auth/login` | `email`, `password` | `access_token`, `refresh_token`, `token_type` | 200 |
| `POST /api/v1/auth/refresh` | `refresh_token` | novo par de tokens e `token_type` | 200 |
| `POST /api/v1/auth/logout` | `refresh_token` | sem corpo | 204 |
| `GET /api/v1/users/me` | Bearer access token | `id`, `email`, `full_name`, `is_active`, `role`, `created_at` | 200 |
| `PATCH /api/v1/users/me/password` | `current_password`, `new_password` | sem corpo | 204 |

A troca de senha foi auditada, mas sua tela não foi implementada porque não foi solicitada entre as telas da Etapa 8.1. Recuperação de senha permanece explicitamente fora do escopo.

## Configuração

A URL do backend é definida em compile time:

```text
--dart-define=API_BASE_URL=http://127.0.0.1:8000
```

O valor acima é o padrão de desenvolvimento. Nenhuma URL de produção é fixa no código. O cliente acrescenta `/api/v1` centralmente.

## Sessão e segurança

- Access token existe somente em memória dentro do coordenador de sessão.
- Refresh token é persistido exclusivamente pelo `flutter_secure_storage`.
- Senhas nunca são persistidas.
- Requisições protegidas recebem `Authorization: Bearer` pelo interceptor.
- Em HTTP 401, apenas uma tentativa de refresh é feita; a request original é marcada e repetida exatamente uma vez.
- A chamada de refresh usa um Dio separado, evitando recursão e loop do interceptor.
- Refreshes simultâneos compartilham uma única operação em andamento.
- Falha de refresh ou novo 401 após retry limpa os tokens e notifica o estado global para logout local.
- Logout tenta revogar o refresh token no backend e sempre limpa a sessão local, mesmo se a API estiver indisponível.
- Tokens, senhas e respostas sensíveis não são registrados em logs.
- Nenhuma chave OpenAI, Stripe, Mercado Pago ou secret do backend existe no frontend.

## Rotas

- `/login`
- `/register`
- `/dashboard`
- `/` é uma rota interna de splash/restauração.

Usuário não autenticado é redirecionado ao login ao tentar acessar o dashboard. Usuário autenticado é redirecionado ao dashboard ao acessar login, cadastro ou splash.

## Interface

- Splash com estado explícito de restauração.
- Login e cadastro responsivos, com validação local alinhada aos limites do backend.
- Campos de senha permitem mostrar/ocultar o conteúdo.
- Loading desabilita submissões repetidas.
- Erros são apresentados em português sem detalhes internos.
- Dashboard usa exclusivamente o usuário retornado por `GET /users/me` e mostra nome, e-mail, role e estado ativo, além do logout.

## Testes

Foram adicionados testes para:

- login válido e inválido;
- validações de e-mail, nome e senha;
- refresh bem-sucedido e falho;
- logout;
- restauração de sessão bem-sucedida e falha;
- expiração global de sessão;
- proteção e redirect de rotas;
- parsing do contrato real de `GET /users/me`;
- fluxo widget de login/dashboard/logout;
- ausência de padrões de secrets hardcoded em `lib/`.

## Execução local

Com Flutter estável instalado e o backend em `127.0.0.1:8000`:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Validação:

```powershell
dart format .
flutter analyze
flutter test
```

## Validação manual da Etapa 8.1

A aplicação Flutter Web foi validada manualmente no Chrome contra o backend local. O smoke test confirmou:

- abertura da aplicação no navegador;
- login real com execução de `POST /api/v1/auth/login`;
- carregamento dos dados reais do usuário por `GET /api/v1/users/me`;
- exibição do usuário real no dashboard;
- logout com limpeza da sessão;
- redirecionamento de `/dashboard` para `/login` após o logout;
- liberação CORS local restrita ao origin usado pelo Flutter Web, sem wildcard com credenciais.

Nenhuma credencial, senha, token ou secret foi incluído neste relatório. A configuração local do backend permanece fora do versionamento.

## Resultado final da Etapa 8.1

- `dart format .`: 29 arquivos verificados, sem alterações pendentes de formatação.
- `flutter analyze`: aprovado, sem issues.
- `flutter test`: 17 testes aprovados e nenhuma falha.
- Ruff do backend: aprovado, sem violações.
- Pytest completo do backend: 79 testes aprovados e nenhuma falha; 2 avisos não bloqueantes de dependência/cache.
- Validação manual Web: aprovada contra o backend local.

Com as validações automatizadas e o smoke test manual aprovados, a Etapa 8.1 está tecnicamente aprovada.

## Etapa 8.2 — Prompt Engine Flutter

### Contratos utilizados

O frontend consome exclusivamente os contratos existentes do backend:

| Endpoint | Uso |
| --- | --- |
| `POST /api/v1/prompts/generate` | Gera, opcionalmente otimiza com IA e salva um prompt. |
| `GET /api/v1/prompts` | Lista o histórico com `offset`, `limit` e ordenação decrescente. |
| `GET /api/v1/prompts/{prompt_id}` | Abre os detalhes de um prompt acessível. |
| `PUT /api/v1/prompts/{prompt_id}` | Edita os campos suportados pelo backend. |
| `DELETE /api/v1/prompts/{prompt_id}` | Exclui um prompt após confirmação. |

O formulário de geração respeita os campos reais `input`, `category`, `language`, `tone`, `mode`, `optimize_with_ai`, `title`, `context`, `audience`, `role`, `instructions`, `constraints`, `output_format`, `additional_information`, `provider` e `model`. A edição usa somente `title`, `generated_prompt`, `category`, `language`, `tone` e `mode`.

### Modos e geração

- Basic produz a estrutura essencial do prompt.
- Pro acrescenta contexto, público e formato de saída.
- Expert acrescenta revisão de consistência e restrições.
- Sem otimização por IA, a geração é determinística no backend e não consome créditos.
- Com `optimize_with_ai=true`, o Flutter envia a opção ao backend e nunca chama um provider diretamente.
- Reserva, cálculo, liquidação e liberação de créditos permanecem sob autoridade exclusiva do backend. O frontend não calcula custo ou saldo.

### Telas, histórico e rotas

O dashboard oferece acesso claro a Criar prompt e Meus prompts. Foram adicionadas as rotas autenticadas:

- `/prompts/new`: formulário responsivo, validação local, modos, campos avançados e otimização opcional com IA;
- `/prompts`: histórico paginado, estado vazio e navegação para detalhes;
- `/prompts/:id`: resultado, metadados retornados, cópia para clipboard, edição e exclusão confirmada.

As regras existentes de redirect protegem todas as novas rotas. Ownership continua validado exclusivamente pelo backend, que usa 404 uniforme para recursos inexistentes ou pertencentes a outro usuário.

### Erros e testes

O fluxo apresenta mensagens sanitizadas para validação, sessão expirada, créditos insuficientes, entitlement, recurso inexistente, conflito, limite de uso, indisponibilidade de IA e falha de rede. Nenhuma resposta interna ou stack trace é mostrada.

Foram adicionados testes de controller e widgets para criação, validação, loading, erro, resultado, disponibilidade da cópia, histórico vazio/preenchido, paginação, detalhes, edição, exclusão com confirmação, `optimize_with_ai`, sessão expirada e proteção das novas rotas. Resultado final: 30 testes Flutter aprovados, sem regressão dos 17 testes da Etapa 8.1.

### CORS para Flutter Web local

Como o Flutter Web usa portas locais dinâmicas durante o desenvolvimento, o backend permite em `development` e `test` somente origins HTTP com host exato `localhost` ou `127.0.0.1` e porta dinâmica. Origins externos continuam rejeitados. Em `production`, a regra local é desativada e o CORS permanece restrito à allowlist explícita configurada, sem wildcard com credenciais.

### Validação manual da Etapa 8.2

O smoke test real do Flutter Web contra o backend local confirmou:

- login real e dashboard com acesso a Criar prompt e Meus prompts;
- CORS funcionando com a porta dinâmica escolhida pelo Flutter Web;
- criação determinística nos modos Basic, Pro e Expert;
- persistência dos prompts criados;
- carregamento do histórico Meus prompts;
- abertura dos detalhes e exibição do resultado;
- disponibilidade da cópia do prompt;
- navegação entre criação, histórico e resultado.

`optimize_with_ai` permaneceu desligado durante todo o smoke test. Nenhuma chamada paga ao provider de IA foi necessária. Nenhuma credencial, senha, token, secret ou configuração privada foi registrada.

Os modos Basic, Pro e Expert funcionam conforme a semântica atual do backend. Uma diferenciação maior entre os modos fica registrada apenas como evolução futura de produto e não faz parte desta etapa.

## Etapa 8.3 — Experiência Inteligente de Criação

### UX implementada

A tela Criar prompt deixou de apresentar primeiro uma configuração técnica e passou a conduzir o usuário por uma experiência orientada à ideia:

1. destaque para a pergunta "O que você quer criar?", com texto livre e exemplos visuais que apenas preenchem a ideia inicial;
2. escolha visual e explicada do nível de construção;
3. seleção visual entre as categorias reais do backend;
4. seção opcional "Conte mais para o GUPMAX" para os dados complementares;
5. otimização com IA separada e claramente descrita como opcional, dependente do servidor e potencial consumidora de créditos;
6. resultado com nome amigável do modo, categoria, uso real de IA e provider/model/tokens somente quando retornados pelo backend.

A experiência se adapta a desktop e largura reduzida. Em mobile, os cards de modo são empilhados e a navegação de prompts usa um menu compacto. Labels, semântica de seleção, loading, erros e contraste do tema foram preservados.

### Mapeamento dos modos

| Experiência visual | Valor enviado ao backend | Semântica atual |
| --- | --- | --- |
| GUPMAX Rápido | `basic` | Construção direta e essencial. |
| GUPMAX Pro | `pro` | Acrescenta contexto, público e organização da resposta quando informados. |
| GUPMAX Expert | `expert` | Acrescenta restrições e revisão estrutural mais profunda. |

Nenhum valor ou regra comercial foi alterado no frontend.

### Categorias e campos complementares

As categorias exibidas correspondem exatamente ao enum do backend: Marketing, Vendas, Redes sociais, E-commerce, Programação, Negócios, Educação, Escrita, Imagem, Vídeo, Produtividade e Geral.

A seção complementar organiza somente campos já aceitos pelo contrato: título, idioma, tom, contexto, público, papel/especialista, instruções, restrições, formato de saída e informações adicionais. Provider e modelo aparecem somente quando a otimização com IA é ativada.

### Limitações e evoluções futuras

O backend atual recebe uma requisição completa e não oferece contrato para analisar uma ideia, devolver perguntas contextuais e consolidar respostas em etapas. Por isso, a entrevista `IDEIA → PERGUNTAS DINÂMICAS → RESPOSTAS → PROMPT FINAL` não foi simulada no Flutter. Uma etapa futura precisará definir contratos de sessão/estado da entrevista, perguntas estruturadas, validação das respostas, ownership, persistência e testes de retomada/expiração.

A diferença determinística entre Pro e Expert ainda é limitada. Uma evolução futura pode enriquecer, no backend, os templates por categoria e modo, com seções e instruções mais específicas, mantendo geração determinística e testes de snapshot/semântica. Nenhuma mudança no Prompt Engine backend foi feita nesta etapa.

### Validação manual da Etapa 8.3

O smoke test real do Flutter Web conectado ao backend local foi aprovado. A validação confirmou:

- carregamento correto da nova tela "O que você quer criar?" e dos exemplos rápidos;
- exibição dos modos GUPMAX Rápido, GUPMAX Pro e GUPMAX Expert;
- seleção do GUPMAX Pro com envio do valor contratual `pro`;
- seleção da categoria Marketing;
- funcionamento da seção "Conte mais para o GUPMAX" e preenchimento dos campos complementares;
- execução bem-sucedida de "Construir meu prompt" e exibição do resultado final;
- permanência de `optimize_with_ai` desligado, sem chamada paga ao provider de IA.

O resultado determinístico incorporou corretamente papel/especialista (`ROLE`), objetivo (`OBJECTIVE`), contexto (`CONTEXT`), público (`AUDIENCE`), instruções e orientações fornecidas (`INSTRUCTIONS`), formato da resposta (`OUTPUT FORMAT`), idioma (`LANGUAGE`) e tom (`TONE`).

O motor atual organiza adequadamente as informações fornecidas, mas não realiza entrevista dinâmica nem enriquece profundamente uma ideia incompleta por conta própria. Essa limitação permanece registrada como evolução futura e não foi implementada na Etapa 8.3.

## Etapa 8.4 — Dashboard de Uso, Limites e Créditos

### Endpoints auditados e utilizados

Todos os endpoints abaixo exigem autenticação Bearer e aplicam ownership pelo usuário autenticado no backend:

| Endpoint | Contrato | Uso no Flutter |
| --- | --- | --- |
| `GET /api/v1/credits/wallet` | `available_balance`, `reserved_balance`, acumulados creditado/gasto e timestamps | Utilizado no resumo Seus créditos. |
| `GET /api/v1/credits/transactions` | Ledger paginado por `offset/limit`, com tipo, valor com sinal, saldo posterior, descrição, expiração opcional e data | Utilizado em Movimentações de créditos. |
| `GET /api/v1/billing/subscription` | Assinatura atual com plano incorporado, status, provider, período, cancelamento e trial | Utilizado no card Plano atual. |
| `GET /api/v1/billing/usage` | Histórico paginado de uso de IA, provider/model, tokens, contagem e data | Utilizado em Uso de IA. |
| `GET /api/v1/billing/limits` | Plano, utilizado/limite/restante para gerações e tokens, período e trial | Utilizado nos cards de limites. |
| `GET /api/v1/billing/plans` | Lista autenticada de planos ativos e limites | Auditado, mas não chamado: a assinatura já retorna o plano completo. |
| `GET /api/v1/credits/packages` | Pacotes ativos de créditos | Auditado e deliberadamente não usado; compra fica fora da etapa. |
| `GET /api/v1/credits/costs` e `POST /api/v1/credits/estimate` | Regras e estimativa autoritativa de custo | Auditados e não usados nesta tela de visualização. |

Erros 401, 403, 404, 429 e falhas de rede são convertidos em mensagens amigáveis com retry. O refresh continua centralizado no interceptor existente.

### Arquitetura e experiência

A feature `features/usage` segue a arquitetura feature-first com models, repository Dio, providers/controller Riverpod e apresentação separada. A rota autenticada `/usage` é acessível pelo botão Meu uso no dashboard.

A tela apresenta somente valores retornados pelo servidor:

- saldo disponível, saldo reservado e acumulados da wallet;
- plano atual, status/trial, período e cancelamento agendado quando aplicável;
- limites reais de gerações com IA, tokens de entrada e saída;
- histórico paginado de uso de IA;
- ledger paginado com nomes amigáveis, sinal positivo/negativo e saldo posterior.

Loading inicial, pull-to-refresh, erro com retry, históricos vazios e layout responsivo foram implementados. Cards se reorganizam em largura reduzida e o ledger usa itens verticais, evitando tabela com overflow horizontal.

### Limitações e itens fora do escopo

Não existe endpoint público para listar lotes de crédito; portanto, créditos próximos a expirar não são exibidos nem inferidos. O endpoint de assinatura provisiona automaticamente o trial quando necessário, logo o contrato atual não retorna estado sem assinatura.

Compra de créditos, checkout, upgrade/downgrade, cancelamento, proration, Stripe, Mercado Pago, webhooks e administração permanecem deliberadamente fora da Etapa 8.4. Nenhum saldo, limite, custo ou valor financeiro é calculado ou controlado pelo Flutter.

### Validação manual da Etapa 8.4

O smoke test real da rota `/usage` no Flutter Web conectado ao backend local foi aprovado. A interface carregou, sem valores hardcoded, os seguintes dados retornados pelo servidor:

- wallet: 1.100 créditos disponíveis, 0 reservados, 1.100 recebidos e 0 utilizados;
- plano Starter em período de teste ativo, exibido até 16/08/2026;
- período de limites de 01/08/2026 a 01/09/2026;
- gerações com IA: 0 de 100 utilizadas e 100 restantes;
- tokens de entrada: 0 de 100.000 utilizados e 100.000 restantes;
- tokens de saída: 0 de 40.000 utilizados e 40.000 restantes;
- estado vazio correto para Uso de IA no período;
- ledger com duas compras de +500 créditos, resultando respectivamente nos saldos 1.100 e 600, e concessão de teste de +100, resultando no saldo 100.

Nenhuma compra foi executada durante esta validação, nenhum checkout foi iniciado e nenhuma chamada paga ao provider de IA foi realizada. Os registros de compra exibidos já existiam no ledger retornado pelo backend.
