-- Recados separados (17/11):
-- 1) Os recados automáticos de "consulta registrada" deixam de ir para o Claudemir (ele já recebe o resumo
--    no WhatsApp, 039). Só a Ana continua recebendo. Controle: perfis.recebe_registros.
-- 2) Quando alguém manda um recado para o Claudemir (cirurgião, Ana, comercial...), ele é avisado no WhatsApp.
--    Controle: funil_config k='diretor_email' (quem é o diretor) e k='diretor_whatsapp' (número).
-- Pode rodar de novo sem problema.

alter table public.perfis add column if not exists recebe_registros boolean not null default true;
update public.perfis set recebe_registros = false where email = 'alinhaface@gmail.com';

-- avisa_registro_consulta (009) passa a respeitar recebe_registros
do $$
declare d text;
begin
  d := pg_get_functiondef('public.avisa_registro_consulta()'::regprocedure);
  if position('recebe_registros' in d) = 0 then
    d := replace(d, 'where papel = ''admin'' and recebe_avisos loop', 'where papel = ''admin'' and recebe_avisos and recebe_registros loop');
    execute d;
  end if;
end $$;

insert into public.funil_config (k, v) values ('diretor_email', 'alinhaface@gmail.com') on conflict (k) do nothing;

create or replace function public.recado_avisa_diretor() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  dir text; tel text; txt text;
begin
  select v into dir from funil_config where k = 'diretor_email';
  if dir is null or lower(new.para) <> lower(dir) or lower(coalesce(new.de,'')) = lower(dir) then return new; end if;
  select v into tel from funil_config where k = 'diretor_whatsapp';
  if coalesce(tel,'') = '' then return new; end if;
  txt := '📩 *Recado para você no funil*' || chr(10)
    || '*De:* ' || coalesce(nullif(new.de_nome,''), new.de, 'alguém') || chr(10)
    || coalesce('*Paciente:* ' || nullif(new.paciente_nome,'') || chr(10), '')
    || chr(10) || left(coalesce(new.texto,''), 1200)
    || case when new.anexo is not null then chr(10) || '(com anexo)' else '' end
    || chr(10) || chr(10) || 'Responder no funil: https://funil-alinhaface.pages.dev/painel.html';
  insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
  values ('diretor', tel, new.paciente_id, 'alerta', txt);
  return new;
end $$;
drop trigger if exists zz_recado_avisa_diretor on public.funil_recados;
create trigger zz_recado_avisa_diretor after insert on public.funil_recados
  for each row execute function public.recado_avisa_diretor();
