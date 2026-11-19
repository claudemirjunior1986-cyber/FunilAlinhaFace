-- Jéssica recebe cópia de todos os avisos do funil para o Dr. Afonso (como a Fernanda com o Dr. Victor, arquivo 038).
insert into public.funil_avisos_copia (email, telefone, nome)
values ('dr.aptrindadefilho@gmail.com', '5511981050594', 'Jéssica')
on conflict (email, telefone) do update set nome = excluded.nome;
