-- Remove os 10 pacientes de exemplo (demo-01..10) e para a recriação diária deles (pedido do Claudemir, 11/11).
-- Continua valendo: o "Dr. Joaquim (teste)" na lista de cirurgiões e o caso de teste que some do funil e é apagado em 60 min.
-- Para recriar os exemplos um dia: select public.demo_renovar(); e reagende o cron 'demo-renovar' (ver 026).
select cron.unschedule('demo-renovar') where exists (select 1 from cron.job where jobname = 'demo-renovar');
delete from public.funil_teleconsultas where paciente_id like 'demo-%';
delete from public.funil_recados where paciente_id like 'demo-%';
delete from public.funil_avisos_medico where paciente_id like 'demo-%';
delete from public.funil_pacientes where id like 'demo-%';
