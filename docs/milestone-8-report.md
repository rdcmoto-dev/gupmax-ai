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

## Etapa 8.5 — Planos, Pacotes de Créditos e Checkout Hospedado

### Auditoria e contratos utilizados

Os módulos completos de billing, credits e payments — routers, schemas, enums, models, repositories, services, providers e testes — foram auditados. Os endpoints usados pelo Flutter exigem autenticação Bearer:

| Método e rota | Request e resposta relevantes | Finalidade e segurança |
| --- | --- | --- |
| `GET /api/v1/credits/packages` | Retorna pacotes ativos com `id`, código, nome, créditos, bônus, preço e moeda | Catálogo autoritativo; o Flutter não envia preço, créditos ou bônus. |
| `GET /api/v1/billing/plans` | Retorna planos ativos com preço, moeda, período, trial, limites e créditos mensais | Catálogo autoritativo de assinaturas. |
| `POST /api/v1/payments/credits/checkout` | Header `Idempotency-Key`; body com apenas `package_id` e `provider`; retorna `payment_id`, provider, status e `checkout_url` | Cria compra avulsa hospedada com preço/moeda obtidos do banco. |
| `POST /api/v1/payments/subscriptions/checkout` | Header `Idempotency-Key`; body com apenas `plan_id` e `provider`; mesma resposta de checkout | Cria assinatura recorrente hospedada conforme plano do banco. |
| `GET /api/v1/payments/{payment_id}` | Retorna status, valor, moeda, finalidade, provider e datas, sem URL de checkout | Consulta autenticada do pagamento próprio; outro usuário recebe 404. |
| `GET /api/v1/credits/wallet` | Retorna saldos e acumulados autoritativos | Recarregado somente após status `paid` confirmado pelo backend. |

Também foram auditados `GET /api/v1/payments` (histórico autenticado e paginado), `POST /api/v1/payments/subscriptions/cancel`, o reconcile administrativo exclusivo do Mercado Pago e os webhooks server-to-server de Stripe e Mercado Pago. O histórico financeiro existe, mas não foi integrado nesta etapa para manter a experiência focada em catálogo, checkout e retorno; ele não foi confundido com o ledger de créditos.

### Catálogos e providers

O Flutter renderiza exclusivamente os pacotes e planos recebidos pelos endpoints. Na base inicial do backend existem quatro pacotes (`CREDITS_500`, `CREDITS_1500`, `CREDITS_5000` e `CREDITS_10000`) e quatro planos (`FREE`, `STARTER`, `PRO` e `BUSINESS`), mas nenhum desses valores comerciais foi hardcoded na interface.

O contrato aceita `stripe` e `mercado_pago` tanto para crédito quanto para assinatura. Não existe endpoint público que informe providers configurados no ambiente; por isso ambos são apresentados e uma configuração ausente é tratada pela resposta 502 do backend como provider indisponível. Nenhuma key ou chamada secreta de provider existe no Flutter.

### Fluxo de checkout e retorno

A rota autenticada `/credits`, acessível pelo dashboard e por Meu uso, apresenta “Créditos e planos”, escolha de provider e cards responsivos. Durante a criação, todos os botões ficam bloqueados para impedir duplo submit e a chave de idempotência é enviada ao backend. A URL HTTPS é aceita somente quando retornada pelo backend e então aberta na mesma janela para o checkout hospedado; nenhum dado de cartão é coletado pelo GUPMAX.

O backend constrói `success_url` e `cancel_url` a partir de `FRONTEND_URL`, no formato de hash routing usado pelo Flutter Web: `FRONTEND_URL/#/payments/success` e `FRONTEND_URL/#/payments/cancel`. Antes do redirecionamento, o Flutter guarda apenas o `payment_id` pendente na sessão do navegador. Ao retornar, ambas as rotas consultam o backend e mostram `pending`, `processing`, `paid`, `failed`, `canceled` ou `refunded`. O simples retorno nunca confirma pagamento nem concede créditos. Apenas `paid` confirmado dispara uma nova leitura de wallet; o saldo nunca é incrementado localmente.

