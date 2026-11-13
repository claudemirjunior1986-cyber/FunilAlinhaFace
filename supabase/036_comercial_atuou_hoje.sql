-- "Já atuei hoje" do comercial (Joaquim): o caso sai da lista dele no dia em que ele agiu e volta sozinho no dia seguinte.
-- Conta como "agiu hoje" (horário de São Paulo):
--   * mandou mensagem no WhatsApp do paciente pelo funil (funil_whats_envios, por = perfil comercial);
--   * mandou mensagem pelo painel sobre o paciente (cirurgião, Ana ou equipe);
--   * clicou "Já atuei hoje" na ficha (dados.comercialAtuouEm = hoje).
-- Se ele clicar "Voltar para a lista", o caso reaparece no mesmo dia (dados.comercialVoltouEm = hoje).
-- Pode rodar de novo sem problema.

drop function if exists public.comercial_casos();
create function public.comercial_casos()
returns table (id text, dados jsonb, cirurgiao_nome text, cirurgiao_whats text, atualizado_em timestamptz, atuou_hoje boolean)
language plpgsql stable security definer set search_path = public as $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not (public.eh_comercial() or public.eh_admin()) then raise exception 'sem acesso'; end if;
  return query
    select f.id, f.dados, coalesce(p.nome, ''), coalesce(p.whatsapp, ''), f.atualizado_em,
      (coalesce(f.dados->>'comercialVoltouEm','') <> hoje::text) and (
           coalesce(f.dados->>'comercialAtuouEm','') = hoje::text
        or exists (select 1 from funil_recados r
                    where r.paciente_id = f.id and (r.criado_em at time zone 'America/Sao_Paulo')::date = hoje
                      and r.de in (select email from perfis where papel = 'comercial'))
        or exists (select 1 from funil_whats_envios e join funil_whats w on w.chat_id = e.chat_id
                    where length(regexp_replace(coalesce(f.dados->>'telefone',''), '\D', '', 'g')) >= 8
                      and w.tel8 = right(regexp_replace(coalesce(f.dados->>'telefone',''), '\D', '', 'g'), 8)
                      and (e.em at time zone 'America/Sao_Paulo')::date = hoje
                      and e.por in (select email from perfis where papel = 'comercial'))
      )
      from funil_pacientes f
      left join perfis p on p.email = f.cirurgiao_email
     where coalesce(f.dados->>'etapa','') = any(public.etapas_comercial())
       and coalesce(f.dados->>'demo','') <> 'true'
     order by f.atualizado_em desc;
end $$;
revoke all on function public.comercial_casos() from public, anon;
grant execute on function public.comercial_casos() to authenticated;

-- botão "Já atuei hoje" / "Voltar para a lista"
create or replace function public.comercial_atuei(p_paciente_id text, p_voltar boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'); nomeq text;
begin
  if not public.eh_comercial() then raise exception 'sem acesso'; end if;
  select nome into nomeq from perfis where email = public.meu_email();
  update funil_pacientes
     set dados = case when p_voltar
         then jsonb_set(dados, '{comercialVoltouEm}', to_jsonb(hoje))
         else jsonb_set(dados - 'comercialVoltouEm', '{comercialAtuouEm}', to_jsonb(hoje))
                || jsonb_build_object('historico',
                     (case when jsonb_typeof(dados->'historico') = 'array' then dados->'historico' else '[]'::jsonb end)
                     || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', coalesce(nomeq,'Comercial') || ' (comercial) atuou no caso hoje')))
         end
   where id = p_paciente_id and coalesce(dados->>'etapa','') = any(public.etapas_comercial());
end $$;
revoke all on function public.comercial_atuei(text, boolean) from public, anon;
grant execute on function public.comercial_atuei(text, boolean) to authenticated;
