-- Agendas do Dr. Afonso (SP) e do Dr. Victor (BA) dentro do funil.
-- O Dr. Gustavo continua no Google Agenda, do jeito que está.
--
-- Como funciona:
--   agenda_medicos   -> quem tem agenda no funil (chave curta, nome, e-mail de login, WhatsApp)
--   agenda_grade     -> dias da semana, horário, modalidades e local de cada médico
--   agenda_bloqueios -> folgas, feriados, congressos (o horário some da oferta)
--   agenda_slots(...)   -> horários livres (online de 15 em 15 min, presencial de 30 em 30)
--   agenda_agendar(...) -> marca a consulta na ficha do paciente, conferindo de novo se o horário está livre
-- A consulta marcada fica na própria ficha (dados.dataConsulta/horaConsulta/modalidade/local),
-- então aparece no painel, na agenda do médico no site e dispara o aviso por WhatsApp (arquivo 012).
-- Pode rodar de novo sem problema.

-- ============ médicos com agenda no funil ============
create table if not exists public.agenda_medicos (
  chave     text primary key,             -- 'afonso', 'victor'
  nome      text not null,
  email     text,                         -- login do médico no site (perfis.email)
  whatsapp  text,                         -- só números, com 55
  ativo     boolean not null default true
);

insert into public.agenda_medicos (chave, nome, email, whatsapp) values
  ('afonso', 'Dr. Afonso', 'dr.aptrindadefilho@gmail.com', '5511933883877'),
  ('victor', 'Dr. Victor', 'admvictorssa@gmail.com',       '5571981944808')
on conflict (chave) do update set nome = excluded.nome, whatsapp = excluded.whatsapp,
  email = coalesce(excluded.email, agenda_medicos.email);

-- ============ grade semanal ============
-- dia_semana: 0 domingo, 1 segunda ... 6 sábado
create table if not exists public.agenda_grade (
  id           bigserial primary key,
  medico       text not null references public.agenda_medicos(chave) on delete cascade,
  dia_semana   int  not null check (dia_semana between 0 and 6),
  inicio       time not null,
  fim          time not null check (fim > inicio),
  modalidades  text[] not null,           -- {'Online'}, {'Presencial'} ou os dois
  local        text,                      -- rótulo curto (o mesmo da lista "Local" da ficha)
  endereco     text                       -- endereço completo, para mandar ao paciente
);
create index if not exists agenda_grade_medico on public.agenda_grade (medico, dia_semana);

-- a grade é regravada inteira a cada vez que este arquivo roda
delete from public.agenda_grade where medico in ('afonso','victor');

insert into public.agenda_grade (medico, dia_semana, inicio, fim, modalidades, local, endereco) values
  -- Dr. Afonso: terça, quinta e sexta na Mooca, 9h às 17h; quarta na Vila Mariana, 14h às 18h
  ('afonso', 2, '09:00', '17:00', '{Online,Presencial}', 'SP · Mooca (Av. Paes de Barros, 3399)',
     'Av. Paes de Barros, 3399, conj. 25 – Mooca, São Paulo/SP'),
  ('afonso', 4, '09:00', '17:00', '{Online,Presencial}', 'SP · Mooca (Av. Paes de Barros, 3399)',
     'Av. Paes de Barros, 3399, conj. 25 – Mooca, São Paulo/SP'),
  ('afonso', 5, '09:00', '17:00', '{Online,Presencial}', 'SP · Mooca (Av. Paes de Barros, 3399)',
     'Av. Paes de Barros, 3399, conj. 25 – Mooca, São Paulo/SP'),
  ('afonso', 3, '14:00', '18:00', '{Online,Presencial}', 'SP · Vila Mariana (R. Francisco Cruz, 131)',
     'Rua Francisco Cruz, 131 – Vila Mariana, São Paulo/SP'),
  -- Dr. Victor: segunda e terça só online, 8h às 20h
  ('victor', 1, '08:00', '20:00', '{Online}', 'Online', null),
  ('victor', 2, '08:00', '20:00', '{Online}', 'Online', null),
  -- quinta 14h às 19h e sexta 8h às 12h + 14h às 18h, online e presencial em Salvador
  ('victor', 4, '14:00', '19:00', '{Online,Presencial}', 'Salvador · Caminho das Árvores (R. da Alfazema, 761)',
     'Rua da Alfazema, 761, Edf. Iguatemi Business & Flat, loja 18 (térreo) – Caminho das Árvores, Salvador/BA. Referência: em frente à agência do Banco do Brasil Estilo'),
  ('victor', 5, '08:00', '12:00', '{Online,Presencial}', 'Salvador · Caminho das Árvores (R. da Alfazema, 761)',
     'Rua da Alfazema, 761, Edf. Iguatemi Business & Flat, loja 18 (térreo) – Caminho das Árvores, Salvador/BA. Referência: em frente à agência do Banco do Brasil Estilo'),
  ('victor', 5, '14:00', '18:00', '{Online,Presencial}', 'Salvador · Caminho das Árvores (R. da Alfazema, 761)',
     'Rua da Alfazema, 761, Edf. Iguatemi Business & Flat, loja 18 (térreo) – Caminho das Árvores, Salvador/BA. Referência: em frente à agência do Banco do Brasil Estilo');

