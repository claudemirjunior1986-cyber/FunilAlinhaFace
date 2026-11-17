-- Pedido de dados do paciente para o pedido de exames.
-- O cirurgião (ou a equipe dele, ou um administrador) clica na ficha e sai pelo WhatsApp da Alinha Face uma
-- mensagem para o paciente pedindo: nome completo, CPF, data de nascimento, nome da mãe, endereço com CEP,
-- telefone com WhatsApp e e-mail. A resposta do paciente é capturada pela função "whats" (sincronização),
-- gravada na ficha (dadosExame) e enviada ao cirurgião pelo WhatsApp.
-- Pode rodar de novo sem problema.

create or replace function public.pedir_dados_exame(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r      funil_pacientes%rowtype;
  d      jsonb;
  eu     text := public.meu_email();
  tel    text;
  medico text;
  nome   text;
  texto  text;
  hoje   text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
begin
  select * into r from funil_pacientes where id = p_id for update;
  if not found then raise exception 'Paciente não encontrado'; end if;
  if not (public.eh_admin() or r.cirurgiao_email = eu
          or (public.meu_cirurgiao() is not null and r.cirurgiao_email = public.meu_cirurgiao())) then
    raise exception 'Sem permissão para este paciente';
  end if;
  d := r.dados;
  tel := regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g');
  if length(tel) in (10, 11) then tel := '55' || tel; end if;
  if length(tel) < 12 then return jsonb_build_object('ok', false, 'motivo', 'paciente sem WhatsApp na ficha'); end if;
  if exists (select 1 from funil_avisos_medico where paciente_id = p_id and tipo = 'dados_exame'
              and criado_em > now() - interval '10 minutes') then
    return jsonb_build_object('ok', true, 'ja_enviado', true);
  end if;

  select p.nome into medico from perfis p where p.email = r.cirurgiao_email;
  medico := coalesce(medico, 'especialista');
  nome := split_part(trim(coalesce(nullif(d->>'nome',''), '')), ' ', 1);

  texto := 'Olá' || coalesce(', ' || nullif(nome, ''), '') || '! Aqui é da Alinha Face 😊' || chr(10) || chr(10)
    || 'Você passou em consulta com o ' || medico || '. Para darmos continuidade ao seu tratamento e o doutor fazer o pedido dos seus exames, precisamos dos dados abaixo.' || chr(10)
    || 'Pode responder aqui mesmo, copiando e preenchendo:' || chr(10) || chr(10)
    || 'Nome completo:' || chr(10)
    || 'CPF:' || chr(10)
    || 'Data de nascimento:' || chr(10)
    || 'Nome da mãe:' || chr(10)
    || 'Endereço completo com CEP:' || chr(10)
    || 'Telefone de contato com WhatsApp:' || chr(10)
    || 'E-mail:' || chr(10) || chr(10)
    || 'Seus dados ficam só com a equipe do seu tratamento. Obrigado! 💙';

  insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
  values ('paciente', tel, p_id, 'dados_exame', texto);

  d := d || jsonb_build_object('pedidoDadosEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                               'pedidoDadosPor', eu, 'atualizadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
         - 'dadosExame' - 'dadosExameEm';
  d := jsonb_set(d, '{historico}', (case when jsonb_typeof(d->'historico') = 'array' then d->'historico' else '[]'::jsonb end)
         || jsonb_build_array(jsonb_build_object('data', hoje, 'texto', 'Pedidos ao paciente, pelo WhatsApp, os dados para o pedido de exames')));
  update funil_pacientes set dados = d where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.pedir_dados_exame(text) from public, anon;
grant execute on function public.pedir_dados_exame(text) to authenticated;
