# Bia (GPT Maker) — agendas do Dr. Afonso e do Dr. Victor

A Bia continua marcando o **Dr. Gustavo** pela agenda do Google, como já faz.
Para o **Dr. Afonso** e o **Dr. Victor**, ela usa duas Intenções (Webhook) que falam com a função `agenda` do Supabase.

## Regra de distribuição (a função aplica sozinha)

| Paciente | Online | Presencial |
|---|---|---|
| Bahia e todo o Nordeste (BA, SE, AL, PE, PB, RN, CE, PI, MA) | Dr. Victor | Dr. Victor, em Salvador |
| São Paulo | Dr. Gustavo (Google) | Dr. Afonso (Mooca ter/qui/sex, Vila Mariana qua) |
| Rio Grande do Sul | Dr. Gustavo (Google) | Ana Clara (como já é feito) |
| Demais estados (sem divulgação) | Dr. Gustavo (Google) | Bia oferece online, ou SP/Salvador |

A resposta da função traz o campo `instrucao` dizendo à Bia o que fazer.

## Antes de ligar

1. Rodar `supabase/013_agendas_medicos.sql` no SQL Editor.
2. Criar a função `agenda` (Edge Functions → Deploy new function → nome `agenda`, colar `index.ts`)
   com **Verify JWT desligado**.
3. Em Edge Functions → Secrets, criar `AGENDA_TOKEN` com uma senha longa (não guardar no Git).

Endereço: `https://odamgyzklsndepklmicl.supabase.co/functions/v1/agenda`
Cabeçalho em todas as chamadas: `x-agenda-token: <AGENDA_TOKEN>`

## Intenção 1 — Consultar horários

- **Descrição:** Consultar horários livres de consulta
- **Quando usar (detalhes):** Use sempre antes de oferecer horário de consulta, depois de saber em qual estado a pessoa mora e se ela prefere consulta online ou presencial. Siga o campo "instrucao" da resposta: se vier encaminhar = "gustavo", ofereça os horários da agenda do Dr. Gustavo como sempre; se vier "ana_clara", envie o link do WhatsApp da Ana Clara; se vier "perguntar", faça a pergunta indicada. Ofereça no máximo 3 horários por vez e confirme qual serve antes de marcar.
- **Tipo:** Webhook · **Método:** POST · **URL:** acima · **Cabeçalho:** `x-agenda-token`
- **Campos que a Bia captura:**
  - `estado` (texto, obrigatório): estado onde a pessoa mora, sigla ou nome
  - `modalidade` (texto, obrigatório): "online" ou "presencial"
  - `data_preferida` (data, opcional): a partir de que dia a pessoa quer
- **Corpo:** `{"acao":"horarios","estado":"…","modalidade":"…","data":"…"}`

## Intenção 2 — Agendar consulta

- **Descrição:** Marcar a consulta no horário escolhido
- **Quando usar (detalhes):** Use só depois que a pessoa confirmar um dos horários que vieram da intenção "Consultar horários livres de consulta". Nunca use para horários do Dr. Gustavo. Se a resposta disser que o horário foi ocupado, ofereça as sugestões que vierem. Depois de marcar, confirme dia, hora, modalidade e, se for presencial, o endereço que vier na resposta.
- **Tipo:** Webhook · **Método:** POST · **URL:** acima · **Cabeçalho:** `x-agenda-token`
- **Campos que a Bia captura:**
  - `estado` (texto, obrigatório), `modalidade` (texto, obrigatório)
  - `data` (data, obrigatório): dia escolhido
  - `hora` (texto, obrigatório): horário escolhido, ex. 14:30
  - `nome` (texto, obrigatório): nome da pessoa
  - `observacao` (texto, opcional): queixa principal em poucas palavras
- **Variáveis do sistema:** `telefone` ← telefone do contato · `chat_id` ← id da conversa
- **Corpo:** `{"acao":"agendar","estado":"…","modalidade":"…","data":"…","hora":"…","nome":"…","telefone":"…","chat_id":"…","observacao":"…"}`

