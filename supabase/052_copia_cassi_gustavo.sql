-- Cassi recebe cópia de todos os avisos do funil para o Dr. Gustavo (como Fernanda/Victor e Jéssica/Afonso).
insert into public.funil_avisos_copia (email, telefone, nome)
values ('gu.martins00@gmail.com', '555133213338', 'Cassi')
on conflict (email, telefone) do update set nome = excluded.nome;
