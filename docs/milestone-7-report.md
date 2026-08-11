# Milestone 7 — Payments: Stripe + Mercado Pago

## Resultado

A Milestone 7 implementa uma camada de pagamentos server-side para checkout hospedado de créditos e assinaturas, webhooks autenticados, confirmação junto ao provider, state machine, idempotência e reconciliação com Credit Wallet e Billing. Nenhuma cobrança real foi realizada e nenhuma credencial de produção foi usada.

## Arquitetura Payments

O módulo `app/modules/payments` contém:

- `contracts.py`: contrato normalizado `PaymentProvider` e DTOs do boundary externo.
- `providers/stripe.py`: adapter da API HTTP oficial Stripe.
- `providers/mercado_pago.py`: adapter da API HTTP oficial Mercado Pago.
- `model.py`: `Payment` e `PaymentEvent`.
- `schemas.py`: contratos públicos sem preço/créditos controláveis pelo frontend.
- `repository.py`: lookup, ownership, filtros e eventos.
- `service.py`: checkouts, state machine, reconciliação, assinatura e cancelamento.
- `router.py`: endpoints autenticados e webhooks provider-to-server.
- `dependencies.py`: registry configurável de providers.
- `enums.py` e `exceptions.py`: domínio e falhas seguras.

Billing e Credits não importam SDKs ou clientes de pagamento. Somente Payments conhece os adapters externos.

## Ambientes e configuração

`PAYMENTS_ENVIRONMENT` aceita `test`, `sandbox` ou `production`. Produção nunca é inferida. Stripe rejeita chave live fora de `production` e chave test em `production`. Mercado Pago exige token `TEST-` fora de produção e o rejeita em produção.

As variáveis foram adicionadas apenas a `backend/.env.example`:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `MERCADO_PAGO_ACCESS_TOKEN`
- `MERCADO_PAGO_WEBHOOK_SECRET`
- `PAYMENTS_ENVIRONMENT`
- `APP_PUBLIC_URL`
- `FRONTEND_URL`
- `PAYMENTS_TIMEOUT_SECONDS`

`backend/.env` não foi modificado. Secrets são `SecretStr`, não são persistidos e não entram em logs.

## Payment e PaymentEvent

`Payment` persiste usuário, provider, finalidade, status, valor `Numeric`, moeda, pacote/plano, IDs externos, URL de checkout, chave idempotente e timestamps. Nenhum dado de cartão é recebido ou armazenado.

`PaymentEvent` armazena somente provider, ID único do evento, tipo, hash SHA-256 do payload, status de processamento e erro sanitizado pelo nome da exceção. O payload completo não é persistido.

## State machine

Transições válidas são centralizadas:

- `PENDING -> PROCESSING | PAID | FAILED | CANCELED`
- `PROCESSING -> PAID | FAILED | CANCELED`
- `PAID -> REFUNDED`

Estados finais não regridem. Evento atrasado de falha não transforma um pagamento pago. Repetição do mesmo estado é idempotente.

## Checkout de créditos

O cliente envia somente `package_id` e provider, além de `Idempotency-Key` no header. Campos extras como `amount` e `credits` são rejeitados. O backend consulta `CreditPackage`, determina preço, moeda, créditos e bônus e cria o Payment interno antes do checkout.

Após webhook válido, Payments consulta o provider server-side e compara valor/moeda. Somente então `CreditService.grant` cria lote `PURCHASED` sem expiração e ledger `PURCHASE`. A chave `purchase:{provider}:{provider_payment_id}` impede grant duplicado.

## Checkout de assinatura

O cliente envia apenas `plan_id` e provider. O backend valida plano ativo e usa preço/moeda persistidos. Uma assinatura já ativa não pode sofrer upgrade/downgrade automático nesta versão; a operação retorna conflito e exige suporte até existir política comercial definida.

Após confirmação, a assinatura existente é atualizada com plano, provider, customer/subscription IDs e período. `grant_plan_period` concede créditos mensais usando a idempotência `subscription + period`, inclusive em renovação repetida.

## StripeProvider

Usa Checkout Session hospedada em modo `payment` para créditos e `subscription` para planos. Valores são enviados na menor unidade monetária, com `Idempotency-Key` oficial. O provider não recebe retries cegos da aplicação.

Webhooks usam o corpo bruto, header `Stripe-Signature`, HMAC-SHA256 sobre `timestamp.payload`, comparação constante e tolerância de cinco minutos. Após validação, o estado é consultado na API Stripe antes de qualquer grant.

## MercadoPagoProvider

Usa `/checkout/preferences` para créditos e `/preapproval` para recorrência, com checkout hospedado. O preço vem do banco e `X-Idempotency-Key` é enviado na criação de preference.

Webhooks validam o manifesto oficial formado por `data.id`, `x-request-id` e `ts`, usando HMAC-SHA256 e `x-signature`. A notificação não é fonte suficiente para confirmar pagamento; o adapter consulta `/v1/payments/{id}`.

## Webhooks e idempotência

Endpoints públicos provider-to-server:

- `POST /api/v1/payments/webhooks/stripe`
- `POST /api/v1/payments/webhooks/mercado-pago`

Eles não usam JWT, mas exigem autenticação do provider. Evento forjado retorna 400. IDs são prefixados pelo provider e únicos. Eventos já processados retornam no-op. Eventos desconhecidos ou fora de ordem são ignorados com registro persistente.

