-- Recados também para os cirurgiões (ex.: "chegou o exame da paciente, pode avaliar?"),
-- com anexo opcional (exame em PDF/imagem). Cada um só vê o que mandou ou recebeu.
alter table public.funil_recados add column if not exists anexo      text;  -- caminho no bucket "anexos"
alter table public.funil_recados add column if not exists anexo_nome text;

-- quem está na lista de acesso do site (admin ou cirurgião)
create or replace function public.tem_perfil() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfis where email = public.meu_email())
$$;
create or replace function public.eh_admin_email(p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfis where email = lower(p_email) and papel = 'admin')
$$;

drop policy if exists recados_ler on public.funil_recados;
create policy recados_ler on public.funil_recados for select to authenticated
  using (public.tem_perfil() and (de = public.meu_email() or para = public.meu_email()));

-- administrador manda para qualquer um da lista; cirurgião só responde para administradores
drop policy if exists recados_criar on public.funil_recados;
create policy recados_criar on public.funil_recados for insert to authenticated
  with check (de = public.meu_email() and (public.eh_admin() or public.eh_admin_email(para)));

drop policy if exists recados_atualizar on public.funil_recados;
create policy recados_atualizar on public.funil_recados for update to authenticated
  using (public.tem_perfil() and (para = public.meu_email() or de = public.meu_email()))
  with check (public.tem_perfil() and (para = public.meu_email() or de = public.meu_email()));

drop policy if exists recados_apagar on public.funil_recados;
create policy recados_apagar on public.funil_recados for delete to authenticated
  using (public.tem_perfil() and de = public.meu_email());

-- anexos dos recados: bucket privado; abre quem mandou ou recebeu o recado
insert into storage.buckets (id, name, public, file_size_limit)
values ('anexos', 'anexos', false, 26214400)
on conflict (id) do nothing;

drop policy if exists anexos_enviar on storage.objects;
create policy anexos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'anexos' and public.tem_perfil());
drop policy if exists anexos_ler on storage.objects;
create policy anexos_ler on storage.objects for select to authenticated
  using (bucket_id = 'anexos' and (
    public.eh_admin()
    or owner_id = auth.uid()::text
    or exists (select 1 from public.funil_recados r
               where r.anexo = storage.objects.name
                 and (r.para = public.meu_email() or r.de = public.meu_email()))
  ));
