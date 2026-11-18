-- 1) Cobrar o registro da consulta: 3 h depois do horário, se o cirurgião ainda não registrou (atendeu? pediu exames?),
--    vai um WhatsApp para o cirurgião e um recado para a Ana. Uma vez por consulta (marca cobrarRegistroEm na ficha).
-- 2) Relatório semanal (segunda 8h): a função "whats" (acao relatorio_semanal) manda um resumo da saúde do sistema
--    para o WhatsApp do diretor.
-- Pode rodar de novo sem problema.

create or replace function public.cobrar_registros() returns int
language plpgsql security definer set search_path = public as $$
declare
  r      record;
  n      int := 0;
  tel    text;
  medico text;
  quando timestamptz;
  txt    text;
  hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  for r in
    select p.id, p.dados, p.cirurgiao_email from funil_pacientes p
     where coalesce(p.dados->>'etapa','') = 'agendou'
       and coalesce(p.dados->>'consultaRegistradaEm','') = ''
       and coalesce(p.dados->>'cobrarRegistroEm','') = ''
       and coalesce((p.dados->>'demo')::boolean, false) = false
       and coalesce(p.cirurgiao_email,'') <> ''
       and (p.dados->>'dataConsulta') ~ '^\d{4}-\d{2}-\d{2}'
       and left(p.dados->>'dataConsulta', 10)::date between hoje - 3 and hoje
  loop
    quando := ((left(r.dados->>'dataConsulta',10) || ' ' ||
               coalesce(nullif(substring(coalesce(r.dados->>'horaConsulta','') from '^\d{1,2}:\d{2}'), ''), '12:00'))::timestamp
               at time zone 'America/Sao_Paulo');
    continue when quando + interval '3 hours' > now();

    select whatsapp, nome into tel, medico from perfis where email = r.cirurgiao_email;
    txt := '📝 *Falta registrar a consulta — Alinha Face*' || chr(10)
      || '*Paciente:* ' || coalesce(nullif(r.dados->>'nome',''), 'Paciente') || chr(10)
      || '*Consulta:* ' || to_char(quando at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI')
      || coalesce(' · ' || nullif(r.dados->>'modalidade',''), '') || chr(10) || chr(10)
      || 'Por favor, registre no funil se o paciente compareceu, se pediu exames e um breve resumo. É rapidinho e já dispara o próximo passo do paciente.' || chr(10)
      || 'Ficha: https://funil-alinhaface.pages.dev/medico.html?abrir=' || r.id;
    if coalesce(tel,'') <> '' then
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
      values (r.cirurgiao_email, tel, r.id, 'cobrar_registro', txt);
    end if;
    insert into funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
    values ('sistema@alinhaface.com.br', 'Funil (automático)', 'acytgiroldo@gmail.com', 'Ana Clara', r.id, r.dados->>'nome',
            'O ' || coalesce(medico, 'cirurgião') || ' ainda não registrou a consulta de ' || to_char(quando at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
            || '. Já mandei um lembrete no WhatsApp dele. Se até amanhã não registrar, vale cobrar.');
    update funil_pacientes set dados = dados || jsonb_build_object('cobrarRegistroEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
     where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.cobrar_registros() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'cobrar-registros') then perform cron.unschedule('cobrar-registros'); end if;
  if exists (select 1 from cron.job where jobname = 'relatorio-semanal') then perform cron.unschedule('relatorio-semanal'); end if;
end $$;
select cron.schedule('cobrar-registros', '7,37 * * * *', $$ select public.cobrar_registros() $$);
select cron.schedule('relatorio-semanal', '13 11 * * 1', $$
  select net.http_post(
    url := 'https://odamgyzklsndepklmicl.supabase.co/functions/v1/whats',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"acao":"relatorio_semanal"}'::jsonb)
$$);
