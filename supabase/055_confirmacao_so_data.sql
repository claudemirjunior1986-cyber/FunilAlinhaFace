-- 055: confirmação automática ao paciente (caso Emilene, 25/11)
--  * "remarcada" só sai quando muda DIA, HORA ou CIRURGIÃO. Trocar só a modalidade não manda nada ao paciente
--    (o cirurgião continua sendo avisado); a equipe confirma com o paciente.
--  * Consulta presencial sem endereço (local vazio ou "Online") não gera mensagem ao paciente.
-- Pode rodar de novo sem problema.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.avisa_consulta_paciente()'::regprocedure);
  if position('presencial sem endereço' in d) = 0 then
    d := regexp_replace(d, '\s+and coalesce\(n->>''modalidade'',''''\) = coalesce\(o->>''modalidade'',''''\)', '');
    d := replace(d, 'online := coalesce(n->>''modalidade'',''Online'') <> ''Presencial'';',
                    'online := coalesce(n->>''modalidade'',''Online'') <> ''Presencial'';'
                    || chr(10) || '  if not online and coalesce(nullif(n->>''local'',''''), ''Online'') = ''Online'' then return new; end if;  -- presencial sem endereço');
    if position('presencial sem endereço' in d) = 0 or position('n->>''modalidade'','''') = coalesce(o->>' in d) > 0 then
      raise exception 'avisa_consulta_paciente: trecho não encontrado';
    end if;
    execute d;
  end if;
end $$;
