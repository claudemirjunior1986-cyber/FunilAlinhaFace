-- Mensagens do comercial (Joaquim) dentro do painel, no lugar do WhatsApp:
--  * "Falar com o cirurgião" -> recado na área do cirurgião (aba "Avisos da equipe" do medico.html).
--  * "Falar com a Ana"       -> recado no painel da Ana Clara.
--  * "Equipe"                -> recado para o Claudemir e a Ana (como antes).
--  Tudo fica anotado no histórico da ficha. O cirurgião e a Ana podem responder ao Joaquim pelo painel.
-- Pode rodar de novo sem problema.

create or replace function public.eh_comercial_email(p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfis where email = lower(p_email) and papel = 'comercial')
$$;

-- quem não é admin (cirurgião) pode responder para administradores e também para o comercial
drop policy if exists recados_criar on public.funil_recados;
create policy recados_criar on public.funil_recados for insert to authenticated
  with check (de = public.meu_email() and (public.eh_admin() or public.eh_admin_email(para) or public.eh_comercial_email(para)));

create or replace function public.comercial_mensagem(p_paciente_id text, p_destino text, p_texto text) returns int
language plpgsql security definer set search_path = public as $$
declare
  eu    text := public.meu_email();
  nomeq text;
  r     public.funil_pacientes%rowtype;
  dest  record;
  n     int := 0;
  para_txt text;
  hoje  text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD');
begin
  if not public.eh_comercial() then raise exception 'sem acesso'; end if;
  if coalesce(trim(p_texto),'') = '' then raise exception 'mensagem vazia'; end if;
  select nome into nomeq from perfis where email = eu;
  nomeq := coalesce(nomeq,'Comercial') || ' (comercial)';
  select * into r from funil_pacientes
   where id = p_paciente_id and coalesce(dados->>'etapa','') = any(public.etapas_comercial());
  if not found then raise exception 'paciente não encontrado'; end if;

  for dest in
    select p.email, p.nome from perfis p
     where (p_destino = 'cirurgiao' and p.email = r.cirurgiao_email and p.papel = 'cirurgiao')
        or (p_destino = 'ana'       and p.email = 'acytgiroldo@gmail.com')
        or (p_destino = 'equipe'    and p.papel = 'admin' and p.recebe_avisos)
  loop
    insert into funil_recados (de, de_nome, para, para_nome, paciente_id, paciente_nome, texto)
    values (eu, nomeq, dest.email, dest.nome, p_paciente_id, r.dados->>'nome', left(p_texto, 4000));
    n := n + 1;
    para_txt := coalesce(para_txt || ', ', '') || dest.nome;
  end loop;
  if n = 0 then raise exception 'sem destinatário'; end if;

  update funil_pacientes
     set dados = jsonb_set(dados, '{historico}',
           (case when jsonb_typeof(dados->'historico') = 'array' then dados->'historico' else '[]'::jsonb end)
           || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', nomeq || ' → ' || para_txt || ': ' || left(p_texto, 500))))
   where id = p_paciente_id;
  return n;
end $$;
revoke all on function public.comercial_mensagem(text,text,text) from public, anon;
grant execute on function public.comercial_mensagem(text,text,text) to authenticated;
