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

## Etapa 9.3 — Entrevista Adaptativa

### Arquitetura e facts

A entrevista agora possui uma camada de facts estruturados, separada das respostas explícitas. Cada fact contém valor, origem e confiança, com suporte às origens `initial_request`, `form`, `answer` e `ai_extraction`. Nesta etapa são produzidos facts determinísticos da solicitação inicial e facts explícitos do formulário; respostas continuam persistidas na tabela própria e têm precedência no `complete`.

Os facts são persistidos como JSON em `interview_sessions.facts` pela migration `0008_adaptive_interview_facts`. Isso mantém refresh, retomada, conclusão e idempotência consistentes sem expor análise interna ou facts no contrato público de leitura. O snapshot adaptativo de perguntas continua congelado em `questions` no momento da criação.

### Extração determinística e perguntas omitidas

`DeterministicFactExtractor` reconhece apenas sinais considerados claros: plataformas/canais conhecidos, tom explicitamente introduzido como tom, público descrito por expressões objetivas, idioma explícito, duração de vídeo, stacks conhecidas e CTA explicitamente marcado. A normalização remove diferenças de caixa e acentuação para comparação, preservando detalhes úteis — por exemplo, Marketing normaliza Instagram como canal `rede social`, mas mantém Instagram no contexto final.

O gerador recebe as chaves conhecidas e omite as perguntas correspondentes. Pro continua limitado às perguntas de maior valor e pode iniciar diretamente em `ready` quando todas as informações obrigatórias já estiverem disponíveis. Expert mantém maior profundidade, perguntas opcionais e limite máximo explícito de dez perguntas antes das omissões. Basic continua sem entrevista visual.

O total é inteiramente dinâmico e retornado pelo backend. O Flutter já usava `progress.total`, suporta sessão que inicia em `ready` e não exigiu mudança visual. A integração do formulário passou a enviar opcionalmente `known_fields`, tipado pelo próprio `PromptGenerateRequest`, preservando compatibilidade com clientes anteriores.

### Precedência e complete

A combinação final segue esta precedência:

1. resposta explícita mais recente;
2. campo explícito do formulário;
3. fact extraído deterministicamente da solicitação inicial;
4. default do Prompt Engine.

Uma resposta explícita pode corrigir um fact omitido da entrevista; ela é validada pelo mesmo contrato da pergunta original, não altera artificialmente o progresso do snapshot e vence no `PromptGenerateRequest`. Contexto, público, tom, idioma, título, role, instruções, restrições, formato e informações adicionais do formulário são preservados. `optimize_with_ai` permanece sempre `false` na conclusão da entrevista.

### IA, billing e fallback

IA assistida não foi habilitada nem chamada. A arquitetura reserva a origem `ai_extraction`, mas não existe feature flag ativa nem integração do extractor com provider nesta etapa. Portanto, o fallback efetivo é sempre a extração determinística local, que não depende de rede, não chama OpenAI, não reserva ou consome créditos e não acessa billing, wallet ou pagamentos.

### Segurança e contratos

Ownership, resposta 404 uniforme e proteção contra IDOR permanecem inalterados. Facts não influenciam autorização nem lógica financeira, não contêm chain-of-thought e não são retornados pela API. Inputs continuam validados por Pydantic; respostas explícitas para perguntas omitidas só são aceitas quando a chave e o valor pertencem ao conjunto formal do modo/categoria.

Os quatro endpoints existentes permanecem os mesmos. A única extensão contratual é o campo opcional e retrocompatível `known_fields` em `POST /api/v1/interviews`, usando `PromptGenerateRequest`. Não houve mudança nos responses.

### Testes e limitações

Os testes cobrem extração determinística, origem dos facts, persistência indireta por refresh, perguntas omitidas, pergunta ainda necessária, Pro iniciando `ready`, total dinâmico, limite Expert, categorias, precedência form/extraction/answer, complete, idempotência e toda a segurança existente. Os casos A–E foram formalizados: entrada sem facts seguros preserva o fluxo; Instagram/público/tom eliminam redundâncias; vídeo reconhece TikTok/duração/público; programação reconhece React/site; e resposta persuasiva vence tom profissional extraído.

Limitações atuais:

- o extrator é deliberadamente conservador e cobre vocabulário explícito conhecido;
- não há interpretação semântica por IA, sinônimos amplos ou inferência probabilística;
- facts não são exibidos para edição no frontend; correções continuam possíveis por resposta explícita/API.

### Correção de regressão do contexto

No smoke test Expert/Programação foi encontrado um registro em que `requirements` havia sido persistido com valor exatamente igual ao enunciado da pergunta. O `complete` concatenava corretamente enunciado e valor uma única vez, e o `PromptBuilder` apenas publicava o contexto recebido; portanto, a aparente duplicação era consequência do valor inválido já armazenado, não de dupla concatenação.

O backend agora rejeita com 422 respostas `text`/`multiline` idênticas ao respectivo enunciado. O teste de regressão percorre resposta, persistência, conclusão e `PromptBuilder`, confirma que uma resposta real aparece uma única vez e preserva `Plataforma: site` e `Stack: React`. Um teste Flutter separado confirma que o repository recebe o conteúdo efetivamente digitado no campo de requisitos.

### Smoke test manual

O smoke test manual da Etapa 9.3 foi aprovado contra o frontend e o backend reais.

No fluxo Pro/Marketing, a solicitação com Instagram, público de mulheres de 18 a 35 anos e tom persuasivo iniciou uma entrevista com somente a lacuna de CTA. O progresso variou de 0/1 para 1/1, o estado `ready` foi exibido e o Prompt final preservou Instagram, público, CTA e tom. O caso B da especificação foi aprovado.

No fluxo Expert/Vídeo, TikTok, duração de 15 segundos e público jovem foram detectados. A entrevista iniciou com seis perguntas em vez do máximo de dez e apresentou como primeira lacuna o estilo ou ritmo do vídeo, confirmando o total adaptativo e a relevância das perguntas restantes.

No fluxo Expert/Programação, React e plataforma site foram detectados e não perguntados novamente. A entrevista iniciou com sete perguntas, permitiu pular as opcionais e manteve obrigatórias bloqueantes. O Prompt final preservou `Plataforma: site` e `Stack: React`, aprovando o caso D e a integração Interview → Prompt Engine.

O reteste da correção de contexto usou em `requirements` a resposta “Cardápio online, botão de WhatsApp e layout responsivo.”. O resultado apresentou uma única vez o enunciado seguido da resposta real, sem repetir a duplicação, e preservou site e React. A correção foi aprovada; o registro histórico anterior não foi modificado.

Durante toda a validação, nenhuma IA ou chamada OpenAI foi utilizada, nenhum crédito de IA foi consumido e nenhuma operação de wallet, pagamento, checkout, Stripe ou Mercado Pago foi executada.

Com as validações automatizadas, o smoke test adaptativo e o reteste da regressão aprovados, a Etapa 9.3 está integralmente aprovada.