Checkout usa chave escopada por usuário/finalidade. PaymentEvent, purchase grant, plan grant e wallet ledger possuem camadas independentes de idempotência. Se houver falha depois do grant e antes do Payment final, o retry executa o mesmo grant como no-op e conclui a reconciliação.

## Atomicidade e reconciliação

Provider e banco não compartilham transação distribuída. A estratégia é confirmação server-side + efeitos locais idempotentes + PaymentEvent reprocessável. O estado `PROCESSED` só é gravado após os efeitos locais. Em falha, o evento fica `FAILED` com erro sanitizado e pode ser reenviado/reprocessado sem crédito duplicado.

## Cancelamento e refunds

`POST /api/v1/payments/subscriptions/cancel` solicita cancelamento ao provider e somente após sucesso marca `cancel_at_period_end=true`. Histórico e créditos comprados não são removidos.

Eventos de refund podem mover `PAID -> REFUNDED`, mas não removem créditos automaticamente. Se créditos já tiverem sido gastos, clawback poderia produzir saldo negativo; essa política permanece deliberadamente pendente para revisão comercial/manual. O ledger histórico nunca é apagado.

## Endpoints

- `POST /api/v1/payments/credits/checkout`
- `POST /api/v1/payments/subscriptions/checkout`
- `POST /api/v1/payments/subscriptions/cancel`
- `GET /api/v1/payments/{payment_id}`
- `GET /api/v1/payments`
- `POST /api/v1/payments/webhooks/stripe`
- `POST /api/v1/payments/webhooks/mercado-pago`

Histórico suporta paginação e filtros por provider, finalidade, status e datas. Usuários veem somente registros próprios; administradores podem consultar todos. IDOR retorna 404.

## Segurança

- Checkout hospedado: nenhum cartão passa pelo GUPMAX AI.
- Preço, moeda, créditos e plano são obtidos do banco.
- Campos financeiros extras no request são rejeitados.
- Redirect usa URLs fixas de configuração; redirect não confirma pagamento.
- Webhook exige assinatura/autenticidade e consulta server-side.
- Payload sensível não é persistido nem logado.
- Logs possuem apenas IDs internos/provider e status, nunca secrets/tokens/cartões.
- Timeout externo é configurável; não há retry cego de criação de cobrança.
- Chaves idempotentes protegem checkout, evento, crédito e renovação.
- Testes cobrem forged webhook, replay, duplicidade, IDOR, divergência de valor/moeda, timeout e evento fora de ordem.

## Migration

A migration `0006_payments`, com `down_revision = "0005_credit_wallet"`, cria `payments` e `payment_events`, constraints e índices. As migrations 0001–0005 não foram alteradas.

Cadeia final:

`0001_create_users -> 0002_auth_roles -> 0003_prompts -> 0004_billing -> 0005_credit_wallet -> 0006_payments`

O SQL offline foi gerado com sucesso. O upgrade foi aplicado no PostgreSQL real e consulta direta confirmou `0006_payments` e as duas tabelas.

## Testes

A suíte cobre:

- Stripe e Mercado Pago checkout;
- checkout de assinatura;
- pacote/plano inexistente;
- preço/moeda vindos do banco;
- webhook válido, inválido e duplicado;
- aprovado, recusado, refund e evento fora de ordem;
- grant de compra e mensal sem duplicação;
- state machine;
- divergência de valor e moeda;
- timeout de provider;
- idempotência de checkout;
- autenticação, ownership, IDOR e acesso administrativo;
- cancelamento no fim do período;
- algoritmos de assinatura Stripe e Mercado Pago;
- compatibilidade com Auth, Billing, Credits, Prompt Engine e AI Gateway.

Resultado final: **65 testes aprovados**, zero falhas, zero skips e um aviso externo do Starlette TestClient. Todos os providers externos foram fake/mockados nos testes de integração.

## Validação operacional

- Ruff: `All checks passed!`.
- Pytest: 65 aprovados.
- Alembic heads/current: somente `0006_payments (head)`.
- PostgreSQL Docker: healthy; migration real confirmada.
- Redis Docker: healthy; `PING` retornou `PONG`.
- Uvicorn: iniciado temporariamente e encerrado após validação.
- `/health`: HTTP 200.
- `/api/v1/openapi.json`: HTTP 200.
- Sete paths Payments publicados no OpenAPI.
- Histórico e checkout sem JWT: HTTP 401.
- Webhook inválido: HTTP 400 nos testes.
- Zero cobranças reais e zero chamadas reais à OpenAI.
- `backend/.env` ignorado, não versionado e inalterado.
- Varredura sem credenciais reais; único padrão foi secret deliberadamente falso de fixture.

## Pendências

- Executar smoke manual em contas Stripe Test e Mercado Pago Sandbox quando credenciais próprias estiverem disponíveis.
- Definir política comercial de upgrade/downgrade e proration.
- Definir política de clawback/reembolso quando créditos comprados já tiverem sido consumidos.
- Conectar processamento assíncrono/fila e reconciliação periódica antes de escala produtiva.
- Revisar versões/documentação dos providers antes do go-live e realizar homologação formal.
- O aviso de depreciação do Starlette TestClient pertence a dependência externa.
