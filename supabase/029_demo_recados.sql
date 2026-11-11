-- Recados da demonstração não ficam no sistema:
--  * a renovação da madrugada dos exemplos não gera recado;
--  * recados do/para o Dr. Joaquim (teste) ou sobre pacientes de exemplo somem 60 min depois (junto com a limpeza).
--  * apaga agora os recados de demonstração que já existem.
-- Pode rodar de novo sem problema.

create or replace function public.bloqueia_recado_demo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('app.demo_renovando', true), '') = 'on' then return null; end if;
  return new;
end $$;
drop trigger if exists bloqueia_recado_demo on public.funil_recados;
create trigger bloqueia_recado_demo before insert on public.funil_recados
  for each row execute function public.bloqueia_recado_demo();

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
  -- recados da demonstração (do/para o Dr. Joaquim (teste) ou sobre paciente de exemplo) com mais de 60 min
  delete from funil_recados r where r.criado_em < now() - interval '60 minutes' and (
       r.de = 'demo@alinhaface.com.br' or r.para = 'demo@alinhaface.com.br' or coalesce(r.paciente_id,'') like 'demo-%'
    or exists (select 1 from funil_pacientes p where p.id = r.paciente_id and p.dados->>'demo' = 'true'));
  delete from funil_pacientes where id not like 'demo-%' and dados->>'demo' = 'true'
     and (dados->>'demoDesde')::timestamptz < now() - interval '60 minutes';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.demo_limpar() from public, anon, authenticated;
grant execute on function public.demo_limpar() to service_role;

-- limpeza agora: todos os recados de demonstração, de qualquer hora
delete from public.funil_recados r where
     r.de = 'demo@alinhaface.com.br' or r.para = 'demo@alinhaface.com.br' or coalesce(r.paciente_id,'') like 'demo-%'
  or exists (select 1 from public.funil_pacientes p where p.id = r.paciente_id and p.dados->>'demo' = 'true');
-- caso de teste criado antes da limpeza automática existir: entra na contagem de 60 min a partir de agora
update public.funil_pacientes set dados = dados || jsonb_build_object('demoDesde', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
 where id not like 'demo-%' and dados->>'demo' = 'true' and coalesce(dados->>'demoDesde','') = '';
select count(*) as recados_restantes from public.funil_recados;
