# Milestone 9 — GUPMAX Inteligente

## Etapa 9.1 — Motor de Entrevista Inteligente

### Arquitetura

A Etapa 9.1 cria uma fundação exclusivamente backend para transformar uma ideia inicial em entrada estruturada do Prompt Engine. O módulo `interviews` segue a arquitetura existente com enums, schemas Pydantic, models SQLAlchemy, repository, service, router e gerador determinístico de perguntas.

O fluxo implementado é:

1. o usuário autenticado inicia uma sessão com ideia, modo e categoria;
2. o backend congela na sessão as perguntas relevantes ao modo/categoria;
3. respostas são validadas e persistidas por chave estável;
4. o progresso determina se a entrevista está `active` ou `ready`;
5. uma entrevista pronta pode ser concluída;
6. a conclusão persiste e retorna um `PromptGenerateRequest` aceito diretamente pelo Prompt Engine.

Nenhum prompt é criado na conclusão desta etapa. Isso separa coleta/estruturação da geração final e evita duplicação, consumo de créditos ou chamada de IA por retry.

### Contratos HTTP

Todos os endpoints exigem autenticação Bearer:

| Método e rota | Contrato |
| --- | --- |
| `POST /api/v1/interviews` | Recebe `initial_request`, `mode` e `category`; cria a sessão e retorna perguntas, respostas, progresso e timestamps. |
| `GET /api/v1/interviews/{interview_id}` | Retoma a sessão própria com estado persistido. |
| `POST /api/v1/interviews/{interview_id}/answers` | Recebe uma ou mais respostas estruturadas e faz upsert por chave de pergunta. |
| `POST /api/v1/interviews/{interview_id}/complete` | Exige estado `ready`; persiste e retorna o payload compatível com `PromptGenerateRequest`. |

`InterviewSession` expõe ID, user ID do próprio recurso, status, modo, categoria, ideia inicial, perguntas, respostas, progresso, payload estruturado quando concluído, criação, atualização, conclusão e expiração. Não expõe raciocínio privado, prompts internos, secrets ou dados de provider.

### Estados e transições

- `active`: ainda existem respostas obrigatórias ausentes;
- `ready`: todas as respostas obrigatórias foram registradas;
- `completed`: o payload estruturado foi produzido e congelado;
- `expired`: o prazo de sete dias foi atingido antes da conclusão.

Basic nasce `ready`, pois preserva a geração rápida sem entrevista. Pro nasce `active` com quatro perguntas: duas específicas da categoria e duas comuns. Expert inclui todas as perguntas da categoria, contexto comum e requisitos adicionais de sucesso, restrições, formato e exemplos.

Sessões expiradas rejeitam acesso operacional com 409. Sessões concluídas rejeitam novas respostas. Conclusão antes de `ready` retorna 409. Repetir a conclusão retorna exatamente o payload já persistido.

### Categorias, perguntas e respostas

O gerador determinístico cobre as 12 categorias contratuais: Marketing, Vendas, Redes sociais, E-commerce, Programação, Negócios, Educação, Escrita, Imagem, Vídeo, Produtividade e Geral.

Cada categoria possui um conjunto pequeno e extensível de perguntas relevantes. Exemplos incluem canal e CTA em Marketing, stack e requisitos em Programação, plataforma/duração em Vídeo e contexto/resultado em Negócios. A implementação suporta os tipos `text`, `multiline`, `single_choice`, `multi_choice` e `boolean`, com obrigatoriedade e opções explícitas.

Nesta fundação, campos ausentes são as chaves de perguntas determinísticas relevantes ao modo/categoria ainda sem resposta. Não existe inferência semântica por IA sobre o texto inicial nesta etapa. A arquitetura permite substituir ou complementar o gerador determinístico futuramente sem alterar persistência e contratos de resposta.

### Persistência e migration

A migration Alembic `0007_interviews`, sucessora direta de `0006_payments`, cria:

- `interview_sessions`, com ownership, estado, modo, categoria, ideia, snapshot das perguntas, payload final e timestamps;
- `interview_answers`, com valor JSON e unicidade `(interview_id, question_key)`;
- foreign keys com cascade, constraints e índices de owner, estado, modo, categoria e expiração.

PostgreSQL é a fonte de verdade para retomada, refresh, múltiplos dispositivos e auditoria. Redis não é utilizado como fonte primária nem foi alterado.

### Prompt Engine, IA e créditos

O payload concluído reutiliza `PromptGenerateRequest`: ideia, modo, categoria, idioma, tom, contexto, público, instruções, restrições e formato são montados de forma determinística. Testes confirmam que o `PromptBuilder` atual aceita a saída.