-- ============ folgas / feriados ============
-- horário local de São Paulo (Salvador tem o mesmo fuso)
create table if not exists public.agenda_bloqueios (
  id      bigserial primary key,
  medico  text not null references public.agenda_medicos(chave) on delete cascade,
  inicio  timestamp not null,
  fim     timestamp not null check (fim > inicio),
  motivo  text
);
create index if not exists agenda_bloq_medico on public.agenda_bloqueios (medico, inicio);

-- ============ quem vê ============
alter table public.agenda_medicos   enable row level security;
alter table public.agenda_grade     enable row level security;
alter table public.agenda_bloqueios enable row level security;
drop policy if exists agm_admin on public.agenda_medicos;
create policy agm_admin on public.agenda_medicos for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());
drop policy if exists agg_admin on public.agenda_grade;
create policy agg_admin on public.agenda_grade for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());
drop policy if exists agb_admin on public.agenda_bloqueios;
create policy agb_admin on public.agenda_bloqueios for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());
-- o médico vê a própria grade e as próprias folgas
drop policy if exists agg_medico on public.agenda_grade;
create policy agg_medico on public.agenda_grade for select to authenticated
  using (medico in (select chave from public.agenda_medicos where email = public.meu_email()));
drop policy if exists agb_medico on public.agenda_bloqueios;
create policy agb_medico on public.agenda_bloqueios for select to authenticated
  using (medico in (select chave from public.agenda_medicos where email = public.meu_email()));

-- ============ duração de cada consulta ============
create or replace function public.agenda_duracao(p_modalidade text) returns int
language sql immutable as $$
  select case when lower(coalesce(p_modalidade,'')) like 'presen%' then 30 else 15 end
$$;

-- ============ o horário [ini, fim) do médico está ocupado? ============
create or replace function public.agenda_ocupado(
  p_chave text, p_ini timestamp, p_fim timestamp, p_ignorar text default null
) returns boolean
language sql stable security definer set search_path = public as $$
  with m as (select email from agenda_medicos where chave = p_chave)
  select exists (
    select 1
    from funil_pacientes f, m
    where (f.dados->>'agendaMedico' = p_chave or (m.email is not null and f.cirurgiao_email = m.email))
      and f.id is distinct from p_ignorar
      and coalesce(f.dados->>'dataConsulta','') = to_char(p_ini::date, 'YYYY-MM-DD')
      and coalesce(f.dados->>'horaConsulta','') ~ '^\d{2}:\d{2}$'
      and coalesce(f.dados->>'etapa','') not in ('perdido','noshow')
      and ((f.dados->>'dataConsulta')::date + (f.dados->>'horaConsulta')::time) < p_fim
      and ((f.dados->>'dataConsulta')::date + (f.dados->>'horaConsulta')::time
           + make_interval(mins => agenda_duracao(f.dados->>'modalidade'))) > p_ini
  ) or exists (
    select 1 from agenda_bloqueios b
    where b.medico = p_chave and b.inicio < p_fim and b.fim > p_ini
  )
$$;

