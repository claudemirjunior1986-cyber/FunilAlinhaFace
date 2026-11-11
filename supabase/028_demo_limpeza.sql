-- Caso de teste para o Dr. Joaquim (teste): é apagado sozinho 60 minutos depois de criado.
-- Os 10 pacientes de exemplo fixos (demo-01..10) não são apagados (eles se renovam de madrugada).
-- Pode rodar de novo sem problema.

create or replace function public.marca_ficha_demo() returns trigger
language plpgsql set search_path = public as $$
begin
  if lower(coalesce(new.dados->>'cirurgiao','')) = 'demo@alinhaface.com.br' then
    if coalesce(new.dados->>'demo','') <> 'true' then new.dados := new.dados || jsonb_build_object('demo', true); end if;
    if new.id not like 'demo-%' and coalesce(new.dados->>'demoDesde','') = '' then
      new.dados := new.dados || jsonb_build_object('demoDesde', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    end if;
  end if;
  return new;
end $$;

create or replace function public.demo_limpar() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from funil_teleconsultas where paciente_id in (
    select id from funil_pacientes where id not like 'demo-%' and dados->>'demo' = 'true'
       and (dados->>'demoDesde')::timestamptz < now() - interval '60 minutes');
  delete from funil_avisos_medico where situacao is distinct from 'enviado' and paciente_id in (
    select id from funil_pacientes where id not like 'demo-%' and dados->>'demo' = 'true'
       and (dados->>'demoDesde')::timestamptz < now() - interval '60 minutes');
  delete from funil_pacientes where id not like 'demo-%' and dados->>'demo' = 'true'
     and (dados->>'demoDesde')::timestamptz < now() - interval '60 minutes';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.demo_limpar() from public, anon, authenticated;
grant execute on function public.demo_limpar() to service_role;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'demo-limpar') then perform cron.unschedule('demo-limpar'); end if;
end $$;
select cron.schedule('demo-limpar', '*/10 * * * *', $$ select public.demo_limpar() $$);