O diagnóstico final confirmou diretamente na API Stripe Sandbox que a sessão nova armazenava as URLs hash corretas. A transformação ocorria no boot Flutter: além da localização inicial fixa e da perda do destino durante `restoring`, o `appRouterProvider` observava todas as notificações do `AuthController` e recriava o `GoRouter` quando a sessão terminava de restaurar. O teste anterior instanciava o router isoladamente e, por isso, não reproduzia essa reconstrução do app real. A correção remove a localização inicial fixa, preserva a rota interna durante restauração/login e observa somente a instância do controller; `refreshListenable` atualiza o mesmo router sem perder o deep link. Após autenticar, `/payments/success` ou `/payments/cancel` permanece ativo. Usuários sem sessão são enviados ao login com o destino original preservado.

Confirmação financeira, validação de valor/moeda, webhook assinado, reconcile administrativo do Mercado Pago, ledger, `CreditLot`, assinatura e concessão exatamente uma vez continuam integralmente no backend. A idempotência é escopada por usuário, finalidade e chave; ownership é aplicado na consulta do pagamento.

### Limitações e itens não implementados

- O ambiente precisa configurar `FRONTEND_URL` com a origem em que o Flutter Web está publicado para que success/cancel retornem à aplicação correta.
- A disponibilidade de cada provider não é consultável antes do checkout porque não há contrato público para isso.
- O histórico financeiro e o cancelamento de assinatura, embora disponíveis no backend, não foram incluídos na interface desta etapa.
- Não houve cobrança, preenchimento de cartão, chamada direta a Stripe/Mercado Pago ou webhook no Flutter. A única alteração backend da etapa foi a composição das URLs de retorno compatíveis com hash routing.

### Validação manual final da Etapa 8.5

O smoke test final do cancelamento Stripe Sandbox foi aprovado no Flutter Web conectado ao backend local. Com usuário autenticado, Stripe selecionado e o pacote real de 500 créditos por BRL 19,90, um checkout Sandbox novo foi criado sem preenchimento de cartão e sem realização de pagamento. Ao usar a seta de retorno do próprio Stripe, o navegador chegou corretamente a `http://localhost:49798/#/payments/cancel` e permaneceu na rota `/payments/cancel`; o dashboard não foi aberto.

A tela exibiu “Status do pagamento”, status real “Pagamento pendente”, valor BRL 19.90, provider Stripe e finalidade Compra de créditos. Também informou corretamente que o retorno não concede créditos e que a confirmação depende do backend. Nenhuma cobrança foi realizada, nenhum crédito foi concedido e nenhuma chamada OpenAI foi executada.

O teste confirmou no navegador real que o deep link é preservado após `restoreSession`. A causa raiz era a recriação do `GoRouter` ao observar notificações do `AuthController`, somada à perda anterior do destino durante a restauração; as correções mantêm a mesma instância do router via `refreshListenable` e preservam o destino durante restauração/login. A apresentação de “Pagamento pendente” após o cancelamento reflete fielmente o status ainda `pending` retornado pelo backend e pode ser refinada futuramente na UX, sem alterar a verdade financeira.

## Etapa 8.6 — Histórico de Pagamentos, Assinatura e Status Comercial

### Contratos auditados e utilizados

| Endpoint | Contrato e uso |
| --- | --- |
| `GET /api/v1/payments` | Histórico financeiro autenticado, ordenado por criação decrescente e paginado por `offset/limit`. Aceita filtros server-side `provider`, `purpose`, `status`, `created_from` e `created_to`. Usuários comuns recebem somente os próprios pagamentos; administradores podem consultar o conjunto conforme a política existente. Utilizado na lista. |
| `GET /api/v1/payments/{payment_id}` | Detalhe autenticado com ownership: outro usuário recebe o mesmo 404 de recurso inexistente. Retorna provider, finalidade, status, valor, moeda, IDs opcionais de pacote/plano e datas de criação, atualização, pagamento, cancelamento ou falha. Utilizado no detalhe. |
| `GET /api/v1/billing/subscription` | Assinatura atual, plano incorporado, status, provider, período, cancelamento agendado e trial. Utilizado em Minha assinatura. |
| `GET /api/v1/credits/wallet` | Saldo disponível, reservado e acumulados. Utilizado no resumo comercial. |
| `GET /api/v1/credits/packages` e `GET /api/v1/billing/plans` | Catálogos ativos utilizados apenas para converter os IDs relacionados em nomes amigáveis reais. |
| `POST /api/v1/payments/subscriptions/cancel` | Endpoint público autenticado que agenda cancelamento no provider e marca `cancel_at_period_end`. Auditado, mas deliberadamente não integrado nem executado nesta etapa. |

