# Funil Alinha Face

Site com login para acompanhar os pacientes da Alinha Face (DTM/ATM e cirurgia ortognática).
Páginas estáticas, sem build, que leem e gravam no Supabase.

## Páginas (`site/`)

- `index.html` — entrada com e-mail e senha. Manda cada pessoa para a página do seu perfil.
- `painel.html` — painel completo (Novos, Dr. Gustavo, Rotina do dia, Funil, Tabela, Relatórios).
  Só para perfil **admin** (Claudemir e Ana Clara).
- `medico.html` — área do cirurgião: agenda, pacientes dele e registro da consulta
  (compareceu, pediu exames, quais exames, resumo). Só para perfil **cirurgiao**.
- `auth.js` — login, perfil e troca de senha, usados por todas as páginas.
- `config.js` — endereço do projeto Supabase e chave pública (publishable).
- `base.css` — cores e componentes das páginas de login e do cirurgião.

## Banco (`supabase/schema.sql`)

Rode o arquivo inteiro no SQL Editor do Supabase. Ele cria:

- `perfis` — quem acessa e com que papel (`admin` ou `cirurgiao`).
- `funil_pacientes` — uma linha por paciente; a ficha inteira fica em `dados` (jsonb).
  `cirurgiao_email` é preenchido sozinho a partir de `dados.cirurgiao`.
- `funil_encaminhamentos` — encaminhamentos do painel.
- Regras de acesso (RLS): admin vê e edita tudo; cirurgião só **lê** os pacientes dele.
- `registrar_consulta(...)` — única forma de o cirurgião gravar algo: avança a etapa
  (nunca volta), guarda o resumo e escreve no histórico, sempre conferindo se o paciente é dele.

Os arquivos numerados (`002_…` a `013_…`) são acréscimos; rode cada um uma vez, na ordem.
`013_agendas_medicos.sql` cria as agendas do Dr. Afonso e do Dr. Victor dentro do funil
(grade semanal, folgas, horários livres e marcação com trava contra horário duplicado).

## Agendas

- **Dr. Gustavo** — Google Agenda (gu.martins00@gmail.com), ligado direto à Bia no GPT Maker.
- **Dr. Afonso e Dr. Victor** — agenda no próprio funil. A Bia consulta e marca pela função
  `supabase/functions/agenda` (Intenções do GPT Maker); a equipe vê e marca na aba **Agendas** do painel.
  Online de 15 em 15 min, presencial de 30 em 30. Configuração da Bia: `supabase/functions/agenda/BIA.md`.

Dados de paciente nunca vão para o Git; ficam só no Supabase.

## Acessos

Os logins são criados no painel do Supabase (Authentication → Users → Add user → Create new user,
com "Auto Confirm User"). Para dar acesso a alguém novo, crie o login lá e acrescente o e-mail
em `perfis` com o papel certo.

## Publicação

Cloudflare Pages, enviando a pasta `site/` (sem etapa de build).

Endereço publicado: https://funil-alinhaface.pages.dev (projeto `funil-alinhaface` no Cloudflare Pages, envio direto).
