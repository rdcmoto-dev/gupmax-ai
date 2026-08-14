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

Com as validações automatizadas e o smoke test manual aprovados, a Etapa 8.1 está tecnicamente aprovada. A Etapa 8.2 não foi iniciada.
