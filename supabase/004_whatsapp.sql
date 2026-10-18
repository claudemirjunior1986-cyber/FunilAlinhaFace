-- WhatsApp dentro do site: lista das conversas da Bia (GPT Maker), atualizada pela
-- função "whats" (supabase/functions/whats). Só administradores enxergam.
create table if not exists public.funil_whats (
  chat_id      text primary key,
  tel8         text,
  telefone     text,
  nome         text,
  foto         text,
  ultima       text,
  ultima_de    text,          -- 'user' = paciente falou por último (aguardando resposta)
  ultima_em    timestamptz,
  humano       boolean not null default false,   -- true = equipe assumiu, a Bia não responde
  nao_lidas    int not null default 0,
  criado_em    timestamptz,
  visto_em     timestamptz,   -- última vez que alguém abriu a conversa no site
  visto_por    text,
  atualizado_em timestamptz not null default now()
);
create index if not exists funil_whats_tel8 on public.funil_whats (tel8);
create index if not exists funil_whats_ultima on public.funil_whats (ultima_em desc);

alter table public.funil_whats enable row level security;
drop policy if exists whats_admin on public.funil_whats;
create policy whats_admin on public.funil_whats for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

do $$ begin
  begin alter publication supabase_realtime add table public.funil_whats; exception when others then null; end;
end $$;
