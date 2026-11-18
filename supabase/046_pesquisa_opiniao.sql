-- 046: pesquisa de opinião pós-consulta (18/11)
-- No dia seguinte à consulta (10h), quem compareceu recebe: "Como foi sua avaliação com o Dr. X?".
-- A Bia responde (treinamento PESQUISA DE OPINIÃO): positiva -> link do Google; negativa -> acolhe e passa para a equipe.
-- A função "whats" lê a resposta, grava na ficha (dados.opiniao) e, se for negativa, avisa o Claudemir e a Ana.
-- Uma vez por paciente. Pode rodar de novo sem problema.

create or replace function public.pedir_opiniao() returns int
language plpgsql security definer set search_path = public as $$
declare
  r      record;
  d      jsonb;
  hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  dc     date;
  tel    text;
  nome1  text;
  medico text;
  quando text;
  n      int := 0;
begin
  for r in
    select p.id, p.dados, p.cirurgiao_email from funil_pacientes p
     where coalesce(p.dados->>'consultaRegistradaEm','') <> ''
       and coalesce(p.dados->>'consultaCompareceu','true') <> 'false'
       and jsonb_typeof(p.dados->'opiniao') is null
       and coalesce((p.dados->>'demo')::boolean, false) = false
       and coalesce(p.dados->>'etapa','') not in ('perdido','noshow','perdido_outra')
       and (p.dados->>'dataConsulta') ~ '^\d{4}-\d{2}-\d{2}'
       and left(p.dados->>'dataConsulta',10)::date between hoje - 3 and hoje - 1
  loop
    d := r.dados;
    tel := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');
    continue when length(tel) < 10 or coalesce(d->>'telefone','') like '%@lid%';
    dc := left(d->>'dataConsulta',10)::date;
    quando := case when dc = hoje - 1 then 'ontem' else 'no dia ' || to_char(dc, 'DD/MM') end;
    select nome into medico from perfis where email = coalesce(r.cirurgiao_email, d->>'consultaRegistradaPor');
    nome1 := initcap(split_part(trim(coalesce(d->>'nome','')), ' ', 1));
    insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values ('paciente', tel, r.id, 'regua_opiniao',
      'Oi' || case when nome1 <> '' then ', ' || nome1 else '' end || '! 😊 Como foi sua avaliação com o ' || coalesce(medico, 'especialista')
      || ' ' || quando || '? Sua opinião é muito importante para nós.');
    update funil_pacientes set dados = dados || jsonb_build_object('opiniao', jsonb_build_object(
      'pedidaEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))) where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.pedir_opiniao() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'pedir-opiniao') then perform cron.unschedule('pedir-opiniao'); end if;
end $$;
select cron.schedule('pedir-opiniao', '3 13 * * *', $$ select public.pedir_opiniao() $$);   -- 10h03 em São Paulo