## Como ficou configurado (26/10/2026)

- As duas Intenções usam **POST**, corpo gerado automaticamente a partir dos campos e a ação em **Params**
  (`acao=horarios` ou `acao=agendar`). Na de agendar, os Params também levam `telefone` = Telefone do Contato
  e `chat_id` = Identificador do Chat.
- Cabeçalho `x-agenda-token` com a mesma senha do segredo `AGENDA_TOKEN` (fica só no Supabase e no GPT Maker).
- Função `agenda` publicada com "Verify JWT" desligado.
- Comportamento da Bia, seção 5: a regra antiga "todo presencial vai para a Ana Clara" foi trocada por:
  consultar horários pela intenção; presencial em SP (Mooca, Vila Mariana) e Salvador marcado pela intenção;
  presencial em Porto Alegre continua com o link da Ana Clara; on-line com o Dr. Gustavo segue as regras de :15/:45.

## Mudança de caminho (26/10/2026, mais tarde)

As Intenções acima foram **inativadas** (não excluídas). A Bia não as chamava: preferia a ferramenta do Google Calendar.
Agora os três médicos são agendas do Google conectadas na integração Google Calendar do GPT Maker, com "Distribuição Inteligente":

- **Gustavo**: gu.martins00@gmail.com (on-line, :15/:45)
- **Dr. Afonso - presencial SP (Mooca/Vila Mariana)**: calendário da conta alinhaface@gmail.com, ter/qui/sex 9h–17h, qua 14h–18h
- **Dr. Victor - Bahia e Nordeste**: calendário da conta alinhaface@gmail.com, seg/ter 8h–20h, qui 14h–19h, sex 8h–12h e 14h–18h

Outros ajustes feitos na Bia:
- Treinamento "Endereço" (documento antigo, sem Salvador) removido; novo treinamento em texto com Moema, Vila Mariana, Mooca, Salvador e Porto Alegre, separado por região.
- Trabalho: descrição da empresa cita presencial em São Paulo, Salvador e Porto Alegre.
- Comportamento: presencial dá só a unidade do estado do paciente; link da Ana Clara só no presencial de Porto Alegre.
- Regras de transferência: transfere para a Ana Clara só quando pedir humano ou presencial em Porto Alegre (antes era qualquer presencial).

## Ajustes de 27/10/2026

- Moema (quartas) é do Dr. Gustavo e quem marca é a Ana Clara: a Bia trata Moema como Porto Alegre (envia o link da Ana Clara e transfere). Mooca e Vila Mariana continuam com o Dr. Afonso, agendados pela Bia.
- Regra de transferência: pedir humano ou presencial em POA ou Moema (não Mooca/Vila Mariana/Salvador).
- Comportamento: só oferece horários exatos (nunca faixas) e não repete a pergunta on-line/presencial se o paciente já disse.
- Calendários do Afonso e do Victor compartilhados (fazer alterações e ver detalhes) com a Ana Clara e com o médico de cada um; continuam na conta alinhaface@gmail.com.
- Manual da Bia corrigido (MANUALFAQBIA-27.10.2026.md) entregue para substituir o documento antigo no GPT Maker.
- Modelo da Bia trocado de GPT-4.1 Mini para GPT-6 Luna (mesmo custo, 1 crédito por mensagem).
- Manual antigo (documento) removido; o conteúdo corrigido entrou como 5 treinamentos em texto: Sobre a Alinha Face, ATM/DTM, Tratamento de DTM, Cirurgia ortognática, Plano de saúde/pagamento.

