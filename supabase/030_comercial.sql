-- Relatório comercial para o gerente comercial (Joaquim):
--  * funil_config guarda o WhatsApp dele e a chave do link secreto da página comercial.html (abre sem login).
--  * Terças e quintas às 8h (São Paulo) a função "whats" (acao comercial_resumo) manda o resumo para ele.
-- Pode rodar de novo sem problema (a chave do link só é criada na primeira vez).
create table if not exists public.funil_config (k text primary key, v text);
alter table public.funil_config enable row level security;
drop policy if exists config_admin on public.funil_config;
create policy config_admin on public.funil_config for select using (public.eh_admin());

insert into public.funil_config (k, v) values ('comercial_whatsapp', '5511981680761')
on conflict (k) do update set v = excluded.v;
insert into public.funil_config (k, v) values ('comercial_chave', replace(gen_random_uuid()::text, '-', ''))
on conflict (k) do nothing;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'comercial-resumo') then perform cron.unschedule('comercial-resumo'); end if;
end $$;
select cron.schedule('comercial-resumo', '3 11 * * 2,4', $$
  select net.http_post(
    url := 'https://odamgyzklsndepklmicl.supabase.co/functions/v1/whats',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"acao":"comercial_resumo"}'::jsonb)
$$);
