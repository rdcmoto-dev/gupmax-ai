# Homologacao do GUPMAX AI

Esta configuracao prepara um piloto por convite em um ambiente de homologacao. Ela nao publica servicos de dados, nao habilita pagamentos reais e nao permite chamadas pagas de IA.

## Segredos e arquivos

1. Copie `deploy/staging/.env.example` para `deploy/staging/.env.staging` fora do Git.
2. Gere valores novos para `POSTGRES_PASSWORD`, `REDIS_PASSWORD` e `JWT_SECRET_KEY`. Nunca reutilize `backend/.env`.
3. Defina `APP_DOMAIN` para um DNS de homologacao que aponte para o proxy. O Caddy obtem e renova o certificado HTTPS automaticamente quando as portas 80 e 443 chegam ao host.
4. Mantenha `PILOT_MODE=true`, `GUPMAX_DEBUG=false`, `DOCS_ENABLED=false` e as credenciais de OpenAI, Stripe e Mercado Pago vazias.
5. Confira que `CORS_ORIGINS` e `API_BASE_URL` usam somente o dominio HTTPS de homologacao.

O arquivo `.env.staging` nao deve ser versionado. O Compose injeta esses valores apenas nos containers; Postgres e Redis ficam na rede `data`, sem portas publicadas no host.

## Validacao sem iniciar servicos

A partir da raiz do repositorio:

```powershell
docker compose --env-file deploy/staging/.env.example -f deploy/staging/docker-compose.yml config
python -m pytest backend/tests/test_pilot_mode.py -q
python -m ruff check backend/app/core backend/app/modules/ai_gateway backend/app/modules/payments backend/tests/test_pilot_mode.py
git diff --check
```

O primeiro comando valida interpolacao e topologia. Ele nao aplica migrations nem inicia containers. Para validar a imagem sem publicar nada, use `docker compose ... build` com o `.env.staging` real e inspecione os logs de build; nao coloque segredos em argumentos Docker.

A release web usa `frontend/Dockerfile.release`, `flutter build web --release` e `--dart-define=API_BASE_URL=...`. O proxy serve os artefatos estaticos e encaminha somente `/api/*` para a API.

## Migrations controladas

Migrations nao fazem parte do comando de inicializacao da homologacao. Depois de validar a imagem e obter uma janela aprovada:

1. Confirme backup, destino e `DATABASE_URL` dentro do container `api`.
2. Rode `docker compose --env-file .env.staging -f docker-compose.yml run --rm api alembic upgrade head` como uma operacao separada e observada.
3. Verifique a revisao com `alembic current` e o endpoint `/health` atraves do proxy.
4. Somente depois inicie ou atualize os servicos de aplicacao.

Nunca execute esses comandos apontando para `backend/.env`, para a porta local `5432` ou para uma base de producao sem aprovacao e backup. O modo piloto continua bloqueando pagamentos reais e IA paga mesmo que uma credencial seja acidentalmente adicionada: a configuracao falha ao iniciar.
