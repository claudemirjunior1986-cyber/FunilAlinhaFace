-- 1) Alertas do sistema (canal do WhatsApp caiu, Bia sem responder, frases suspeitas da Bia).
--    A função "whats" abre e fecha os alertas; o painel mostra os abertos. Pode rodar de novo sem problema.
create table if not exists public.funil_alertas (
  id            bigserial primary key,
  criado_em     timestamptz not null default now(),
  tipo          text not null,          -- canal | bia_sem_resposta | bia_frase
  chave         text not null,          -- identifica o alerta (não abre o mesmo duas vezes)
  titulo        text not null,
  detalhe       text,
  chat_id       text,
  paciente_id   text,
  resolvido_em  timestamptz,
  resolvido_por text
);
create unique index if not exists funil_alertas_chave on public.funil_alertas (chave);
create index if not exists funil_alertas_abertos on public.funil_alertas (criado_em desc) where resolvido_em is null;
alter table public.funil_alertas enable row level security;
drop policy if exists alertas_admin_ler on public.funil_alertas;
create policy alertas_admin_ler on public.funil_alertas for select using (public.eh_admin());
drop policy if exists alertas_admin_resolver on public.funil_alertas;
create policy alertas_admin_resolver on public.funil_alertas for update using (public.eh_admin()) with check (public.eh_admin());

