-- Alinha Implantes: funil próprio (Protocolo All-on-4 e Implante Zigomático), só com o Dr. Victor.
--  * dados.linha = 'implantes' separa os pacientes de implante dos da Alinha Face.
--  * A marcação é automática: qualquer ficha que tenha "ALINHA IMPLANTES" (a Bia escreve isso no resumo
--    ao agendar) ou tratamento começando com "Implantes" vira linha implantes.
--  * Paciente de implantes sem cirurgião vai sozinho para o Dr. Victor.
--  * Quem vê: admin (tudo), o Dr. Victor (pacientes dele) e a equipe dele (perfis.papel='equipe', equipe_de = Dr. Victor).
--  * implantes_atualizar(...): única função de gravação da página implantes.html (etapa, procedimento, orçamento, nota).
-- Pode rodar de novo sem problema.

create or replace function public.funil_preenche() returns trigger
language plpgsql as $$
begin
  if tg_table_name = 'funil_pacientes' then
    -- Alinha Implantes: marca a linha e põe o Dr. Victor quando ainda não há cirurgião
    if coalesce(new.dados ->> 'linha','') = '' and (
         new.dados::text ilike '%alinha implantes%'
         or coalesce(new.dados ->> 'tratamento','') ilike 'implantes%') then
      new.dados := new.dados || jsonb_build_object('linha','implantes');
    end if;
    if new.dados ->> 'linha' = 'implantes' and coalesce(trim(new.dados ->> 'cirurgiao'),'') = '' then
      new.dados := new.dados || jsonb_build_object('cirurgiao','admvictorssa@gmail.com');
    end if;
    new.cirurgiao_email := lower(nullif(trim(coalesce(new.dados ->> 'cirurgiao','')),''));
  end if;
  new.atualizado_em := now();
  return new;
end $$;

-- fichas que já existem com a marca da Alinha Implantes
update public.funil_pacientes set dados = dados
 where coalesce(dados ->> 'linha','') = ''
   and (dados::text ilike '%alinha implantes%' or coalesce(dados ->> 'tratamento','') ilike 'implantes%');

-- gravação pela página do funil de implantes
create or replace function public.implantes_atualizar(
  p_id text, p_etapa text default null, p_procedimento text default null,
  p_valor numeric default null, p_nota text default null, p_dados jsonb default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  r     public.funil_pacientes%rowtype;
  d     jsonb;
  eu    text := public.meu_email();
  hoje  text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  etapas text[] := array['triagem','lead','agendou','compareceu','exames_sol','im_orcamento','im_fechado','im_cirurgia','im_protese','noshow','perdido'];
  rotulo jsonb := '{"triagem":"A classificar","lead":"Lead novo","agendou":"Avaliação agendada","compareceu":"Avaliado",
                    "exames_sol":"Tomografia pedida","im_orcamento":"Planejamento e orçamento","im_fechado":"Fechou tratamento",
                    "im_cirurgia":"Cirurgia realizada","im_protese":"Prótese definitiva","noshow":"Faltou","perdido":"Perdido"}';
  quem  text;
  linhas jsonb := '[]'::jsonb;
begin
  select * into r from public.funil_pacientes where id = p_id for update;
  if not found then raise exception 'Paciente não encontrado'; end if;
  if coalesce(r.dados ->> 'linha','') <> 'implantes' and not public.eh_admin() then
    raise exception 'Paciente não é da Alinha Implantes';
  end if;
  if not (public.eh_admin()
          or r.cirurgiao_email = eu
          or (public.meu_cirurgiao() is not null and r.cirurgiao_email = public.meu_cirurgiao())) then
    raise exception 'Sem acesso a este paciente';
  end if;

  select coalesce(nome, eu) into quem from public.perfis where email = eu;
  d := r.dados || jsonb_build_object('linha','implantes');

  if p_etapa is not null and p_etapa <> '' and p_etapa <> coalesce(d ->> 'etapa','') then
    if not (p_etapa = any(etapas)) then raise exception 'Etapa inválida'; end if;
    d := jsonb_set(d, '{etapa}', to_jsonb(p_etapa));
    if p_etapa = 'exames_sol' and coalesce(d ->> 'dataExames','') = '' then d := d || jsonb_build_object('dataExames', hoje); end if;
    if p_etapa = 'im_orcamento' then d := d || jsonb_build_object('dataProposta', hoje); end if;
    if p_etapa = 'im_fechado' then d := d || jsonb_build_object('dataFechamento', hoje); end if;
    if p_etapa = 'im_cirurgia' then d := d || jsonb_build_object('dataCirurgia', coalesce(nullif(d ->> 'dataCirurgia',''), hoje)); end if;
    linhas := linhas || jsonb_build_array(jsonb_build_object('data', hoje,
                'texto', 'Etapa → ' || coalesce(rotulo ->> p_etapa, p_etapa) || ' (' || coalesce(quem, eu) || ')'));
  end if;

  if p_procedimento is not null and p_procedimento <> coalesce(d ->> 'tratamento','') then
    d := d || jsonb_build_object('tratamento', p_procedimento);
  end if;

  if p_valor is not null then
    d := d || jsonb_build_object('valorProposta', p_valor);
  end if;

  -- campos simples da ficha (nome, cidade, telefone, data/hora da avaliação, próxima ação)
  if p_dados is not null then
    d := d || (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from jsonb_each(p_dados) as e(k, v)
               where k in ('nome','cidade','telefone','dataConsulta','horaConsulta','modalidade','proximaAcao','dataProximaAcao','motivoPerda','arcadas'));
  end if;

  if nullif(trim(coalesce(p_nota,'')),'') is not null then
    linhas := linhas || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', coalesce(quem, eu) || ': ' || left(trim(p_nota), 600)));
  end if;

  if jsonb_array_length(linhas) > 0 then
    d := jsonb_set(d, '{historico}', coalesce(d -> 'historico','[]'::jsonb) || linhas);
  end if;
  d := d || jsonb_build_object('atualizadoEm', to_jsonb(now()));

  update public.funil_pacientes set dados = d where id = p_id;
end $$;

revoke all on function public.implantes_atualizar(text,text,text,numeric,text,jsonb) from public, anon;
grant execute on function public.implantes_atualizar(text,text,text,numeric,text,jsonb) to authenticated;
