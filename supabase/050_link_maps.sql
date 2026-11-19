-- Link do Google Maps junto do endereço do presencial na confirmação que vai para o paciente.
create or replace function public.link_maps(t text) returns text
language sql immutable as $$
  -- o campo "local" da ficha guarda só o bairro; aqui vira o endereço completo do consultório.
  -- Sem endereço conhecido (ex.: Moema, Porto Alegre do Dr. Gustavo) não manda link.
  select 'https://www.google.com/maps/search/?api=1&query=' || e
    from (select case
      when t ~* 'vila mariana|francisco cruz' and t !~* '^mooca' then 'R.+Francisco+Cruz,+131+-+Vila+Mariana,+São+Paulo+-+SP'
      when t ~* 'mooca|paes de barros' then 'Av.+Paes+de+Barros,+3399+-+Mooca,+São+Paulo+-+SP'
      when t ~* 'alfazema|caminho das [áa]rvores|salvador' then 'R.+da+Alfazema,+761+-+Caminho+das+Árvores,+Salvador+-+BA'
    end e) x where e is not null
$$;

do $$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'avisa_consulta_paciente' and p.prokind = 'f';
  -- primeira versão deste arquivo (sem coalesce): corrige
  def := replace(def,
    $a$|| chr(10) || '🗺️ ' || link_maps(n->>'local') else '' end$a$,
    $b$|| coalesce(chr(10) || '🗺️ ' || link_maps(n->>'local'), '') else '' end$b$);
  if position('link_maps' in def) = 0 then
    def := replace(def,
      $a$then chr(10) || '📍 ' || (n->>'local') else '' end$a$,
      $b$then chr(10) || '📍 ' || (n->>'local') || coalesce(chr(10) || '🗺️ ' || link_maps(n->>'local'), '') else '' end$b$);
  end if;
  if position('coalesce(chr(10) || ''🗺️ '' || link_maps' in def) = 0 then raise exception 'trecho não encontrado'; end if;
  execute def;
end $$;

select link_maps('Mooca') a, link_maps('Moema') b, link_maps('Vila Mariana') c,
       position('coalesce(chr(10) || ''🗺️ '' || link_maps' in pg_get_functiondef('public.avisa_consulta_paciente()'::regprocedure)) > 0 aplicado,
       (select json_agg(distinct dados->>'local') from funil_pacientes where dados->>'modalidade'='Presencial') locais;