-- ============ horários livres ============
-- Não oferece horário com menos de 1 hora de antecedência.
-- Conversa depois das 18h30 (horário de SP) já começa a oferta no dia seguinte.
create or replace function public.agenda_slots(
  p_chave text, p_modalidade text, p_de date default null, p_ate date default null, p_ignorar text default null
) returns table (data date, hora text, local text, endereco text)
language sql stable security definer set search_path = public as $$
  with agora as (select (now() at time zone 'America/Sao_Paulo') as t),
  periodo as (
    select greatest(coalesce(p_de, a.t::date),
                    case when a.t::time > '18:30' then a.t::date + 1 else a.t::date end) as de,
           coalesce(p_ate, greatest(coalesce(p_de, a.t::date), a.t::date) + 14) as ate,
           agenda_duracao(p_modalidade) as dur,
           case when lower(coalesce(p_modalidade,'')) like 'presen%' then 'Presencial' else 'Online' end as mod
    from agora a
  )
  select ts::date, to_char(ts, 'HH24:MI'), g.local, g.endereco
  from periodo p
  cross join lateral generate_series(p.de::timestamp, p.ate::timestamp, interval '1 day') dd
  join agenda_grade g on g.medico = p_chave
                     and g.dia_semana = extract(dow from dd)::int
                     and p.mod = any(g.modalidades)
  join agenda_medicos m on m.chave = g.medico and m.ativo
  cross join lateral generate_series(dd + g.inicio, dd + g.fim - make_interval(mins => p.dur),
                                     make_interval(mins => p.dur)) ts
  cross join agora a
  where ts >= a.t + interval '60 minutes'
    and not agenda_ocupado(p_chave, ts, ts + make_interval(mins => p.dur), p_ignorar)
  order by ts
$$;

