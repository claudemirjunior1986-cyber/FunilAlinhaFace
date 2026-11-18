-- 047: o aviso de consulta ao cirurgião (nova, remarcada e lembrete de 15 min) passa a trazer o celular do paciente,
-- com link do WhatsApp, para o cirurgião não precisar abrir a ficha (sugestão do Dr. Gustavo, 18/11).
-- Pode rodar de novo sem problema.

create or replace function public.tel_paciente(d jsonb) returns text
language plpgsql immutable as $$
declare
  t text := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');
  ddd text; num text;
begin
  if coalesce(d->>'telefone','') like '%@lid%' or length(t) < 10 then return null; end if;
  if length(t) in (10, 11) then t := '55' || t; end if;
  if left(t, 2) = '55' and length(t) in (12, 13) then
    ddd := substr(t, 3, 2); num := substr(t, 5);
    return 'WhatsApp: (' || ddd || ') ' || left(num, length(num) - 4) || '-' || right(num, 4) || ' · https://wa.me/' || t;
  end if;
  return 'WhatsApp: +' || t || ' · https://wa.me/' || t;
end $$;

do $$
declare d text;
begin
  -- nova / remarcada
  d := pg_get_functiondef('public.avisa_consulta_cirurgiao()'::regprocedure);
  if position('tel_paciente' in d) = 0 then
    d := replace(d, $r$'Paciente: ' || nome || chr(10) || consulta_texto(n) ||$r$,
                    $r$'Paciente: ' || nome || chr(10) || coalesce(tel_paciente(n) || chr(10), '') || consulta_texto(n) ||$r$);
    if position('tel_paciente' in d) = 0 then raise exception 'avisa_consulta_cirurgiao: trecho não encontrado'; end if;
    execute d;
  end if;
  -- lembrete de 15 min ao cirurgião
  d := pg_get_functiondef('public.gerar_lembretes()'::regprocedure);
  if position('tel_paciente' in d) = 0 then
    d := replace(d, $r$'Paciente: ' || coalesce(nullif(trim(d->>'nome'),''), 'Paciente') || chr(10)$r$,
                    $r$'Paciente: ' || coalesce(nullif(trim(d->>'nome'),''), 'Paciente') || chr(10) || coalesce(tel_paciente(d) || chr(10), '')$r$);
    if position('tel_paciente' in d) = 0 then raise exception 'gerar_lembretes: trecho não encontrado'; end if;
    execute d;
  end if;
end $$;
