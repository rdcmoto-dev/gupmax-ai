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

Uma resposta explícita pode corrigir um fact omitido da entrevista; ela é validada pelo mesmo contrato da pergunta original, não altera artificialmente o progresso do snapshot e vence no `PromptGenerateRequest`. Contexto, público, tom, idioma, título, role, instruções, restrições, formato e informações adicionais do formulário são preservados. A partir da Etapa 9.4, a escolha explícita por `optimize_with_ai=true` também é preservada; o default continua `false`.

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

## Etapa 9.4 — Otimização inteligente com IA

### Fluxo técnico e comercial

Com `optimize_with_ai=false`, o Prompt Engine permanece integralmente determinístico: constrói e persiste o prompt sem gateway, usage, reserva ou consumo de créditos. Com a opção ativa, o backend constrói primeiro o resultado determinístico, registra a operação idempotente, valida entitlement e limites, calcula a estimativa pelas regras de custo existentes, reserva créditos, chama exclusivamente o AI Gateway e valida a saída antes de marcá-la como otimizada.

Após sucesso, provider, model e tokens são persistidos no Prompt, o usage é finalizado com vínculo ao Prompt e a reserva de créditos sofre settlement pelo custo real limitado ao valor reservado. O ledger existente registra reserva, consumo de IA e eventual liberação do excesso. Nenhuma decisão de preço, saldo ou concessão de créditos ocorre no Flutter.

### Estimate, idempotência e falhas

O endpoint existente `POST /api/v1/credits/estimate` continua sendo a fonte da estimativa. A tela consulta esse endpoint ao ativar a opção, mostra custo e saldo retornados pelo backend e oferece acesso a “Créditos e planos” quando `can_execute=false`. A estimativa é informativa; autorização e reserva são revalidadas server-side na geração.

`POST /api/v1/prompts/generate` aceita o header opcional e retrocompatível `Idempotency-Key`. O Flutter envia uma chave por tentativa. A migration `0009_prompt_idempotency` adiciona chave e fingerprint ao Prompt, com unicidade por usuário. A operação é persistida antes do gateway; repetição da mesma chave e payload retorna o mesmo Prompt sem nova chamada, usage ou débito. Reutilização da chave com payload diferente, ou enquanto a operação está processando, retorna 409.

Saldo insuficiente bloqueia antes do provider. Falhas de configuração, timeout, provider ou saída inválida liberam usage e reserva e mantêm o prompt determinístico persistido como fallback seguro. Um retry deliberado recebe chave nova; retries do mesmo request permanecem idempotentes.

### Validação, segurança e frontend

O conteúdo do usuário é delimitado como não confiável e o gateway recebe instruções para somente otimizar o prompt, preservar requisitos e ignorar tentativas de alterar autorização, billing ou revelar instruções internas. Saídas vazias, excessivas ou que removam solicitação, contexto, público, role, formato, instruções ou constraints explícitas são rejeitadas. Nenhuma API key, system prompt interno ou chain-of-thought é retornado.

Basic, Pro e Expert usam o mesmo fluxo. Em entrevistas, a preferência explícita por IA passa pelos facts persistidos e reaparece no `PromptGenerateRequest` de `/complete`, com categoria, modo, audience, tone, context, constraints, formato e demais respostas.

O toggle comunica consumo possível, apresenta loading da estimativa e é desabilitado durante submissão. O controller impede clique duplo. As mensagens cobrem sessão, saldo, entitlement, conflito, limite e provider. O resultado mostra “IA utilizada” somente para status `optimized`; provider, model e tokens aparecem apenas quando persistidos.

### Testes, limitações e smoke test

Gateway e repositories falsos cobrem fluxo determinístico gratuito, sucesso nos três modos, estimativa, saldo insuficiente antes do provider, reserva, settlement, release, usage, ledger, falha do provider, saída inválida, idempotência de Prompt/usage/créditos e preservação da IA em entrevistas. Nenhuma chamada OpenAI real ou operação financeira externa é executada.

O Gateway atual não expõe schema estruturado específico para Prompt; por isso a saída textual é validada contra limites e requisitos explícitos. A estimativa usa contagem aproximada de entrada e máximo configurado de saída; o settlement usa tokens reais. O smoke test manual controlado permanece pendente e deve usar ambiente dev/sandbox, poucos créditos e uma única geração.

### Adendo visual

Atualização da identidade de cores do frontend, com azul como cor dominante, dourado como acento premium e superfícies claras.

## Etapa 9.5 — Refinamento e versões

### Modelagem e contratos

