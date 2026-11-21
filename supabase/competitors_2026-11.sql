-- Competitor projects (nearby developer projects), tracked like leads:
-- one row per project with its latest figures, phases (plots / sold / left
-- per phase), a history of price & sales checks, photos / documents, and
-- hand links to leads (leads also see projects within 2/5/10 km and in the
-- same village automatically, in the app).

create sequence if not exists public.competitor_code_seq;

create table if not exists public.competitor_projects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique
    default ('C-' || lpad(nextval('public.competitor_code_seq')::text, 3, '0')),
  name text not null,
  builder text not null default '',
  project_type text not null default 'layout'
    check (project_type in ('layout', 'villa', 'apartment', 'land')),
  stage text not null default 'ongoing'
    check (stage in ('upcoming', 'ongoing', 'completed', 'resale')),
  village text not null default '',
  taluk text not null default '',
  district text not null default '',
  lat double precision,
  lng double precision,
  gps_note text not null default '',
  maps_link text not null default '',
  extent_acres numeric,
  approval_authority text not null default '',
  approval_no text not null default '',
  rera_no text not null default '',
  main_road_ft numeric,
  min_plot_sqft integer,
  max_plot_sqft integer,
  pre_launch_price numeric,
  quoted_price numeric,
  negotiated_price numeric,
  plc_corner numeric,
  plc_facing numeric,
  plc_road numeric,
  glv numeric,
  documentation_charges numeric,
  maintenance_charge numeric,
  corpus numeric,
  other_charges text not null default '',
  sales_person text not null default '',
  sales_phone text not null default '',
  amenities text not null default '',
  launch_date date,
  notes text not null default '',
  owner_name text not null default '',
  owner_email text not null default '',
  created_by_name text not null default '',
  source text not null default 'field'
    check (source in ('field', 'import', 'portal')),
  last_checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter sequence public.competitor_code_seq owned by public.competitor_projects.code;

create table if not exists public.competitor_phases (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.competitor_projects(id) on delete cascade,
  label text not null default '',
  launch_date date,
  plots integer,
  sold integer,
  available integer,
  min_plot_sqft integer,
  max_plot_sqft integer,
  sort integer not null default 0
);
create index if not exists competitor_phases_project_idx
  on public.competitor_phases (project_id, sort);

create table if not exists public.competitor_checks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.competitor_projects(id) on delete cascade,
  checked_at timestamptz not null default now(),
  checked_by_name text not null default '',
  pre_launch_price numeric,
  quoted_price numeric,
  negotiated_price numeric,
  sold integer,
  available integer,
  notes text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists competitor_checks_project_idx
  on public.competitor_checks (project_id, checked_at desc);

create table if not exists public.competitor_media (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.competitor_projects(id) on delete cascade,
  kind text not null default 'photo' check (kind in ('photo', 'document')),
  storage_path text not null,
  file_name text not null default '',
  content_type text not null default '',
  uploaded_by_name text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists competitor_media_project_idx
  on public.competitor_media (project_id, created_at desc);

create table if not exists public.competitor_lead_links (
  project_id uuid not null references public.competitor_projects(id) on delete cascade,
  lead_id text not null,
  linked_by_name text not null default '',
  created_at timestamptz not null default now(),
  primary key (project_id, lead_id)
);
create index if not exists competitor_lead_links_lead_idx
  on public.competitor_lead_links (lead_id);

-- Everyone signed in can see, add and update; only admins delete projects.
alter table public.competitor_projects enable row level security;
alter table public.competitor_phases enable row level security;
alter table public.competitor_checks enable row level security;
alter table public.competitor_media enable row level security;
alter table public.competitor_lead_links enable row level security;

do $$
declare t text;
begin
  foreach t in array array['competitor_projects', 'competitor_phases',
      'competitor_checks', 'competitor_media', 'competitor_lead_links'] loop
    execute format('drop policy if exists "authenticated read %1$s" on public.%1$I', t);
    execute format('create policy "authenticated read %1$s" on public.%1$I for select to authenticated using (true)', t);
    execute format('drop policy if exists "authenticated add %1$s" on public.%1$I', t);
    execute format('create policy "authenticated add %1$s" on public.%1$I for insert to authenticated with check (true)', t);
    execute format('drop policy if exists "authenticated update %1$s" on public.%1$I', t);
    execute format('create policy "authenticated update %1$s" on public.%1$I for update to authenticated using (true) with check (true)', t);
  end loop;
end $$;

drop policy if exists "admin delete competitor_projects" on public.competitor_projects;
create policy "admin delete competitor_projects" on public.competitor_projects
  for delete to authenticated using (public.current_access_role() = 'admin');
-- Phases are replaced when a project is edited; links can be removed; a
-- wrong photo can be removed.
drop policy if exists "authenticated delete competitor_phases" on public.competitor_phases;
create policy "authenticated delete competitor_phases" on public.competitor_phases
  for delete to authenticated using (true);
drop policy if exists "authenticated delete competitor_lead_links" on public.competitor_lead_links;
create policy "authenticated delete competitor_lead_links" on public.competitor_lead_links
  for delete to authenticated using (true);
drop policy if exists "authenticated delete competitor_media" on public.competitor_media;
create policy "authenticated delete competitor_media" on public.competitor_media
  for delete to authenticated using (true);

-- Names with capitals, like leads (cap_words keeps existing capitals).
create or replace function public.competitor_projects_cap_names()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.name := cap_words(new.name);
  new.builder := cap_words(new.builder);
  new.village := cap_words(new.village);
  new.taluk := cap_words(new.taluk);
  new.district := cap_words(new.district);
  new.sales_person := cap_words(new.sales_person);
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_competitor_projects_cap_names on public.competitor_projects;
create trigger trg_competitor_projects_cap_names
  before insert or update on public.competitor_projects
  for each row execute function public.competitor_projects_cap_names();

-- Photos and documents: private; played / opened through short-lived links.
insert into storage.buckets (id, name, public)
values ('competitor-media', 'competitor-media', false)
on conflict (id) do update set public = false;

drop policy if exists "authenticated can read competitor media" on storage.objects;
create policy "authenticated can read competitor media"
  on storage.objects for select to authenticated
  using (bucket_id = 'competitor-media');
drop policy if exists "authenticated can upload competitor media" on storage.objects;
create policy "authenticated can upload competitor media"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'competitor-media');
drop policy if exists "authenticated can delete competitor media" on storage.objects;
create policy "authenticated can delete competitor media"
  on storage.objects for delete to authenticated
  using (bucket_id = 'competitor-media');
