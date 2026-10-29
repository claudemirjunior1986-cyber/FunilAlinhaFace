-- Toda conversa nova do WhatsApp vira ficha na hora (etapa "A classificar"), sem esperar a sincronização das 8h.
-- 1) A cada 2 minutos o agendador pede para a função "whats" (acao sincronizar) trazer as conversas recentes do GPT Maker.
-- 2) Quando entra (ou é atualizada) uma conversa recente cujo telefone ainda não tem ficha, este gatilho cria a ficha.
--    A sincronização das 8h continua: ela reconhece o telefone e só completa a ficha (nome, origem, queixa…).
-- Pode rodar de novo sem problema.

create or replace function public.ficha_da_conversa() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t8   text := nullif(regexp_replace(coalesce(new.tel8,''), '\D', '', 'g'), '');
  hoje text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYYMMDD');
  lid  boolean := coalesce(new.telefone,'') like '%@lid%';
begin
  if t8 is null or length(t8) < 8 then return new; end if;
  -- só conversas que começaram nos últimos 3 dias (não ressuscita conversa antiga)
  if new.criado_em is null or new.criado_em < now() - interval '3 days' then return new; end if;
  -- já tem ficha, está nos ignorados ou é alguém da equipe/cirurgião
  if exists (select 1 from funil_pacientes p
              where right(regexp_replace(coalesce(p.dados->>'telefone',''), '\D', '', 'g'), 8) = t8) then return new; end if;
  if exists (select 1 from funil_ignorados where id = 'k' || t8) then return new; end if;
  if exists (select 1 from perfis where right(regexp_replace(coalesce(whatsapp,''), '\D', '', 'g'), 8) = t8) then return new; end if;

  insert into funil_pacientes (id, dados) values (
    'gm' || hoje || '-' || t8,
    jsonb_build_object(
      'nome', coalesce(nullif(trim(new.nome),''), 'Sem nome'),
      'telefone', case when lid then new.telefone else regexp_replace(coalesce(new.telefone,''), '\D', '', 'g') end,
      'etapa', 'triagem',
      'opme', 0, 'valorProposta', 0, 'local', 'Online', 'pagamento', 'A definir',
      'tratamento', 'A definir',
      'observacoes', '⚠ ficha criada sozinha quando a conversa chegou no WhatsApp; nome do contato'
                     || case when lid then '; ⚠ telefone não identificado (@lid)' else '' end,
      'ultimaMensagem', left(coalesce(new.ultima,''), 120),
      'ultimaMensagemEm', new.ultima_em,
      'fonte', 'WhatsApp (na hora)',
      'criadoEm', coalesce(new.criado_em, now()),
      'atualizadoEm', now(),
      'cirurgiao', '',
      'historico', jsonb_build_array(jsonb_build_object('data', to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD'),
                                                        'texto', 'Entrou pelo WhatsApp (ficha criada automaticamente)'))
    ))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists ficha_da_conversa on public.funil_whats;
create trigger ficha_da_conversa after insert or update of ultima_em, tel8 on public.funil_whats
  for each row execute function public.ficha_da_conversa();

-- agendador: a cada 2 minutos traz as conversas recentes do GPT Maker
do $$ begin
  if exists (select 1 from cron.job where jobname = 'whats-sincronizar') then perform cron.unschedule('whats-sincronizar'); end if;
end $$;
select cron.schedule('whats-sincronizar', '*/2 * * * *', $$
  select net.http_post(
    url := 'https://odamgyzklsndepklmicl.supabase.co/functions/v1/whats',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"acao":"sincronizar"}'::jsonb)
$$);

-- conversas que já chegaram nos últimos 3 dias e ainda não têm ficha: cria agora
update public.funil_whats set atualizado_em = now() where criado_em >= now() - interval '3 days';
update public.funil_whats set ultima_em = ultima_em where criado_em >= now() - interval '3 days';
