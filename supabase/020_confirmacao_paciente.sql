-- Confirmação ao PACIENTE na hora em que a consulta é marcada ou remarcada (além do lembrete de 15 min).
-- Consulta on-line: já vai com o link da sala de vídeo. A mesma sala é usada no lembrete de 15 minutos.
-- Vai pela fila funil_avisos_medico (tipo confirmacao_paciente); a função "whats" envia sem tirar a conversa da Bia.
-- Pode rodar de novo sem problema.

alter table public.funil_teleconsultas add column if not exists consulta text;   -- "AAAA-MM-DD HH:MM" da consulta

-- sala de vídeo da consulta (reaproveita a da mesma data/hora, se ainda não foi encerrada)
create or replace function public.sala_da_consulta(p_id text, p_nome text, p_cir text, p_quando text) returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid;
begin
  select id into s from funil_teleconsultas
   where paciente_id = p_id and fim is null and (consulta = p_quando or (consulta is null and criada_em > now() - interval '12 hours'))
   order by criada_em desc limit 1;
  if s is null then
    insert into funil_teleconsultas (paciente_id, paciente_nome, cirurgiao, criada_por, consulta)
    values (p_id, p_nome, p_cir, 'agendamento automático', p_quando) returning id into s;
  else
    update funil_teleconsultas set consulta = p_quando, cirurgiao = coalesce(p_cir, cirurgiao) where id = s;
  end if;
  return s;
end $$;
revoke all on function public.sala_da_consulta(text, text, text, text) from public, anon, authenticated;

create or replace function public.avisa_consulta_paciente() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  agora  timestamp := (now() at time zone 'America/Sao_Paulo');
  n      jsonb := new.dados;
  o      jsonb := case when tg_op = 'UPDATE' then old.dados else '{}'::jsonb end;
  n_ok   boolean; o_ok boolean;
  quando timestamp;
  tel    text;
  nome1  text;
  medico text;
  online boolean;
  sala   uuid;
  base   text := 'https://funil-alinhaface.pages.dev/';
  remarc boolean;
begin
  n_ok := coalesce(n->>'dataConsulta','') ~ '^\d{4}-\d{2}-\d{2}$' and coalesce(n->>'horaConsulta','') ~ '^\d{2}:\d{2}'
          and coalesce(n->>'etapa','') not in ('perdido','noshow');
  if not n_ok then return new; end if;
  quando := (n->>'dataConsulta')::date + (left(n->>'horaConsulta',5))::time;
  if quando <= agora + interval '20 minutes' then return new; end if;   -- tão perto: o lembrete de 15 min cuida
  o_ok := coalesce(o->>'dataConsulta','') ~ '^\d{4}-\d{2}-\d{2}$' and coalesce(o->>'horaConsulta','') ~ '^\d{2}:\d{2}'
          and coalesce(o->>'etapa','') not in ('perdido','noshow');
  -- só quando a consulta é nova ou mudou de dia, hora, modalidade ou cirurgião
  if o_ok and (n->>'dataConsulta') = (o->>'dataConsulta') and left(n->>'horaConsulta',5) = left(o->>'horaConsulta',5)
     and coalesce(n->>'modalidade','') = coalesce(o->>'modalidade','')
     and new.cirurgiao_email is not distinct from (case when tg_op = 'UPDATE' then old.cirurgiao_email end) then
    return new;
  end if;
  remarc := o_ok;

  tel := regexp_replace(coalesce(n->>'telefone',''), '\D', '', 'g');
  if length(tel) < 10 or coalesce(n->>'telefone','') like '%@lid%' then return new; end if;

  select nome into medico from perfis where email = new.cirurgiao_email;
  medico := coalesce(medico, 'especialista');
  nome1 := initcap(split_part(trim(coalesce(n->>'nome','')), ' ', 1));
  online := coalesce(n->>'modalidade','Online') <> 'Presencial';
  if online then
    sala := sala_da_consulta(new.id, n->>'nome', new.cirurgiao_email, (n->>'dataConsulta') || ' ' || left(n->>'horaConsulta',5));
  end if;

  insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values ('paciente', tel, new.id, 'confirmacao_paciente',
    'Oi' || case when nome1 <> '' then ', ' || nome1 else '' end || '! 😊 '
    || case when remarc then 'Sua consulta de avaliação com o ' || medico || ' foi *remarcada*:'
            else 'Sua consulta de avaliação com o ' || medico || ' está *confirmada*:' end
    || chr(10) || '📅 ' || consulta_texto(n || jsonb_build_object('modalidade', case when online then 'por vídeo' else 'presencial' end))
    || case when not online and nullif(n->>'local','') is not null then chr(10) || '📍 ' || (n->>'local') else '' end
    || case when online then chr(10) || chr(10) || 'No dia e horário, é só tocar neste link (de preferência pelo celular, com fone de ouvido) e permitir câmera e microfone:'
                             || chr(10) || base || 'sala.html?c=' || sala || '&p=1'
            else '' end
    || chr(10) || chr(10) || '15 minutos antes eu te mando um lembrete. Se precisar remarcar, é só responder aqui.');
  return new;
end $$;

drop trigger if exists avisa_consulta_paciente on public.funil_pacientes;
create trigger avisa_consulta_paciente after insert or update of dados, cirurgiao_email on public.funil_pacientes
  for each row execute function public.avisa_consulta_paciente();

-- lembrete de 15 min passa a usar a MESMA sala da confirmação
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
       and coalesce(p.dados->>'etapa','') = 'agendou'
       and (agora::date + left(p.dados->>'horaConsulta',5)::time) > agora
       and (agora::date + left(p.dados->>'horaConsulta',5)::time) <= agora + interval '16 minutes'
  loop
    d := r.dados;
    hora := left(d->>'horaConsulta',5);
    chave := (d->>'dataConsulta') || ' ' || hora;
    if coalesce(d->>'lembrete15','') = chave then continue; end if;

    online := coalesce(d->>'modalidade','Online') <> 'Presencial';
    onde := case when online then 'por vídeo' else 'presencial' || coalesce(' · ' || nullif(d->>'local',''), '') end;
    select nome, whatsapp, avisos_whats into pr from perfis where email = r.cirurgiao_email;
    medico := coalesce(pr.nome, 'especialista');
    nome1 := initcap(split_part(trim(coalesce(d->>'nome','')), ' ', 1));

    sala := null;
    if online then sala := sala_da_consulta(r.id, d->>'nome', r.cirurgiao_email, chave); end if;

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