-- abre um alerta; devolve true se é novo (para avisar só uma vez)
create or replace function public.abrir_alerta(p_tipo text, p_chave text, p_titulo text, p_detalhe text default null,
                                               p_chat text default null, p_paciente text default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into funil_alertas (tipo, chave, titulo, detalhe, chat_id, paciente_id)
  values (p_tipo, p_chave, p_titulo, p_detalhe, p_chat, p_paciente)
  on conflict (chave) do nothing;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- fecha um alerta aberto; devolve quando ele tinha sido aberto (null se não havia)
create or replace function public.fechar_alerta(p_chave text, p_por text default 'sistema') returns timestamptz
language plpgsql security definer set search_path = public as $$
declare t timestamptz;
begin
  update funil_alertas set resolvido_em = now(), resolvido_por = p_por,
         chave = p_chave || '#' || id            -- libera a chave para um próximo alerta igual
   where chave = p_chave and resolvido_em is null
   returning criado_em into t;
  return t;
end $$;
revoke all on function public.abrir_alerta(text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.fechar_alerta(text, text) from public, anon, authenticated;
grant execute on function public.abrir_alerta(text, text, text, text, text, text) to service_role;
grant execute on function public.fechar_alerta(text, text) to service_role;

-- quem resolve pelo painel também libera a chave
create or replace function public.alerta_resolvido() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.resolvido_em is not null and old.resolvido_em is null and position('#' in new.chave) = 0 then
    new.chave := new.chave || '#' || new.id;
    new.resolvido_por := coalesce(new.resolvido_por, public.meu_email());
  end if;
  return new;
end $$;
drop trigger if exists alerta_resolvido on public.funil_alertas;
create trigger alerta_resolvido before update on public.funil_alertas for each row execute function public.alerta_resolvido();

-- 2) Presencial: lembrete forte para a Ana cobrar o cirurgião.
--    encaminhar_presencial passa a marcar a ficha com presencialEncaminhado (data) e a próxima ação
--    "Cobrar o Dr.: a secretária já marcou?" para daqui a 2 dias. O painel mostra esses casos na Rotina do dia
--    até alguém colocar a data da consulta presencial.
create or replace function public.encaminhar_presencial(
  p_email text, p_medico text, p_nome text, p_telefone text, p_chat_id text,
  p_local text, p_preferencia text, p_resumo text, p_quiz text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  dig   text := regexp_replace(coalesce(p_telefone,''), '\D', '', 'g');
  t8    text;
  r     funil_pacientes%rowtype;
  achou boolean;
  d     jsonb;
  pr    record;
  hoje  text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  cobrar text := to_char((now() at time zone 'America/Sao_Paulo')::date + 2, 'YYYY-MM-DD');
  nome  text;
  conv  text;
  texto text;
begin
  if length(dig) < 8 then return jsonb_build_object('ok', false, 'motivo', 'telefone_invalido'); end if;
  if length(dig) in (10, 11) then dig := '55' || dig; end if;
  t8 := right(dig, 8);

  select * into pr from perfis where email = p_email and whatsapp is not null;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'cirurgiao_sem_whatsapp'); end if;

  select * into r from funil_pacientes
   where right(regexp_replace(coalesce(dados->>'telefone',''), '\D', '', 'g'), 8) = t8
   order by atualizado_em desc limit 1 for update;
  achou := found;

  if achou and exists (select 1 from funil_avisos_medico where paciente_id = r.id and email = p_email
                        and tipo = 'presencial' and criado_em > now() - interval '12 hours') then
    return jsonb_build_object('ok', true, 'ja_enviado', true, 'paciente_id', r.id);
  end if;

  if achou then d := r.dados;
  else
    d := jsonb_build_object(
      'etapa', 'lead', 'tratamento', 'A definir', 'convenio', 'Não sabe', 'pagamento', 'A definir',
      'origem', 'Outro', 'fonte', 'Bia (WhatsApp)', 'opme', 0, 'valorProposta', 0,
      'historico', '[]'::jsonb, 'criadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    r.id := 'p' || substr(md5(random()::text || clock_timestamp()::text), 1, 12);
  end if;

  if nullif(trim(coalesce(p_nome,'')),'') is not null and coalesce(trim(d->>'nome'),'') in ('', '.') then
    d := d || jsonb_build_object('nome', trim(p_nome));
  end if;
  if coalesce(d->>'telefone','') = '' then d := d || jsonb_build_object('telefone', dig); end if;
  if p_chat_id is not null and p_chat_id <> '' then d := d || jsonb_build_object('chatId', p_chat_id); end if;
  if nullif(trim(coalesce(p_resumo,'')),'') is not null then
    d := d || jsonb_build_object('resumoCaso', left(trim(p_resumo), 600));
  end if;

  d := d || jsonb_build_object(
    'cirurgiao', p_email,
    'modalidade', 'Presencial',
    'local', coalesce(nullif(trim(coalesce(p_local,'')),''), d->>'local', ''),
    'presencialEncaminhado', hoje,
    'presencialPreferencia', coalesce(nullif(trim(coalesce(p_preferencia,'')),''), ''),
    'proximaAcao', 'Cobrar o ' || p_medico || ': a secretária já marcou a consulta presencial?',
    'dataProximaAcao', cobrar,
    'atualizadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
  d := jsonb_set(d, '{historico}', (
    select coalesce(jsonb_agg(z.h order by z.n), '[]'::jsonb)
    from (
      select e.h, e.n
      from jsonb_array_elements(
             (case when jsonb_typeof(d->'historico') = 'array' then d->'historico' else '[]'::jsonb end)
             || jsonb_build_array(jsonb_build_object('data', hoje,
                  'texto', 'Bia encaminhou consulta presencial ao ' || p_medico || ' (secretária marca)'
                           || coalesce(' — prefere: ' || nullif(trim(coalesce(p_preferencia,'')),''), ''))))
           with ordinality as e(h, n)
      order by e.n desc limit 40
    ) z));

  insert into funil_pacientes (id, dados) values (r.id, d)
  on conflict (id) do update set dados = excluded.dados;

  nome := coalesce(nullif(trim(d->>'nome'),''), nullif(trim(coalesce(p_nome,'')),''), 'Paciente');
  conv := case when d->>'convenio' = 'Sim' then coalesce(nullif(d->>'nomeConvenio',''), 'sim')
               when d->>'convenio' = 'Não' then 'não (particular)' else null end;

  texto := '🏥 *Consulta presencial — Alinha Face*' || chr(10)
    || 'Paciente pediu consulta presencial. Por favor, encaminhe para sua secretária marcar.' || chr(10) || chr(10)
    || '*Paciente:* ' || nome || chr(10)
    || '*WhatsApp:* https://wa.me/' || dig || chr(10)
    || coalesce('*Cidade:* ' || nullif(d->>'cidade','') || chr(10), '')
    || coalesce('*Unidade:* ' || nullif(trim(coalesce(p_local,'')),'') || chr(10), '')
    || coalesce('*Convênio:* ' || conv || chr(10), '')
    || coalesce('*Prefere:* ' || nullif(trim(coalesce(p_preferencia,'')),'') || chr(10), '')
    || coalesce(chr(10) || '*Avaliação do site:*' || chr(10) || nullif(trim(coalesce(p_quiz,'')),'') || chr(10), '')
    || coalesce(chr(10) || '*Resumo da conversa:*' || chr(10) || nullif(trim(coalesce(p_resumo,'')),'') || chr(10), '')
    || chr(10) || 'Ficha: https://funil-alinhaface.pages.dev/medico.html?abrir=' || r.id;

  insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
  values (p_email, pr.whatsapp, r.id, 'presencial', texto);

  return jsonb_build_object('ok', true, 'paciente_id', r.id, 'medico', p_medico);
end $$;
revoke all on function public.encaminhar_presencial(text, text, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.encaminhar_presencial(text, text, text, text, text, text, text, text, text) to service_role;

-- casos presenciais já encaminhados e ainda sem data: entram na lista de cobrança
update public.funil_pacientes p
   set dados = p.dados || jsonb_build_object(
         'presencialEncaminhado', coalesce(
            (select max(h->>'data') from jsonb_array_elements(case when jsonb_typeof(p.dados->'historico')='array' then p.dados->'historico' else '[]'::jsonb end) h
              where h->>'texto' like 'Bia encaminhou consulta presencial%'),
            to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD')),
         'proximaAcao', 'Cobrar o ' || coalesce((select nome from public.perfis where email = p.cirurgiao_email), 'cirurgião') || ': a secretária já marcou a consulta presencial?')
 where coalesce(p.dados->>'proximaAcao','') like 'Secretária do %'
   and coalesce(p.dados->>'dataConsulta','') = ''
   and coalesce(p.dados->>'etapa','') not in ('perdido','noshow')
   and coalesce(p.dados->>'presencialEncaminhado','') = '';