O versionamento reutiliza a tabela `prompts`. A migration `0010_prompt_versions`, sucessora direta de `0009`, adiciona `parent_prompt_id`, `root_prompt_id`, `version_number` e `refinement_instruction`, com chaves estrangeiras, índices e unicidade de número dentro da raiz. A versão original permanece como v1; cada refino cria um novo Prompt ligado à versão imediatamente anterior e à raiz da família, sem sobrescrever conteúdo histórico.

Os endpoints autenticados `POST /api/v1/prompts/{prompt_id}/refine` e `GET /api/v1/prompts/{prompt_id}/versions` seguem o mesmo ownership seguro dos detalhes existentes: recurso inexistente ou pertencente a outro usuário retorna a resposta uniforme já adotada contra IDOR. A instrução é normalizada, não pode ser vazia e possui limite de 1.000 caracteres. O header `Idempotency-Key` usa o mecanismo de chave e fingerprint já existente e impede versão, usage ou cobrança duplicados.

### Refino determinístico e IA

Sem IA, o serviço parte do texto integral da versão anterior e aplica alterações estruturadas reconhecidas de tom, idioma e concisão; a instrução também é registrada em seção própria. Campos não alterados, categoria, modo Basic/Pro/Expert e requisitos existentes permanecem no novo texto. Em conflitos explícitos, como profissional → persuasivo, a instrução mais recente substitui somente a seção correspondente.

Com IA, o fluxo reutiliza entitlement, estimate, reserva, AI Gateway, validação de saída, usage, settlement e release da Etapa 9.4. O prompt e a instrução são delimitados como conteúdo não confiável. A saída precisa manter as seções da versão anterior. O ledger conserva os tipos existentes e registra `purpose=prompt_refinement` no metadata. Falha do provider libera usage e créditos, remove a versão em processamento e mantém integralmente a versão anterior.

### Histórico, comparação e frontend

A rota existente `/prompts/:id` ganhou a ação “Refinar prompt”, campo de instrução, opção de IA, estimativa real, bloqueio por saldo, loading e mensagens do backend. A mesma página lista o histórico cronológico com data, modo, categoria, indicação de IA e instrução de refino. A comparação simples apresenta versão anterior e nova lado a lado no desktop e em coluna no mobile, com cópia independente e escolha local da versão exibida. Nenhuma rota adicional foi necessária, preservando deep link e refresh atuais.

### Segurança, testes e limitações

O refinamento não autoriza mudanças em ownership, billing, wallet ou instruções internas. API keys, tokens, system prompts e secrets não são expostos. Testes com gateways falsos cobrem refino determinístico e IA, Basic/Pro/Expert, linhagem, preservação da versão anterior, alteração explícita de tom, validação, IDOR, idempotência, usage, reserva, settlement, release, metadata do ledger, falha do provider e ausência de duplicação. Nenhuma chamada OpenAI real é feita.

O mapeamento determinístico é deliberadamente conservador: reconhece alterações simples de tom, idioma e concisão; instruções mais livres são preservadas como orientação de refinamento, sem tentar simular compreensão semântica ampla. A comparação é textual e não implementa diff avançado ou editor rico. O smoke test manual da Etapa 9.5 permanece pendente.

## Etapa 9.6 — GUPMAX Score

### Arquitetura e critérios

`PromptQualityEvaluator` calcula a avaliação sob demanda diretamente sobre cada Prompt persistido. O evaluator apenas analisa as seções estruturadas já produzidas pelo Prompt Engine; não executa o conteúdo, não altera o Prompt e não acessa AI Gateway, billing, credits, wallet ou ledger. Nenhuma migration ou persistência de score foi necessária.

O score total varia de 0 a 100 e agrega dez critérios: objetivo, contexto, público, instruções, clareza, formato de saída, restrições, tom, idioma e especificidade. Cada critério informa nota, máximo, estado e feedback relacionado à presença e profundidade observadas. As classificações são Fraco, Pode melhorar, Bom, Muito bom e Excelente. Pontos fortes são derivados somente de critérios bem atendidos; melhorias e sugestões acionáveis são produzidas somente para itens ausentes ou parciais.

Os pesos somam 100 em todos os modos. Basic privilegia objetivo, instruções e clareza e reduz o peso de contexto profundo, público, formato e restrições, permitindo nota alta para prompts simples e claros. Pro aumenta a expectativa de contexto, público, tom e instruções. Expert distribui mais peso para contexto, instruções, restrições, formato e especificidade, sem conceder bônus por comprimento ou por uso de IA.

