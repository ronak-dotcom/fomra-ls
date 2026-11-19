-- Background fill of saved infrastructure scores (lead_infra_scores).
-- pg_cron calls POST https://land.fomrahousing.in/api/poi/fill-next every
-- 2 minutes (via pg_net) with a secret kept in Vault; the endpoint claims the
-- next lead + radius here, fetches its score from OpenStreetMap and saves it.

-- Retry bookkeeping per lead + radius; also the short lease while a fetch
-- runs. No policies: only the service role (the fill endpoint) uses it.
create table if not exists public.lead_infra_score_attempts (
  lead_id text not null,
  radius_km int not null,
  failures int not null default 0,
  last_error text,
  last_attempt_at timestamptz,
  next_try_at timestamptz,
  primary key (lead_id, radius_km)
);
alter table public.lead_infra_score_attempts enable row level security;

-- Shared secret between the scheduler and the endpoint (generated here, never
-- typed anywhere).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'infra_fill_secret') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'infra_fill_secret',
      'Lets the pg_cron infra score job call /api/poi/fill-next');
  end if;
end $$;

-- Next job(s): leads with GPS and no score for a radius (or one older than
-- 80 days, or from an older scoring version), not waiting on a retry. 2 km
-- first (what the app opens on), open leads before signed / dropped, newest
-- first. Leases each picked job for 3 minutes.
create or replace function public.infra_score_claim(p_secret text, p_limit int default 1)
returns table (lead_id text, radius_km int, gps text, road_width text, failures int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'infra_fill_secret' limit 1;
  if v_secret is null or p_secret is distinct from v_secret then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('infra_score_claim'));

  return query
  with picked as (
    select l.id as lead_id, r.radius_km, l.gps_coordinates as gps, l.road_width,
           coalesce(a.failures, 0) as failures
    from public.land_leads l
    cross join (values (2, 1), (5, 2), (10, 3)) as r(radius_km, prio)
    left join public.lead_infra_scores s
      on s.lead_id = l.id and s.radius_km = r.radius_km
    left join public.lead_infra_score_attempts a
      on a.lead_id = l.id and a.radius_km = r.radius_km
    where coalesce(btrim(l.gps_coordinates), '') <> ''
      and (s.lead_id is null
           or s.fetched_at < now() - interval '80 days'
           or coalesce(s.payload->>'v', '') <> '2')
      and (a.next_try_at is null or a.next_try_at <= now())
    order by r.prio, (l.status in ('signed', 'dropped')), l.added_on desc nulls last, l.id
    limit greatest(1, least(coalesce(p_limit, 1), 5))
  ), leased as (
    insert into public.lead_infra_score_attempts as t
      (lead_id, radius_km, failures, last_attempt_at, next_try_at)
    select p.lead_id, p.radius_km, p.failures, now(), now() + interval '3 minutes'
    from picked p
    on conflict (lead_id, radius_km) do update
      set last_attempt_at = excluded.last_attempt_at,
          next_try_at = excluded.next_try_at
    returning t.lead_id
  )
  select p.lead_id, p.radius_km, p.gps, p.road_width, p.failures from picked p;
end;
$$;

revoke all on function public.infra_score_claim(text, int) from public, anon, authenticated;
grant execute on function public.infra_score_claim(text, int) to service_role;

-- A saved score is for one pin and road width: clear it when either changes,
-- so the app and the fill job fetch it afresh.
create or replace function public.lead_infra_scores_invalidate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.gps_coordinates is distinct from old.gps_coordinates
     or new.road_width is distinct from old.road_width then
    delete from public.lead_infra_scores where lead_id = new.id;
    delete from public.lead_infra_score_attempts where lead_id = new.id;
  end if;
  return null;
end;
$$;

drop trigger if exists land_leads_infra_scores_invalidate on public.land_leads;
create trigger land_leads_infra_scores_invalidate
  after update of gps_coordinates, road_width on public.land_leads
  for each row execute function public.lead_infra_scores_invalidate();

-- The scheduler (run once the endpoint is deployed).
create extension if not exists pg_cron;
select cron.schedule(
  'infra-score-fill',
  '*/2 * * * *',
  $cron$
  select net.http_post(
    url := 'https://land.fomrahousing.in/api/poi/fill-next',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-fill-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'infra_fill_secret')),
    timeout_milliseconds := 60000
  );
  $cron$
);
