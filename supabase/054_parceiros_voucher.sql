-- Parceiros do voucher de exames (fim da parceria com a Blume).
--  * Lista de clínicas parceiras: o voucher sai com nome, unidades, telefone e horário da escolhida.
--  * Todos os logados leem a lista; só administradores alteram (pelo próprio voucher.html).
--  * A equipe do cirurgião (secretária) também gera voucher.
--  * Régua de exames deixa de citar a Blume e usa o parceiro gravado na ficha; voucher automático (Blume/SP) desligado.
-- Pode rodar de novo sem problema.

create table if not exists public.funil_parceiros (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  subtitulo text not null default '',
  unidades jsonb not null default '[]'::jsonb,   -- [{nome, endereco, telefone, horario}]
  validade_dias int not null default 5,
  ativo boolean not null default true,
  ordem int not null default 0,
  criado_em timestamptz not null default now()
);
alter table public.funil_parceiros enable row level security;
drop policy if exists parc_ler on public.funil_parceiros;
create policy parc_ler on public.funil_parceiros for select to authenticated using (true);
drop policy if exists parc_admin on public.funil_parceiros;
create policy parc_admin on public.funil_parceiros for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

-- Oral Imagem (Salvador/BA)
insert into public.funil_parceiros (nome, subtitulo, unidades, validade_dias, ativo, ordem)
select 'Oral Imagem', 'IMAGEM ODONTOLÓGICA · SALVADOR',
  '[{"nome":"","endereco":"Av. Antônio Carlos Magalhães, 442 — Itaigara, Salvador/BA","telefone":"(71) 3565-1333 · WhatsApp (71) 99281-3277","horario":"seg. a sex. 8h às 18h, sáb. 8h às 12h"}]'::jsonb,
  5, true, 0
where not exists (select 1 from public.funil_parceiros where nome ilike 'Oral Imagem%');

-- Blume fica na lista, desativada (histórico)
insert into public.funil_parceiros (nome, subtitulo, unidades, validade_dias, ativo, ordem)
select 'Blume Medicina Diagnóstica', 'MEDICINA DIAGNÓSTICA',
  '[{"nome":"Vila Olímpia","endereco":"Av. dos Bandeirantes, 679 — Subsolo 1 — Vila Olímpia, São Paulo/SP — CEP 04553-010","telefone":"(11) 5198-0900","horario":"seg. a sex. 7h às 19h, sáb. 7h às 12h"}]'::jsonb,
  5, false, 99
where not exists (select 1 from public.funil_parceiros where nome ilike 'Blume%');

-- Régua de exames (D+2): cita o parceiro e a validade gravados na ficha
do $$
declare def text;
begin
  select pg_get_functiondef('public.regua_exames()'::regprocedure) into def;
  def := replace(def, 'voucher de cortesia da Blume, válido até ''',
                      'voucher de cortesia da '' || coalesce(nullif(d->>''voucherParceiro'',''''), ''clínica parceira'') || '', válido até ''');
  def := replace(def, 'left(d->>''voucherEmitido'',10)::date + 5',
                      'left(d->>''voucherEmitido'',10)::date + coalesce(nullif(d->>''voucherValidade'','''')::int, 5)');
  execute def;
end $$;

-- Voucher automático (era Blume, só SP) desligado: a Oral Imagem é de Salvador e o voucher passa a ser gerado à mão
do $$
declare def text; f regprocedure;
begin
  select p.oid::regprocedure into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'registrar_consulta' order by p.oid desc limit 1;
  def := pg_get_functiondef(f);
  if position('voucher automático desligado' in def) = 0 then
    def := regexp_replace(def, '(and\s+coalesce\(d->>''voucherEmitido'',''''\)\s*=\s*''''\s+)then',
                          '\1and false /* voucher automático desligado */ then');
    if position('voucher automático desligado' in def) = 0 then raise exception 'não achei o voucher automático em registrar_consulta'; end if;
    execute def;
  end if;
end $$;
