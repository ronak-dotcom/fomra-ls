-- Infrastructure score saved per lead (and radius) once the map servers
-- answer, so the lead page shows it instantly afterwards and doesn't depend
-- on the public Overpass servers being free.
create table if not exists public.lead_infra_scores (
  lead_id text not null,
  radius_km int not null,
  lat double precision not null,
  lon double precision not null,
  payload jsonb not null,
  fetched_at timestamptz not null default now(),
  primary key (lead_id, radius_km)
);
alter table public.lead_infra_scores enable row level security;
create policy "authenticated read infra scores" on public.lead_infra_scores for select to authenticated using (true);
create policy "authenticated write infra scores" on public.lead_infra_scores for insert to authenticated with check (true);
create policy "authenticated update infra scores" on public.lead_infra_scores for update to authenticated using (true) with check (true);
