-- On-line do Dr. Afonso e do Dr. Victor com almoço (04/11/2026):
--   segunda a sexta 8h–12h e 13h–20h; sábado 8h–14h (sem mudança).
-- Só mexe nas linhas on-line; o presencial fica como está. Consultas já marcadas não mudam.
delete from public.agenda_grade where medico in ('afonso','victor') and modalidades = '{Online}';

insert into public.agenda_grade (medico, dia_semana, inicio, fim, modalidades, local, endereco)
select m, d, h.ini, h.fim, '{Online}'::text[], 'Online', null
from unnest(array['afonso','victor']) m,
     generate_series(1,5) d,
     (values ('08:00'::time, '12:00'::time), ('13:00'::time, '20:00'::time)) h(ini, fim)
union all
select m, 6, '08:00'::time, '14:00'::time, '{Online}'::text[], 'Online', null from unnest(array['afonso','victor']) m;

select medico, dia_semana, inicio, fim from public.agenda_grade where modalidades = '{Online}' order by medico, dia_semana, inicio;
