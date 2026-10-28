-- O cirurgião responde, na área dele, os casos em que a equipe está esperando retorno.
-- A resposta: (1) vira a próxima ação da equipe para hoje ("Retorno do Dr. X: ..."),
-- (2) entra no histórico da ficha e (3) chega como recado para quem recebe avisos.
-- Pode rodar de novo sem problema.

create or replace function public.responder_equipe(p_id text, p_texto text) returns void
language plpgsql security definer set search_path = public as $$
declare
  eu    text := public.meu_email();
  nomeq text;
  r     public.funil_pacientes%rowtype;
  d     jsonb;
  hoje  text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  hojeb text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'DD/MM');
  txt   text := left(trim(coalesce(p_texto,'')), 2000);
  antes text;
  h     jsonb;
  a     record;
begin
  select nome into nomeq from perfis where email = eu;
  if nomeq is null then raise exception 'sem acesso'; end if;
  if txt = '' then raise exception 'resposta vazia'; end if;
  select * into r from funil_pacientes where id = p_id and (cirurgiao_email = eu or public.eh_admin());
  if not found then raise exception 'paciente não encontrado'; end if;

  d := r.dados;
  antes := coalesce(nullif(trim(d->>'proximaAcao'),''), 'Retorno pedido pela equipe');
  d := d || jsonb_build_object(
    'ultimaAcao',      antes || ' (respondido por ' || nomeq || ' em ' || hojeb || ')',
    'proximaAcao',     'Retorno do ' || nomeq || ': ' || left(regexp_replace(txt, '\s+', ' ', 'g'), 90) || case when length(txt) > 90 then '…' else '' end,
    'dataProximaAcao', hoje,
    'retornoMedico',   txt,
    'retornoMedicoEm', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI'),
    'retornoMedicoPor', eu);
  h := coalesce(d->'historico','[]'::jsonb) || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', nomeq || ' respondeu: ' || txt));
  if jsonb_array_length(h) > 40 then
    h := (select jsonb_agg(x order by i) from jsonb_array_elements(h) with ordinality t(x, i) where i > jsonb_array_length(h) - 40);
  end if;
  d := jsonb_set(d, '{historico}', h);
  update funil_pacientes set dados = d, atualizado_em = now() where id = p_id;

  for a in select email, nome from perfis where papel = 'admin' and recebe_avisos and email <> eu loop
    insert into funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
    values (eu, nomeq, a.email, a.nome, p_id, d->>'nome', '↩️ Retorno sobre o paciente: ' || txt);
  end loop;
end $$;
revoke all on function public.responder_equipe(text,text) from public, anon;
grant execute on function public.responder_equipe(text,text) to authenticated;

-- casos "cobrar retorno do Dr. Gustavo" que ainda não estavam no nome dele: passam para ele,
-- para aparecerem na área dele (só consultas passadas, então não dispara aviso de consulta)
update public.funil_pacientes
   set dados = dados || jsonb_build_object('cirurgiao', 'gu.martins00@gmail.com')
 where coalesce(dados->>'cirurgiao','') = ''
   and lower(dados->>'proximaAcao') like 'cobrar%gustavo%'
   and coalesce(dados->>'etapa','') not in ('perdido')
   and (coalesce(dados->>'dataConsulta','') !~ '^\d{4}-\d{2}-\d{2}$' or (dados->>'dataConsulta')::date < (now() at time zone 'America/Sao_Paulo')::date);