`optimize_with_ai` permanece `false`. O OpenAI Gateway, billing, usage, entitlement, wallet e créditos não são chamados. O custo de uma futura entrevista assistida por IA ainda não possui regra comercial formal; portanto, nenhuma cobrança foi criada silenciosamente.

### Idempotência e segurança

Respostas usam upsert pela constraint única de sessão/chave, de modo que retries não duplicam respostas. A conclusão é idempotente e não cria prompts. A criação de uma nova sessão representa intencionalmente uma nova entrevista e não recebe chave de idempotência nesta primeira versão.

Ownership é decidido exclusivamente no backend. Sessão inexistente e sessão de outro usuário retornam o mesmo 404, inclusive em leitura, resposta e conclusão, prevenindo IDOR. Administradores não recebem bypass implícito: cada usuário acessa somente suas entrevistas.

### Testes e validações

Os testes adicionados cobrem autenticação, Basic/Pro/Expert, todas as categorias, cinco tipos de pergunta, opções inválidas, respostas obrigatórias e opcionais, múltiplas respostas, progresso, `ready`, expiração, completed, retries, conclusão idempotente, ownership/IDOR, recurso inexistente e integração com o builder determinístico. Nenhuma chamada OpenAI real é possível pelo serviço de entrevistas atual.

Ruff e os 104 testes backend foram aprovados. A migration foi validada e aplicada no banco de desenvolvimento, levando o Alembic de `0006_payments` para `0007_interviews (head)`. Os quatro paths estão publicados no OpenAPI e `/health` retorna 200.

### Smoke test manual/API

O smoke test manual/API da Etapa 9.1 foi aprovado contra o backend local real. A autenticação existente funcionou e exatamente uma entrevista Pro de Marketing foi criada. A sessão iniciou em `active`, com quatro perguntas obrigatórias e progresso 0/4; perguntas, tipos, obrigatoriedade e opções foram retornados corretamente.

As respostas de canal, CTA, público e tom foram enviadas progressivamente, validando os estados 1/4, 2/4, 3/4 e 4/4. Após a quarta resposta, a entrevista passou para `ready`. A conclusão retornou HTTP 200, alterou o estado para `completed`, preencheu `completed_at` e produziu um `PromptGenerateRequest` compatível com o Prompt Engine, preservando modo `pro`, categoria `marketing`, tom, público e incorporando canal e CTA ao contexto, com `optimize_with_ai` desativado.

A idempotência também foi validada no backend real: uma segunda chamada de conclusão retornou HTTP 200, manteve o estado `completed`, preservou exatamente o mesmo `completed_at` e devolveu exatamente o mesmo `PromptGenerateRequest` persistido. A criação e a conclusão da entrevista não criaram um registro `Prompt`, não chamaram OpenAI, não consumiram nem reservaram créditos e não realizaram operações em pagamentos ou wallet.

Com as validações automatizadas e o smoke test manual/API aprovados, a Etapa 9.1 está integralmente aprovada.

### Limitações e próxima etapa

- não há geração de perguntas por IA nem interpretação semântica da ideia;
- não há endpoint de cancelamento ou listagem histórica nesta fundação;
- a criação de sessão não usa chave de idempotência;
- a conclusão retorna o payload, mas não persiste um `Prompt`;
- não houve alteração Flutter.

A Etapa 9.2 poderá construir a UX Flutter de entrevista sobre esses contratos, mantendo o backend como autoridade e sem inferir regras financeiras no cliente.

## Etapa 9.2 — Frontend da Entrevista Guiada

### Arquitetura frontend

A feature isolada `features/interviews` segue os padrões existentes do Flutter, separando modelos de domínio, repository HTTP, controller baseado em `ChangeNotifier`, providers Riverpod e página de apresentação. O frontend reutiliza `ApiClient`, autenticação e tratamento global de 401 já existentes. Nenhuma alteração backend foi necessária.

O repository consome exclusivamente os contratos publicados pela Etapa 9.1:

- `POST /api/v1/interviews` para iniciar a sessão;
- `GET /api/v1/interviews/{interview_id}` para carregamento, refresh e deep link;
- `POST /api/v1/interviews/{interview_id}/answers` para persistir uma resposta;
- `POST /api/v1/interviews/{interview_id}/complete` para concluir e receber o `PromptGenerateRequest`.

### Fluxo Basic, Pro e Expert