Também foram auditados os endpoints de checkout, webhooks, reconcile administrativo, limites, uso e ledger. Eles não são chamados pela nova área de visualização.

### UX e rotas

A rota autenticada `/payments`, acessível pelo dashboard, exibe a situação comercial da conta sem cálculos autoritativos no cliente:

- Minha assinatura, com plano, status, provider, período, trial e cancelamento agendado;
- saldo disponível, reservado e acumulados reais da wallet;
- histórico financeiro em cards responsivos;
- filtros reais por status, provider e finalidade;
- paginação server-side;
- estados de loading, vazio, erro e retry.

A rota autenticada `/payments/:id` mostra o detalhe próprio com status traduzido, provider, finalidade, valor, moeda, produto amigável quando presente nos catálogos e somente as datas aplicáveis. Os estados `pending`, `processing`, `paid`, `failed`, `canceled` e `refunded` permanecem fiéis ao backend. Nenhum identificador de sessão do provider, idempotency key, payload de webhook, dado de cartão ou secret é apresentado.

### Segurança, limitações e itens futuros

Ownership, status e valores permanecem sob autoridade do backend. O Flutter não altera pagamentos, assinatura, créditos, wallet ou ledger e não chama Stripe/Mercado Pago diretamente.

O contrato não inclui nome do produto dentro de `PaymentRead`; por isso a interface cruza apenas os IDs retornados com os catálogos públicos ativos. Um produto posteriormente desativado pode aparecer somente pela finalidade, sem expor seu UUID. Filtros de período existem no backend, mas não foram adicionados à primeira UX para evitar complexidade excessiva. Cancelamento de assinatura exige uma experiência dedicada de confirmação e consequências comerciais e fica para etapa futura; nenhum cancelamento foi executado.

Não houve compra, checkout, pagamento, refund ou alteração backend na Etapa 8.6.

### Validação manual da Etapa 8.6

O smoke test manual contra o backend real foi aprovado. A rota `/payments` abriu corretamente e o resumo comercial apresentou o plano Starter, trial ativo, 1.100 créditos disponíveis, 0 reservados, 1.100 recebidos e 0 utilizados.

O histórico financeiro real carregou registros de Stripe e Mercado Pago, preservando corretamente os status Pendente e Pago. Os filtros server-side foram validados: Pendente mostrou somente pagamentos pendentes; Pago mostrou somente pagamentos pagos e incluiu registros reais de Mercado Pago e Stripe.

O detalhe de um pagamento Pago abriu corretamente em `/payments/:id` e exibiu finalidade Compra de créditos, produto 500 créditos, provider Mercado Pago, valor BRL 19.90 e datas de criação, atualização e pagamento. Nenhuma informação financeira sensível foi apresentada.

Durante o smoke test não foi executada compra, criação de checkout, pagamento, refund ou cancelamento de assinatura. A validação foi exclusivamente de visualização e acompanhamento dos dados já existentes no backend.

## Etapa 8.7 — Perfil, Conta e Segurança

### Contratos auditados e utilizados

| Endpoint | Disponibilidade e uso |
| --- | --- |
| `GET /api/v1/users/me` | Perfil do usuário autenticado. Utilizado para carregar nome, e-mail, role, status e data de criação. |
| `PATCH /api/v1/users/{user_id}` | Permite ao próprio usuário alterar nome e e-mail. Role e status enviados por usuário comum são descartados pelo backend. Utilizado na edição do perfil. |
| `PATCH /api/v1/users/me/password` | Exige senha atual e nova senha com pelo menos oito caracteres. Utilizado na alteração de senha. |
| `POST /api/v1/auth/logout` | Revoga o refresh token recebido; o logout local continua obrigatório mesmo se o backend estiver indisponível. Reutilizado pelo fluxo existente. |
| `POST /api/v1/auth/login`, `/refresh`, `/register`, `/password-recovery` e `/password-reset` | Auditados para confirmar o ciclo de autenticação. Não receberam alterações nesta etapa. |
| `GET /api/v1/users`, `GET/PATCH/DELETE /api/v1/users/{user_id}` | Contratos administrativos/ownership auditados. Listagem e exclusão não foram expostas na conta do usuário. |

