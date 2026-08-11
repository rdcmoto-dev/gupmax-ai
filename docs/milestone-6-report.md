# Milestone 6 — Credit Wallet System

## Resultado

A Milestone 6 implementa uma carteira de créditos auditável e baseada em ledger, com lotes por origem, expiração, reservas transacionais, settlement por usage real, pacotes, regras persistentes de custo e integração com Billing, Prompt Engine e AI Gateway. Stripe, Mercado Pago, checkout e webhooks não foram implementados.

## Arquitetura

O módulo `app/modules/credits` contém:

- `model.py`: wallet, ledger, lotes, reservas, alocações, pacotes e regras de custo.
- `enums.py`: origens, tipos de transação, operações e status de reserva.
- `defaults.py`: trial, pacotes e regras iniciais centralizados.
- `repository.py`: locking, queries FEFO, ledger, seeds e configuração.
- `service.py`: grants, expiração, estimativa, reserva, release, settlement, refund e ajuste.
- `schemas.py`: contratos públicos e validações financeiras.
- `router.py`: endpoints de usuário e operações administrativas.
- `dependencies.py` e `exceptions.py`: integração FastAPI e erros específicos.

## Wallet e ledger

Cada usuário possui no máximo uma `CreditWallet`, com saldos disponível/reservado e acumuladores vitalícios. Constraints PostgreSQL impedem valores negativos. `BigInteger` é usado nos valores de crédito para reduzir risco de overflow.

Toda alteração patrimonial cria `CreditTransaction`. Grants e refunds possuem valores positivos; consumo e expiração possuem valores negativos. Reserva e liberação têm valor contábil zero porque apenas movem créditos entre disponível e reservado; o débito patrimonial ocorre no `AI_USAGE`. Assim, o saldo total é reconciliável pelo ledger sem dupla contagem da reserva.

O schema público do extrato não expõe metadata operacional interna nem IDs de outros usuários.

## Lotes e expiração

`CreditLot` distingue as origens `PLAN`, `PURCHASED`, `TRIAL` e `PROMOTIONAL`. Trial expira em `trial_ends_at`; grants de plano expiram no fim do período; créditos comprados e refunds não expiram automaticamente nesta versão; promoções aceitam expiração configurável.

O consumo usa FEFO: lotes com vencimento mais próximo são consumidos primeiro, seguidos pelos lotes sem expiração. A expiração é calculada e registrada no momento da leitura/autorização, sem depender de cron job.

## Pacotes e regras de custo

O seed idempotente disponibiliza quatro pacotes provisórios: `CREDITS_500`, `CREDITS_1500`, `CREDITS_5000` e `CREDITS_10000`. Preços continuam provisórios.

`CreditCostRule` configura operação, provider, modelo opcional, custo base, taxas por token e custo mínimo. Regras específicas por modelo têm prioridade sobre a regra genérica do provider. Os defaults cobrem `PROMPT_OPTIMIZATION` e `TEXT_GENERATION` para OpenAI. Operações futuras de imagem e vídeo já são representáveis sem custo hardcoded no Prompt Engine.

O cálculo usa arredondamento para cima e nunca aceita taxas negativas. O endpoint de estimativa recebe apenas características da operação; o frontend não envia o custo final.

## Reserva e settlement

O fluxo de IA executa:

1. entitlement e limites existentes do Billing;
2. estimativa pela regra persistida;
3. advisory lock e row lock da carteira;
4. expiração de lotes vencidos;
5. reserva FEFO e commit;
6. chamada ao AI Gateway;
7. cálculo final com usage real;
8. settlement, release do excesso, persistência de usage e ledger.

Falhas normais do provider liberam a reserva. Release e settlement são idempotentes. A estimativa usa o máximo de output solicitado, sendo conservadora. Se um custo real excepcional superar a reserva, a política segura limita a cobrança ao valor reservado, registra custo calculado/cobrado na metadata interna e nunca deixa saldo negativo.

## Idempotência

Ledger e reservas possuem `idempotency_key` única. Trial usa `trial:{subscription_id}`. Grant periódico usa assinatura e início do período. Refunds, ajustes, reservation, release e settlement têm chaves determinísticas próprias. Chamadas repetidas retornam a operação existente e não duplicam créditos ou débitos.

## Integração com Billing

`Plan` recebeu `monthly_credit_grant`: FREE 0, STARTER 500, PRO 2.000 e BUSINESS 10.000. O serviço `grant_plan_period` concede exatamente uma vez por assinatura/período e poderá ser acionado futuramente por scheduler ou webhook.

Os limites mensais da Milestone 5 permanecem como proteção adicional de gerações e tokens. Créditos passam a representar o custo econômico configurável, enquanto os limites continuam protegendo capacidade e abuso.

Novos usuários recebem wallet e 100 créditos de trial, configurados centralmente e concedidos uma única vez, com expiração alinhada ao trial.

## Prompt Engine e AI Gateway

`optimize_with_ai=false` permanece gratuito: não reserva créditos, não cria `AI_USAGE` e não consome quota/tokens de IA.

`optimize_with_ai=true` passa por Billing, reserva de créditos, gateway fake/real injetado, settlement e usage. Os endpoints diretos de geração e streaming do AI Gateway também usam o mesmo controle. O módulo de créditos nunca chama OpenAI diretamente.

## Concorrência

O check-and-reserve reutiliza `pg_advisory_xact_lock` derivado do UUID do usuário e também bloqueia a row da wallet. A idempotência é revalidada após o lock.

Uma validação específica foi executada no PostgreSQL real com saldo de 1 crédito e duas reservas simultâneas. Resultado: `reserved=1 blocked=1`. Portanto, apenas uma operação reservou o crédito e a outra recebeu saldo insuficiente. Os dados temporários da validação foram removidos ao final pelo próprio script.

