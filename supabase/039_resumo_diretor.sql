-- Resumo de cada consulta no WhatsApp do diretor (Claudemir).
-- Quando o cirurgião registra (ou corrige) a consulta no funil, sai um WhatsApp para o número em
-- funil_config k='diretor_whatsapp' com: paciente, cirurgião, resultado (compareceu / pediu exames) e o resumo.
-- O resumo é o que o cirurgião escreveu; se ele não escreveu, vai o resumo da IA da teleconsulta (se houver).
-- Pode rodar de novo sem problema.

insert into public.funil_config (k, v) values ('diretor_whatsapp', '5511988157588')
on conflict (k) do nothing;

create or replace function public.avisa_diretor_consulta() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  d      jsonb := new.dados;
  tel    text;
  quem   text := lower(coalesce(d->>'consultaRegistradaPor',''));
  nomeq  text;
  nomec  text;
  exames text;
  resumo text;
  origem text := '';
  txt    text;
begin
  if coalesce(d->>'consultaRegistradaEm','') = '' or coalesce((d->>'demo')::boolean, false) then return new; end if;
  if tg_op = 'UPDATE' and (old.dados->>'consultaRegistradaEm') is not distinct from (d->>'consultaRegistradaEm') then
    return new;
  end if;
  select v into tel from funil_config where k = 'diretor_whatsapp';
  if coalesce(tel,'') = '' then return new; end if;

  select nome into nomeq from perfis where email = quem;
  select nome into nomec from perfis where email = coalesce(nullif(d->>'cirurgiao',''), quem);
  select string_agg(x, ', ') into exames
    from (select jsonb_array_elements_text(coalesce(d->'examesTipos','[]'::jsonb)) x
          union all select nullif(d->>'examesPedidos','')) t where x is not null;

  resumo := nullif(trim(coalesce(d->>'resumoConsulta','')), '');
  if resumo is null then
    select nullif(trim(resumo_ia), '') into resumo from funil_teleconsultas
     where paciente_id = new.id and coalesce(resumo_ia,'') <> '' order by criada_em desc limit 1;
    if resumo is not null then origem := ' (gerado pela IA da teleconsulta)'; end if;
  end if;

  txt := '🩺 *Consulta registrada — Alinha Face*' || chr(10)
    || case when tg_op = 'UPDATE' and coalesce(old.dados->>'consultaRegistradaEm','') <> '' then '(registro corrigido)' || chr(10) else '' end
    || '*Paciente:* ' || coalesce(nullif(d->>'nome',''), 'Paciente') || chr(10)
    || '*Cirurgião:* ' || coalesce(nomec, nomeq, 'cirurgião') || chr(10)
    || coalesce('*Consulta:* ' || regexp_replace(nullif(d->>'dataConsulta',''), '^(\d{4})-(\d{2})-(\d{2}).*$', '\3/\2') || coalesce(' ' || nullif(d->>'horaConsulta',''), '')
                || coalesce(' · ' || nullif(d->>'modalidade',''), '') || chr(10), '')
    || '*Resultado:* ' || case when (d->>'consultaCompareceu') = 'false' then 'paciente NÃO compareceu'
                               when (d->>'consultaPediuExames') = 'true' then 'atendeu e pediu exames' || coalesce(' (' || exames || ')', '')
                               else 'atendeu, sem pedido de exames' end || chr(10)
    || coalesce('*Convênio:* ' || case when d->>'convenio' = 'Sim' then coalesce(nullif(d->>'nomeConvenio',''), 'sim')
                                       when d->>'convenio' = 'Não' then 'particular' end || chr(10), '')
    || case when resumo is not null then chr(10) || '*Resumo' || origem || ':*' || chr(10) || resumo || chr(10)
            else chr(10) || '(o cirurgião não escreveu resumo)' || chr(10) end
    || chr(10) || 'Ficha: https://funil-alinhaface.pages.dev/painel.html';

  insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
  values ('diretor', tel, new.id, 'resumo_diretor', left(txt, 3800));
  return new;
end $$;

drop trigger if exists funil_avisa_diretor on public.funil_pacientes;
create trigger funil_avisa_diretor after insert or update on public.funil_pacientes
  for each row execute function public.avisa_diretor_consulta();