## Ajuste de 29/10/2026 — São Paulo
- On-line de SP passa a ser só do **Dr. Afonso** (mesmos dias e horários da agenda dele: ter/qui/sex 9h–17h, qua 14h–18h).
- Presencial SP: Mooca e Vila Mariana com o Dr. Afonso, marcado pela Bia; Moema (qua) continua com o Dr. Gustavo, via Ana Clara.
- Dr. Gustavo on-line fica para fora de SP e do Nordeste (ex.: Porto Alegre e demais estados).
- GPT Maker → Integrações → Google Calendar: agendas renomeadas para "Dr. Afonso - SP (on-line e presencial Mooca/Vila Mariana)" e "Dr. Gustavo - on-line (fora de SP e do Nordeste)".
- Comportamento, seção 5: "SP (on-line e presencial) = Dr. Afonso; on-line dos demais = Gustavo".

## Ajuste de 29/10/2026 (tarde) — horário do on-line
- On-line de todos os médicos: seg–sex 08:00–20:00 e sáb 08:00–14:00 (Config. Horários das três agendas no GPT Maker).
- Presencial continua restrito, escrito no nome da agenda (a Bia lê): Dr. Afonso Mooca ter/qui/sex 9h–17h, Vila Mariana qua 14h–18h; Dr. Victor Salvador seg/ter 8h–20h, qui 14h–19h, sex 8h–12h e 14h–18h.
- Testado: presencial Mooca na segunda 19h → Bia ofereceu ter/qui/sex 9h–17h; on-line sábado de manhã → 9h, 10h30, 11h30.

## Mudança de 29/10/2026 (fim da tarde) — Afonso e Victor 100% no funil
- Agendas Google do Dr. Afonso e do Dr. Victor **removidas** da integração Google Calendar da Bia (os calendários continuam existindo na conta alinhaface@gmail.com, só não são mais usados).
- Intenções "Consultar horários livres de consulta" e "Agendar consulta no horário escolhido" **reativadas**.
- Função `agenda`: SP (online e presencial) → Dr. Afonso; Bahia/Nordeste → Dr. Victor; demais online → Dr. Gustavo (Google). Oferece 2 horários por dia (manhã/tarde/noite) em até 3 dias.
- Grade (arquivo 015): online seg–sex 8h–20h, sáb 8h–14h; presencial Afonso Mooca ter/qui/sex 9h–17h e Vila Mariana qua 14h–18h; Victor Salvador qui 14h–19h, sex 8h–12h e 14h–18h.
- Comportamento seção 5: "SP e Bahia/Nordeste: use a intenção Consultar horários e, escolhido, Agendar consulta (nunca o Google). On-line dos demais: agenda do Gustavo."
- A consulta marcada pela intenção vai direto para a ficha (cirurgião, data, hora, modalidade) e dispara o aviso de WhatsApp ao médico.

## Mudança de 03/11/2026 — presencial vai para o cirurgião (secretária marca)
- A Bia **não marca mais consulta presencial** (nenhum médico). Ana Clara deixa de receber presencial.
- `acao=horarios` / `acao=agendar` com modalidade presencial devolvem `encaminhar: "presencial"` e a instrução de perguntar unidade e preferência.
- Nova `acao=presencial` (intenção "Agendar consulta on-line ou encaminhar presencial ao cirurgião", modalidade presencial sem data/hora; resumo vai em observacao):
  campos `estado`, `local` (unidade), `nome`, `preferencia` (dias/períodos), `resumo` (resumo curto da conversa, escrito pela Bia);
  Params `acao=presencial`, `telefone` = Telefone do Contato, `chat_id` = Identificador do Chat.
- Quem recebe: Nordeste → Dr. Victor; SP → Dr. Afonso (Moema → Dr. Gustavo); RS → Dr. Gustavo.
- A função lê a avaliação do site na conversa (GPT Maker), atualiza/cria a ficha (`supabase/018_presencial_para_cirurgiao.sql`:
  cirurgião, modalidade Presencial, unidade, resumoCaso, próxima ação "Secretária do Dr. X marca") e põe na fila o WhatsApp ao cirurgião
  (tipo `presencial`): paciente, wa.me, cidade, unidade, convênio, preferência, avaliação do site, resumo e link da ficha.
