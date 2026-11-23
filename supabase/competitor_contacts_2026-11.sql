-- Several sales contacts per competitor project (name, phone, role, one
-- main contact). The project's sales_person / sales_phone keep the main
-- contact, for the comparison table and older screens.

create table if not exists public.competitor_contacts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.competitor_projects(id) on delete cascade,
  name text not null default '',
  phone text not null default '',
  role text not null default 'sales'
    check (role in ('sales', 'sales_manager', 'site_incharge', 'channel_partner', 'other')),
  is_main boolean not null default false,
  sort integer not null default 0,
  created_by_name text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists competitor_contacts_project_idx
  on public.competitor_contacts (project_id, sort);

alter table public.competitor_contacts enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'competitor_contacts'
                 and policyname = 'authenticated read competitor_contacts') then
    create policy "authenticated read competitor_contacts" on public.competitor_contacts
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'competitor_contacts'
                 and policyname = 'authenticated add competitor_contacts') then
    create policy "authenticated add competitor_contacts" on public.competitor_contacts
      for insert to authenticated with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'competitor_contacts'
                 and policyname = 'authenticated update competitor_contacts') then
    create policy "authenticated update competitor_contacts" on public.competitor_contacts
      for update to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'competitor_contacts'
                 and policyname = 'authenticated delete competitor_contacts') then
    create policy "authenticated delete competitor_contacts" on public.competitor_contacts
      for delete to authenticated using (true);
  end if;
end $$;

-- Names with capitals, like everywhere else.
create or replace function public.competitor_contacts_cap_names()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.name := cap_words(new.name);
  return new;
end;
$$;
create or replace trigger trg_competitor_contacts_cap_names
  before insert or update on public.competitor_contacts
  for each row execute function public.competitor_contacts_cap_names();

-- Today's single sales person becomes each project's main contact.
insert into public.competitor_contacts (project_id, name, phone, role, is_main, sort, created_by_name)
select p.id, p.sales_person, p.sales_phone, 'sales', true, 0, p.created_by_name
from public.competitor_projects p
where (btrim(p.sales_person) <> '' or btrim(p.sales_phone) <> '')
  and not exists (select 1 from public.competitor_contacts c where c.project_id = p.id);
