# Milestone 5 — Planos, Trial, Assinaturas e Controle de Uso

## Resultado

A Milestone 5 adiciona a camada interna de monetização do GUPMAX AI sem integrar Stripe ou Mercado Pago. Planos, trials, assinaturas, consumo mensal e autorização de uso de IA são persistentes e integrados ao Prompt Engine e aos endpoints diretos do AI Gateway.

## Arquitetura

O módulo `app/modules/billing` contém:

- `enums.py`: intervalos, providers internos/futuros, status de assinatura e trial.
- `defaults.py`: configuração central dos planos iniciais e trial padrão.
- `model.py`: `Plan`, `Subscription` e `UsageRecord`.
- `schemas.py`: contratos públicos e validações comerciais.
- `repository.py`: persistência, agregação mensal e locking PostgreSQL.
- `service.py`: provisionamento, entitlement, trial e limites.
- `dependencies.py`: injeção do serviço.
- `exceptions.py`: erros específicos de entitlement e limite.
- `router.py`: endpoints autenticados e operações administrativas.

Não foi criada uma abstração de provider de pagamento porque nenhum checkout ou integração externa faz parte desta milestone.

## Models

`Plan` persiste código, nome, descrição, preço, moeda, intervalo, trial, três limites mensais, ativação e timestamps. Preços e limites não aceitam valores negativos.

`Subscription` mantém uma assinatura por usuário, plano, status, provider, período, cancelamento e datas de trial. IDs externos existem apenas no modelo para integração futura e não são expostos no schema público.

`UsageRecord` registra usuário, prompt opcional, provider, modelo, tokens de entrada/saída/total, quantidade de gerações e instante de ocorrência. Usuários não possuem endpoint de escrita de usage.

## Migration e seed

A migration `0004_billing`, com `down_revision = "0003_prompts"`, cria as três tabelas, constraints, chaves estrangeiras e índices. As migrations anteriores não foram alteradas.

Cadeia final:

`0001_create_users -> 0002_auth_roles -> 0003_prompts -> 0004_billing`

O seed usa códigos únicos e `ON CONFLICT DO NOTHING`, sendo idempotente. A migration também atribui trial STARTER aos usuários preexistentes que ainda não possuem assinatura. Novos usuários recebem trial no registro.

## Planos e trial

Defaults provisórios centralizados:

- `FREE`: sem uso de IA.
- `STARTER`: 100 gerações, 100.000 input tokens e 40.000 output tokens/mês.
- `PRO`: 1.000 gerações, 500.000 input tokens e 200.000 output tokens/mês.
- `BUSINESS`: 5.000 gerações, 3.000.000 input tokens e 1.000.000 output tokens/mês.

O trial inicial é STARTER por 5 dias. A condição `active`, `expired` ou `not_eligible` é calculada no momento da consulta/autorização usando `trial_ends_at`; não depende de cron job.

## Limites e integração com IA

Geração determinística com `optimize_with_ai=false` não conta como geração do plano, pois não utiliza recurso pago nem tokens de provider. Ela também não cria registro de usage.

Geração com `optimize_with_ai=true` passa pelo Billing antes do AI Gateway. O fluxo valida assinatura/trial, plano ativo, geração mensal e limites de tokens. Após sucesso, os tokens retornados pelo gateway e o prompt são associados à reserva. Falhas do provider liberam a reserva.

Os endpoints diretos `/ai/generate` e `/ai/generate/stream` também passam pelo mesmo entitlement e registram usage com `prompt_id` nulo.

## Concorrência

No PostgreSQL, a autorização usa `pg_advisory_xact_lock` derivado do UUID do usuário. Dentro da mesma transação são agregados os consumos mensais e criada uma reserva persistente de uma geração antes da chamada ao provider. Assim, requisições simultâneas do mesmo usuário são serializadas durante o check-and-reserve e não ultrapassam facilmente o limite de gerações.

