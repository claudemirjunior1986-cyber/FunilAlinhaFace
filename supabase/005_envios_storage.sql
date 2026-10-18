-- Arquivos que o site envia pelo WhatsApp (voucher, fotos, PDFs).
-- Bucket privado: o GPT Maker recebe só um link assinado que expira em 1 hora.
insert into storage.buckets (id, name, public, file_size_limit)
values ('envios', 'envios', false, 16777216)
on conflict (id) do nothing;

drop policy if exists envios_admin_inserir on storage.objects;
create policy envios_admin_inserir on storage.objects for insert to authenticated
  with check (bucket_id = 'envios' and public.eh_admin());
drop policy if exists envios_admin_ler on storage.objects;
create policy envios_admin_ler on storage.objects for select to authenticated
  using (bucket_id = 'envios' and public.eh_admin());
