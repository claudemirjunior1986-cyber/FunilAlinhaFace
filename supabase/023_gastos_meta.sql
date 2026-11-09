-- Gasto com anúncios do Meta (Facebook/Instagram), por dia e campanha.
-- A função "whats" (acao gastos_meta) busca no Meta e grava aqui; o agendador roda de 3 em 3 horas.
-- O painel (Relatórios) usa para custo por lead, por consulta e por cirurgia. Pode rodar de novo sem problema.
create table if not exists public.funil_gastos (
  data          date not null,
  conta         text not null,
  campanha_id   text not null,
  campanha      text,
  valor         numeric(12,2) not null default 0,
  impressoes    bigint not null default 0,
  cliques       bigint not null default 0,
  conversas     int not null default 0,     -- conversas iniciadas no WhatsApp/Messenger pelo anúncio
  leads         int not null default 0,     -- cadastros de formulário do anúncio
  atualizado_em timestamptz not null default now(),
  primary key (data, campanha_id)
);
alter table public.funil_gastos enable row level security;
drop policy if exists gastos_admin_ler on public.funil_gastos;
create policy gastos_admin_ler on public.funil_gastos for select using (public.eh_admin());

-- agendador: últimos 3 dias a cada 3 horas (o Meta ainda ajusta os números dos dias recentes)
do $$ begin
  if exists (select 1 from cron.job where jobname = 'gastos-meta') then perform cron.unschedule('gastos-meta'); end if;
end $$;
select cron.schedule('gastos-meta', '17 */3 * * *', $$
  select net.http_post(
    url := 'https://odamgyzklsndepklmicl.supabase.co/functions/v1/whats',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"acao":"gastos_meta","dias":3}'::jsonb)
$$);
