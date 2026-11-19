-- 19/11/2026: sai o presencial do Dr. Afonso na Vila Mariana (quarta).
-- Entra o presencial em Moema com a Dra. Kathye Bomfim (equipe do Dr. Victor): terça e sexta, 9h–17h,
-- Av. Iraí, 300, sala 207 – pertinho do metrô e ao lado do shopping. (O Dr. Gustavo segue em Moema às quartas.)
-- A Bia não marca presencial: o caso vai para o Dr. Victor (com cópia para a Fernanda) e a equipe agenda.
delete from public.agenda_grade where medico = 'afonso' and local ilike '%vila mariana%';
delete from public.agenda_grade where medico = 'victor' and local ilike '%moema%';
insert into public.agenda_grade (medico, dia_semana, inicio, fim, modalidades, local, endereco) values
  ('victor', 2, '09:00', '17:00', '{Presencial}', 'SP · Moema (Av. Iraí, 300, sala 207) · Dra. Kathye',
     'Av. Iraí, 300, sala 207 – Moema, São Paulo/SP. Pertinho do metrô e ao lado do shopping. Atendimento com a Dra. Kathye Bomfim (equipe do Dr. Victor)'),
  ('victor', 5, '09:00', '17:00', '{Presencial}', 'SP · Moema (Av. Iraí, 300, sala 207) · Dra. Kathye',
     'Av. Iraí, 300, sala 207 – Moema, São Paulo/SP. Pertinho do metrô e ao lado do shopping. Atendimento com a Dra. Kathye Bomfim (equipe do Dr. Victor)');

-- link do mapa: Moema da Dra. Kathye (Av. Iraí) no lugar da Vila Mariana
create or replace function public.link_maps(t text) returns text
language sql immutable as $$
  select 'https://www.google.com/maps/search/?api=1&query=' || e
    from (select case
      when t ~* 'ira[ií]|kathye' then 'Av.+Iraí,+300+-+Moema,+São+Paulo+-+SP'
      when t ~* 'moema|jandira' then 'Av.+Jandira,+257+-+Moema,+São+Paulo+-+SP'
      when t ~* 'porto alegre|ygartua' then 'R.+Dr.+Florêncio+Ygartua,+422+-+Porto+Alegre+-+RS'
      when t ~* 'mooca|paes de barros' then 'Av.+Paes+de+Barros,+3399+-+Mooca,+São+Paulo+-+SP'
      when t ~* 'alfazema|caminho das [áa]rvores|salvador' then 'R.+da+Alfazema,+761+-+Caminho+das+Árvores,+Salvador+-+BA'
    end e) x where e is not null
$$;

select medico, dia_semana, inicio, fim, local from public.agenda_grade where modalidades @> '{Presencial}' order by medico, dia_semana;