O backend não oferece contrato para listar dispositivos/sessões, revogar uma sessão individual ou encerrar todas as sessões. Também não existe exclusão ou desativação self-service: a exclusão existente exige a permissão administrativa `users:manage`. Essas capacidades não foram simuladas no Flutter e nenhuma alteração backend foi realizada.

### UX implementada

A rota autenticada `/account`, acessível pelo botão Minha conta no dashboard, apresenta:

- dados reais do perfil, incluindo nome, e-mail, papel, status e data de criação;
- edição validada de nome e e-mail, os únicos campos self-service aceitos pelo contrato atual;
- alteração de senha com senha atual, nova senha, confirmação, campos obscurecidos e limpeza após sucesso;
- seção final Sessão com a ação explícita Sair da conta, reutilizando o fluxo seguro de logout existente e seguida de redirecionamento ao login;
- loading, mensagens amigáveis, confirmação de sucesso, erro com retry e layout responsivo.

O mesmo modelo `AuthUser` é reutilizado, e uma edição bem-sucedida sincroniza o usuário autenticado em memória. Nenhuma senha é persistida, registrada em log ou enviada a outro destino; os campos existem apenas nos controllers da tela durante a operação. Tokens continuam no armazenamento seguro e não aparecem na UI ou nos logs de rota.

### Segurança, limitações e testes

Autenticação Bearer, ownership e autorização permanecem no backend. O Flutter não permite editar role/status, acessar conta alheia, excluir/desativar conta nem gerenciar sessões inexistentes. Erros 401, 403, 409, 422 e 429 são convertidos em mensagens amigáveis sem expor detalhes internos.

Os testes Flutter cobrem proteção de `/account`, perfil e campos reais, loading, erro/retry, edição e validação, senha obscurecida, confirmação divergente, sucesso e erro backend, presença da ação Sair da conta, logout/redirect, proteção posterior ao logout e viewport mobile. Alteração real de e-mail ou senha, exclusão, desativação e revogação global não foram executadas, conforme o escopo.

### Validação manual da Etapa 8.7

O smoke test manual contra o backend real foi aprovado. A rota `/account` abriu corretamente para um usuário autenticado e exibiu os dados reais da conta: nome, e-mail, perfil/role, status e data de criação. A interface apresentou corretamente as seções Dados pessoais, Alterar senha, Conta e Sessão, incluindo a ação explícita Sair da conta.

Nenhuma alteração real de nome, e-mail ou senha foi executada durante o smoke test. O logout real pela ação Sair da conta redirecionou o usuário para o login e encerrou o acesso à área protegida. Em seguida, uma tentativa manual de acessar `/account` sem autenticação foi bloqueada, mantendo/redirecionando o navegador para `/login?redirect=/account`.

Com a UX da conta, o logout, a proteção posterior ao logout e as validações automatizadas aprovadas, a Etapa 8.7 está integralmente aprovada.

## Etapa 8.8 — Polimento Final, Navegação e Responsividade

### Auditoria realizada

Foram revisados os fluxos existentes de login, cadastro, restauração de sessão e logout; dashboard; criação, histórico e detalhe de prompts; Meu uso; Créditos e planos; retornos success/cancel de pagamento; histórico e detalhe financeiro; e Minha conta. Recuperação e redefinição de senha continuam não expostas no frontend e não foram criadas nesta etapa.

A auditoria incluiu rotas e redirects, deep links e restauração da sessão, botões de voltar, AppBars, estados de loading/erro/vazio/retry, feedback de sucesso, textos visíveis, layouts desktop/tablet/mobile, testes existentes e busca por valores comerciais ou secrets hardcoded.

### Problemas encontrados e correções

O problema comprovado foi a navegação fragmentada: o dashboard oferecia todos os destinos, mas as demais telas exibiam subconjuntos diferentes. A área de prompts tinha navegação própria; Meu uso, Créditos e planos e Pagamentos ofereciam pares distintos de atalhos; detalhes, retornos de checkout e Minha conta dependiam do botão voltar ou de destinos contextuais. Isso tornava algumas áreas acessíveis apenas após retornar ao dashboard.

