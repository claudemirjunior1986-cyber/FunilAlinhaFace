-- Funil Alinha Face — banco do site com login
-- Rode este arquivo inteiro uma vez no SQL Editor do Supabase.
-- Pode rodar de novo sem problema: ele não apaga dados.

-- ============ quem acessa o site ============
create table if not exists public.perfis (
  email  text primary key,
  nome   text not null,
  papel  text not null check (papel in ('admin','cirurgiao'))
);

insert into public.perfis (email, nome, papel) values
  ('alinhaface@gmail.com',          'Claudemir',  'admin'),
  ('acytgiroldo@gmail.com',         'Ana Clara',  'admin'),
  ('camilaguana@gmail.com',         'Camila',     'admin'),
  ('gu.martins00@gmail.com',        'Dr. Gustavo','cirurgiao'),
  ('dr.aptrindadefilho@gmail.com',  'Dr. Afonso', 'cirurgiao')
on conflict (email) do update set nome = excluded.nome, papel = excluded.papel;

-- e-mail de quem está logado, sempre em minúsculas
create or replace function public.meu_email() returns text
language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email','')) $$;

create or replace function public.eh_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfis where email = public.meu_email() and papel = 'admin')
$$;

-- ============ pacientes ============
-- "dados" guarda a ficha inteira do painel (o mesmo formato de antes).
-- "cirurgiao_email" é preenchido sozinho a partir de dados.cirurgiao.
create table if not exists public.funil_pacientes (
  id               text primary key,
  dados            jsonb not null default '{}'::jsonb,
  cirurgiao_email  text,
  atualizado_em    timestamptz not null default now()
);
create index if not exists funil_pacientes_cirurgiao on public.funil_pacientes (cirurgiao_email);

create table if not exists public.funil_encaminhamentos (
  id             text primary key,
  dados          jsonb not null default '{}'::jsonb,
  atualizado_em  timestamptz not null default now()
);

create or replace function public.funil_preenche() returns trigger
language plpgsql as $$
begin
  if tg_table_name = 'funil_pacientes' then
    new.cirurgiao_email := lower(nullif(trim(coalesce(new.dados ->> 'cirurgiao','')),''));
  end if;
  new.atualizado_em := now();
  return new;
end $$;

drop trigger if exists funil_pacientes_preenche on public.funil_pacientes;
create trigger funil_pacientes_preenche before insert or update on public.funil_pacientes
  for each row execute function public.funil_preenche();
drop trigger if exists funil_enc_preenche on public.funil_encaminhamentos;
create trigger funil_enc_preenche before insert or update on public.funil_encaminhamentos
  for each row execute function public.funil_preenche();

-- ============ quem vê o quê ============
alter table public.perfis                enable row level security;
alter table public.funil_pacientes       enable row level security;
alter table public.funil_encaminhamentos enable row level security;

drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (email = public.meu_email() or public.eh_admin());

-- admin (Claudemir e Ana Clara): tudo
drop policy if exists pac_admin on public.funil_pacientes;
create policy pac_admin on public.funil_pacientes for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

-- cirurgião: só lê os pacientes dele. Para registrar a consulta ele usa a função abaixo.
drop policy if exists pac_cirurgiao_ler on public.funil_pacientes;
create policy pac_cirurgiao_ler on public.funil_pacientes for select to authenticated
  using (cirurgiao_email = public.meu_email());

drop policy if exists enc_admin on public.funil_encaminhamentos;
create policy enc_admin on public.funil_encaminhamentos for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

-- ============ o cirurgião registra a consulta ============
-- Só funciona em paciente dele. Avança a etapa (nunca volta uma etapa já mais adiante),
-- grava o resumo e deixa uma linha no histórico.
create or replace function public.registrar_consulta(
  p_id text, p_compareceu boolean, p_pediu_exames boolean, p_resumo text, p_exames text default ''
) returns void
language plpgsql security definer set search_path = public as $$
declare
  r      public.funil_pacientes%rowtype;
  d      jsonb;
  hoje   text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  etapa  text;
  inicio text[] := array['triagem','lead','agendou','compareceu','noshow'];
  nova   text;
  texto  text;
begin
  select * into r from public.funil_pacientes where id = p_id for update;
  if not found or r.cirurgiao_email is distinct from public.meu_email() then
    raise exception 'Paciente não encontrado para este cirurgião';
  end if;

  d := r.dados;
  etapa := coalesce(d ->> 'etapa','lead');

  if not p_compareceu then nova := 'noshow';
  elsif p_pediu_exames then nova := 'exames_sol';
  else nova := 'compareceu';
  end if;

  if etapa = any(inicio) then
    d := jsonb_set(d, '{etapa}', to_jsonb(nova));
    if nova = 'exames_sol' then d := jsonb_set(d, '{dataExames}', to_jsonb(hoje)); end if;
  end if;

  d := d || jsonb_build_object(
    'resumoConsulta', coalesce(p_resumo,''),
    'examesPedidos', coalesce(p_exames,''),
    'consultaCompareceu', p_compareceu,
    'consultaPediuExames', p_pediu_exames,
    'consultaRegistradaEm', to_jsonb(now()),
    'consultaRegistradaPor', public.meu_email(),
    'atualizadoEm', to_jsonb(now())
  );

  texto := case when not p_compareceu then 'Cirurgião: paciente não compareceu'
                when p_pediu_exames then 'Cirurgião: atendeu e pediu exames'
                else 'Cirurgião: atendeu' end;
  if coalesce(p_resumo,'') <> '' then texto := texto || ' — ' || left(p_resumo, 300); end if;

  d := jsonb_set(d, '{historico}',
        coalesce(d -> 'historico','[]'::jsonb) || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', texto)));

  update public.funil_pacientes set dados = d where id = p_id;
end $$;

revoke all on function public.registrar_consulta(text,boolean,boolean,text,text) from public, anon;
grant execute on function public.registrar_consulta(text,boolean,boolean,text,text) to authenticated;

-- ============ atualização ao vivo no painel ============
do $$ begin
  begin alter publication supabase_realtime add table public.funil_pacientes; exception when others then null; end;
  begin alter publication supabase_realtime add table public.funil_encaminhamentos; exception when others then null; end;
end $$;

-- ============ tela de entrada ============
-- A página de login pergunta se o e-mail tem acesso antes de mandar o código,
-- para quem não está na lista receber um aviso claro em vez de um e-mail inútil.
create or replace function public.email_autorizado(p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfis where email = lower(trim(p_email)))
$$;
grant execute on function public.email_autorizado(text) to anon, authenticated;
