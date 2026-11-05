-- A Bia desmarca a consulta quando o paciente pede (intenção de agendar com cancelar = "sim").
-- Tira data e hora da ficha, volta para "lead", deixa a próxima ação para oferecer nova data.
-- O aviso de "consulta desmarcada" ao cirurgião sai sozinho (gatilho 012); a agenda do Google do Dr. Gustavo
-- perde o evento na próxima sincronização. Pode rodar de novo sem problema.

create or replace function public.cancelar_consulta(p_telefone text, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t8    text := right(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), 8);
  hoje  text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  r     funil_pacientes%rowtype;
  d     jsonb;
  era   text;
  med   text;
begin
  if length(t8) < 8 then return jsonb_build_object('ok', false, 'motivo', 'telefone_invalido'); end if;
  select * into r from funil_pacientes
   where right(regexp_replace(coalesce(dados->>'telefone',''), '\D', '', 'g'), 8) = t8
     and coalesce(dados->>'dataConsulta','') >= hoje
   order by dados->>'dataConsulta', atualizado_em desc limit 1 for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'sem_consulta_marcada'); end if;

  d := r.dados;
  era := to_char((d->>'dataConsulta')::date, 'DD/MM') || coalesce(' às ' || nullif(left(d->>'horaConsulta',5),''), '');
  select nome into med from perfis where email = r.cirurgiao_email;
  d := d || jsonb_build_object(
    'dataConsulta', '', 'horaConsulta', '',
    'proximaAcao', 'Paciente desmarcou pelo WhatsApp (era ' || era || ') — oferecer nova data',
    'dataProximaAcao', hoje,
    'atualizadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
  if coalesce(d->>'etapa','') = 'agendou' then d := jsonb_set(d, '{etapa}', '"lead"'); end if;
  d := jsonb_set(d, '{historico}', (
    select coalesce(jsonb_agg(z.h order by z.n), '[]'::jsonb)
    from (
      select e.h, e.n
      from jsonb_array_elements(
             (case when jsonb_typeof(d->'historico') = 'array' then d->'historico' else '[]'::jsonb end)
             || jsonb_build_array(jsonb_build_object('data', hoje,
                  'texto', 'Paciente desmarcou a consulta pelo WhatsApp (Bia): era ' || era || coalesce(' com ' || med, '')
                           || coalesce(' — ' || nullif(trim(coalesce(p_motivo,'')),''), ''))))
           with ordinality as e(h, n)
      order by e.n desc limit 40
    ) z));
  update funil_pacientes set dados = d where id = r.id;
  return jsonb_build_object('ok', true, 'paciente_id', r.id, 'era', era, 'medico', coalesce(med, ''));
end $$;
revoke all on function public.cancelar_consulta(text, text) from public, anon, authenticated;
grant execute on function public.cancelar_consulta(text, text) to service_role;
