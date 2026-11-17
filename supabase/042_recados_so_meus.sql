-- Recados "só os meus" para o Claudemir (17/11):
-- recados gerais para a equipe (cirurgião -> equipe, resposta à equipe, comercial -> equipe) deixam de ir para
-- quem tem perfis.recebe_registros = false (Claudemir). Ele recebe só o que for mandado direto para ele
-- (e é avisado no WhatsApp, 041). Fecha também os recados antigos dele que eram automáticos ou cópia de recado geral.
-- Pode rodar de novo sem problema.

do $$
declare f text; d text;
begin
  foreach f in array array['public.recado_para_equipe(text,text)', 'public.responder_equipe(text,text)', 'public.comercial_recado(text,text)'] loop
    begin
      d := pg_get_functiondef(f::regprocedure);
      if position('recebe_registros' in d) = 0 then
        d := replace(d, 'and recebe_avisos and email <> eu loop', 'and recebe_avisos and recebe_registros and email <> eu loop');
        execute d;
      end if;
    exception when undefined_function then null;
    end;
  end loop;
  -- mensagem do comercial com destino "equipe"
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and pg_get_functiondef(p.oid) like '%p_destino = ''equipe''    and p.papel = ''admin'' and p.recebe_avisos)%' loop
    d := pg_get_functiondef(f::regprocedure);
    d := replace(d, 'p_destino = ''equipe''    and p.papel = ''admin'' and p.recebe_avisos)', 'p_destino = ''equipe''    and p.papel = ''admin'' and p.recebe_avisos and p.recebe_registros)');
    execute d;
  end loop;
end $$;

-- fecha os antigos do Claudemir: registros automáticos e cópias de recado geral (o mesmo recado foi para outra pessoa)
update public.funil_recados r
   set feito_em = now()
 where r.para = 'alinhaface@gmail.com' and r.feito_em is null
   and (r.texto ~ '^(\(registro corrigido\) )?(Atendeu|Paciente NÃO compareceu)'
        or exists (select 1 from public.funil_recados o
                    where o.id <> r.id and o.para <> r.para and o.de = r.de
                      and o.texto = r.texto and o.paciente_id is not distinct from r.paciente_id));
