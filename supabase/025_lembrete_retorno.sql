-- Lembrete de 15 min (com o link da sala) também para quem já é paciente: consulta de retorno com a ficha em
-- "exames solicitados", "proposta" etc. Antes só saía quando a etapa era "agendou".
-- Isso cobre também a consulta marcada em cima da hora (menos de 20 min), que não recebe a confirmação. Pode rodar de novo.
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
       and coalesce(p.dados->>'etapa','') not in ('perdido','noshow','triagem')   -- vale também para retorno (exames, proposta...)
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
