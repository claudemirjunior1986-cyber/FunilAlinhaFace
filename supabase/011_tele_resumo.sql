-- Resumo por IA da teleconsulta: transcrição acumulada por trechos de áudio.
alter table public.funil_teleconsultas add column if not exists transcricao text;
alter table public.funil_teleconsultas add column if not exists resumo_em timestamptz;

-- os trechos de áudio (bucket "anexos", pasta tele/) são apagados logo depois de transcritos
drop policy if exists anexos_apagar_tele on storage.objects;
create policy anexos_apagar_tele on storage.objects for delete to authenticated
  using (bucket_id = 'anexos' and name like 'tele/%' and (owner_id = auth.uid()::text or public.eh_admin()));