A especificidade usa regras pequenas por categoria para Marketing, Vendas, Redes sociais, E-commerce, Programação, Negócios, Educação, Escrita, Imagem, Vídeo, Produtividade e Geral. Os sinais são adequados ao domínio, como canal/CTA em Marketing, stack/funcionalidades em Programação e plataforma/duração em Vídeo. Prompts originados de entrevistas aproveitam as mesmas seções e facts já incorporados ao resultado final.

### API, ownership e versões

O endpoint autenticado `GET /api/v1/prompts/{prompt_id}/score` avalia exclusivamente o Prompt persistido solicitado. O acesso reutiliza a regra de ownership do Prompt Engine; Prompt inexistente ou de outro usuário retorna 404 uniforme. O cálculo é barato, determinístico e repetível, portanto cada versão possui seu próprio score sem armazenamento adicional. Prompts antigos e versões 1 compatíveis funcionam sem backfill.

### Frontend e comparação

A página Resultado apresenta o card GUPMAX SCORE com nota, classificação e progresso. “Ver análise” expande critérios, feedbacks, pontos fortes, melhorias e sugestões sem sobrecarregar o topo da página. “Melhorar este prompt” abre o painel de refinamento existente e preenche a instrução com as sugestões; nenhuma nova versão é criada até confirmação explícita do usuário, e a opção de IA permanece desligada.

O histórico mostra o score de cada versão. A comparação anterior × nova apresenta as duas notas e a diferença em pontos, em colunas no desktop e empilhada no mobile. Loading e erro do score são isolados dos estados de detalhe, versões, estimate e refinamento.

### Segurança, custo e limitações

O score determinístico não chama OpenAI, não cria Usage ou reservation, não consome créditos e não gera lançamentos no ledger. Ele não favorece prompts otimizados por IA e não reabre entrevistas. Testes cobrem faixa 0–100, repetibilidade, Basic/Pro/Expert, as 12 categorias, prompt simples versus completo, ownership/IDOR, ausência de efeitos financeiros, versões, loading, erro, extremos 0/100, classificação, expansão, critérios, sugestões, ação de melhoria e layout mobile.

A análise é estrutural e baseada em seções e sinais explícitos; ela não mede veracidade, criatividade, segurança factual ou qualidade da futura resposta de um modelo. O smoke test manual da Etapa 9.6 permanece pendente.

## Etapa 9.7 — Smart Profile

### Objetivo, consentimento e modelagem

O GUPMAX Smart Profile permite que cada usuário salve explicitamente um único conjunto de preferências reutilizáveis. A migration `0011_smart_profile`, sucessora direta de `0010`, cria `user_prompt_preferences` com vínculo único e cascata ao usuário. O perfil pode permanecer vazio, ser ativado ou desativado sem perda dos dados e ser removido integralmente. Não existe aprendizado automático, inferência silenciosa ou armazenamento de prompts no perfil.

Os campos opcionais são idioma, tom, público, canal/plataforma, formato de saída, contexto do negócio/projeto, restrições e orientações padrão. Strings vazias são normalizadas para `null`, listas são normalizadas e todos os campos possuem limites explícitos.

### Endpoints, ownership e privacidade

Os endpoints autenticados `GET`, `PUT` e `DELETE /api/v1/profile/prompt-preferences` consultam, fazem upsert e removem exclusivamente o perfil do usuário atual. Nenhum `user_id` é aceito no payload. Perfil inexistente retorna uma representação vazia e desativada. O conteúdo não é registrado em logs e não altera prompts ou entrevistas históricos.

### Precedência e integrações

O perfil habilitado fornece somente fallbacks. Informações explícitas da solicitação atual — incluindo idioma, tom, público e canal detectáveis — vencem o perfil; campos atuais preenchidos também permanecem locais à operação. Respostas de entrevista vencem todos os facts anteriores. O perfil entra na entrevista com origem `profile` e confiança 1.0, abaixo de extração/formulário/resposta, reduzindo perguntas redundantes em Pro sem eliminar perguntas avançadas necessárias em Expert.

Basic continua direto e recebe fallbacks sem formulário obrigatório. Pro e Expert reutilizam a camada de facts adaptativa. Refinamento parte apenas da versão atual e não reaplica o perfil. O GUPMAX Score avalia o texto final sem bônus pela origem das informações.

### Frontend e segurança operacional

Minha conta ganhou o card Smart Profile com controle de ativação, campos curtos responsivos, campos multiline, salvar e limpar preferências. A tela Criar Prompt mostra “Smart Profile ativo” quando há dados habilitados e oferece acesso às preferências. Overrides feitos no formulário atual não atualizam o perfil automaticamente.