- Não repete o envio para o mesmo paciente e cirurgião em 12 horas.

## Ajuste de 04/11/2026 — opções abertas
- Comportamento: a Bia oferece SEMPRE por faixa do dia ("Amanhã temos agenda das 8h às 12h e das 13h às 20h. Qual o melhor horário para você?"). A regra antiga "nunca dê faixa / 4 opções em 3 dias" saiu.
- Dr. Gustavo: só horário quebrado (:15 ou :45); hora cheia pedida vira o quebrado mais próximo.
- Grade on-line Afonso/Victor (`019_almoco_online.sql`): seg–sex 8h–12h e 13h–20h; sáb 8h–14h.

## 04/11/2026 — agenda do Google do Dr. Gustavo casada com o funil
- Script `supabase/google-apps-script/agenda-gustavo.gs` (Apps Script na própria conta do Dr. Gustavo, gu.martins00@gmail.com — a alinhaface@gmail.com não enxerga essa agenda), a cada 5 min.
- Só eventos da Alinha Face: título = id da conversa da Bia (`3F6791F1…-55…`) ou título com "Alinha Face". O resto da agenda não é lido.
- Função `agenda`, `acao=google` (e `google_vincular`): liga evento ↔ ficha (`dados.googleEventId`, `dados.googleQuando`).
  Google → funil: evento novo/movido atualiza a ficha (cria ficha se não existir, só para datas futuras); evento apagado tira a data e põe próxima ação.
  Funil → Google: consulta do Gustavo sem evento é criada ("Alinha Face — Nome (on-line)"); mudou no funil, o evento é movido; desmarcada/perdido/outro cirurgião, o evento é apagado.
  Se os dois mudaram, vale o Google. `simular=true` só mostra o que faria.

## 05/11/2026 — Bia remarca e desmarca; fora do horário da Ana a conversa volta para a Bia
- Intenção "Agendar…": campo novo `cancelar` ("sim" = desmarcar). Função `cancelar_consulta` (021): tira data/hora, volta para lead, próxima ação "Paciente desmarcou… oferecer nova data"; o cirurgião recebe "desmarcada"; o Google do Gustavo perde o evento na sincronização.
- Remarcar = agendar de novo (a função já troca a data da ficha). Dr. Gustavo: a Bia remarca no Google e a sincronização liga o novo evento à ficha.
- `whats` acao=sincronizar (a cada 2 min): fora de ter–sex 14h–18h devolve para a Bia (stop-human) as conversas que estão com a equipe — menos as dos cirurgiões e dos contatos ignorados, e menos se alguém da equipe escreveu nos últimos 20 min.

## 05/11/2026 — rede de segurança do presencial
- Houve caso em que a Bia disse "a secretária do Dr. vai entrar em contato" sem acionar a intenção, e o resumo não foi ao cirurgião.
- `whats` acao=sincronizar: se a última mensagem da Bia (últimos 10 min) fala de secretária/contato e não há aviso `presencial` do paciente em 24 h, chama `agenda` acao=presencial_auto, que monta o caso pela conversa (estado = resposta à pergunta da cidade; unidade; preferência; avaliação do site) e envia ao cirurgião.
- Comportamento: a frase da secretária só depois de usar a intenção.

## Vigia do WhatsApp e da Bia (022 + função whats)
- A cada 2 minutos a sincronização confere:
  1. Se o canal do WhatsApp da Bia está conectado no GPT Maker. Se não for possível perguntar ao GPT Maker, usa um sinal: nenhuma mensagem de paciente há 3 horas entre 11h e 22h. Abre o alerta "canal" (faixa vermelha no topo do painel). Quando o canal volta, fecha o alerta e manda WhatsApp aos administradores com número no perfil e avisos ligados.
  2. Paciente sem resposta da Bia há 15 minutos a 6 horas, em conversa que está com a Bia: abre o alerta e a Bia tenta responder de novo (até 3 por rodada).
  3. Frases da Bia de 10 a 30 minutos atrás: "consulta marcada" sem consulta no funil, valor em reais, afirmação sobre cobertura do convênio. Abre alerta; o caso da consulta inexistente também vai por WhatsApp aos administradores.
