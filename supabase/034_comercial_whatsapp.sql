-- WhatsApp da Bia para o comercial (Joaquim), dentro do funil.
--  * Ele lê, responde, assume e devolve para a Bia SOMENTE as conversas dos pacientes que ele já enxerga
--    (consulta agendada em diante). Leads e demais conversas continuam só com a Ana/Claudemir.
--  * A função "whats" confere cada pedido com comercial_pode_chat / comercial_pode_tel antes de agir.
-- Pode rodar de novo sem problema.

create or replace function public.comercial_pode_tel(p_tel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.eh_comercial()
     and length(regexp_replace(coalesce(p_tel,''), '\D', '', 'g')) >= 8
     and exists(
       select 1 from funil_pacientes f
        where coalesce(f.dados->>'etapa','') = any(public.etapas_comercial())
          and coalesce(f.dados->>'demo','') <> 'true'
          and right(regexp_replace(coalesce(f.dados->>'telefone',''), '\D', '', 'g'), 8)
            = right(regexp_replace(p_tel, '\D', '', 'g'), 8))
$$;
revoke all on function public.comercial_pode_tel(text) from public, anon;
grant execute on function public.comercial_pode_tel(text) to authenticated;

create or replace function public.comercial_pode_chat(p_chat text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select public.comercial_pode_tel(w.tel8) from funil_whats w where w.chat_id = p_chat), false)
$$;
revoke all on function public.comercial_pode_chat(text) from public, anon;
grant execute on function public.comercial_pode_chat(text) to authenticated;

-- conversas dos pacientes do comercial (para a lista e o status "Bia / equipe")
create or replace function public.comercial_whats()
returns table (chat_id text, tel8 text, nome text, ultima text, ultima_de text, ultima_em timestamptz, humano boolean, nao_lidas int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.eh_comercial() or public.eh_admin()) then raise exception 'sem acesso'; end if;
  return query
    select w.chat_id, w.tel8, w.nome, w.ultima, w.ultima_de, w.ultima_em, w.humano, w.nao_lidas
      from funil_whats w
     where w.tel8 in (
       select right(regexp_replace(coalesce(f.dados->>'telefone',''), '\D', '', 'g'), 8)
         from funil_pacientes f
        where coalesce(f.dados->>'etapa','') = any(public.etapas_comercial())
          and coalesce(f.dados->>'demo','') <> 'true')
     order by w.ultima_em desc nulls last;
end $$;
revoke all on function public.comercial_whats() from public, anon;
grant execute on function public.comercial_whats() to authenticated;