Consultar, salvar, aplicar ou apagar o perfil não chama OpenAI, não cria Usage ou reservation, não consome créditos e não altera wallet, ledger ou pagamentos. As limitações atuais são deliberadas: um perfil por usuário, sem histórico, equipes, sincronização externa, aprendizado ou sugestões automáticas.

### Status e smoke test manual

**Status: CONCLUÍDA. Smoke manual: APROVADO.**

O smoke real confirmou criação, salvamento, ativação/desativação, persistência após reload, card e toggle em Minha conta, indicador “Smart Profile ativo” e acesso às preferências em Criar Prompt. Em uma nova geração Basic/Marketing determinística, sem campos manuais e sem IA, as oito preferências foram aplicadas: idioma, tom, público, canal/plataforma, formato de saída, contexto, restrições e orientações. Pro e Expert preservam a integração pela camada de facts e a precedência final permanece: solicitação explícita atual > entrevista atual > Smart Profile > fallback/default.

A correção final incluiu `CONTEXT` e `AUDIENCE` entre as seções estruturais do `PromptBuilder` também no modo Basic, mantendo a omissão de seções vazias. O Smart Profile é aplicado somente em novas gerações, não modifica o perfil salvo, entrevistas ou prompts históricos e não é reaplicado em refinamentos. Seu funcionamento determinístico não exige chamada de IA, Usage, reserva, settlement, créditos ou lançamento no ledger.

## Etapa 9.8 — GUPMAX Templates

### Modelagem e API

A migration reversível `0012_prompt_templates`, sucessora direta de `0011`, cria templates privados vinculados ao usuário. O registro mantém nome, descrição, categoria, modo, conteúdo/base, campos estruturais reutilizáveis, estado ativo, Prompt de origem opcional e datas. Provider, model, tokens, Usage, score, reservation, ledger e idempotency key não são copiados.

Os endpoints autenticados `GET/POST /api/v1/templates`, `GET/PUT/DELETE /api/v1/templates/{id}` e `POST /api/v1/templates/from-prompt/{prompt_id}` implementam criação manual, listagem, consulta, edição, exclusão e captura de uma versão específica. Todos derivam o proprietário da sessão; acesso cruzado retorna 404 uniforme. Excluir ou editar um template não altera o Prompt de origem, versões ou Prompts derivados.

### Reutilização, precedência e frontend

Salvar como template captura somente a versão atualmente exibida. A página Meus templates oferece cards responsivos com Usar, Editar e Excluir. A tela Criar Prompt permite escolher um template ou recebê-lo por deep link, pré-carrega os campos relevantes e nunca gera automaticamente. O usuário pode revisar modo, categoria, conteúdo e preferências antes de construir.

O template é um ponto de partida local: alterações no formulário vencem seus valores e não modificam o registro salvo. Campos preenchidos pelo template vencem fallbacks do Smart Profile; informação explícita atual e entrevista permanecem superiores. Basic, Pro, Expert e as 12 categorias usam os fluxos existentes. Refinar um Prompt derivado não reaplica nem modifica o template, e cada Prompt novo recebe seu próprio GUPMAX Score.

### Segurança, custos e limitações

Conteúdo de template é tratado somente como dado do usuário, nunca como autorização ou instrução interna, e não é registrado integralmente em logs. Criar, consultar, editar, excluir ou selecionar templates não chama OpenAI, não cria Usage/reservation/settlement, não consome créditos e não altera wallet ou ledger.

Não fazem parte desta etapa marketplace, templates públicos, compartilhamento, colaboração, equipes, ranking, comentários, compra ou venda.

### Status e smoke test manual

**Status: CONCLUÍDA. Smoke manual: APROVADO.**

O smoke real confirmou o fluxo Resultado → Salvar como template → Meus templates → Usar, sem geração automática. Um template Basic/Marketing com tom profissional e canal Instagram preencheu o novo formulário; antes da geração determinística, o usuário alterou explicitamente esses valores para tom casual e canal TikTok. O Prompt resultante preservou casual/TikTok, enquanto o template original permaneceu profissional/Instagram ao ser reaberto. Assim, ficou validada em ambiente real a precedência valor atual explícito > template > Smart Profile > defaults, sem chamada OpenAI, consumo de créditos ou efeitos em Usage e ledger pelas operações de template.

## Etapa 9.9 — GUPMAX Projects

### Modelagem, API e ownership

