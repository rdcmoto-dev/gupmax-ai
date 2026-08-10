# GUPMAX AI

Backend do SaaS de geração de prompts com múltiplas IAs.

## Sprint 1

- API FastAPI versionada em `/api/v1`;
- cadastro, login, renovação de JWT e consulta do usuário autenticado;
- persistência assíncrona com SQLAlchemy 2 e PostgreSQL;
- migração inicial com Alembic;
- cliente Redis preparado para os próximos serviços;
- execução local via Docker Compose;
- validação com Ruff e Pytest.

## Milestone 2 — autenticação completa

- RBAC com papéis `user` e `admin`, além de permissões de leitura e gestão de usuários;
- refresh tokens persistidos, rotacionados e revogáveis;
- logout, troca de senha e estrutura segura de recuperação de senha;
- CRUD administrativo de usuários e rota protegida de perfil;
- middleware de contexto de autenticação, dependências FastAPI protegidas e OpenAPI documentado.

## Milestone 3 — AI Gateway

- gateway extensível para providers de geração de texto;
- provider OpenAI assíncrono, baseado na Responses API do SDK oficial;
- geração síncrona e streaming SSE em rotas autenticadas;
- timeout, retries transitórios configuráveis e mapeamento seguro de erros;
- métricas de provider, modelo, latência e tokens em logs, sem prompts ou segredos;
- configuração opcional por `OPENAI_API_KEY`, `OPENAI_DEFAULT_MODEL` e `OPENAI_MODELS`.

Para validar uma conta OpenAI de forma manual e com baixo custo, preencha a chave e um modelo autorizado no `.env` e execute, no diretório `backend`:

```powershell
..\.venv\Scripts\python.exe scripts\openai_smoke.py
```

## Executar

1. Copie `backend/.env.example` para `backend/.env` e defina uma chave JWT forte.
2. Execute `docker compose up --build`.
3. Acesse `http://localhost:8000/docs`.

O serviço aplica a migração `0001_create_users` antes de iniciar a API. Para desenvolvimento sem Docker, no diretório `backend`, instale com `pip install -e ".[dev]"`, configure as variáveis do `.env` e execute `alembic upgrade head` seguido de `uvicorn app.main:app --reload`.

## Validação

No diretório `backend`:

```powershell
..\.venv\Scripts\ruff.exe check .
..\.venv\Scripts\python.exe -m pytest -q
```
