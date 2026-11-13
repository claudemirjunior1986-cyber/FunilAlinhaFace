-- Módulo "Equipe do cirurgião": secretária / assistente / auxiliar de um cirurgião usa o mesmo painel da Ana Clara,
-- mas só com os pacientes daquele cirurgião. Pode anotar, alterar a ficha, fazer follow-up, mudar etapa, criar paciente.
-- Não vê WhatsApp da Bia, alertas, configurações, agendas dos outros, nem pacientes de outros cirurgiões.
--  * perfis.papel = 'equipe' e perfis.equipe_de = e-mail do cirurgião.
-- Primeiro acesso: equipe do Dr. Victor (equipevictor@alinhaface.com.br).
-- Pode rodar de novo sem problema.

alter table public.perfis add column if not exists equipe_de text;
alter table public.perfis drop constraint if exists perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check check (papel in ('admin','cirurgiao','comercial','equipe'));

create or replace function public.meu_cirurgiao() returns text
language sql stable security definer set search_path = public as $$
  select lower(equipe_de) from public.perfis where email = public.meu_email() and papel = 'equipe' limit 1
$$;

-- pacientes: a equipe lê, cria e altera só os do seu cirurgião
drop policy if exists pac_equipe on public.funil_pacientes;
create policy pac_equipe on public.funil_pacientes for all to authenticated
  using (public.meu_cirurgiao() is not null and cirurgiao_email = public.meu_cirurgiao())
  with check (public.meu_cirurgiao() is not null and cirurgiao_email = public.meu_cirurgiao());

-- perfis: a equipe enxerga o próprio perfil, o do seu cirurgião e os administradores (para mandar recados)
drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (email = public.meu_email() or public.eh_admin()
         or (public.meu_cirurgiao() is not null and (email = public.meu_cirurgiao() or papel = 'admin')));

-- equipe do Dr. Victor
insert into public.perfis (email, nome, papel, equipe_de)
values ('equipevictor@alinhaface.com.br', 'Equipe Dr. Victor', 'equipe', 'admvictorssa@gmail.com')
on conflict (email) do update set papel = 'equipe', equipe_de = excluded.equipe_de, nome = excluded.nome;