A migration reversível `0013_projects`, sucessora direta de `0012_prompt_templates`, cria projetos privados com nome, descrição, contexto, status ativo/arquivado e timestamps. `prompts.project_id` e `prompt_templates.project_id` são opcionais, indexados e usam `ON DELETE SET NULL`; registros históricos continuam válidos fora de projetos. Os endpoints autenticados `/api/v1/projects` fornecem CRUD, detalhe com prompts/templates e associações explícitas. O proprietário sempre deriva da sessão, e acesso cruzado a projeto ou associação retorna 404 uniforme.

### Contexto, precedência e integrações

Novas gerações iniciadas em projeto carregam `project_id`; o contexto do projeto preenche somente contexto ausente, antes do Smart Profile. A precedência final é valor atual/entrevista > template > contexto do projeto > Smart Profile > defaults. Basic usa o contexto diretamente; Pro e Expert preservam `project_id` pelos dados conhecidos da entrevista e aplicam o mesmo fallback ao gerar. Projetos arquivados permanecem legíveis, mas novas gerações neles exigem reativação.

Associar um Prompt existente nunca reescreve seu conteúdo. Refinamentos herdam `project_id`, mantendo parent/root e a linhagem no projeto. Templates podem ser movidos ou removidos de projeto, e salvar uma versão como template herda a associação da versão selecionada. Templates, Smart Profile e GUPMAX Score continuam independentes: o score avalia somente cada Prompt final e nenhuma preferência ou template é alterado implicitamente.

### Frontend, segurança e limitações

Meus projetos oferece grid desktop e cards em coluna no mobile, estados loading/erro/vazio, criar, editar, arquivar/reativar, excluir e abrir. O detalhe mostra contexto, Prompts e Templates, permite criar Prompt no projeto, associar/remover registros existentes e usar um Template dentro do projeto. Criar Prompt exibe o projeto selecionado; Resultado mostra chip do projeto. Exclusão preserva prompts, versões e templates sem associação.

CRUD e associações de projeto não executam conteúdo, não chamam OpenAI, não criam Usage/reservation/settlement e não alteram créditos ou ledger. Contexto completo e conteúdos não são registrados em logs. Não fazem parte desta etapa equipes, membros, convites, permissões, colaboração, comentários, tarefas, kanban, arquivos, integrações externas, chat, analytics ou compartilhamento público.

### Status, smokes e validações finais

**Status: CONCLUÍDA. Smokes manuais: APROVADOS.**

Os smokes reais confirmaram CRUD e exibição de projetos, criação e associação de Prompt, chip do projeto no Resultado, contexto do projeto e precedência valor explícito/template > projeto > Smart Profile > defaults. A compatibilidade com templates legados foi corrigida sem alterar os registros originais: estruturas persistidas em `base_input`/`template_content` são normalizadas antes da geração, cada seção aparece uma única vez e o título volta a usar somente o objetivo. A exclusão do projeto Pizzaria Donatello removeu o projeto e suas associações, preservando os Prompts em Meus prompts; históricos criados antes da correção permaneceram intactos.

A auditoria final aprovou arquitetura, ownership/IDOR, CRUD, associações, Basic/Pro/Expert, Interviews, refinamento, versionamento e ausência de efeitos em OpenAI, créditos, Usage e ledger nas operações de projeto. Ruff passou, os 210 testes backend e 158 testes Flutter passaram, `flutter analyze` não encontrou issues, `dart format` verificou 106 arquivos sem alterações, `/health` e `/api/v1/openapi.json` responderam 200, `git diff --check` passou e o Alembic permaneceu em `0013_projects` como único head.

## Etapa 9.10 — Target AI / Destino do Prompt

### Modelagem e arquitetura

A migration reversível `0014_target_ai`, sucessora direta de `0013_projects`, adiciona `target_ai` a Prompts e Templates com fallback não destrutivo `generic`. O enum compartilhado valida os destinos `generic`, `chatgpt`, `claude`, `gemini`, `midjourney`, `image_generator`, `video_generator` e `coding_assistant`. Cada Prompt e versão registra seu destino; refinamentos preservam o valor da origem e Templates salvos a partir de uma versão o herdam. Registros e Templates anteriores continuam compatíveis como `generic`.

As regras determinísticas permanecem centralizadas no `PromptBuilder`. Perfis declarativos ordenam somente as seções relevantes para cada destino, mantendo o filtro de valores vazios e sem espalhar condicionais pelo domínio. `generic` conserva exatamente a construção aprovada anteriormente. Target AI define a forma da saída, sem substituir `mode`, categoria ou dados e sem alterar a precedência formulário/request > Template > Projeto > Smart Profile > defaults.

### Fluxos e interface

