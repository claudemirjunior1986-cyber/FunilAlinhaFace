-- Dr. Afonso e Dr. Victor (agenda do funil): atendem em qualquer minuto livre — 10:00, 10:15, 10:25, 10:30, 10:50...
--  * A lista de horários livres volta a ser de 15 em 15 min (desfaz a versão de 30 em 30 desta mesma correção).
--  * Ao marcar, qualquer horário pedido serve se estiver dentro da grade e livre (não precisa estar na lista).
-- O Dr. Gustavo não usa esta agenda: só ele segue com :15 e :45, pela agenda do Google. Pode rodar de novo sem problema.

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
revoke all on function public.agenda_slots(text, text, date, date, text) from public, anon, authenticated;
grant execute on function public.agenda_slots(text, text, date, date, text) to service_role;

-- o horário exato (qualquer minuto) está dentro da grade do médico e livre?
create or replace function public.agenda_livre_em(
  p_chave text, p_modalidade text, p_data date, p_hora text, p_ignorar text default null
) returns table (local text, endereco text)
language sql stable security definer set search_path = public as $$
  with x as (
    select (p_data + p_hora::time) as ini, agenda_duracao(p_modalidade) as dur,
           case when lower(coalesce(p_modalidade,'')) like 'presen%' then 'Presencial' else 'Online' end as mod,
           (now() at time zone 'America/Sao_Paulo') as agora
  )
  select g.local, g.endereco
  from x
  join agenda_grade g on g.medico = p_chave and g.dia_semana = extract(dow from p_data)::int and x.mod = any(g.modalidades)
  join agenda_medicos m on m.chave = g.medico and m.ativo
  where p_hora::time >= g.inicio
    and p_hora::time + make_interval(mins => x.dur) <= g.fim
    and x.ini >= x.agora + interval '60 minutes'
    and not agenda_ocupado(p_chave, x.ini, x.ini + make_interval(mins => x.dur), p_ignorar)
  limit 1
$$;
revoke all on function public.agenda_livre_em(text, text, date, text, text) from public, anon, authenticated;
grant execute on function public.agenda_livre_em(text, text, date, text, text) to service_role;

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

  -- qualquer minuto serve (10:00, 10:25, 10:50...), desde que esteja dentro da grade e livre
  select * into slot from agenda_livre_em(p_chave, mod, p_data, hh, case when achou then r.id end);
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
revoke all on function public.agenda_agendar(text, text, date, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.agenda_agendar(text, text, date, text, text, text, text, text) to service_role;
