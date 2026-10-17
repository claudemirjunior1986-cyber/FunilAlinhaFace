-- Funil Alinha Face — voucher só para capital, Grande SP e Baixada Santista;
-- e a lista de contatos ignorados que a sincronização do WhatsApp usa.
-- Pode rodar de novo sem problema.

create or replace function public.paciente_de_sp(d jsonb) returns boolean
language sql immutable as $$
  with t as (
    select trim(lower(translate(coalesce(d->>'cidade',''),
             'ÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇáàãâäéèêëíìîïóòõôöúùûüç',
             'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'))) c,
           coalesce(d->>'local','') l
  )
  select l like 'SP %'
      or c in ('sp','sao paulo','sao paulo sp','sao paulo - sp','sao paulo/sp','capital','sao paulo capital')
      or c like 'sao paulo%'
      -- Grande São Paulo (39 municípios)
      or c ~ '\m(aruja|barueri|biritiba[ -]?mirim|caieiras|cajamar|carapicuiba|cotia|diadema|embu das artes|embu[ -]guacu|embu|ferraz de vasconcelos|francisco morato|franco da rocha|guararema|guarulhos|itapecerica da serra|itapevi|itaquaquecetuba|jandira|juquitiba|mairipora|maua|mogi das cruzes|osasco|pirapora do bom jesus|ribeirao pires|rio grande da serra|salesopolis|santa isabel|santana de parnaiba|santo andre|sao bernardo( do campo)?|sao caetano( do sul)?|sao lourenco da serra|suzano|taboao da serra|vargem grande paulista)\M'
      or c ~ '(^|[^a-z])poa( ?- ?sp| sp)'   -- Poá/SP (sem confundir com "POA" = Porto Alegre)
      -- Baixada Santista (9 municípios)
      or c ~ '\m(bertioga|cubatao|guaruja|itanhaem|mongagua|peruibe|praia grande|santos|sao vicente)\M'
  from t
$$;

create table if not exists public.funil_ignorados (
  id         text primary key,          -- "k" + 8 últimos dígitos do telefone
  dados      jsonb not null default '{}'::jsonb,
  criado_em  timestamptz not null default now()
);
alter table public.funil_ignorados enable row level security;
drop policy if exists ign_admin on public.funil_ignorados;
create policy ign_admin on public.funil_ignorados for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());
