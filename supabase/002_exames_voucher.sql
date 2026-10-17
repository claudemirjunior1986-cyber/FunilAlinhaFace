-- Funil Alinha Face — exames pedidos pelo cirurgião e voucher Blume automático
-- Rode depois de schema.sql. Pode rodar de novo sem problema.

-- Paciente "de SP" (estado de São Paulo), olhando a cidade escrita na ficha
-- ou o local de atendimento em São Paulo.
create or replace function public.paciente_de_sp(d jsonb) returns boolean
language sql immutable as $$
  with t as (
    select lower(translate(coalesce(d->>'cidade',''),
             'ÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇáàãâäéèêëíìîïóòõôöúùûüç',
             'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')) c,
           coalesce(d->>'local','') l
  )
  select l like 'SP %'
      or c ~ '(^|[^a-z])sp([^a-z]|$)'
      or c like '%sao paulo%'
      or c ~ '\m(santo andre|sao bernardo|sao caetano|diadema|maua|ribeirao pires|guarulhos|osasco|barueri|carapicuiba|cotia|taboao|embu|itapevi|jandira|santana de parnaiba|cajamar|caieiras|franco da rocha|mogi das cruzes|suzano|ferraz de vasconcelos|poa|itaquaquecetuba|aruja|santa isabel|santos|sao vicente|praia grande|guaruja|cubatao|jundiai|campinas|valinhos|vinhedo|indaiatuba|itatiba|atibaia|braganca paulista|sorocaba|salto|itu|mairinque|sao jose dos campos|jacarei|taubate|bauru|piracicaba|americana|ribeirao preto|sao jose do rio preto)\M'
  from t
$$;

-- Nova versão do registro da consulta: recebe também os tipos de exame.
drop function if exists public.registrar_consulta(text,boolean,boolean,text,text);

create or replace function public.registrar_consulta(
  p_id text, p_compareceu boolean, p_pediu_exames boolean, p_resumo text,
  p_exames text default '', p_exames_tipos text[] default '{}'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r      public.funil_pacientes%rowtype;
  d      jsonb;
  hoje   text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  etapa  text;
  inicio text[] := array['triagem','lead','agendou','compareceu','noshow'];
  nova   text;
  texto  text;
  hist   jsonb;
  voucher boolean := false;
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
    'examesPedidos', case when p_pediu_exames then coalesce(p_exames,'') else '' end,
    'examesTipos', case when p_pediu_exames then to_jsonb(coalesce(p_exames_tipos,'{}')) else '[]'::jsonb end,
    'consultaCompareceu', p_compareceu,
    'consultaPediuExames', p_compareceu and p_pediu_exames,
    'consultaRegistradaEm', to_jsonb(now()),
    'consultaRegistradaPor', public.meu_email(),
    'atualizadoEm', to_jsonb(now())
  );

  -- pedido de exame novo: entra na lista "Exames pedidos" do painel até alguém marcar como visto
  if p_compareceu and p_pediu_exames then
    if coalesce(d->>'examesPedidosEm','') = '' or coalesce(r.dados->>'consultaPediuExames','false') <> 'true' then
      d := d || jsonb_build_object('examesPedidosEm', hoje, 'examesVistoEm', '');
    end if;
  end if;

  texto := case when not p_compareceu then 'Cirurgião: paciente não compareceu'
                when p_pediu_exames then 'Cirurgião: atendeu e pediu exames'
                  || case when coalesce(array_length(p_exames_tipos,1),0) > 0 then ' (' || array_to_string(p_exames_tipos, ', ') || ')' else '' end
                else 'Cirurgião: atendeu' end;
  if coalesce(p_resumo,'') <> '' then texto := texto || ' — ' || left(p_resumo, 300); end if;
  hist := coalesce(d -> 'historico','[]'::jsonb) || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', texto));

  -- voucher Blume automático: ressonância + paciente de SP + ainda sem voucher
  if p_compareceu and p_pediu_exames
     and 'Ressonância magnética' = any(coalesce(p_exames_tipos,'{}'))
     and public.paciente_de_sp(d)
     and coalesce(d->>'voucherEmitido','') = '' then
    d := d || jsonb_build_object('voucherEmitido', hoje, 'voucherStatus', 'Aguardando uso',
                                 'voucherBaixa', '', 'voucherAuto', true);
    hist := hist || jsonb_build_array(jsonb_build_object('data', hoje,
              'texto', 'Voucher Blume emitido automaticamente (ressonância, paciente de SP)'));
    voucher := true;
  end if;

  d := jsonb_set(d, '{historico}', hist);
  update public.funil_pacientes set dados = d where id = p_id;
  return jsonb_build_object('voucherEmitido', voucher);
end $$;

revoke all on function public.registrar_consulta(text,boolean,boolean,text,text,text[]) from public, anon;
grant execute on function public.registrar_consulta(text,boolean,boolean,text,text,text[]) to authenticated;
