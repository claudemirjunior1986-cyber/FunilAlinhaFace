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
