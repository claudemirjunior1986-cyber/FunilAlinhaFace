-- 053: pesquisa de opinião em UMA mensagem, já com o link do Google (bom ou ruim, a pessoa avalia).
-- Se a equipe já tiver perguntado como foi a consulta, a função "whats" troca o texto por só o pedido + link.
do $$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'pedir_opiniao' and p.prokind = 'f';
  if position('g.page' in def) = 0 then
    def := replace(def,
      $a$|| ' ' || quando || '? Sua opinião é muito importante para nós.');$a$,
      $b$|| ' ' || quando || '? Se puder, deixe sua opinião no Google, leva 1 minuto e ajuda muito outros pacientes: https://g.page/r/CQ179zbf70_VEAI/review 💙');$b$);
    if position('g.page' in def) = 0 then raise exception 'trecho não encontrado'; end if;
    execute def;
  end if;
end $$;
select position('g.page' in pg_get_functiondef('public.pedir_opiniao()'::regprocedure)) > 0 aplicado;
