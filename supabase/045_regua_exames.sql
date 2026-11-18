-- 045: régua pós-consulta dos exames (18/11)
-- Depois que o cirurgião pede exames, o paciente recebe pelo WhatsApp da Alinha Face:
--   D+2: "já conseguiu agendar o exame?" (+ voucher Blume, se tiver) · D+5: lembrete do prazo de 10 dias
--   D+8: recado para a Ana ligar.
-- Para sozinha quando a ficha tem exame agendado ou realizado (ou etapa perdido/no-show).
-- Quando a ficha recebe "já fez o exame", o paciente recebe o pedido do laudo/imagens.
-- Marca em dados.reguaExame {d2,d5,d8,feito}. Pode rodar de novo sem problema.

create or replace function public.regua_exames() returns int
language plpgsql security definer set search_path = public as $$
declare
  r      record;
  d      jsonb;
  rg     jsonb;
  hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  base   date;
  dias   int;
  etapa  text;
  tel    text;
  nome1  text;
  medico text;
  exame  text;
  venc   text;
  txt    text;
  n      int := 0;
begin
  for r in
    select p.id, p.dados, p.cirurgiao_email from funil_pacientes p
     where coalesce((p.dados->>'consultaPediuExames')::boolean, false)
       and coalesce(p.dados->>'exameAgendadoPara','') = '' and coalesce(p.dados->>'exameRealizadoEm','') = ''
       and coalesce(p.dados->>'etapa','') not in ('perdido','noshow','perdido_outra')
       and coalesce((p.dados->>'demo')::boolean, false) = false
  loop
    d := r.dados;
    base := coalesce(
      case when left(coalesce(d->>'examesPedidosEm',''),10) ~ '^\d{4}-\d{2}-\d{2}$' then left(d->>'examesPedidosEm',10)::date end,
      case when left(coalesce(d->>'consultaRegistradaEm',''),10) ~ '^\d{4}-\d{2}-\d{2}$' then left(d->>'consultaRegistradaEm',10)::date end);
    continue when base is null or base < hoje - 12;
    dias := hoje - base;
    etapa := case when dias >= 8 then 'd8' when dias >= 5 then 'd5' when dias >= 2 then 'd2' else null end;
    continue when etapa is null;
    rg := case when jsonb_typeof(d->'reguaExame') = 'object' then d->'reguaExame' else '{}'::jsonb end;
    continue when rg ? etapa;

    select nome into medico from perfis where email = coalesce(r.cirurgiao_email, d->>'consultaRegistradaPor');
    medico := coalesce(medico, 'especialista');
    nome1 := initcap(split_part(trim(coalesce(d->>'nome','')), ' ', 1));
    select string_agg(lower(x), ', ') into exame
      from (select jsonb_array_elements_text(case when jsonb_typeof(d->'examesTipos') = 'array' then d->'examesTipos' else '[]'::jsonb end) x
            union all select nullif(d->>'examesPedidos','')) t where x is not null;
    tel := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');

    if etapa = 'd8' then
      insert into funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
      values ('sistema@alinhaface.com.br', 'Funil (automático)', 'acytgiroldo@gmail.com', 'Ana Clara', r.id, d->>'nome',
              'Ligar para ' || coalesce(nullif(d->>'nome',''), 'o paciente') || ': exame pedido pelo ' || medico || ' em ' || to_char(base, 'DD/MM')
              || coalesce(' (' || exame || ')', '') || ' e ainda sem data. Já recebeu 2 mensagens no WhatsApp. Telefone: ' || coalesce(d->>'telefone',''));
    elsif length(tel) >= 10 and coalesce(d->>'telefone','') not like '%@lid%' then
      if etapa = 'd2' then
        venc := null;
        if coalesce(d->>'voucherEmitido','') ~ '^\d{4}-\d{2}-\d{2}' and coalesce(d->>'voucherStatus','Aguardando uso') = 'Aguardando uso' then
          venc := to_char(left(d->>'voucherEmitido',10)::date + 5, 'DD/MM');
        end if;
        txt := 'Oi' || case when nome1 <> '' then ', ' || nome1 else '' end || '! Tudo bem? 😊 Aqui é a Bia, da Alinha Face. Passando para saber: já conseguiu agendar '
          || coalesce('o exame (' || exame || ')', 'o exame') || ' que o ' || medico || ' pediu? Se precisar de ajuda com o agendamento ou com a autorização do seu plano, é só me falar que a gente resolve junto.'
          || coalesce(chr(10) || chr(10) || 'Lembrando que você tem o voucher de cortesia da Blume, válido até ' || venc || '.', '');
      else
        txt := case when nome1 <> '' then nome1 || ', p' else 'P' end || 'assando para lembrar do seu exame 🙂 O ideal é fazer em até 10 dias do pedido, para o '
          || medico || ' avaliar seu caso o quanto antes. Já tem data marcada? Se o plano estiver travando a autorização, me avisa que nossa equipe ajuda.';
      end if;
      insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values ('paciente', tel, r.id, 'regua_exame_' || etapa, txt);
    end if;

    -- marca a etapa (e as anteriores, para nunca mandar duas no mesmo dia)
    rg := rg || jsonb_build_object(etapa, hoje::text);
    if etapa in ('d5','d8') and not rg ? 'd2' then rg := rg || jsonb_build_object('d2', hoje::text); end if;
    if etapa = 'd8' and not rg ? 'd5' then rg := rg || jsonb_build_object('d5', hoje::text); end if;
    update funil_pacientes set dados = jsonb_set(dados, '{reguaExame}', rg) where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.regua_exames() from public, anon, authenticated;

-- "Já fez o exame": pede o laudo e as imagens
create or replace function public.exame_feito_pede_laudo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  d jsonb := new.dados; tel text; nome1 text; medico text;
begin
  if coalesce(d->>'exameRealizadoEm','') = '' or coalesce(old.dados->>'exameRealizadoEm','') <> '' then return new; end if;
  if coalesce((d->>'demo')::boolean, false) or (d->'reguaExame') ? 'feito' then return new; end if;
  tel := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');
  if length(tel) < 10 or coalesce(d->>'telefone','') like '%@lid%' then return new; end if;
  select nome into medico from perfis where email = coalesce(new.cirurgiao_email, d->>'consultaRegistradaPor');
  nome1 := initcap(split_part(trim(coalesce(d->>'nome','')), ' ', 1));
  insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto) values ('paciente', tel, new.id, 'regua_exame_feito',
    'Que ótimo' || case when nome1 <> '' then ', ' || nome1 else '' end || '! 🙌 Pode me mandar o laudo e as imagens por aqui que eu já encaminho ao '
    || coalesce(medico, 'especialista') || ' para agendarmos seu retorno.');
  new.dados := jsonb_set(d, '{reguaExame}', (case when jsonb_typeof(d->'reguaExame') = 'object' then d->'reguaExame' else '{}'::jsonb end)
                 || jsonb_build_object('feito', to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD')));
  return new;
end $$;
drop trigger if exists exame_feito_pede_laudo on public.funil_pacientes;
create trigger exame_feito_pede_laudo before update on public.funil_pacientes
  for each row execute function public.exame_feito_pede_laudo();

do $$ begin
  if exists (select 1 from cron.job where jobname = 'regua-exames') then perform cron.unschedule('regua-exames'); end if;
end $$;
select cron.schedule('regua-exames', '23 13 * * 1-6', $$ select public.regua_exames() $$);   -- 10h23 em São Paulo, seg a sáb
