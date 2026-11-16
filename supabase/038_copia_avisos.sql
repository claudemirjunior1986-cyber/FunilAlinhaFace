-- Cópia dos avisos do cirurgião para outra pessoa (ex.: tudo o que vai para o Dr. Victor vai também para a Fernanda).
-- Cada aviso que entra na fila para o cirurgião ganha uma cópia para o número cadastrado aqui.
-- A cópia usa o e-mail "cirurgiao#nome" para não ser descartada pela regra "só vale o aviso mais recente" da fila.
-- Pode rodar de novo sem problema.

create table if not exists public.funil_avisos_copia (
  email    text not null,          -- e-mail do cirurgião (perfis.email)
  telefone text not null,          -- WhatsApp de quem recebe a cópia (só números, com 55)
  nome     text not null,
  primary key (email, telefone)
);
alter table public.funil_avisos_copia enable row level security;
drop policy if exists copia_admin on public.funil_avisos_copia;
create policy copia_admin on public.funil_avisos_copia for all using (public.eh_admin()) with check (public.eh_admin());

insert into public.funil_avisos_copia (email, telefone, nome)
values ('admvictorssa@gmail.com', '5521964290798', 'Fernanda')
on conflict (email, telefone) do update set nome = excluded.nome;

create or replace function public.copia_aviso_medico() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if position('#' in new.email) > 0 then return new; end if;   -- já é uma cópia
  insert into funil_avisos_medico (email, telefone, paciente_id, tipo, texto)
  select new.email || '#' || lower(c.nome), c.telefone, new.paciente_id, new.tipo, new.texto
    from funil_avisos_copia c
   where c.email = new.email
     and right(regexp_replace(coalesce(new.telefone,''), '\D', '', 'g'), 8) <> right(c.telefone, 8);
  return new;
end $$;
drop trigger if exists zz_copia_aviso_medico on public.funil_avisos_medico;
create trigger zz_copia_aviso_medico after insert on public.funil_avisos_medico
  for each row execute function public.copia_aviso_medico();
