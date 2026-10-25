-- Aviso por WhatsApp ao cirurgião quando uma consulta dele é marcada, remarcada ou cancelada.
-- O banco monta a mensagem e põe na fila (funil_avisos_medico); a cada minuto o agendador
-- chama a função "whats" (acao processar_avisos), que envia pelo número da Alinha Face.
-- Pode rodar de novo sem problema.

alter table public.perfis add column if not exists whatsapp text;          -- só números, com 55
alter table public.perfis add column if not exists avisos_whats boolean not null default false;

create table if not exists public.funil_avisos_medico (
  id          bigserial primary key,
  criado_em   timestamptz not null default now(),
  email       text not null,
  telefone    text not null,
  paciente_id text,
  tipo        text,               -- nova | remarcada | cancelada
  texto       text not null,
  enviado_em  timestamptz,
  situacao    text not null default 'fila',   -- fila | enviado | substituido | erro
  erro        text,
  tentativas  int not null default 0
);
create index if not exists funil_avisos_fila on public.funil_avisos_medico (situacao, criado_em);
alter table public.funil_avisos_medico enable row level security;
drop policy if exists avisos_med_ler on public.funil_avisos_medico;
create policy avisos_med_ler on public.funil_avisos_medico for select to authenticated using (public.eh_admin());
-- ninguém grava pelo site: só o gatilho (security definer) e a função (chave de serviço)

create or replace function public.consulta_texto(d jsonb) returns text
language sql immutable as $$
  select
    (array['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[extract(dow from (d->>'dataConsulta')::date)::int + 1]
    || ', ' || to_char((d->>'dataConsulta')::date, 'DD/MM')
    || coalesce(' às ' || nullif(d->>'horaConsulta',''), '')
    || coalesce(' · ' || nullif(d->>'modalidade',''), '')
$$;

create or replace function public.avisa_consulta_cirurgiao() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  n      jsonb := new.dados;
  o      jsonb := case when tg_op = 'UPDATE' then old.dados else '{}'::jsonb end;
  n_cir  text := new.cirurgiao_email;
  o_cir  text := case when tg_op = 'UPDATE' then old.cirurgiao_email else null end;
  n_ok   boolean; o_ok boolean;
  nome   text := coalesce(nullif(trim(n->>'nome'),''), 'Paciente');
  pr     record;
  link   text := 'https://funil-alinhaface.pages.dev/medico.html?abrir=' || new.id;
begin
  -- consulta "valendo": tem cirurgião, data de hoje em diante e não está perdida/faltou
  n_ok := n_cir is not null and coalesce(n->>'dataConsulta','') ~ '^\d{4}-\d{2}-\d{2}$'
          and (n->>'dataConsulta')::date >= hoje and coalesce(n->>'etapa','') not in ('perdido','noshow');
  o_ok := o_cir is not null and coalesce(o->>'dataConsulta','') ~ '^\d{4}-\d{2}-\d{2}$'
          and (o->>'dataConsulta')::date >= hoje and coalesce(o->>'etapa','') not in ('perdido','noshow');

  -- cancelada para o cirurgião antigo (trocou de cirurgião, tirou a data ou marcou perdido/faltou)
  if o_ok and (not n_ok or n_cir is distinct from o_cir) then
    select * into pr from perfis where email = o_cir and avisos_whats and whatsapp is not null;
    if found then
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
      values (o_cir, pr.whatsapp, new.id, 'cancelada',
        '❌ *Consulta desmarcada — Alinha Face*' || chr(10) || 'Paciente: ' || coalesce(nullif(trim(o->>'nome'),''), nome) || chr(10) ||
        consulta_texto(o) || chr(10) || chr(10) || 'Esse horário ficou livre.');
    end if;
  end if;

  -- nova ou remarcada para o cirurgião atual
  if n_ok and (not o_ok or n_cir is distinct from o_cir
               or (n->>'dataConsulta') is distinct from (o->>'dataConsulta')
               or coalesce(n->>'horaConsulta','') is distinct from coalesce(o->>'horaConsulta','')
               or coalesce(n->>'modalidade','') is distinct from coalesce(o->>'modalidade','')) then
    select * into pr from perfis where email = n_cir and avisos_whats and whatsapp is not null;
    if found then
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
      values (n_cir, pr.whatsapp, new.id,
        case when o_ok and n_cir = o_cir then 'remarcada' else 'nova' end,
        case when o_ok and n_cir = o_cir then '🔁 *Consulta remarcada — Alinha Face*' else '📅 *Nova consulta — Alinha Face*' end || chr(10) ||
        'Paciente: ' || nome || chr(10) || consulta_texto(n) ||
        case when o_ok and n_cir = o_cir then chr(10) || '(antes: ' || consulta_texto(o) || ')' else '' end ||
        chr(10) || chr(10) || 'Ficha: ' || link);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists avisa_consulta_cirurgiao on public.funil_pacientes;
create trigger avisa_consulta_cirurgiao after insert or update of dados, cirurgiao_email on public.funil_pacientes
  for each row execute function public.avisa_consulta_cirurgiao();

-- agendador: a cada minuto pede para a função enviar o que estiver na fila
create extension if not exists pg_net;
create extension if not exists pg_cron;
do $$ begin
  if exists (select 1 from cron.job where jobname = 'avisos-cirurgiao') then perform cron.unschedule('avisos-cirurgiao'); end if;
end $$;
select cron.schedule('avisos-cirurgiao', '* * * * *', $$
  select net.http_post(
    url := 'https://odamgyzklsndepklmicl.supabase.co/functions/v1/whats',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"acao":"processar_avisos"}'::jsonb)
  where exists (select 1 from public.funil_avisos_medico where situacao = 'fila')
$$);

-- teste: primeiro o aviso do Dr. Gustavo vai para o WhatsApp do Claudemir
update public.perfis set whatsapp = '5511988157588', avisos_whats = true where email = 'gu.martins00@gmail.com';
