-- 044: lembretes de consulta (18/11)
-- * 24 h antes: o paciente recebe o lembrete pedindo para confirmar respondendo SIM (a função "whats" lê o SIM e
--   marca a consulta como confirmada na Rotina; quem não confirmar continua na Rotina para a Ana ligar).
-- * 30 min antes: lembrete do paciente com o link (antes era 15 min). O do cirurgião continua 15 min antes.
-- Pode rodar de novo sem problema.

-- texto da confirmação na hora do agendamento: "30 minutos antes"
do $$
declare d text;
begin
  d := pg_get_functiondef('public.avisa_consulta_paciente()'::regprocedure);
  if position('15 minutos antes eu te mando' in d) > 0 then
    execute replace(d, '15 minutos antes eu te mando', '30 minutos antes eu te mando');
  end if;
end $$;

create or replace function public.gerar_lembretes() returns int
language plpgsql security definer set search_path = public as $$
declare
  agora  timestamp := (now() at time zone 'America/Sao_Paulo');
  r      record;
  d      jsonb;
  chave  text;
  sala   uuid;
  nome1  text;
  hora   text;
  medico text;
  pr     record;
  tel    text;
  base   text := 'https://funil-alinhaface.pages.dev/';
  online boolean;
  onde   text;
  n      int := 0;
begin
  for r in
    select p.id, p.dados, p.cirurgiao_email
      from funil_pacientes p
     where p.dados->>'dataConsulta' = to_char(agora::date, 'YYYY-MM-DD')
       and coalesce(p.dados->>'horaConsulta','') ~ '^\d{2}:\d{2}'
       and coalesce(p.dados->>'etapa','') not in ('perdido','noshow')   -- vale também para retorno (exames, proposta...)
       and (agora::date + left(p.dados->>'horaConsulta',5)::time) > agora
       and (agora::date + left(p.dados->>'horaConsulta',5)::time) <= agora + interval '31 minutes'
  loop
    d := r.dados;
    hora := left(d->>'horaConsulta',5);
    chave := (d->>'dataConsulta') || ' ' || hora;
    -- paciente: 30 min antes (chave lembrete30); cirurgião: 15 min antes (chave lembrete15)
    if coalesce(d->>'lembrete30','') = chave and coalesce(d->>'lembrete15','') = chave then continue; end if;

    online := coalesce(d->>'modalidade','Online') <> 'Presencial';
    onde := case when online then 'por vídeo' else 'presencial' || coalesce(' · ' || nullif(d->>'local',''), '') end;
    select nome, whatsapp, avisos_whats into pr from perfis where email = r.cirurgiao_email;
    medico := coalesce(pr.nome, 'especialista');
    nome1 := initcap(split_part(trim(coalesce(d->>'nome','')), ' ', 1));

    sala := null;
    if online then sala := sala_da_consulta(r.id, d->>'nome', r.cirurgiao_email, chave); end if;

    tel := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');
    if coalesce(d->>'lembrete30','') <> chave and coalesce(d->>'lembrete15','') <> chave and length(tel) >= 10 and coalesce(d->>'telefone','') not like '%@lid%' then
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values ('paciente', tel, r.id, 'lembrete_paciente',
        case when nome1 <> '' then nome1 || ', s' else 'S' end || 'ua consulta com o ' || medico || ' é daqui a 30 minutos, às ' || hora || ', ' || onde || ' 😊'
        || case when online then chr(10) || chr(10) || 'No horário, é só tocar neste link (de preferência pelo celular, com fone de ouvido) e permitir câmera e microfone:'
                                 || chr(10) || base || 'sala.html?c=' || sala || '&p=1'
                else '' end
        || chr(10) || chr(10) || 'Se tiver algum imprevisto, é só responder aqui. Até já!');
      n := n + 1;
    end if;
    update funil_pacientes set dados = dados || jsonb_build_object('lembrete30', chave) where id = r.id;

    if coalesce(d->>'lembrete15','') <> chave and (agora::date + hora::time) <= agora + interval '16 minutes'
       and pr.whatsapp is not null and coalesce(pr.avisos_whats, false) then
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values (r.cirurgiao_email, pr.whatsapp, r.id, 'lembrete_medico',
        '⏰ *Consulta em 15 minutos — Alinha Face*' || chr(10) || 'Paciente: ' || coalesce(nullif(trim(d->>'nome'),''), 'Paciente') || chr(10)
        || 'Hoje às ' || hora || ' · ' || onde
        || case when online then chr(10) || chr(10) || 'Entrar na sala de vídeo: ' || base || 'sala.html?c=' || sala else '' end
        || chr(10) || 'Ficha: ' || base || 'medico.html?abrir=' || r.id);
      n := n + 1;
    end if;
    if (agora::date + hora::time) <= agora + interval '16 minutes' then
      update funil_pacientes set dados = dados || jsonb_build_object('lembrete15', chave) where id = r.id;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.gerar_lembretes() from public, anon, authenticated;

