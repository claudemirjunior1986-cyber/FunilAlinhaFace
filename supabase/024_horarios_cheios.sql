-- Dr. Afonso e Dr. Victor: horários de 30 em 30 minutos, sempre em hora cheia ou meia (10:00, 10:30, 14:00...).
-- A consulta on-line continua durando 15 minutos (só muda de quanto em quanto tempo se oferece).
-- O Dr. Gustavo não usa esta agenda: ele segue com :15 e :45 pela agenda do Google. Pode rodar de novo sem problema.
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
  cross join lateral generate_series(dd + g.inicio, dd + g.fim - make_interval(mins => p.dur), interval '15 minutes') ts
  cross join agora a
  where extract(minute from ts) in (0, 30)                     -- só hora cheia ou meia
    and ts >= a.t + interval '60 minutes'
    and not agenda_ocupado(p_chave, ts, ts + make_interval(mins => p.dur), p_ignorar)
  order by ts
$$;
revoke all on function public.agenda_slots(text, text, date, date, text) from public, anon, authenticated;
grant execute on function public.agenda_slots(text, text, date, date, text) to service_role;
