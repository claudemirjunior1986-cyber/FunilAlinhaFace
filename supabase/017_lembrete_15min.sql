-- Lembrete por WhatsApp 15 minutos antes da consulta: um para o paciente e outro para o cirurgião.
-- Consulta online: cria (ou reaproveita) a sala de vídeo do site e manda o link a cada um.
-- O banco põe os lembretes na mesma fila dos avisos (funil_avisos_medico); a função "whats" envia.
-- Pode rodar de novo sem problema.

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
       and coalesce(p.dados->>'horaConsulta','') ~ '^\d{2}:\d{2}$'
       and coalesce(p.dados->>'etapa','') = 'agendou'
       and (agora::date + (p.dados->>'horaConsulta')::time) > agora
       and (agora::date + (p.dados->>'horaConsulta')::time) <= agora + interval '16 minutes'
  loop
    d := r.dados;
    hora := d->>'horaConsulta';
    chave := (d->>'dataConsulta') || ' ' || hora;
    if coalesce(d->>'lembrete15','') = chave then continue; end if;

    online := coalesce(d->>'modalidade','Online') <> 'Presencial';
    onde := case when online then 'por vídeo' else 'presencial' || coalesce(' · ' || nullif(d->>'local',''), '') end;
    select nome, whatsapp, avisos_whats into pr from perfis where email = r.cirurgiao_email;
    medico := coalesce(pr.nome, 'especialista');
    nome1 := initcap(split_part(trim(coalesce(d->>'nome','')), ' ', 1));

    sala := null;
    if online then
      select id into sala from funil_teleconsultas
       where paciente_id = r.id and fim is null and criada_em > now() - interval '12 hours'
       order by criada_em desc limit 1;
      if sala is null then
        insert into funil_teleconsultas (paciente_id, paciente_nome, cirurgiao, criada_por)
        values (r.id, d->>'nome', r.cirurgiao_email, 'lembrete automático') returning id into sala;
      end if;
    end if;

    -- paciente
    tel := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');
    if length(tel) >= 10 and coalesce(d->>'telefone','') not like '%@lid%' then
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values ('paciente', tel, r.id, 'lembrete_paciente',
        'Oi' || case when nome1 <> '' then ', ' || nome1 else '' end || '! 😊 Passando para lembrar que sua consulta de avaliação com o '
        || medico || ' é hoje às ' || hora || ', ' || onde || '.'
        || case when online then chr(10) || chr(10) || 'No horário, é só tocar neste link (de preferência pelo celular, com fone de ouvido) e permitir câmera e microfone:'
                                 || chr(10) || base || 'sala.html?c=' || sala || '&p=1'
                else '' end
        || chr(10) || chr(10) || 'Se tiver algum imprevisto, é só responder aqui. Até já!');
      n := n + 1;
    end if;

    -- cirurgião
    if pr.whatsapp is not null and coalesce(pr.avisos_whats, false) then
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values (r.cirurgiao_email, pr.whatsapp, r.id, 'lembrete_medico',
        '⏰ *Consulta em 15 minutos — Alinha Face*' || chr(10) || 'Paciente: ' || coalesce(nullif(trim(d->>'nome'),''), 'Paciente') || chr(10)
        || 'Hoje às ' || hora || ' · ' || onde
        || case when online then chr(10) || chr(10) || 'Entrar na sala de vídeo: ' || base || 'sala.html?c=' || sala else '' end
        || chr(10) || 'Ficha: ' || base || 'medico.html?abrir=' || r.id);
      n := n + 1;
    end if;

    update funil_pacientes set dados = dados || jsonb_build_object('lembrete15', chave) where id = r.id;
  end loop;
  return n;
end $$;
revoke all on function public.gerar_lembretes() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'lembretes-15min') then perform cron.unschedule('lembretes-15min'); end if;
end $$;
select cron.schedule('lembretes-15min', '* * * * *', $$ select public.gerar_lembretes() $$);
