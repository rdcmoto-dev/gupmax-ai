# Milestone 4 — Prompt Engine

## Resultado

A Milestone 4 implementa geração determinística, otimização opcional pelo AI Gateway, persistência e histórico de prompts. O fluxo padrão não depende de OpenAI e todos os endpoints são autenticados.

## Arquitetura implementada

O módulo `app/modules/prompt_engine` contém apenas as responsabilidades necessárias:

- `enums.py`: categorias, modos `basic`, `pro`, `expert` e estados.
- `model.py`: entidade SQLAlchemy `Prompt`, UUID e relacionamento com `User`.
- `schemas.py`: contratos, limites de payload e respostas OpenAPI.
- `builder.py`: montagem determinística das seções profissionais.
- `repository.py`: persistência, paginação, filtros e ordenação.
- `service.py`: fluxo builder, otimização opcional, ownership e persistência.
- `router.py`: endpoints autenticados.

A otimização não importa nem chama o SDK OpenAI. Ela recebe `AIGatewayService` pela dependência existente e usa `generate()` do gateway.

## Arquivos

Criados:

- `backend/app/modules/prompt_engine/__init__.py`
- `backend/app/modules/prompt_engine/enums.py`
- `backend/app/modules/prompt_engine/model.py`
- `backend/app/modules/prompt_engine/schemas.py`
- `backend/app/modules/prompt_engine/builder.py`
- `backend/app/modules/prompt_engine/repository.py`
- `backend/app/modules/prompt_engine/service.py`
- `backend/app/modules/prompt_engine/router.py`
- `backend/alembic/versions/0003_create_prompts.py`
- `backend/tests/test_prompt_engine.py`
- `backend/tests/integration/test_prompts.py`
- `docs/milestone-4-report.md`

Alterados:

- `backend/app/api/router.py`: registro das rotas de prompts.
- `backend/app/modules/users/model.py`: relacionamento `User.prompts`.
- `backend/alembic/env.py`: execução online corrigida para SQLAlchemy Async/asyncpg.
- `backend/tests/integration/conftest.py`: inclusão do modelo nos metadados de teste.

## Banco de dados

A migration `0003_prompts` cria a tabela `prompts`, chave estrangeira para `users` com `ON DELETE CASCADE` e índices para usuário, categoria, idioma e modo. Ela preserva integralmente as migrations anteriores.

O comando `alembic heads` confirmou somente `0003_prompts (head)`. A cadeia `0001_create_users -> 0002_auth_roles -> 0003_prompts` foi compilada com sucesso pelo PostgreSQL dialect usando `alembic upgrade head --sql`.

Posteriormente, `alembic upgrade head` foi executado com sucesso contra o PostgreSQL real. O comando `alembic current` retornou `0003_prompts (head)`, confirmando que o banco chegou à revisão mais recente.

## Endpoints

- `POST /api/v1/prompts/generate`
- `GET /api/v1/prompts`
- `GET /api/v1/prompts/{prompt_id}`
- `PUT /api/v1/prompts/{prompt_id}`
- `DELETE /api/v1/prompts/{prompt_id}`

A listagem aceita `offset`, `limit`, `category`, `language`, `mode`, `created_from`, `created_to` e ordenação `asc`/`desc` por criação. Usuários comuns recebem somente seus registros; administradores podem consultar e manipular todos os prompts.

## Testes adicionados

Foram adicionados testes para:

- determinismo e seções do Prompt Builder;
- diferenças entre os modos basic, pro e expert;
- limites, itens e idioma dos schemas;
- otimização usando gateway injetado falso;
- geração sem IA;
- listagem, filtros e paginação;
- get, update e delete;
- exigência de autenticação;
- isolamento entre usuários e prevenção de IDOR.

Resultado final: **23 testes aprovados**, com um aviso de depreciação externo do Starlette TestClient e nenhuma falha.

## Qualidade e validação operacional

- Ruff: aprovado, sem erros.
- Pytest completo: 23 aprovados.
- Alembic: cadeia e head aprovados; upgrade online no PostgreSQL real executado com sucesso e `alembic current` confirmado em `0003_prompts (head)`.
- Uvicorn: iniciado com sucesso localmente e encerrado após a validação.
- `GET /health`: HTTP 200, `{"status":"ok"}`.
- `GET /api/v1/openapi.json`: HTTP 200, OpenAPI 3.1.0, rotas de prompts publicadas.
- `GET /api/v1/prompts` sem token: HTTP 401.

## Segurança

- Todos os endpoints usam `get_current_user`.
- Ownership é aplicado em get, update e delete; acessos a IDs de outro usuário retornam 404 para não revelar existência.
- A listagem de usuário comum sempre inclui filtro por `user_id`.
- Entradas, listas, strings, paginação e campos de IA têm limites explícitos.
- Nenhum conteúdo de prompt ou segredo foi adicionado a logs.
- Testes automatizados não fizeram chamadas reais à OpenAI nem consumiram créditos.
- `backend/.env` continua ignorado por `.gitignore` e não foi modificado.
- Nenhum commit ou push foi realizado.

## Pendências

- O smoke test real da OpenAI não foi executado, pois a integração já havia sido validada na Milestone 3 e a Milestone 4 não exige consumo adicional para validar a geração determinística.
