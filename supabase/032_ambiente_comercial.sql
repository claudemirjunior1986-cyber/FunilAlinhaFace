-- Ambiente do gerente comercial (Joaquim) — página comercial.html com login.
--  * Novo papel "comercial" em perfis.
--  * Ele só enxerga os casos da consulta agendada em diante (agendou, faltou, atendido, exames,
--    retorno, proposta, convênio, autorização, cirurgia marcada/realizada e pós-operatório).
--    Leads, conversas a classificar, perdidos e fichas de demonstração ficam de fora.
--  * Ele não lê a tabela de pacientes direto: tudo passa pela função comercial_casos(), que já filtra.
--  * Ele não altera a ficha. Pode deixar recado para a equipe (Claudemir e Ana Clara) sobre um caso;
--    o recado também fica anotado no histórico da ficha.
-- Pode rodar de novo sem problema.

-- 1) papel "comercial"
alter table public.perfis drop constraint if exists perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check check (papel in ('admin','cirurgiao','comercial'));

insert into public.perfis (email, nome, papel, whatsapp)
values ('joaquim@alinhaface.com.br', 'Joaquim', 'comercial', '5511981680761')
on conflict (email) do update set nome = excluded.nome, papel = 'comercial', whatsapp = excluded.whatsapp;

create or replace function public.eh_comercial() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfis where email = public.meu_email() and papel = 'comercial')
$$;

-- etapas que o comercial enxerga (da consulta agendada em diante)
create or replace function public.etapas_comercial() returns text[]
language sql immutable as $$
  select array['agendou','noshow','compareceu','exames_sol','exames_ok','retorno','proposta',
               'docs_conv','autorizacao','autorizado','cir_marcada','cir_feita','posop']
$$;

-- 2) casos do comercial (admin também pode abrir, para conferir o que o Joaquim vê)
create or replace function public.comercial_casos()
returns table (id text, dados jsonb, cirurgiao_nome text, cirurgiao_whats text, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.eh_comercial() or public.eh_admin()) then raise exception 'sem acesso'; end if;
  return query
    select f.id, f.dados, coalesce(p.nome, ''), coalesce(p.whatsapp, ''), f.atualizado_em
      from funil_pacientes f
      left join perfis p on p.email = f.cirurgiao_email
     where coalesce(f.dados->>'etapa','') = any(public.etapas_comercial())
       and coalesce(f.dados->>'demo','') <> 'true'
     order by f.atualizado_em desc;
end $$;
revoke all on function public.comercial_casos() from public, anon;
grant execute on function public.comercial_casos() to authenticated;

-- WhatsApp da Ana Clara (para o botão "Falar com a Ana")
create or replace function public.comercial_contatos()
returns table (nome text, whatsapp text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.eh_comercial() or public.eh_admin()) then raise exception 'sem acesso'; end if;
  return query select p.nome, coalesce(p.whatsapp,'') from perfis p where p.papel = 'admin' and p.recebe_avisos order by p.nome;
end $$;
revoke all on function public.comercial_contatos() from public, anon;
grant execute on function public.comercial_contatos() to authenticated;

-- 3) recado do comercial para a equipe sobre um caso (fica também no histórico da ficha)
create or replace function public.comercial_recado(p_paciente_id text, p_texto text) returns int
language plpgsql security definer set search_path = public as $$
declare
  eu    text := public.meu_email();
  nomeq text;
  pnome text;
  a     record;
  n     int := 0;
  hoje  text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD');
begin
  if not public.eh_comercial() then raise exception 'sem acesso'; end if;
  select nome into nomeq from perfis where email = eu;
  if coalesce(trim(p_texto),'') = '' then raise exception 'recado vazio'; end if;
  select dados->>'nome' into pnome from funil_pacientes
   where id = p_paciente_id and coalesce(dados->>'etapa','') = any(public.etapas_comercial());
  if not found then raise exception 'paciente não encontrado'; end if;

  for a in select email, nome from perfis where papel = 'admin' and recebe_avisos and email <> eu loop
    insert into funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
    values (eu, nomeq, a.email, a.nome, p_paciente_id, pnome, left(p_texto, 4000));
    n := n + 1;
  end loop;

  update funil_pacientes
     set dados = jsonb_set(dados, '{historico}',
           (case when jsonb_typeof(dados->'historico') = 'array' then dados->'historico' else '[]'::jsonb end)
           || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', 'Comercial (' || nomeq || '): ' || left(p_texto, 500))))
   where id = p_paciente_id;
  return n;
end $$;
revoke all on function public.comercial_recado(text,text) from public, anon;
grant execute on function public.comercial_recado(text,text) to authenticated;
