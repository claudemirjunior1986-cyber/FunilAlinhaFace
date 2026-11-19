-- Link do Google Maps junto do endereço do presencial na confirmação que vai para o paciente.
create or replace function public.link_maps(t text) returns text
language sql immutable as $$
  select 'https://www.google.com/maps/search/?api=1&query='
    || regexp_replace(regexp_replace(trim(regexp_replace(coalesce(t,''), '[()#&?]', ' ', 'g')), '\s+', '+', 'g'), '\++', '+', 'g')
$$;

do $$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'avisa_consulta_paciente' and p.prokind = 'f';
  if position('link_maps' in def) = 0 then
    def := replace(def,
      $a$then chr(10) || '📍 ' || (n->>'local') else '' end$a$,
      $b$then chr(10) || '📍 ' || (n->>'local') || chr(10) || '🗺️ ' || link_maps(n->>'local') else '' end$b$);
    if position('link_maps' in def) = 0 then raise exception 'trecho não encontrado'; end if;
    execute def;
  end if;
end $$;

select link_maps('Mooca (Av. Paes de Barros, 3399)') exemplo,
       position('link_maps' in pg_get_functiondef('public.avisa_consulta_paciente()'::regprocedure)) > 0 aplicado,
       (select json_agg(distinct dados->>'local') from funil_pacientes where dados->>'modalidade'='Presencial') locais;
