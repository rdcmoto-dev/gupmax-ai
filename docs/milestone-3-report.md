# Relatório — Milestone 3: AI Gateway + OpenAI

## Arquivos criados

- `backend/app/core/ai_exceptions.py`
- `backend/app/modules/ai_gateway/contracts.py`
- `backend/app/modules/ai_gateway/dependencies.py`
- `backend/app/modules/ai_gateway/openai_provider.py`
- `backend/app/modules/ai_gateway/router.py`
- `backend/app/modules/ai_gateway/schemas.py`
- `backend/app/modules/ai_gateway/service.py`
- `backend/scripts/openai_smoke.py`
- `backend/tests/test_ai_gateway.py`
- `backend/tests/integration/test_ai_api.py`

## Arquivos alterados

- `backend/pyproject.toml`
- `backend/.env.example`
- `backend/app/core/config.py`
- `backend/app/api/router.py`
- `README.md`

## Endpoints

- `GET /api/v1/ai/providers` — lista providers e modelos configurados.
- `POST /api/v1/ai/generate` — geração de texto autenticada.
- `POST /api/v1/ai/generate/stream` — geração autenticada com Server-Sent Events.

## Segurança e operação

- A chave OpenAI é lida exclusivamente de `OPENAI_API_KEY` e nunca é registrada.
- O provider só fica disponível quando possui chave configurada.
- O modelo não é fixado no código: deve ser definido por configuração ou pela requisição.
- O smoke test manual verifica o modelo na conta antes de enviar uma única solicitação de baixo custo.
- Retries são delegados ao SDK oficial, configurado por `OPENAI_MAX_RETRIES`, que aplica-os somente a falhas transitórias compatíveis.

## Validação

- Ruff: aprovado.
- Pytest: 12 testes aprovados; não consumiram créditos OpenAI.
- Migrações: nenhuma nova tabela foi necessária nesta milestone.
- Smoke real: inicialmente condicionado à configuração de chave e modelo; o resultado final consta na seção seguinte.

## Problemas encontrados e corrigidos

- Havia conflito de nomes entre um teste unitário e um teste de integração; o arquivo de integração foi renomeado para permitir a coleta pelo pytest.
- Um processo Uvicorn antigo ainda atendia a porta `8000` após o reload. Ele foi encerrado e a instância atualizada confirmou as rotas AI no OpenAPI.

## Pendências

- A listagem de modelos mostra somente os modelos permitidos/configurados pela aplicação; a validação de acesso de conta é feita pelo smoke manual antes da geração.

## Validação final

- Ruff: aprovado, sem violações.
- Pytest: `12 passed`. Os testes do gateway usam provider sem credenciais e verificações HTTP de autenticação; não fazem chamadas à OpenAI e não consomem créditos.
- API: `GET /health` e `GET /api/v1/openapi.json` retornaram `200`.
- OpenAPI: contém `/api/v1/ai/providers`, `/api/v1/ai/generate` e `/api/v1/ai/generate/stream`.
- Proteção HTTP: uma requisição sem bearer token para `POST /api/v1/ai/generate` retornou `401` sem iniciar geração.
- Segredos: `.env` é coberto pela regra `.env` em `.gitignore`; a varredura de código e logs, excluindo o próprio `.env`, não encontrou padrões de chaves OpenAI nem registro de `api_key` em logs.
- OpenAI: `OPENAI_TIMEOUT_SECONDS` é aplicado ao `AsyncOpenAI`; `OPENAI_MAX_RETRIES` limita retries do SDK. `APITimeoutError`, `RateLimitError`, erros de conexão e 5xx são mapeados para indisponibilidade temporária, sem repassar mensagens internas.
- Smoke real: concluído pelo responsável pela configuração com `gpt-5.6-luna`; status `passed`, `19` input tokens, `5` output tokens e `24` tokens totais.

## Pendência de auditoria

- O executável Git não está disponível neste ambiente. A regra de ignore foi verificada no `.gitignore`, mas uma auditoria completa do histórico de commits deve ser executada em um ambiente com Git para confirmação independente de que nenhum segredo histórico foi versionado.
