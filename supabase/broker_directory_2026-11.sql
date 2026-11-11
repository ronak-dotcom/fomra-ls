-- Broker Directory: one broker per mobile number, with one display name.
-- Leads keep their typed broker_name / broker_contact; the app shows the
-- directory's display_name for a lead's broker number, so a spelling slip
-- ("kalai" vs "Kalaiarasu") no longer splits one broker into two.
-- Applied to production 2026-11-11.

-- Last 10 digits of a phone, or null when it has fewer than 10 digits.
create or replace function public.broker_phone_key(raw text)
returns text language sql immutable as $$
  select case
    when length(regexp_replace(coalesce(raw, ''), '\D', '', 'g')) >= 10
    then right(regexp_replace(raw, '\D', '', 'g'), 10)
  end;
$$;

-- Spelling-insensitive form of a name: lower case, letters only.
create or replace function public.broker_name_key(raw text)
returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(raw, '')), '[^a-z]', '', 'g');
$$;

create table if not exists public.brokers (
  phone           text primary key check (phone ~ '^\d{10}$'),
  display_name    text not null,
  -- Every spelling the team has entered for this number.
  aliases         text[] not null default '{}',
  -- Spellings genuinely differ (not just case/spaces): management picks or
  -- types the name in the Broker Directory.
  needs_review    boolean not null default false,
  reviewed_by     text,
  reviewed_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table public.brokers enable row level security;

-- Every signed-in staff member can read the directory (the add-lead form
-- fills a known broker's name from their number) and add a new broker.
drop policy if exists "brokers readable by staff" on public.brokers;
create policy "brokers readable by staff" on public.brokers
  for select to authenticated using (true);
drop policy if exists "brokers added by staff" on public.brokers;
create policy "brokers added by staff" on public.brokers
  for insert to authenticated with check (true);
-- Only management renames or removes a broker.
drop policy if exists "brokers edited by management" on public.brokers;
create policy "brokers edited by management" on public.brokers
  for update to authenticated
  using (public.current_access_role() = 'admin')
  with check (public.current_access_role() = 'admin');
drop policy if exists "brokers removed by management" on public.brokers;
create policy "brokers removed by management" on public.brokers
  for delete to authenticated
  using (public.current_access_role() = 'admin');

-- Keep the directory in step with leads, whatever path saved them (form,
-- offline sync, approval). A new number becomes a new broker; a known
-- number gains the spelling as an alias, and is flagged for review when
-- that spelling genuinely differs from the ones already seen.
create or replace function public.sync_broker_directory()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  k text := public.broker_phone_key(new.broker_contact);
  n text := btrim(coalesce(new.broker_name, ''));
begin
  if k is null or n = '' then
    return new;
  end if;
  insert into public.brokers (phone, display_name, aliases)
  values (k, n, array[n])
  on conflict (phone) do update set
    aliases = case when n = any(brokers.aliases) then brokers.aliases
                   else brokers.aliases || n end,
    needs_review = brokers.needs_review or (
      public.broker_name_key(n) <> public.broker_name_key(brokers.display_name)
      and not exists (
        select 1 from unnest(brokers.aliases) a
        where public.broker_name_key(a) = public.broker_name_key(n)
      )
    ),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_sync_broker_directory on public.land_leads;
create trigger trg_sync_broker_directory
  after insert or update of broker_name, broker_contact on public.land_leads
  for each row execute function public.sync_broker_directory();

-- Management: move every lead filed under a mistyped number onto the right
-- one (e.g. 0875488083 -> 8754880836), fold its spellings in, and drop it.
create or replace function public.merge_broker_phone(from_phone text, to_phone text)
returns integer language plpgsql security definer set search_path = public as $$
declare
  moved integer;
  src public.brokers;
begin
  if public.current_access_role() <> 'admin' then
    raise exception 'Only management can merge brokers.';
  end if;
  if from_phone = to_phone then
    raise exception 'Choose two different numbers.';
  end if;
  if not exists (select 1 from public.brokers where phone = to_phone) then
    raise exception 'Unknown broker number %.', to_phone;
  end if;
  select * into src from public.brokers where phone = from_phone;
  update public.land_leads
     set broker_contact = to_phone, updated_at = now()
   where public.broker_phone_key(broker_contact) = from_phone;
  get diagnostics moved = row_count;
  if src.phone is not null then
    update public.brokers b
       set aliases = (select array_agg(distinct a) from unnest(b.aliases || src.aliases) a),
           updated_at = now()
     where b.phone = to_phone;
    delete from public.brokers where phone = from_phone;
  end if;
  return moved;
end;
$$;
revoke all on function public.merge_broker_phone(text, text) from public, anon;
grant execute on function public.merge_broker_phone(text, text) to authenticated;

-- Seed from existing leads. Numbers whose spellings differ only by case or
-- spaces get a tidy name automatically; the rest are flagged for review,
-- pre-filled with the most-used spelling.
insert into public.brokers (phone, display_name, aliases, needs_review)
select k,
       (array_agg(n order by cnt desc, (n ~ '^[A-Z]') desc, length(n) desc))[1],
       array_agg(n order by cnt desc),
       count(distinct public.broker_name_key(n)) > 1
from (
  select public.broker_phone_key(broker_contact) k, btrim(broker_name) n, count(*) cnt
  from public.land_leads
  where public.broker_phone_key(broker_contact) is not null
    and btrim(coalesce(broker_name, '')) <> ''
  group by 1, 2
) s
group by k
on conflict (phone) do nothing;

-- Tidy auto-named entries: an all-lower-case name gets initial capitals.
update public.brokers
   set display_name = initcap(display_name)
 where not needs_review and display_name = lower(display_name);