create or replace function public.lembretes_24h() returns int
language plpgsql security definer set search_path = public as $$
declare
  agora  timestamp := (now() at time zone 'America/Sao_Paulo');
  r      record;
  d      jsonb;
  quando timestamp;
  chave  text;
  nome1  text;
  medico text;
  tel    text;
  dia    text;
  n      int := 0;
begin
  for r in
    select p.id, p.dados, p.cirurgiao_email from funil_pacientes p
     where (p.dados->>'dataConsulta') ~ '^\d{4}-\d{2}-\d{2}'
       and coalesce(p.dados->>'horaConsulta','') ~ '^\d{1,2}:\d{2}'
       and left(p.dados->>'dataConsulta',10)::date between agora::date and agora::date + 2
       and coalesce(p.dados->>'etapa','') not in ('perdido','noshow','perdido_outra')
       and coalesce((p.dados->>'demo')::boolean, false) = false
  loop
    d := r.dados;
    quando := (left(d->>'dataConsulta',10) || ' ' || substring(d->>'horaConsulta' from '^\d{1,2}:\d{2}'))::timestamp;
    continue when quando <= agora + interval '23 hours' or quando > agora + interval '24 hours';
    chave := left(d->>'dataConsulta',10) || ' ' || substring(d->>'horaConsulta' from '^\d{1,2}:\d{2}');
    continue when coalesce(d->>'lembrete24','') = chave;
    -- marcada há pouco (a confirmação do agendamento acabou de sair): não manda
    if exists (select 1 from funil_avisos_medico where paciente_id = r.id and tipo = 'confirmacao_paciente'
                and criado_em > now() - interval '12 hours') then
      update funil_pacientes set dados = dados || jsonb_build_object('lembrete24', chave) where id = r.id;
      continue;
    end if;
    tel := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');
    if length(tel) < 10 or coalesce(d->>'telefone','') like '%@lid%' then continue; end if;
    select nome into medico from perfis where email = r.cirurgiao_email;
    nome1 := initcap(split_part(trim(coalesce(d->>'nome','')), ' ', 1));
    dia := (array['domingo','segunda','terça','quarta','quinta','sexta','sábado'])[extract(dow from quando)::int + 1];
    insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values ('paciente', tel, r.id, 'lembrete_24h',
      'Oi' || case when nome1 <> '' then ', ' || nome1 else '' end || '! Passando para lembrar da sua avaliação amanhã, ' || dia
      || ', às ' || to_char(quando, 'HH24"h"MI') || coalesce(', com o ' || medico, '')
      || case when coalesce(d->>'modalidade','Online') = 'Presencial' then ', presencial' || coalesce(' (' || nullif(d->>'local','') || ')', '') else ', por vídeo' end
      || ' 😊' || chr(10) || chr(10) || 'Pode confirmar respondendo *SIM*? Se precisar remarcar, é só me avisar.');
    update funil_pacientes set dados = dados || jsonb_build_object('lembrete24', chave,
      'lembrete24Em', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')) where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.lembretes_24h() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'lembretes-24h') then perform cron.unschedule('lembretes-24h'); end if;
end $$;
select cron.schedule('lembretes-24h', '*/10 * * * *', $$ select public.lembretes_24h() $$);
