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