## Endpoints

Usuário autenticado:

- `GET /api/v1/credits/wallet`
- `GET /api/v1/credits/transactions`
- `GET /api/v1/credits/packages`
- `GET /api/v1/credits/costs`
- `POST /api/v1/credits/estimate`

Administrador:

- `POST /api/v1/credits/packages`
- `PATCH /api/v1/credits/packages/{package_id}`
- `POST /api/v1/credits/costs`
- `PATCH /api/v1/credits/costs/{rule_id}`
- `POST /api/v1/credits/adjustments`

Não existem endpoints para usuário alterar wallet, criar purchase/refund, excluir transações ou modificar custos.

## Segurança

- Wallet e extrato sempre usam o usuário autenticado, sem `user_id` controlado pelo cliente.
- Operações administrativas exigem `credits:manage`, concedida apenas a administradores.
- Ajustes exigem motivo e chave idempotente e sempre geram ledger `ADJUSTMENT`.
- Valores, preços, bônus, taxas e custos negativos são rejeitados.
- Constraints, locks, FEFO e idempotência protegem contra saldo negativo, replay e double-spend.
- Não há checkout, compra falsa ou integração com provider de pagamento.
- Testes usam gateways fake; nenhuma chamada real à OpenAI ocorreu.
- `backend/.env` permanece ignorado, não versionado e inalterado.
- A varredura final encontrou zero credenciais OpenAI reais em arquivos versionáveis.

## Migration

A migration `0005_credit_wallet`, com revision ID abaixo de 32 caracteres, adiciona `monthly_credit_grant`, sete tabelas, constraints, índices, seeds e wallets/trial grants para usuários elegíveis preexistentes. Nenhuma migration anterior foi alterada.

Cadeia final:

`0001_create_users -> 0002_auth_roles -> 0003_prompts -> 0004_billing -> 0005_credit_wallet`

O PostgreSQL real confirmou sete tabelas de créditos, quatro pacotes e duas regras iniciais.

## Testes e validação operacional

- Ruff: `All checks passed!`.
- Pytest: **53 testes aprovados**, nenhuma falha e um aviso externo do Starlette TestClient.
- Alembic history/heads: cadeia linear e somente `0005_credit_wallet (head)`.
- SQL offline: `alembic upgrade head --sql` aprovado.
- PostgreSQL real: upgrade aplicado; `alembic current` retornou `0005_credit_wallet (head)`.
- Concorrência PostgreSQL: uma reserva aprovada e uma bloqueada sobre o mesmo crédito.
- PostgreSQL Docker: healthy.
- Redis Docker: healthy e `PING` retornou `PONG`.
- Uvicorn: iniciado temporariamente e encerrado após a validação.
- `/health`: HTTP 200.
- `/api/v1/openapi.json`: HTTP 200.
- Endpoints de leitura `/credits`: publicados e protegidos com HTTP 401 sem token.
- Endpoints autenticados, estimate e autorização administrativa: aprovados nos testes de integração.

## Pendências

- Stripe, Mercado Pago, checkout, purchases reais, webhooks e scheduler permanecem fora do escopo.
- O acionamento automático do grant periódico será conectado a evento de renovação/scheduler futuro; o serviço idempotente já está pronto.
- Custos, grants, pacotes e preços são provisórios e administráveis.
- O aviso de depreciação do Starlette TestClient pertence a dependência externa e não afeta os resultados.

## Revalidação final — 2026-08-11

A validação final foi repetida sem implementação de novas funcionalidades:

- Ruff completo: `All checks passed!`.
- Pytest completo: **53 aprovados**, zero falhas e zero testes skipped; um aviso externo do Starlette.
- Alembic history confirmou `0001_create_users -> 0002_auth_roles -> 0003_prompts -> 0004_billing -> 0005_credit_wallet`.
- Alembic heads: somente `0005_credit_wallet (head)`.
- Alembic current conectado ao PostgreSQL: `0005_credit_wallet (head)`.
- Consulta direta dentro do PostgreSQL Docker confirmou `0005_credit_wallet`, sete tabelas de créditos, quatro pacotes e duas regras de custo.
- PostgreSQL e Redis Docker: `healthy`; Redis respondeu `PONG`.
- Concorrência repetida no PostgreSQL real: `reserved=1 blocked=1`, sem double-spend.
- `/health`: HTTP 200.
- `/api/v1/openapi.json`: HTTP 200.
- Wallet, transactions, packages, costs, estimate e operações administrativas estão publicados; endpoints privados retornam 401 sem credenciais válidas, conforme runtime e testes de integração.
- A suíte confirma wallet, ledger, lotes FEFO, expiração, packages, cost rules, estimate, reservation, settlement, release, refund, plan/trial grants e adjustment administrativo.
- Grants, refunds, releases e settlements repetidos são idempotentes; chaves únicas impedem replay e duplicidade.
- `optimize_with_ai=false` mantém custo zero e não cria `AI_USAGE`; `optimize_with_ai=true` percorre entitlement, reserva, AI Gateway fake, settlement, usage e ledger.
- Falha do provider libera a reserva e restaura integralmente o saldo disponível.
- Nenhum teste chamou a OpenAI real ou consumiu créditos OpenAI.
- `backend/.env` continua ignorado, não versionado, com timestamp inalterado desde 2026-08-10 15:11:00 -03:00.
- A varredura não encontrou credenciais reais. O único padrão genérico foi uma senha fictícia usada exclusivamente no teste de hash.
- Stripe e Mercado Pago permanecem apenas como enums preparatórios; não há SDK, checkout, webhook ou integração de pagamento.
