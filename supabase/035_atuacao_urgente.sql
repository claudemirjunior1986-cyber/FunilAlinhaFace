-- "Atuação urgente" para o comercial (Joaquim): conversas especiais do WhatsApp que pedem a atuação dele.
--  * A função "whats" (a cada 2 min) marca sozinha quando o paciente:
--      - manda foto ou arquivo (ex.: foto do exame);
--      - fala de plano de saúde / convênio / cobertura / reembolso;
--      - fala de resultado de exame / laudo;
--      - pergunta valor ou diz que quer operar.
--  * A Ana (ou o Claudemir) também marca na mão, no WhatsApp do painel: botão "⚡ Urgente p/ Joaquim".
--  * Cada marcação vira um alerta do tipo urgente_comercial (uma por conversa enquanto aberta),
--    manda WhatsApp para o Joaquim e aparece em vermelho no topo da tela dele até ele clicar "Resolvido".
--  * Enquanto a marcação está aberta, o Joaquim pode ler e responder essa conversa mesmo que seja um lead.
-- Pode rodar de novo sem problema.

-- 1) conversa marcada como urgente também pode ser aberta pelo comercial
create or replace function public.comercial_pode_chat(p_chat text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.eh_comercial() and (
       coalesce((select public.comercial_pode_tel(w.tel8) from funil_whats w where w.chat_id = p_chat), false)
    or exists(select 1 from funil_alertas a where a.tipo = 'urgente_comercial' and a.chat_id = p_chat and a.resolvido_em is null))
$$;
revoke all on function public.comercial_pode_chat(text) from public, anon;
grant execute on function public.comercial_pode_chat(text) to authenticated;

-- 2) lista de urgentes abertos (para a tela do comercial)
create or replace function public.comercial_urgentes()
returns table (id bigint, criado_em timestamptz, titulo text, detalhe text, chat_id text, nome text, telefone text,
               humano boolean, ultima text, ultima_de text, ultima_em timestamptz, paciente_id text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.eh_comercial() or public.eh_admin()) then raise exception 'sem acesso'; end if;
  return query
    select a.id, a.criado_em, a.titulo, a.detalhe, a.chat_id, coalesce(w.nome, ''), coalesce(w.telefone, ''),
           coalesce(w.humano, false), w.ultima, w.ultima_de, w.ultima_em,
           (select f.id from funil_pacientes f
             where w.tel8 is not null
               and right(regexp_replace(coalesce(f.dados->>'telefone',''), '\D', '', 'g'), 8) = w.tel8
               and coalesce(f.dados->>'etapa','') = any(public.etapas_comercial())
               and coalesce(f.dados->>'demo','') <> 'true'
             limit 1)
      from funil_alertas a
      left join funil_whats w on w.chat_id = a.chat_id
     where a.tipo = 'urgente_comercial' and a.resolvido_em is null
     order by a.criado_em desc;
end $$;
revoke all on function public.comercial_urgentes() from public, anon;
grant execute on function public.comercial_urgentes() to authenticated;

-- 3) o comercial (ou admin) dá baixa
create or replace function public.comercial_resolver_urgente(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.eh_comercial() or public.eh_admin()) then raise exception 'sem acesso'; end if;
  update funil_alertas set resolvido_em = now(), resolvido_por = public.meu_email()
   where id = p_id and tipo = 'urgente_comercial' and resolvido_em is null;
end $$;
revoke all on function public.comercial_resolver_urgente(bigint) from public, anon;
grant execute on function public.comercial_resolver_urgente(bigint) to authenticated;

-- 4) a Ana / o Claudemir marcam na mão pelo WhatsApp do painel
create or replace function public.marcar_urgente_comercial(p_chat text, p_motivo text default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare nm text; n int;
begin
  if not public.eh_admin() then raise exception 'sem acesso'; end if;
  select coalesce(nullif(nome,''), telefone, 'Paciente') into nm from funil_whats where chat_id = p_chat;
  insert into funil_alertas (tipo, chave, titulo, detalhe, chat_id)
  values ('urgente_comercial', 'urg:' || p_chat,
          '⚡ ' || coalesce(nm, 'Paciente') || ' — ' || coalesce(nullif(trim(p_motivo),''), 'a equipe pediu sua atuação'),
          (select nome from perfis where email = public.meu_email()) || ' marcou como urgente', p_chat)
  on conflict (chave) do nothing;
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.marcar_urgente_comercial(text, text) from public, anon;
grant execute on function public.marcar_urgente_comercial(text, text) to authenticated;

-- 5) cada urgente novo manda WhatsApp para o Joaquim (fila de avisos, sai pelo número da Alinha Face)
create or replace function public.avisa_urgente_comercial() returns trigger
language plpgsql security definer set search_path = public as $$
declare tel text;
begin
  if new.tipo <> 'urgente_comercial' then return new; end if;
  select coalesce((select whatsapp from perfis where papel = 'comercial' and coalesce(whatsapp,'') <> '' limit 1),
                  (select v from funil_config where k = 'comercial_whatsapp')) into tel;
  if coalesce(tel,'') = '' then return new; end if;
  insert into funil_avisos_medico (email, telefone, tipo, texto)
  values ('comercial@alinhaface', tel, 'alerta',
          '⚡ *Atuação urgente — Alinha Face*' || chr(10) || new.titulo
          || coalesce(chr(10) || left(new.detalhe, 200), '')
          || chr(10) || chr(10) || 'Abra o funil para continuar a conversa:' || chr(10) || 'https://funil-alinhaface.pages.dev/comercial.html');
  return new;
end $$;
drop trigger if exists avisa_urgente_comercial on public.funil_alertas;
create trigger avisa_urgente_comercial after insert on public.funil_alertas
  for each row execute function public.avisa_urgente_comercial();

-- 6) os dois exemplos do Claudemir (12/11/2026) já entram como urgentes
insert into public.funil_alertas (tipo, chave, titulo, detalhe, chat_id)
select 'urgente_comercial', 'urg:' || chat_id, '⚡ ' || coalesce(nullif(nome,''), telefone) || ' — falou do plano de saúde (já respondemos que cobre)',
       'Marcado pelo Claudemir', chat_id
  from public.funil_whats where tel8 = '95560111'
on conflict (chave) do nothing;
insert into public.funil_alertas (tipo, chave, titulo, detalhe, chat_id)
select 'urgente_comercial', 'urg:' || chat_id, '⚡ ' || coalesce(nullif(nome,''), telefone) || ' — mandou foto do exame, continuar a conversa',
       'Marcado pelo Claudemir', chat_id
  from public.funil_whats where tel8 = '91002017'
on conflict (chave) do nothing;
