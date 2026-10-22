-- Teleconsulta dentro do site: cada sala é uma linha aqui. O link do paciente leva o id
-- (uuid aleatório, impossível de adivinhar). O paciente não acessa o banco: a chamada vai
-- direto entre os aparelhos, e o Supabase Realtime só faz a "apresentação" entre eles.
create table if not exists public.funil_teleconsultas (
  id               uuid primary key default gen_random_uuid(),
  paciente_id      text not null,
  paciente_nome    text,
  cirurgiao        text,
  criada_por       text not null default public.meu_email(),
  criada_em        timestamptz not null default now(),
  consentimento    boolean,          -- paciente autorizou gravar o áudio para o resumo
  consentimento_em timestamptz,
  inicio           timestamptz,      -- primeira vez que os dois se conectaram
  fim              timestamptz,
  resumo_ia        text
);
create index if not exists funil_tele_paciente on public.funil_teleconsultas (paciente_id, criada_em desc);

alter table public.funil_teleconsultas enable row level security;
drop policy if exists tele_ler on public.funil_teleconsultas;
create policy tele_ler on public.funil_teleconsultas for select to authenticated
  using (public.eh_admin() or cirurgiao = public.meu_email());
drop policy if exists tele_criar on public.funil_teleconsultas;
create policy tele_criar on public.funil_teleconsultas for insert to authenticated
  with check (public.eh_admin() or (cirurgiao = public.meu_email() and exists (
    select 1 from public.funil_pacientes p where p.id = paciente_id and p.cirurgiao_email = public.meu_email())));
drop policy if exists tele_atualizar on public.funil_teleconsultas;
create policy tele_atualizar on public.funil_teleconsultas for update to authenticated
  using (public.eh_admin() or cirurgiao = public.meu_email())
  with check (public.eh_admin() or cirurgiao = public.meu_email());
