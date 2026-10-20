-- Recados internos da equipe (orientações do Claudemir para a Ana Clara, etc.).
-- Só quem mandou e quem recebeu enxergam cada recado. O paciente nunca vê.
create table if not exists public.funil_recados (
  id            bigserial primary key,
  de            text not null default public.meu_email(),
  de_nome       text,
  para          text not null,
  para_nome     text,
  paciente_id   text,
  paciente_nome text,
  texto         text not null check (length(texto) between 1 and 4000),
  responde_a    bigint references public.funil_recados(id) on delete set null,
  criado_em     timestamptz not null default now(),
  lido_em       timestamptz,
  feito_em      timestamptz
);
create index if not exists funil_recados_para on public.funil_recados (para, feito_em);
create index if not exists funil_recados_paciente on public.funil_recados (paciente_id);

alter table public.funil_recados enable row level security;
drop policy if exists recados_ler on public.funil_recados;
create policy recados_ler on public.funil_recados for select to authenticated
  using (public.eh_admin() and (de = public.meu_email() or para = public.meu_email()));
drop policy if exists recados_criar on public.funil_recados;
create policy recados_criar on public.funil_recados for insert to authenticated
  with check (public.eh_admin() and de = public.meu_email());
-- quem recebe marca como lido/feito; quem mandou pode apagar
drop policy if exists recados_atualizar on public.funil_recados;
create policy recados_atualizar on public.funil_recados for update to authenticated
  using (public.eh_admin() and (para = public.meu_email() or de = public.meu_email()))
  with check (public.eh_admin() and (para = public.meu_email() or de = public.meu_email()));
drop policy if exists recados_apagar on public.funil_recados;
create policy recados_apagar on public.funil_recados for delete to authenticated
  using (public.eh_admin() and de = public.meu_email());

do $$ begin
  begin alter publication supabase_realtime add table public.funil_recados; exception when others then null; end;
end $$;