Foi criado um menu principal único e reutilizável, presente nas AppBars de todas as telas autenticadas. Ele oferece acesso coerente a Dashboard, Criar prompt, Meus prompts, Meu uso, Créditos e planos, Pagamentos e Minha conta. Ações contextuais permanecem nas respectivas telas, incluindo voltar, atualizar, copiar, editar e Sair da conta. Os atalhos diferentes e redundantes das AppBars foram removidos.

No dashboard, o logout textual passa a ser um ícone com tooltip em larguras inferiores a 600 px, preservando a ação sem comprimir o título e o novo menu. Em desktop, o botão textual existente permanece. O menu utiliza ícones, rótulos legíveis e tooltip de navegação principal.

Nenhum contrato, dado, regra financeira ou comportamento de autenticação foi alterado. Os redirects globais continuam protegendo todas as rotas privadas e preservando destinos internos durante restore/login. Os testes de boot real para `/payments/success` e `/payments/cancel` continuam cobrindo refresh e deep link.

### Responsividade, estados e testes

Os layouts existentes já utilizavam scroll, limites de largura, Wrap/LayoutBuilder e breakpoints nas principais áreas. A cobertura anterior de mobile para prompts, uso, comércio, pagamentos e conta foi preservada. Foram acrescentados testes do menu em 320, 768 e 1.280 px, dashboard em 320 px, retorno de pagamento em 320 px e detalhe financeiro em 320 px, todos sem overflow.

Loading, erro, retry e estados vazios já existentes foram auditados e preservados. Nenhum saldo, preço, crédito, plano, limite, status financeiro ou dado de usuário hardcoded foi encontrado. Tokens, refresh tokens e chaves de idempotência permanecem somente nos mecanismos internos existentes e não são exibidos ou registrados.

Arquivos criados nesta etapa:

- `frontend/lib/core/widgets/app_navigation_menu.dart`;
- `frontend/test/core/navigation/app_navigation_menu_test.dart`.

Arquivos modificados nesta etapa:

- telas de dashboard, prompts, uso, comércio/retorno, pagamentos/detalhe e conta para adoção do menu;
- testes de autenticação, prompts, comércio e pagamentos para navegação e responsividade;
- este relatório.

### Limitações

Esta etapa não introduz recuperação/reset de senha no frontend, gerenciamento de sessões, exclusão self-service nem qualquer operação financeira nova. A consistência visual foi polida sem redesign ou nova dependência.

### Validação manual da Etapa 8.8

O smoke test manual contra o frontend e o backend reais foi aprovado. Pelo menu principal da aplicação, a navegação desktop abriu corretamente Dashboard, Criar prompt, Meus prompts, Meu uso, Créditos e planos, Pagamentos e Minha conta.

O dashboard exibiu os dados reais do usuário e manteve seus atalhos funcionais. A criação de prompt carregou o formulário e os modos GUPMAX Rápido, Pro e Expert, sem executar geração. Meus prompts carregou o histórico existente e manteve paginação e Novo prompt disponíveis, sem criar, editar ou excluir registros.

Meu uso carregou saldo, plano Starter, limites do período e o estado real de uso de IA. Créditos e planos apresentou Mercado Pago, Stripe, os pacotes de 500, 1.500, 5.000 e 10.000 créditos e os planos Free, Starter, Pro e Business. Pagamentos carregou situação comercial, assinatura, saldo, filtros e histórico financeiro. Nenhuma compra, assinatura, criação de checkout ou outra operação financeira foi iniciada.

Minha conta carregou dados pessoais, alteração de senha, card Conta e a seção Sessão com Sair da conta. Nenhum dado pessoal foi alterado; o logout não foi repetido porque já havia sido aprovado no smoke test da Etapa 8.7.

A responsividade manual foi aprovada no dashboard, Minha conta e Créditos e planos em viewport mobile. Os cards foram reorganizados em coluna, a navegação permaneceu acessível, botões permaneceram dentro dos cards, textos continuaram legíveis e não houve overflow horizontal aparente.

Durante o smoke test não houve cobrança, checkout, pagamento, concessão de créditos, chamada OpenAI nem alteração de dados pessoais. Navegação desktop e mobile, responsividade e ausência de regressão visual nas áreas principais foram aprovadas. Com as validações automatizadas e manuais concluídas, a Etapa 8.8 está integralmente aprovada.
