# Relatório — Milestone 2: autenticação completa

## Entregas

- Ampliação da entidade `User` com os campos `role` e `is_active`.
- Papéis `user` e `admin`; permissões `users:read` e `users:manage`.
- CRUD administrativo de usuários, com atualização do próprio perfil limitada aos campos permitidos.
- Cadastro e login com hash Argon2 por meio de `pwdlib`.
- Access tokens JWT e refresh tokens JWT com identificador único (`jti`).
- Persistência dos refresh tokens, rotação no refresh, logout e revogação em troca/redefinição de senha.
- Estrutura de recuperação de senha que persiste somente o hash SHA-256 do token de uso único.
- Middleware que extrai o sujeito de access tokens válidos para o contexto da requisição.
- Dependências de autenticação e autorização do FastAPI, refletidas na especificação OpenAPI.
- Migração Alembic `0002_add_authentication_and_roles`.

## Endpoints adicionados

- `POST /api/v1/auth/logout`
- `POST /api/v1/auth/password-recovery`
- `POST /api/v1/auth/password-reset`
- `PATCH /api/v1/users/me/password`
- `POST /api/v1/users`
- `GET /api/v1/users`
- `GET /api/v1/users/{user_id}`
- `PATCH /api/v1/users/{user_id}`
- `DELETE /api/v1/users/{user_id}`

## Validação

- Ruff: aprovado.
- Pytest: 8 testes aprovados, incluindo fluxos HTTP de cadastro, login, rota protegida, rotação de refresh token, logout e troca de senha.
- Uvicorn em modo reload: iniciado com êxito; `GET /health` respondeu `200`.