O formulário existente de criação continua sendo a origem da solicitação inicial, modo e categoria. Basic preserva o fluxo direto do Prompt Engine e não abre uma entrevista visual vazia. Pro e Expert criam uma entrevista real com os dados escolhidos pelo usuário e navegam para `/interviews/:id`; a diferença de profundidade continua sendo definida pelas perguntas retornadas pelo backend.

A rota nova é protegida pelo redirect global de autenticação. A página sempre pode recuperar a entrevista pelo ID, sem depender exclusivamente de estado em memória, permitindo refresh e deep link. Um usuário sem sessão é encaminhado ao login com o destino original preservado.

### Perguntas, respostas e progresso

A interface renderiza dinamicamente `text`, `multiline`, `single_choice`, `multi_choice` e `boolean`. Textos, chaves, obrigatoriedade e opções vêm integralmente do backend; não existem perguntas específicas codificadas no Flutter. Choices usam componentes que reorganizam seu conteúdo e a tela permanece limitada a uma largura legível com rolagem vertical.

Cada avanço envia somente a resposta da pergunta atual. O backend realiza o upsert por chave e devolve a sessão completa; o controller substitui seu estado pela resposta real, preservando respostas e atualizando progresso e status sem simulação local. Falhas mantêm a pergunta visível e permitem retry seguro.

### Ready, complete e Prompt Engine

Quando o backend retorna `ready`, a página apresenta a confirmação “Pronto para criar seu prompt”. O botão fica desabilitado durante a requisição, evitando chamadas concorrentes por clique duplo. `/complete` fornece o `PromptGenerateRequest`, convertido para o mesmo `PromptGenerateInput` utilizado pelo fluxo existente e encaminhado a `PromptController.generate`; não há segundo Prompt Engine nem montagem manual duplicada do payload.

Uma sessão `completed` não aceita novas respostas e reutiliza o `structured_prompt` persistido. Uma sessão expirada apresenta orientação para iniciar nova criação. 404 é exibido sem revelar ownership, erros recuperáveis oferecem retry e 401 permanece sob responsabilidade do fluxo global de autenticação.

### Testes e validação

Os testes Flutter cobrem criação Pro e Expert, Basic sem entrevista visual, renderização dos cinco tipos de pergunta, envio e progresso, erro e retry, `ready`, `complete`, bloqueio de clique duplo, `completed`, `expired`, rota protegida, deep link com consulta por ID e ausência de overflow nas larguras 320, 768 e 1280 pixels. Repositories falsos impedem acesso a OpenAI, pagamentos ou geração real de prompts.

### Smoke test manual

O smoke test manual da Etapa 9.2 foi aprovado contra o frontend e o backend reais.

No fluxo Basic de Marketing, a solicitação seguiu diretamente para o Prompt Engine, sem abrir entrevista guiada. A tela de resultado preservou o modo GUPMAX Rápido, a categoria, o idioma `pt-BR` e informou que IA não foi utilizada.

No fluxo Pro de Marketing, a entrevista apresentou quatro perguntas obrigatórias. O progresso real foi validado de 0/4 até 4/4 com respostas de canal, CTA, público e tom. O backend retornou `ready`, a ação “Gerar meu prompt” concluiu a entrevista com uma única interação e o resultado preservou modo, categoria, idioma e tom, incorporando as respostas ao prompt final.

No fluxo Expert de Marketing, dez perguntas foram carregadas. O progresso avançou corretamente e uma pergunta opcional foi pulada; a entrevista alcançou `ready` com 9/10 respostas, confirmando que campos opcionais não bloqueiam a conclusão. O resultado preservou GUPMAX Expert e apresentou as estruturas ROLE, OBJECTIVE, CONTEXT, AUDIENCE, INSTRUCTIONS, CONSTRAINTS, OUTPUT FORMAT, LANGUAGE e TONE, com as respostas incorporadas.

Nos três fluxos, a tela de resultado e as ações de copiar prompt, criar outro e consultar histórico permaneceram funcionais. A integração Interview → `/complete` → Prompt Engine foi aprovada. Durante o smoke test, a otimização com IA permaneceu desligada; nenhuma chamada OpenAI foi intencionalmente executada, nenhuma compra ou checkout foi iniciado e nenhuma operação de payment ou wallet foi solicitada.

Com as validações automatizadas e o smoke test manual aprovados, a Etapa 9.2 está integralmente aprovada.

### Limitações

- perguntas e enriquecimento continuam determinísticos conforme a Etapa 9.1;
- não existe listagem histórica ou cancelamento de entrevistas;
- respostas já enviadas são preservadas pelo backend, mas esta versão conduz sequencialmente apenas pelas perguntas ainda não respondidas.
