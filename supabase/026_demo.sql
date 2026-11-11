-- Ambiente de demonstração para apresentar o sistema a novos cirurgiões, sem mexer nos dados reais.
--  * Perfil "Dr. Demonstração" (demo@alinhaface.com.br), sem WhatsApp: nunca recebe avisos.
--  * 10 pacientes de exemplo (ids demo-01..demo-10), com telefone falso 5500000000xxx e dados.demo = true.
--  * Nada que envolva esses pacientes sai por WhatsApp (o gatilho abaixo descarta o aviso antes de entrar na fila).
--  * O painel da equipe não mostra os pacientes de exemplo; a Bia e as agendas reais não os enxergam.
--  * Toda madrugada (3h10) os exemplos voltam ao estado original, com datas a partir do dia.
-- Pode rodar de novo sem problema.

insert into public.perfis (email, nome, papel) values ('demo@alinhaface.com.br', 'Dr. Demonstração', 'cirurgiao')
on conflict (email) do update set nome = excluded.nome, papel = 'cirurgiao', whatsapp = null, avisos_whats = false;

-- nenhum aviso de WhatsApp para o médico de demonstração nem para pacientes de exemplo
create or replace function public.bloqueia_aviso_demo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email = 'demo@alinhaface.com.br' or coalesce(new.telefone,'') like '5500%' or coalesce(new.paciente_id,'') like 'demo-%' then
    return null;
  end if;
  return new;
end $$;
drop trigger if exists bloqueia_aviso_demo on public.funil_avisos_medico;
create trigger bloqueia_aviso_demo before insert on public.funil_avisos_medico
  for each row execute function public.bloqueia_aviso_demo();

-- recria os pacientes de exemplo com datas a partir de hoje
create or replace function public.demo_renovar() returns int
language plpgsql security definer set search_path = public as $$
declare
  h   date := (now() at time zone 'America/Sao_Paulo')::date;
  med text := 'demo@alinhaface.com.br';
  agora text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  base jsonb := jsonb_build_object('demo', true, 'cirurgiao', med, 'fonte', 'WhatsApp (na hora)', 'pagamento', 'Pelo convênio',
                                   'opme', 0, 'valorProposta', 0, 'convenio', 'Sim', 'modalidade', 'Online', 'atualizadoEm', agora);
  function_rows int := 0;