- Os alertas ficam em funil_alertas e aparecem na Rotina do dia (bloco "Bia · conferir"), com os botões Ver conversa e Resolvido.
- Ação "situacao_canal" (só administradores) mostra o que o GPT Maker responde sobre o canal.

## Presencial: cobrar o cirurgião (022)
- encaminhar_presencial marca a ficha com presencialEncaminhado (data) e a próxima ação "Cobrar o Dr. X: a secretária já marcou a consulta presencial?" para dali a 2 dias.
- A Rotina do dia mostra o bloco vermelho "Presencial · cobrar o cirurgião" até a ficha ganhar data de consulta, com o botão "Cobrar o Dr. no WhatsApp" (abre o WhatsApp de quem está usando, com o texto pronto) e "Já tem data".
- Ao salvar a ficha com data de consulta, o caso sai da lista e o histórico registra que a secretária marcou.

## Horários do Dr. Afonso e do Dr. Victor (024)
- Eles atendem em qualquer minuto livre da grade (10:00, 10:15, 10:25, 10:30, 10:50...). A lista de horários livres segue de 15 em 15 min, mas ao marcar qualquer horário pedido serve se estiver dentro da grade e livre (agenda_livre_em).
- A resposta de "horarios" lembra a Bia que a regra de só :15/:45 é exclusiva do Dr. Gustavo, que segue pela agenda do Google.

## Rede de segurança quando a intenção do presencial falha
- Se a última mensagem da Bia (últimos 10 min) diz que não conseguiu encaminhar ("não consegui encaminhar", "falha no sistema"...) e fala de presencial/unidade, a sincronização chama presencial_auto.
- Deu certo: manda à paciente "Pronto, consegui passar seu caso para o Dr. X; a secretária vai entrar em contato". Não deu: abre alerta "Bia · conferir" para a equipe encaminhar.

## Resumo da teleconsulta sem a autorização do paciente
- Paciente autorizou: grava médico e paciente (como antes). Não autorizou: o aparelho do médico grava SÓ a voz do médico (o áudio do paciente nunca entra nessa gravação).
- Os trechos vão marcados "só a voz do médico" e o resumo é montado a partir do que o médico falou, sem inventar respostas do paciente.
- Se a autorização mudar no meio da chamada, a gravação recomeça no modo certo.

## Ambiente de demonstração (026, 027)
- "Dr. Demonstração" (demo@alinhaface.com.br) com 10 pacientes de exemplo (demo-01..10, telefone 5500...), recriados toda madrugada com datas do dia (demo_renovar, sem disparar avisos).
- Os avisos do Dr. Demonstração vão para o WhatsApp do parceiro que faz o papel de cirurgião nas apresentações (perfil). Pacientes de exemplo nunca recebem mensagem.
- Painel: botão "Demonstração" no topo liga/desliga (só naquele navegador) a exibição do médico e dos exemplos. Ficha cadastrada para o Dr. Demonstração vira exemplo sozinha.

## Relatório comercial (030)
- Página comercial.html: casos com potencial de cirurgia agrupados (exames pedidos sem retorno, exames prontos sem retorno, atendidos sem próximo passo, proposta enviada, convênio/autorização, cirurgias marcadas), com dias parados e botões que abrem o WhatsApp para cobrar a Ana ou sinalizar o cirurgião.
- Abre pelo botão "Comercial" do painel (admin logado) ou pelo link secreto com a chave de funil_config (para o gerente comercial, sem login).
- Terças e quintas às 8h o resumo vai para o WhatsApp do gerente comercial (funil_config.comercial_whatsapp), com o link da página.