-- ============ marcar a consulta ============
-- Acha o paciente pelos 8 últimos dígitos do telefone (cria a ficha se não existir),
-- confere de novo se o horário está livre (com trava, para dois pacientes não pegarem o mesmo)
-- e grava a consulta. Remarcação: se o paciente já tinha consulta futura, ela é trocada.
create or replace function public.agenda_agendar(
  p_chave text, p_modalidade text, p_data date, p_hora text,
  p_nome text, p_telefone text, p_chat_id text default null, p_obs text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      agenda_medicos%rowtype;
  mod    text := case when lower(coalesce(p_modalidade,'')) like 'presen%' then 'Presencial' else 'Online' end;
  dig    text := regexp_replace(coalesce(p_telefone,''), '\D', '', 'g');
  t8     text;
  hh     text;
  slot   record;
  r      funil_pacientes%rowtype;
  achou  boolean := false;
  d      jsonb;
  hoje   text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  dias   text[] := array['domingo','segunda-feira','terça-feira','quarta-feira','quinta-feira','sexta-feira','sábado'];
  quando text;
  sug    jsonb;
begin
  select * into m from agenda_medicos where chave = p_chave and ativo;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'medico_desconhecido');
  end if;
  if length(dig) < 8 then
    return jsonb_build_object('ok', false, 'motivo', 'telefone_invalido');
  end if;
  t8 := right(dig, 8);

  -- "9", "9h", "9:00", "09h30", "9.30" -> "09:00" / "09:30"
  hh := regexp_replace(lower(coalesce(p_hora,'')), '[^0-9]+', ':', 'g');
  hh := trim(both ':' from hh);
  if hh !~ ':' then hh := hh || ':00'; end if;
  begin
    hh := to_char(hh::time, 'HH24:MI');
  exception when others then
    return jsonb_build_object('ok', false, 'motivo', 'hora_invalida');
  end;

  perform pg_advisory_xact_lock(hashtext('agenda:' || p_chave));

  select * into r from funil_pacientes
   where right(regexp_replace(coalesce(dados->>'telefone',''), '\D', '', 'g'), 8) = t8
   order by atualizado_em desc limit 1
   for update;
  achou := found;

  select * into slot from agenda_slots(p_chave, mod, p_data, p_data, case when achou then r.id end) s
   where s.hora = hh limit 1;
  if not found then
    select coalesce(jsonb_agg(jsonb_build_object('data', x.data, 'hora', x.hora) order by x.data, x.hora), '[]'::jsonb) into sug
      from (select * from agenda_slots(p_chave, mod, p_data, null, case when achou then r.id end) z
            order by z.data, z.hora limit 5) x;
    return jsonb_build_object('ok', false, 'motivo', 'horario_indisponivel', 'sugestoes', sug);
  end if;

  quando := dias[extract(dow from p_data)::int + 1] || ', ' || to_char(p_data, 'DD/MM') || ' às ' || hh;

  if achou then
    d := r.dados;
  else
    d := jsonb_build_object(
      'etapa', 'lead', 'tratamento', 'A definir', 'convenio', 'Não sabe', 'pagamento', 'A definir',
      'origem', 'Outro', 'fonte', 'Bia (WhatsApp)', 'opme', 0, 'valorProposta', 0,
      'historico', '[]'::jsonb, 'criadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    r.id := 'p' || substr(md5(random()::text || clock_timestamp()::text), 1, 12);
  end if;

  if nullif(trim(coalesce(p_nome,'')),'') is not null and coalesce(trim(d->>'nome'),'') = '' then
    d := d || jsonb_build_object('nome', trim(p_nome));
  end if;
  if coalesce(d->>'telefone','') = '' then d := d || jsonb_build_object('telefone', dig); end if;
  if p_chat_id is not null then d := d || jsonb_build_object('chatId', p_chat_id); end if;

  d := d || jsonb_build_object(
    'agendaMedico', p_chave,
    'cirurgiao', coalesce(m.email, ''),
    'dataConsulta', to_char(p_data, 'YYYY-MM-DD'),
    'horaConsulta', hh,
    'modalidade', mod,
    'local', case when mod = 'Presencial' then coalesce(slot.local, '') else 'Online' end,
    'agendadoPor', 'Bia',
    'atualizadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
  if coalesce(d->>'etapa','lead') in ('triagem','lead','agendou','noshow','perdido') then
    d := jsonb_set(d, '{etapa}', '"agendou"');
  end if;
  -- histórico: acrescenta a linha e guarda só as 40 mais recentes, em ordem cronológica
  d := jsonb_set(d, '{historico}', (
    select coalesce(jsonb_agg(z.h order by z.n), '[]'::jsonb)
    from (
      select e.h, e.n
      from jsonb_array_elements(
             (case when jsonb_typeof(d->'historico') = 'array' then d->'historico' else '[]'::jsonb end)
             || jsonb_build_array(jsonb_build_object('data', hoje,
                  'texto', 'Bia agendou consulta ' || lower(mod) || ' com ' || m.nome || ': ' || quando
                           || case when nullif(trim(coalesce(p_obs,'')),'') is not null then ' — ' || trim(p_obs) else '' end))
           ) with ordinality as e(h, n)
      order by e.n desc limit 40
    ) z));

  insert into funil_pacientes (id, dados) values (r.id, d)
  on conflict (id) do update set dados = excluded.dados;

  return jsonb_build_object(
    'ok', true,
    'paciente_id', r.id,
    'medico', m.nome,
    'modalidade', mod,
    'data', to_char(p_data, 'YYYY-MM-DD'),
    'hora', hh,
    'quando', quando,
    'local', case when mod = 'Presencial' then slot.local else 'Online' end,
    'endereco', case when mod = 'Presencial' then slot.endereco else null end);
end $$;

-- só a função "agenda" (chave de serviço) chama estas funções
revoke all on function public.agenda_ocupado(text, timestamp, timestamp, text) from public, anon, authenticated;
revoke all on function public.agenda_slots(text, text, date, date, text) from public, anon, authenticated;
revoke all on function public.agenda_agendar(text, text, date, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.agenda_ocupado(text, timestamp, timestamp, text) to service_role;
grant execute on function public.agenda_slots(text, text, date, date, text) to service_role;
grant execute on function public.agenda_agendar(text, text, date, text, text, text, text, text) to service_role;

-- ============ aviso por WhatsApp aos médicos ============
-- o aviso do arquivo 012 passa a mostrar o local quando a consulta é presencial
create or replace function public.consulta_texto(d jsonb) returns text
language sql immutable as $$
  select
    (array['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[extract(dow from (d->>'dataConsulta')::date)::int + 1]
    || ', ' || to_char((d->>'dataConsulta')::date, 'DD/MM')
    || coalesce(' às ' || nullif(d->>'horaConsulta',''), '')
    || coalesce(' · ' || nullif(d->>'modalidade',''), '')
    || case when d->>'modalidade' = 'Presencial' and nullif(d->>'local','') is not null
            then ' · ' || (d->>'local') else '' end
$$;

update public.perfis set whatsapp = '5511933883877', avisos_whats = true
 where email = 'dr.aptrindadefilho@gmail.com';

-- Dr. Victor: perfil de cirurgião com aviso por WhatsApp.
-- O login dele ainda precisa ser criado em Authentication → Users (admvictorssa@gmail.com).
insert into public.perfis (email, nome, papel, whatsapp, avisos_whats)
values ('admvictorssa@gmail.com', 'Dr. Victor', 'cirurgiao', '5571981944808', true)
on conflict (email) do update set nome = excluded.nome, papel = excluded.papel,
  whatsapp = excluded.whatsapp, avisos_whats = true;
-- consultas que já tenham sido marcadas para ele sem e-mail passam a ser dele
update public.funil_pacientes set dados = dados || jsonb_build_object('cirurgiao','admvictorssa@gmail.com')
 where dados->>'agendaMedico' = 'victor' and coalesce(dados->>'cirurgiao','') = '';