A tela Criar Prompt apresenta um seletor responsivo com os oito destinos e default “Genérico / Outra IA”. Templates carregam o destino persistido, mas a troca feita no formulário é local e não modifica o Template. Basic gera diretamente; Pro e Expert transportam `target_ai` em `known_fields` durante toda a entrevista. Projetos continuam preservando `project_id` e sua regra de contexto.

Resultado mostra o chip “Destino” separado do indicador “IA utilizada”, deixando explícito que escolher ChatGPT, Claude ou outra ferramenta não executa integração externa. O histórico também identifica o destino de cada Prompt, e o GUPMAX Score aceita aliases estruturais dos destinos sem conceder bônus nem penalizar apenas a nomenclatura das seções.

### Segurança, custo e status

Selecionar Target AI é apenas configuração determinística: não chama plataformas externas, não executa conteúdo, não cria Usage/reservation/settlement, não consome créditos e não altera wallet ou ledger. O fluxo `optimize_with_ai=true` continua usando sem mudanças o entitlement, gateway e settlement já existentes.

**Status: CONCLUÍDA. Smokes manuais finais: APROVADOS.**

A validação final aprovou Ruff, 244 testes backend, `dart format` em 106 arquivos sem alterações, `flutter analyze` sem issues e 159 testes Flutter. O ciclo controlado de downgrade/upgrade confirmou `0014_target_ai` como único Alembic head. `/health` e `/api/v1/openapi.json` responderam 200, incluindo `target_ai` no contrato OpenAPI.

O primeiro smoke manual revelou que campos gerais do Smart Profile eram transferidos mecanicamente para slots especializados: contexto empresarial virava ambiente visual, formato textual virava composição e orientações comerciais viravam detalhes/restrições visuais. A correção mantém a precedência e o Smart Profile, mas aplica compatibilidade semântica determinística antes de preencher campos de imagem, vídeo e programação. A entrada explícita continua sendo a fonte principal do assunto/cena, enquanto dados incompatíveis são omitidos em vez de renomeados ou inventados. Targets gerais permanecem inalterados. A suíte backend passou a ter 257 testes, incluindo a reprodução exata do smoke e regressões em Basic, Pro, Expert e todos os Targets. É necessário repetir o smoke manual antes da aprovação definitiva.

O segundo smoke mostrou que somente filtrar fontes incompatíveis deixava o Midjourney reduzido a `SUBJECT`. O adaptador agora também decompõe deterministicamente a entrada explícita: identifica segmentos ambientais e detalhes visuais, duração e ação de vídeo e stacks técnicos conhecidos. Defaults seguros de composição e estilo agregam estrutura sem inventar fatos específicos. Para a pizza do smoke, o resultado inclui ambiente (mesa de madeira e pizzaria elegante), composição publicitária, fotografia gastronômica realista, mood elegante e detalhes explicitamente citados, sem recuperar os valores comerciais incompatíveis do Smart Profile. A suíte backend passou a ter 259 testes aprovados. A aprovação definitiva continua condicionada a um novo smoke manual real.

O smoke seguinte do Gerador de Vídeo identificou duplicação entre `SCENE` e `SUBJECT` e truncamento da sequência de ações na primeira vírgula. O extrator de vídeo agora separa assunto, cena resumida, sequência temporal, ambiente e duração diretamente da entrada. A correção é genérica: regressões com pizza, tênis e café preservam todas as ações e seus complementos, sem importar dados incompatíveis do Smart Profile. Midjourney e os demais Targets permanecem preservados. A suíte backend passou a ter 262 testes aprovados, e um novo smoke manual de vídeo ainda é obrigatório.

Os smokes manuais finais aprovaram ChatGPT, Midjourney, Gerador de Vídeo e Assistente de Programação em modo Basic sem IA. Confirmaram persistência e exibição do destino, filtragem de Smart Profile incompatível, estrutura visual útil, separação de cena/assunto, sequência completa de ações, duração, ambiente e extração de Python/FastAPI com CRUD preservado. A auditoria final aprovou arquitetura, oito Targets, Basic/Pro/Expert, precedência, Templates novos e legados, Projects, Smart Profile, Interviews, refinamento, versionamento e Score. Ruff e os 262 testes backend passaram; `dart format` verificou 106 arquivos sem alterações, `flutter analyze` não encontrou issues e os 159 testes Flutter passaram. Health e OpenAPI responderam 200, `git diff --check` passou e `0014_target_ai` permaneceu como único Alembic head.

## Etapa 9.11 — Multi-Target / Comparador de Prompts por IA

