-- Grade das agendas do Dr. Afonso e do Dr. Victor (29/10/2026):
--   online de todos: segunda a sexta 8h–20h, sábado 8h–14h
--   presencial: Afonso Mooca ter/qui/sex 9h–17h e Vila Mariana qua 14h–18h;
--               Victor Salvador qui 14h–19h e sex 8h–12h + 14h–18h
-- Online e presencial do mesmo médico nunca se sobrepõem: a checagem de ocupado olha todas as consultas dele.
delete from public.agenda_grade where medico in ('afonso','victor');

insert into public.agenda_grade (medico, dia_semana, inicio, fim, modalidades, local, endereco)
select m, d, '08:00', case when d = 6 then '14:00'::time else '20:00'::time end, '{Online}', 'Online', null
from unnest(array['afonso','victor']) m, generate_series(1,6) d;

insert into public.agenda_grade (medico, dia_semana, inicio, fim, modalidades, local, endereco) values
  ('afonso', 2, '09:00', '17:00', '{Presencial}', 'SP · Mooca (Av. Paes de Barros, 3399)', 'Av. Paes de Barros, 3399, conj. 25 – Mooca, São Paulo/SP'),
  ('afonso', 4, '09:00', '17:00', '{Presencial}', 'SP · Mooca (Av. Paes de Barros, 3399)', 'Av. Paes de Barros, 3399, conj. 25 – Mooca, São Paulo/SP'),
  ('afonso', 5, '09:00', '17:00', '{Presencial}', 'SP · Mooca (Av. Paes de Barros, 3399)', 'Av. Paes de Barros, 3399, conj. 25 – Mooca, São Paulo/SP'),
  ('afonso', 3, '14:00', '18:00', '{Presencial}', 'SP · Vila Mariana (R. Francisco Cruz, 131)', 'Rua Francisco Cruz, 131 – Vila Mariana, São Paulo/SP'),
  ('victor', 4, '14:00', '19:00', '{Presencial}', 'Salvador · Caminho das Árvores (R. da Alfazema, 761)',
     'Rua da Alfazema, 761, Edf. Iguatemi Business & Flat, loja 18 (térreo) – Caminho das Árvores, Salvador/BA. Referência: em frente à agência do Banco do Brasil Estilo'),
  ('victor', 5, '08:00', '12:00', '{Presencial}', 'Salvador · Caminho das Árvores (R. da Alfazema, 761)',
     'Rua da Alfazema, 761, Edf. Iguatemi Business & Flat, loja 18 (térreo) – Caminho das Árvores, Salvador/BA. Referência: em frente à agência do Banco do Brasil Estilo'),
  ('victor', 5, '14:00', '18:00', '{Presencial}', 'Salvador · Caminho das Árvores (R. da Alfazema, 761)',
     'Rua da Alfazema, 761, Edf. Iguatemi Business & Flat, loja 18 (térreo) – Caminho das Árvores, Salvador/BA. Referência: em frente à agência do Banco do Brasil Estilo');

select medico, dia_semana, inicio, fim, modalidades from public.agenda_grade order by medico, dia_semana, modalidades;
