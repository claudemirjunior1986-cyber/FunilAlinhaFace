-- Quem da equipe mandou cada mensagem pelo site (o GPT Maker registra tudo com o nome
-- do dono da chave da API, então o site guarda o nome certo aqui).
create table if not exists public.funil_whats_envios (
  id        bigserial primary key,
  chat_id   text not null,
  texto     text,
  por       text,
  por_nome  text,
  em        timestamptz not null default now()
);
create index if not exists funil_whats_envios_chat on public.funil_whats_envios (chat_id, em desc);
alter table public.funil_whats_envios enable row level security;
drop policy if exists whats_envios_admin on public.funil_whats_envios;
create policy whats_envios_admin on public.funil_whats_envios for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());