Tokens reais só são conhecidos após a resposta do provider. O serviço bloqueia novas chamadas quando os limites agregados já foram atingidos e registra os tokens reais na finalização. Não foi introduzido lock distribuído ou dependência de Redis para essa garantia local ao PostgreSQL.

## Endpoints

- `GET /api/v1/billing/plans`
- `GET /api/v1/billing/subscription`
- `GET /api/v1/billing/usage`
- `GET /api/v1/billing/limits`
- `POST /api/v1/billing/plans` — administrador
- `PATCH /api/v1/billing/plans/{plan_id}` — administrador, incluindo ativação/desativação

Não existe checkout nem endpoint para alteração de assinatura ou usage pelo usuário.

## Segurança

- Todos os endpoints Billing exigem autenticação.
- Criação e alteração de planos exigem `billing:manage`, concedida apenas a administradores.
- Usage e assinatura são sempre resolvidos pelo usuário autenticado, sem `user_id` controlado pelo cliente.
- Schemas rejeitam preços, trials e limites negativos e validam códigos e moedas.
- IDs de customer/subscription de providers não aparecem nas respostas públicas.
- Falta de entitlement retorna 403; limite mensal atingido retorna 429.
- Os testes usam gateway fake e não fizeram chamadas reais à OpenAI.
- `backend/.env` permanece ignorado pelo Git, não está versionado e não foi alterado.

## Testes

A suíte cobre planos, trial ativo/expirado/não elegível, períodos mensais, assinatura automática, limits, usage, agregação, bloqueio antes do provider, valores negativos, permissão administrativa, geração determinística gratuita e otimização com gateway fake.

Resultado final: **37 testes aprovados**, nenhuma falha e um aviso externo de depreciação do Starlette TestClient.

## Validação operacional

- Ruff: aprovado em todo o backend, sem erros.
- Pytest: 37 aprovados.
- Alembic history e heads: cadeia linear e somente `0004_billing (head)`.
- SQL offline: `alembic upgrade head --sql` aprovado.
- PostgreSQL real: `alembic upgrade head` executado com sucesso.
- `alembic current`: `0004_billing (head)`.
- Uvicorn: iniciado localmente e encerrado após a validação.
- `/health`: HTTP 200 com `{"status":"ok"}`.
- OpenAPI: HTTP 200, versão 3.1.0 e cinco paths Billing publicados.
- Billing sem autenticação: HTTP 401.

## Pendências

- Valores comerciais e limites permanecem provisórios e podem ser administrados sem alteração de código.
- Integrações Stripe e Mercado Pago, checkout, webhooks e sincronização externa permanecem fora do escopo.
- O aviso de depreciação do Starlette TestClient é proveniente de dependência externa e não afeta os testes.

## Validação final

Validação final repetida após a implementação:

- Ruff: `All checks passed!`.
- Pytest: **37 testes aprovados**, nenhuma falha e um aviso externo do Starlette.
- Alembic history: `<base> -> 0001_create_users -> 0002_auth_roles -> 0003_prompts -> 0004_billing`.
- Alembic heads: somente `0004_billing (head)`.
- Alembic current no PostgreSQL real: `0004_billing (head)`.
- `/health`: HTTP 200.
- `/api/v1/openapi.json`: HTTP 200.
- Os quatro endpoints públicos de leitura Billing estão presentes no OpenAPI, funcionam nos testes autenticados e retornam HTTP 401 sem credenciais.
- A geração determinística não cria usage nem consome quota/tokens de IA; a otimização com IA exige entitlement e registra usage.
- O check-and-reserve permanece protegido por `pg_advisory_xact_lock` por usuário no PostgreSQL.
- Testes automatizados usam gateway fake e não chamam a OpenAI real.
- `backend/.env` permanece ignorado, não versionado e inalterado.
- A varredura final encontrou zero credenciais OpenAI reais em arquivos versionáveis.