## Equipe escreveu = Bia sai da conversa
- A cada 2 min, conversas com mensagem nova: se alguém da equipe (mensagem com nome de usuário no GPT Maker) escreveu nos últimos 10 min e a conversa ainda está com a Bia, passa para atendimento humano na hora.
- Volta para a Bia só com "Devolver para a Bia" no funil. A devolução automática fora do horário da Ana agora só vale para conversa em que ninguém da equipe escreveu nas últimas 24 h e o paciente está esperando.

## Ambiente comercial com login (032)
- Papel novo `comercial` em perfis (Joaquim). Ao entrar, vai direto para comercial.html.
- Vê só os casos da consulta agendada em diante (agendou, faltou, atendido, exames, retorno, proposta, documentos, autorização, autorizado, cirurgia marcada/realizada, pós-op), via função `comercial_casos()` — não lê a tabela direto.
- Cada caso mostra a situação, o que falta e como ele pode ajudar, com botões de WhatsApp (paciente, cirurgião, Ana) e recado para a equipe (`comercial_recado`, que também anota no histórico). Não altera a ficha.
- (033) "Falar com o cirurgião" e "Falar com a Ana" viraram mensagens dentro do painel (funil_recados), via `comercial_mensagem(paciente, 'cirurgiao'|'ana'|'equipe', texto)`. O cirurgião vê em "Avisos da equipe" e pode responder ao Joaquim (política recados_criar aceita destinatário comercial). Fica anotado no histórico.
- (034) WhatsApp para o comercial: na ficha (e no botão "WhatsApp" do topo) ele vê a conversa da Bia, envia, assume e devolve para a Bia — só nas conversas de pacientes da consulta agendada em diante. A função `whats` confere com `comercial_pode_chat`/`comercial_pode_tel` e só libera mensagens/enviar/assumir/devolver/iniciar. Lista: `comercial_whats()`.
- (035) Atuação urgente do comercial: a função `whats` (sincronizar, passo 4 do `vigiar`) abre alerta `urgente_comercial` quando o paciente manda foto/arquivo ou fala de convênio/cobertura, resultado de exame, valor ou quer operar (últimos 15 min; ignora a mensagem pronta do quiz). A Ana marca na mão pelo botão "⚡ Urgente p/ Joaquim" no WhatsApp do painel (`marcar_urgente_comercial`). Cada urgente novo manda WhatsApp ao Joaquim (gatilho `avisa_urgente_comercial`) e aparece em vermelho no topo do comercial.html (com apito/notificação) até ele clicar "Resolvido". Esses alertas não aparecem nos alertas do painel da Ana.
- Pedidos do Joaquim (recados vindos do perfil comercial) aparecem em destaque roxo no topo do painel (#comercialTopo, recados.js rcComercialTopo), com Abrir ficha / Responder / Feito.
- Exames pedidos (exames_sol): prazo de 10 dias para o paciente fazer; aparecem para o Joaquim em seção própria no topo e em 'Precisam de ajuda' já no dia seguinte ao pedido, com contagem regressiva (dataExames + 10).
- (036) 'Já atuei hoje': caso em que o Joaquim agiu hoje (WhatsApp pelo funil, mensagem pelo painel ou botão) sai da lista dele e volta no dia seguinte; comercial_casos() devolve atuou_hoje; botão comercial_atuei(id, voltar).
- (037) Módulo equipe do cirurgião: papel 'equipe' + perfis.equipe_de; usa o painel.html (sem WhatsApp da Bia, alertas, agendas, comercial, importar, demo, voucher) e o banco só entrega os pacientes do cirurgião dela (política pac_equipe). Primeiro: equipevictor@alinhaface.com.br → Dr. Victor.
- Recados do painel: separados em 'Mandaram para mim' / 'Eu mandei', agrupados por pessoa (cirurgiões primeiro) com filtro por pessoa, e selo de respondido / aguardando resposta / responder.
