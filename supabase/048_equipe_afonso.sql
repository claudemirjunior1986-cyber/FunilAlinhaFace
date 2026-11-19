-- Equipe do Dr. Afonso (mesmos moldes da equipe do Dr. Victor, arquivo 037).
-- O login (Authentication → Users) é criado à mão, com senha definida pelo Claudemir.
insert into public.perfis (email, nome, papel, equipe_de)
values ('equipeafonso@alinhaface.com.br', 'Equipe Dr. Afonso', 'equipe', 'dr.aptrindadefilho@gmail.com')
on conflict (email) do update set papel = 'equipe', equipe_de = excluded.equipe_de, nome = excluded.nome;