begin
  delete from funil_teleconsultas where paciente_id like 'demo-%';
  delete from funil_pacientes where id like 'demo-%';

  insert into funil_pacientes (id, dados) values
  ('demo-01', base || jsonb_build_object(
     'nome','Mariana Lopes','telefone','5500000000001','cidade','Porto Alegre - RS','etapa','agendou','origem','Quiz do site',
     'tratamento','DTM / ATM','nomeConvenio','Unimed','criadoEm', to_char(h - 3,'YYYY-MM-DD')||'T13:20:00Z',
     'dataConsulta', to_char(h,'YYYY-MM-DD'), 'horaConsulta','16:15',
     'observacoes','Q:Dor na mandíbula, têmporas ou cabeça · H:Mais de 2 anos · T:Placa de mordida',
     'resumoCaso','Dor na mandíbula e nas têmporas há mais de 2 anos, pior ao acordar. Já usou placa de mordida sem melhora. Quer resolver o quanto antes.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-3,'YYYY-MM-DD'),'texto','Entrou pelo quiz do site'),
                                    jsonb_build_object('data',to_char(h-3,'YYYY-MM-DD'),'texto','Bia agendou consulta on-line')))),
  ('demo-02', base || jsonb_build_object(
     'nome','Rafael Teixeira','telefone','5500000000002','cidade','Canoas - RS','etapa','agendou','origem','Anúncio (clique no WhatsApp)',
     'tratamento','Ortognática','nomeConvenio','SulAmérica','criadoEm', to_char(h - 2,'YYYY-MM-DD')||'T15:00:00Z',
     'dataConsulta', to_char(h + 1,'YYYY-MM-DD'), 'horaConsulta','10:45',
     'observacoes','Q:Mordida torta / queixo para frente · H:Desde a adolescência',
     'resumoCaso','Queixo para frente e mordida cruzada desde a adolescência. Dificuldade para mastigar e incômodo com a aparência. Já fez ortodontia.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-2,'YYYY-MM-DD'),'texto','Bia agendou consulta on-line')))),
  ('demo-03', base || jsonb_build_object(
     'nome','Camila Rocha','telefone','5500000000003','cidade','Novo Hamburgo - RS','etapa','agendou','origem','Clique na foto (Instagram)',
     'tratamento','DTM + Ortognática','nomeConvenio','Bradesco Saúde','criadoEm', to_char(h - 1,'YYYY-MM-DD')||'T18:40:00Z',
     'dataConsulta', to_char(h + 2,'YYYY-MM-DD'), 'horaConsulta','19:15',
     'resumoCaso','Estalos na ATM ao abrir a boca e travamento ocasional. Mordida aberta anterior. Ronca à noite segundo o marido.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-1,'YYYY-MM-DD'),'texto','Bia agendou consulta on-line')))),
  ('demo-04', base || jsonb_build_object(
     'nome','Bruno Carvalho','telefone','5500000000004','cidade','Gravataí - RS','etapa','agendou','origem','Quiz do site',
     'tratamento','DTM / ATM','nomeConvenio','Cassi','criadoEm', to_char(h - 6,'YYYY-MM-DD')||'T12:00:00Z',
     'dataConsulta', to_char(h - 1,'YYYY-MM-DD'), 'horaConsulta','18:45',
     'resumoCaso','Dor de cabeça frequente e bruxismo. Desgaste nos dentes apontado pelo dentista.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-6,'YYYY-MM-DD'),'texto','Bia agendou consulta on-line')))),
  ('demo-05', base || jsonb_build_object(
     'nome','Juliana Martins','telefone','5500000000005','cidade','Porto Alegre - RS','etapa','exames_sol','origem','Quiz do site',
     'tratamento','DTM + Ortognática','nomeConvenio','Unimed','criadoEm', to_char(h - 12,'YYYY-MM-DD')||'T14:00:00Z',
     'dataConsulta', to_char(h - 5,'YYYY-MM-DD'), 'horaConsulta','09:45', 'dataExames', to_char(h - 5,'YYYY-MM-DD'),
     'consultaCompareceu', true, 'consultaPediuExames', true, 'consultaRegistradaEm', to_char(h - 5,'YYYY-MM-DD')||'T13:30:00Z',
     'examesTipos', jsonb_build_array('Tomografia de face','Ressonância magnética de ATM'),
     'examesPedidos','Tomografia de face e ressonância das ATMs com boca aberta e fechada.',
     'resumoConsulta','Dor bilateral na ATM com limitação de abertura (32 mm). Classe III esquelética. Suspeita de deslocamento de disco à direita. Pedidos exames de imagem para planejamento.',
     'resumoCaso','Dor nas duas ATMs e limitação para abrir a boca. Queixo para frente.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-5,'YYYY-MM-DD'),'texto','Consulta registrada: pediu exames')))),
  ('demo-06', base || jsonb_build_object(
     'nome','Pedro Henrique Alves','telefone','5500000000006','cidade','São Leopoldo - RS','etapa','exames_ok','origem','Anúncio (clique no WhatsApp)',
     'tratamento','Ortognática','nomeConvenio','Unimed','criadoEm', to_char(h - 30,'YYYY-MM-DD')||'T14:00:00Z',
     'dataConsulta', to_char(h - 21,'YYYY-MM-DD'), 'horaConsulta','11:15', 'dataExames', to_char(h - 21,'YYYY-MM-DD'), 'dataExamesOk', to_char(h - 2,'YYYY-MM-DD'),
     'consultaCompareceu', true, 'consultaPediuExames', true, 'consultaRegistradaEm', to_char(h - 21,'YYYY-MM-DD')||'T15:00:00Z',
     'examesTipos', jsonb_build_array('Tomografia de face','Documentação ortodôntica'),
     'examesPedidos','Tomografia e documentação ortodôntica completa.',
     'resumoConsulta','Mordida aberta anterior e retrognatia mandibular. Candidato a cirurgia bimaxilar. Aguardar exames para planejamento virtual.',
     'resumoCaso','Mordida aberta e queixo para trás. Respira pela boca.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-2,'YYYY-MM-DD'),'texto','Exames entregues — pronto para o retorno')))),
  ('demo-07', base || jsonb_build_object(
     'nome','Fernanda Ribeiro','telefone','5500000000007','cidade','Porto Alegre - RS','etapa','proposta','origem','Quiz do site',
     'tratamento','Ortognática','nomeConvenio','Bradesco Saúde','criadoEm', to_char(h - 45,'YYYY-MM-DD')||'T14:00:00Z',
     'dataConsulta', to_char(h - 35,'YYYY-MM-DD'), 'horaConsulta','17:45', 'dataProposta', to_char(h - 3,'YYYY-MM-DD'),
     'valorProposta', 18500, 'opme', 12400, 'consultaCompareceu', true, 'consultaRegistradaEm', to_char(h - 35,'YYYY-MM-DD')||'T21:00:00Z',
     'resumoConsulta','Classe III com assimetria. Planejada cirurgia bimaxilar com mentoplastia.',
     'resumoCaso','Queixo para frente e rosto assimétrico. Muito motivada para operar.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-3,'YYYY-MM-DD'),'texto','Proposta enviada')))),
  ('demo-08', base || jsonb_build_object(
     'nome','Lucas Ferreira','telefone','5500000000008','cidade','Caxias do Sul - RS','etapa','autorizacao','origem','Clique na foto (Instagram)',
     'tratamento','DTM + Ortognática','nomeConvenio','Unimed','criadoEm', to_char(h - 60,'YYYY-MM-DD')||'T14:00:00Z',
     'dataConsulta', to_char(h - 50,'YYYY-MM-DD'), 'horaConsulta','10:15', 'hospital','Hospital de exemplo',
     'consultaCompareceu', true, 'consultaRegistradaEm', to_char(h - 50,'YYYY-MM-DD')||'T14:00:00Z',
     'resumoConsulta','Deslocamento de disco bilateral e retrognatia. Indicada cirurgia ortognática com artroscopia de ATM.',
     'resumoCaso','Travamento da boca e dor ao mastigar.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-7,'YYYY-MM-DD'),'texto','Pedido enviado ao convênio — aguardando autorização')))),
  ('demo-09', base || jsonb_build_object(
     'nome','Beatriz Santos','telefone','5500000000009','cidade','Porto Alegre - RS','etapa','cir_marcada','origem','Quiz do site',
     'tratamento','Ortognática','nomeConvenio','SulAmérica','criadoEm', to_char(h - 90,'YYYY-MM-DD')||'T14:00:00Z',
     'dataConsulta', to_char(h - 80,'YYYY-MM-DD'), 'horaConsulta','15:45', 'hospital','Hospital de exemplo', 'dataCirurgia', to_char(h + 12,'YYYY-MM-DD'),
     'consultaCompareceu', true, 'consultaRegistradaEm', to_char(h - 80,'YYYY-MM-DD')||'T19:00:00Z',
     'resumoConsulta','Classe II com retrognatia mandibular. Cirurgia de avanço mandibular autorizada.',
     'resumoCaso','Queixo para trás e ronco. Cirurgia autorizada pelo convênio.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-4,'YYYY-MM-DD'),'texto','Cirurgia marcada')))),
  ('demo-10', base || jsonb_build_object(
     'nome','Thiago Moreira','telefone','5500000000010','cidade','Viamão - RS','etapa','posop','origem','Anúncio (clique no WhatsApp)',
     'tratamento','Ortognática','nomeConvenio','Unimed','criadoEm', to_char(h - 150,'YYYY-MM-DD')||'T14:00:00Z',
     'dataConsulta', to_char(h - 140,'YYYY-MM-DD'), 'horaConsulta','09:15', 'hospital','Hospital de exemplo', 'dataCirurgia', to_char(h - 20,'YYYY-MM-DD'),
     'consultaCompareceu', true, 'consultaRegistradaEm', to_char(h - 140,'YYYY-MM-DD')||'T13:00:00Z',
     'resumoConsulta','Cirurgia bimaxilar realizada. Evolução boa no pós-operatório.',
     'resumoCaso','Pós-operatório de cirurgia bimaxilar. Retorno em 30 dias.',
     'historico', jsonb_build_array(jsonb_build_object('data',to_char(h-20,'YYYY-MM-DD'),'texto','Cirurgia realizada'))));
  get diagnostics function_rows = row_count;
  return function_rows;
end $$;
revoke all on function public.demo_renovar() from public, anon, authenticated;
grant execute on function public.demo_renovar() to service_role;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'demo-renovar') then perform cron.unschedule('demo-renovar'); end if;
end $$;
select cron.schedule('demo-renovar', '10 6 * * *', $$ select public.demo_renovar() $$);   -- 3h10 em São Paulo

select public.demo_renovar() as pacientes_de_exemplo;
