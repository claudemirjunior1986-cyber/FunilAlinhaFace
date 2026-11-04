-- Consulta presencial: a Bia não marca mais. Ela junta os dados e a função "agenda" (acao=presencial)
-- chama encaminhar_presencial(): atualiza (ou cria) a ficha e põe na fila um WhatsApp para o cirurgião,
-- com dados do paciente, avaliação do site e resumo da conversa, para ele passar à secretária.
-- Pode rodar de novo sem problema.

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
  amanha text := to_char((now() at time zone 'America/Sao_Paulo')::date + 1, 'YYYY-MM-DD');
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

  -- já mandou este paciente para este cirurgião nas últimas 12 horas? não repete
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
    'proximaAcao', 'Secretária do ' || p_medico || ' marca a consulta presencial (resumo enviado ao Dr.)',
    'dataProximaAcao', amanha,
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
