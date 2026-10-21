-- Quando o cirurgião registra (ou corrige) a consulta, a equipe recebe um recado
-- automático com o resultado e o resumo. Quem recebe: perfis com recebe_avisos = true.
alter table public.perfis add column if not exists recebe_avisos boolean not null default false;
update public.perfis set recebe_avisos = true where email in ('alinhaface@gmail.com','acytgiroldo@gmail.com');

create or replace function public.avisa_registro_consulta() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  d      jsonb := new.dados;
  quem   text  := lower(coalesce(d->>'consultaRegistradaPor',''));
  nomeq  text;
  txt    text;
  exames text;
  a      record;
begin
  if coalesce(d->>'consultaRegistradaEm','') = '' then return new; end if;
  if tg_op = 'UPDATE' and (old.dados->>'consultaRegistradaEm') is not distinct from (d->>'consultaRegistradaEm') then
    return new;
  end if;
  select nome into nomeq from perfis where email = quem;
  nomeq := coalesce(nomeq, quem, 'Cirurgião');

  select string_agg(x, ', ') into exames
    from (select jsonb_array_elements_text(coalesce(d->'examesTipos','[]'::jsonb)) x
          union all select nullif(d->>'examesPedidos','')) t where x is not null;

  txt := case when (d->>'consultaCompareceu') = 'false' then 'Paciente NÃO compareceu.'
              when (d->>'consultaPediuExames') = 'true' then 'Atendeu e pediu exames' || coalesce(': ' || exames, '') || '.'
              else 'Atendeu, sem pedido de exames.' end;
  if (tg_op = 'UPDATE' and coalesce(old.dados->>'consultaRegistradaEm','') <> '') then
    txt := '(registro corrigido) ' || txt;
  end if;
  if coalesce(d->>'resumoConsulta','') <> '' then
    txt := txt || E'\n\nResumo do ' || nomeq || E':\n' || (d->>'resumoConsulta');
  end if;

  for a in select email, nome from perfis where papel = 'admin' and recebe_avisos loop
    insert into funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
    values (coalesce(nullif(quem,''),'sistema'), nomeq, a.email, a.nome, new.id, d->>'nome', left(txt, 4000));
  end loop;
  return new;
end $$;

drop trigger if exists funil_avisa_registro on public.funil_pacientes;
create trigger funil_avisa_registro after insert or update on public.funil_pacientes
  for each row execute function public.avisa_registro_consulta();

-- registros feitos desde ontem, antes deste aviso existir (ex.: Marli)
insert into public.funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
select lower(p.dados->>'consultaRegistradaPor'),
       coalesce(c.nome, p.dados->>'consultaRegistradaPor'),
       a.email, a.nome, p.id, p.dados->>'nome',
       left(case when (p.dados->>'consultaCompareceu') = 'false' then 'Paciente NÃO compareceu.'
                 when (p.dados->>'consultaPediuExames') = 'true' then 'Atendeu e pediu exames.'
                 else 'Atendeu, sem pedido de exames.' end
            || case when coalesce(p.dados->>'resumoConsulta','') <> ''
                    then E'\n\nResumo do ' || coalesce(c.nome,'cirurgião') || E':\n' || (p.dados->>'resumoConsulta') else '' end, 4000)
from public.funil_pacientes p
join public.perfis a on a.papel = 'admin' and a.recebe_avisos
left join public.perfis c on c.email = lower(p.dados->>'consultaRegistradaPor')
where (p.dados->>'consultaRegistradaEm') >= '2026-10-20'
  and not exists (select 1 from public.funil_recados r where r.paciente_id = p.id and r.para = a.email
                    and r.de = lower(p.dados->>'consultaRegistradaPor') and r.criado_em >= '2026-10-20');

-- o cirurgião manda um recado para a equipe (quem tem recebe_avisos), sobre um paciente dele
create or replace function public.recado_para_equipe(p_paciente_id text, p_texto text) returns int
language plpgsql security definer set search_path = public as $$
declare
  eu    text := public.meu_email();
  nomeq text;
  pnome text;
  a     record;
  n     int := 0;
begin
  select nome into nomeq from perfis where email = eu;
  if nomeq is null then raise exception 'sem acesso'; end if;
  if coalesce(trim(p_texto),'') = '' then raise exception 'recado vazio'; end if;
  if p_paciente_id is not null then
    select dados->>'nome' into pnome from funil_pacientes
     where id = p_paciente_id and (cirurgiao_email = eu or public.eh_admin());
    if not found then raise exception 'paciente não encontrado'; end if;
  end if;
  for a in select email, nome from perfis where papel = 'admin' and recebe_avisos and email <> eu loop
    insert into funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
    values (eu, nomeq, a.email, a.nome, p_paciente_id, pnome, left(p_texto, 4000));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.recado_para_equipe(text,text) from public, anon;
grant execute on function public.recado_para_equipe(text,text) to authenticated;
