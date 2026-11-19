-- Names with a capital at the start of every word ("mani" -> "Mani",
-- "dinesh kumar" -> "Dinesh Kumar", "k.mani" -> "K.Mani"); the rest of each
-- word stays as typed, so "NRI" / "McArthur" are kept. Same rule as
-- lib/utils/name_case.dart capWords. Applied on every save by triggers, and
-- once to everything already saved.

create or replace function public.cap_words(t text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  result text := '';
  ch text;
  start_of_word boolean := true;
begin
  if t is null or t = '' then
    return t;
  end if;
  foreach ch in array regexp_split_to_array(t, '') loop
    result := result || case when start_of_word then upper(ch) else ch end;
    start_of_word := ch ~ '[[:space:].(\[/,&+-]';
  end loop;
  return result;
end;
$$;

-- The same for the "name" of each entry in a JSON list
-- ([{"name": "dinesh", "contact": "..."}]).
create or replace function public.cap_names_json(j jsonb)
returns jsonb
language sql
immutable
set search_path = public, pg_catalog
as $$
  select case
    when j is null or jsonb_typeof(j) <> 'array' then j
    else coalesce((
      select jsonb_agg(
        case
          when jsonb_typeof(e) = 'object' and jsonb_typeof(e -> 'name') = 'string'
            then jsonb_set(e, '{name}', to_jsonb(public.cap_words(e ->> 'name')))
          else e
        end
        order by ord)
      from jsonb_array_elements(j) with ordinality as a(e, ord)
    ), '[]'::jsonb)
  end
$$;

-- Leads: people, places and the lead name.
create or replace function public.land_leads_cap_names()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.owner_name := cap_words(new.owner_name);
  new.broker_name := cap_words(new.broker_name);
  new.source_contact_name := cap_words(new.source_contact_name);
  new.lead_name := cap_words(new.lead_name);
  new.village := cap_words(new.village);
  new.location := cap_words(new.location);
  new.taluk := cap_words(new.taluk);
  new.district := cap_words(new.district);
  new.created_by_name := cap_words(new.created_by_name);
  new.assigned_to_name := cap_words(new.assigned_to_name);
  new.additional_owners := cap_names_json(new.additional_owners);
  return new;
end;
$$;
drop trigger if exists trg_land_leads_cap_names on public.land_leads;
create trigger trg_land_leads_cap_names
  before insert or update on public.land_leads
  for each row execute function public.land_leads_cap_names();

-- Broker directory: the shown name and every spelling seen.
create or replace function public.brokers_cap_names()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.display_name := cap_words(new.display_name);
  new.aliases := (
    select coalesce(array_agg(a order by first_seen), '{}')
    from (
      select cap_words(x) as a, min(ord) as first_seen
      from unnest(new.aliases) with ordinality as u(x, ord)
      group by cap_words(x)
    ) d
  );
  return new;
end;
$$;
drop trigger if exists trg_brokers_cap_names on public.brokers;
create trigger trg_brokers_cap_names
  before insert or update on public.brokers
  for each row execute function public.brokers_cap_names();

-- Employees.
create or replace function public.employee_profiles_cap_names()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.full_name := cap_words(new.full_name);
  return new;
end;
$$;
drop trigger if exists trg_employee_profiles_cap_names on public.employee_profiles;
create trigger trg_employee_profiles_cap_names
  before insert or update on public.employee_profiles
  for each row execute function public.employee_profiles_cap_names();

-- Meetings: who was met, and who logged it.
create or replace function public.land_lead_meetings_cap_names()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.people_met := cap_names_json(new.people_met);
  new.logged_by_name := cap_words(new.logged_by_name);
  return new;
end;
$$;
drop trigger if exists trg_land_lead_meetings_cap_names on public.land_lead_meetings;
create trigger trg_land_lead_meetings_cap_names
  before insert or update on public.land_lead_meetings
  for each row execute function public.land_lead_meetings_cap_names();

-- One-time: everything already saved (only rows that change; the triggers
-- above do the capitalising).
update public.land_leads set owner_name = owner_name
where owner_name is distinct from cap_words(owner_name)
   or broker_name is distinct from cap_words(broker_name)
   or source_contact_name is distinct from cap_words(source_contact_name)
   or lead_name is distinct from cap_words(lead_name)
   or village is distinct from cap_words(village)
   or location is distinct from cap_words(location)
   or taluk is distinct from cap_words(taluk)
   or district is distinct from cap_words(district)
   or created_by_name is distinct from cap_words(created_by_name)
   or assigned_to_name is distinct from cap_words(assigned_to_name)
   or additional_owners is distinct from cap_names_json(additional_owners);

update public.brokers set display_name = display_name
where display_name is distinct from cap_words(display_name)
   or exists (select 1 from unnest(aliases) a where a is distinct from cap_words(a));

update public.employee_profiles set full_name = full_name
where full_name is distinct from cap_words(full_name);

update public.land_lead_meetings set people_met = people_met
where people_met is distinct from cap_names_json(people_met)
   or logged_by_name is distinct from cap_words(logged_by_name);
