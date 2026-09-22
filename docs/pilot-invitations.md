# Convites do piloto — cadastro por convite

O cadastro público exige convite. Esta etapa integra backend e Flutter; não
habilita produção, pagamentos reais ou validação de IA paga.

## Emissão e entrega

- Um administrador ativo com `users:manage` chama `POST /api/v1/auth/invitations`
  com o e-mail do convidado no corpo JSON e sua autenticação habitual.
- A resposta 201 contém `invitation_token` e `expires_at`, com `Cache-Control:
  no-store`. A validade é de 72 horas. E-mail já cadastrado recebe 409.
- A entrega é manual ao destinatário. Não existe envio automático de e-mail,
  tela administrativa ou endpoint para revogação individual nesta etapa.
- O token é uma credencial: não registrar em logs, relatórios, URLs ou comandos
  persistidos no histórico. JWT assinado não cifra o e-mail contido no payload.

### Roteiro do administrador

1. Usar uma sessão administrativa válida em um cliente HTTP que não registre
   corpos de requisição/resposta nem sincronize credenciais. Enviar o e-mail do
   destinatário em `POST /api/v1/auth/invitations`, autenticado com Bearer.
2. Confirmar 201 e anotar somente a expiração. Não copiar o token para tickets,
   relatórios, logs ou comandos de terminal.
3. Entregar manualmente ao destinatário, por canal privado previamente combinado,
   o convite e o endereço da página de cadastro, separadamente. Não anexar o
   convite como parâmetro de URL. Informar o e-mail autorizado e a validade de 72h.
4. Orientar a preencher nome, e-mail convidado, senha e o campo **Convite** no
   Flutter. O campo fica oculto; o convite é enviado somente no corpo do cadastro,
   sem persistência no armazenamento de sessão nem logging pela aplicação.
5. Convite ausente é bloqueado no formulário. Recusa 403 mostra “Convite inválido,
   vencido ou já utilizado”, orientando conferir o e-mail ou solicitar outro.
   Emitir outro convite exige nova ação administrativa; não há reenvio automático.

Em produção, emissão, entrega e aceite exigem HTTPS e o procedimento autorizado
para o primeiro administrador. Esta documentação não autoriza criar contas no
banco operacional durante a preparação.

## Aceite

`POST /api/v1/auth/register` recebe os campos existentes `email`, `full_name` e
`password`, acrescidos de `invitation_token`. O e-mail normalizado deve coincidir
com o convite. A API valida assinatura, finalidade, audiência, expiração, registro
do convite e permissão atual do emissor. Convite ausente, inválido, expirado ou
consumido recebe 403 genérico, sem cadastro nem concessão. Login de contas
existentes permanece disponível. Campos administrativos enviados pelo convidado
não promovem a conta, que é criada como usuário comum.

O aceite cria conta, trial e créditos pelo serviço existente e devolve a sessão
habitual. Convite consumido não pode ser reutilizado, inclusive após mudança de
e-mail ou exclusão do convidado. Conflito de e-mail recebe 409 e não consome outro
convite. Emissão, por si só, não cria conta de convidado, trial ou créditos.

## Persistência e atomicidade sem migration

A tabela existente `refresh_tokens` armazena a permissão de cadastro, vinculada
ao administrador emissor. O JTI usa o namespace `inv:` (36 caracteres); o JWT
tem finalidade `invitation` e audiência exclusiva. Esse token não funciona como
access token nem refresh token. `expires_at` define a validade; `revoked_at`
registra consumo ou invalidação. Nenhum token de convite em texto é persistido.

O aceite bloqueia o registro com `FOR UPDATE` no PostgreSQL. Os serviços existentes
são executados em uma sessão subordinada à transação externa, com
`join_transaction_mode="rollback_only"`: seus commits internos não confirmam a
transação externa. Conta, trial, créditos, sessão e consumo do convite são
confirmados juntos; falha desfaz todos eles. O índice único de e-mail protege
também cadastros concorrentes com convites diferentes.

Desativar ou remover a permissão do emissor impede novos aceites. Excluir o emissor
remove os registros vinculados. A revogação de todas as sessões do emissor, como
na troca de senha, também invalida seus convites pendentes. Registros de convite
não devem ser eliminados antes da expiração, mesmo quando consumidos.

## Validação e pendências operacionais

Testes isolados cobrem autorização do GET de usuários, emissão administrativa,
assinatura, audiência/finalidade, validade, e-mail, replay, concessão única,
rollback após concessão e isolamento entre convites e tokens de sessão. As
fixtures antigas simulam admissão somente dentro dos testes; o código de produção
não tem caminho para ignorar a validação.

Em 21/09/2026, `backend/scripts/invitation_concurrency_check.py` executou duas
requisições HTTP simultâneas no app ASGI real, com validação de convite habilitada
e duas conexões distintas em PostgreSQL 17 descartável. Uma barreira sincronizou
as conexões antes do processamento. Resultado: **201 e 403; exatamente uma conta,
um trial, um lançamento `trial_grant` de 100 créditos, saldo 100, Usage zero e
reservas zero** para o convidado. A API foi exercitada em memória; nenhuma porta
de API operacional foi usada.

O banco de auditoria usou container exclusivo, dados em tmpfs, sem volumes do
projeto, e porta loopback exclusiva. O script recusa banco não vazio e exige o
`system_identifier` consultado diretamente no container, além do endereço e nome
fixos reservados à auditoria. O schema foi criado por `metadata.create_all` apenas
nesse banco descartável; nenhuma migration foi executada. Para repetir, preparar
outro container vazio nessas condições e executar, no diretório backend,
`python -m scripts.invitation_concurrency_check --system-identifier <identificador-do-container>`.
Encerrar apenas esse container ao concluir. O teste não comprova carga sustentada
nem o processo de migrations de produção.

Validação desta integração: 100 testes backend relacionados, 18 testes Flutter
de autenticação e 339 testes Flutter completos aprovados; Flutter Analyze sem
issues, Ruff e `git diff --check` aprovados. O container de auditoria foi removido
ao concluir, sem alterar containers ou dados operacionais. Os testes do Flutter
verificam envio do convite no corpo, bloqueio de campo vazio, mensagem segura de
403, ausência do token nos logs capturados e preservação da sessão no sucesso.

Antes de usar o fluxo: provisionar o primeiro administrador por procedimento
separado e autorizado e ensaiar entrega/aceite manual no Flutter integrado.
O endpoint administrativo de criação de usuários mantém
seu contrato anterior e continua restrito a `users:manage`.

Os bloqueios específicos de pagamentos reais e IA paga ainda pertencem à próxima
etapa. Não publicar o piloto apenas com esta mudança. Nenhum banco operacional,
segredo ou migration precisa ser alterado para revisar e testar este código.