O fluxo Multi-Target permite selecionar de dois a quatro destinos únicos e gera previews determinísticos pelo mesmo `PromptBuilder` usado na geração normal. A preparação de Projeto, Smart Profile e fatos explícitos ocorre uma única vez; depois, cada destino recebe somente sua adaptação semântica da Etapa 9.10. A comparação não chama provedores externos, não consome créditos, não cria Usage/ledger e não persiste Prompts automaticamente.

No frontend, o modo de comparação desabilita a otimização por IA e apresenta cartões responsivos lado a lado no desktop e empilhados no mobile. Cada cartão identifica o Target AI, conteúdo, nota e classificação individuais, além de permitir copiar ou salvar apenas aquela versão. O salvamento reutiliza a geração normal, preservando modo, categoria, idioma, Projeto e demais campos de origem. Basic compara diretamente; Pro e Expert realizam uma única entrevista e preservam os destinos escolhidos até a tela comparativa.

O endpoint autenticado `POST /api/v1/prompts/compare-targets` valida o mínimo de dois, máximo de quatro, unicidade, valores do enum, ownership do Projeto e proíbe `optimize_with_ai=true`. A implementação é somente preview e não exige migration; `0014_target_ai` permanece o único head. O smoke manual permanece obrigatório após a validação técnica automatizada.

### Fechamento final

O smoke manual final foi aprovado com a entrada “TESTE FINAL 911 - criar campanha para aumentar as vendas da Pizzaria Donatello.” e os destinos ChatGPT, Claude e Gemini. Os três previews foram gerados corretamente e somente Gemini foi escolhida em “Salvar versão”. O histórico apresentou exatamente um novo registro, identificado como Marketing, BASIC e Gemini; ChatGPT e Claude permaneceram apenas como previews transitórios.

A evidência confirma o contrato de persistência da Etapa 9.11: comparar não cria Prompts, reabrir ou atualizar a página não cria registros adicionais e somente uma ação explícita de salvamento usa o fluxo persistente normal. A comparação determinística permanece sem OpenAI, créditos, Usage ou alterações de ledger. **Status: CONCLUÍDA E APROVADA. Smoke manual final: APROVADO.**

## Etapa 9.12 — Prompt Variables

Templates passam a aceitar placeholders textuais seguros na sintaxe `{identificador}`. O identificador começa por letra e contém somente letras ASCII, números ou underscore, com até 64 caracteres. O parser determinístico centralizado detecta no máximo 20 variáveis únicas, normaliza seus nomes internamente para lowercase e gera labels legíveis; não interpreta JSON, dicionários, objetos, CSS, expressões com espaços ou hífen, nem a sintaxe `{{variavel}}`.

Os contratos de Template expõem `has_variables` e a lista `variables` com `name`, `label` e `required=true`, sem migration ou metadata persistida. Criar e editar Templates mostra as variáveis encontradas, e a listagem apresenta sua quantidade. Ao usar um Template dinâmico, Criar Prompt exibe um formulário responsivo com os valores obrigatórios; Templates sem variáveis e registros legados preservam o fluxo anterior.

O frontend envia `template_id` e `variable_values`, mas a resolução autoritativa ocorre no backend: o serviço recarrega o Template pertencente ao usuário, retorna 404 uniforme para IDOR, redetecta, valida campos ausentes/desconhecidos e limites, substitui strings sem `eval` ou motor executável e somente então aplica Projeto, Smart Profile, adaptador do Target AI, `PromptBuilder` e Score. A precedência é valor da variável atual > Template > Projeto > Smart Profile > defaults. Valores não são registrados em logs.

Os mesmos valores resolvidos percorrem Basic, Pro, Expert e Interviews, preservando `template_id`, `project_id`, Targets e `variable_values`. Multi-Target preenche o formulário uma vez e reutiliza a mesma preparação para dois a quatro previews transitórios. Os oito Targets são suportados. Refinamento e versionamento operam sobre o Prompt já resolvido, sem reaplicar placeholders ou modificar o Template original; salvar um Prompt como Template continua literal e não cria variáveis automaticamente.

Detecção, labels, validação e substituição são locais e não chamam OpenAI. A resolução não cria Usage, não consome créditos e não altera wallet ou ledger; eventual otimização opcional mantém o billing existente. Não foram adicionados condicionais, loops, scripts, fórmulas, Jinja, lógica executável ou campos dependentes.

**Status: CONCLUÍDA E APROVADA. Smoke manual final: APROVADO.**

O primeiro smoke manual revelou que o formulário de variáveis não aparecia depois de criar o Template e navegar por “Usar”. O teste anterior construía `PromptCreatePage` diretamente e, por isso, não exercitava criação, listagem, `GoRouter`, query parameter e nova consulta do Template. A desserialização agora usa a metadata retornada pela API e recalcula deterministicamente as variáveis a partir dos campos do Template quando a metadata estiver ausente; a página mantém o `template_id` selecionado no próprio estado e recarrega o registro quando a rota muda. Um teste de regressão percorre o fluxo de produção completo, preenche Produto, Público e Canal, confirma `variable_values`, reentrada e preservação do Template original.

O smoke manual final aprovou o Template “Campanha dinâmica”: `{produto}`, `{publico}` e `{canal}` foram substituídos respectivamente por “Pizza artesanal”, “Famílias da região” e “Instagram”. O Prompt Basic final não apresentou placeholders restantes e indicou IA não utilizada. A auditoria final aprovou Ruff e os 302 testes backend, `dart format` em 108 arquivos sem alterações, Flutter Analyze sem issues e os 168 testes Flutter. Health e OpenAPI responderam 200, `0014_target_ai` permaneceu como único Alembic head e `git diff --check` passou. A resolução determinística não chamou OpenAI, não consumiu créditos, não criou Usage e não alterou o ledger.

## Etapa 9.13 — Prompt Chains

Prompt Chains organizam sequências privadas e reutilizáveis sem executar provedores externos. A migration `0015_prompt_chains`, sucessora direta de `0014_target_ai`, cria `prompt_chains` e `prompt_chain_steps`. Chains pertencem ao usuário, podem ter Project opcional e status active/archived. Steps têm posição única e determinística, título, base, modo, categoria, Target AI e Template opcional; Project e Template usam `ON DELETE SET NULL`, enquanto excluir uma Chain remove somente sua estrutura, nunca Prompts históricos.

O backend oferece CRUD de Chains e Steps, arquivamento/reativação, reordenação completa e limite de 20 etapas. Ownership de Chain, Project e Template é validado com 404 uniforme. Cada etapa é aberta manualmente em Criar Prompt e pode seguir Basic, Pro ou Expert, entrevistas, Multi-Target, refinamento, versionamento e Score já existentes. Não existe execução da cadeia inteira, agente, scheduler, DAG, branch ou background job.

O placeholder reservado `{resultado_anterior}` reutiliza o parser textual seguro da Etapa 9.12. Em uso Basic, a resposta externa é transitória e não é gravada na Chain ou no Step; é validada e substituída autoritativamente no backend. Em Pro/Expert, seu transporte acompanha os facts da entrevista existente pelo tempo de vida da sessão, necessário para concluir a entrevista, sem logs de conteúdo. Variáveis normais continuam obrigatórias e Templates dinâmicos permanecem intactos. A precedência continua valor atual > Template > Project > Smart Profile > defaults.

O frontend adiciona “Meus fluxos”, cards responsivos, criação, edição, arquivamento, reativação e exclusão, além do detalhe ordenado com adicionar, editar, mover, excluir e usar etapa. Etapas com a referência reservada exibem “Resultado da etapa anterior”; variáveis comuns usam o formulário dinâmico existente. Nenhum conteúdo é executado por `eval`, shell, SQL, JavaScript ou Python.

Criar, editar, ordenar, resolver variáveis e substituir o resultado anterior são operações determinísticas: não chamam OpenAI, não consomem créditos, não criam Usage e não alteram wallet ou ledger. O resultado anterior é separado semanticamente do objetivo atual e renderizado em `PREVIOUS STEP RESULT (CONTEXT ONLY)`, como texto citado e não executável; cabeçalhos existentes no conteúdo anterior não podem substituir o objetivo da Step atual. Steps sem instrução própria além de `{resultado_anterior}` são rejeitadas.

**SMOKE MANUAL REAL DA ETAPA 9.13: APROVADO**

O smoke final aprovou a Chain “Lançamento Pizzaria Donatello”, criação e numeração das Steps Posicionamento e campanha de lançamento, botão “+ Adicionar etapa”, reabertura, campo “Resultado da etapa anterior” e ação “Usar etapa”. Na Step 2, o objetivo de criar a campanha para Instagram foi preservado; o resultado da Step 1 apareceu somente como contexto e nenhum `{resultado_anterior}` permaneceu. A IA ficou desligada durante todo o fluxo.

A auditoria final aprovou Ruff, os 329 testes backend, os 3 testes de integração específicos de Chains, a matriz semântica de 24 combinações BASIC/PRO/EXPERT e Targets, `dart format` em 116 arquivos sem alterações, Flutter Analyze sem issues e os 172 testes Flutter. `0015_prompt_chains` é o único Alembic head; Health e OpenAPI responderam 200. **Status: CONCLUÍDA E APROVADA. Smoke manual final: APROVADO.**
