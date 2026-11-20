-- Voice notes on a lead: the audio (private bucket — only signed-in users can
-- play it, through a short-lived link) and the text written while speaking.
-- The lead's notes also get one line per voice note, which the timeline shows.

insert into storage.buckets (id, name, public)
values ('land-lead-voice-notes', 'land-lead-voice-notes', false)
on conflict (id) do update set public = false;

drop policy if exists "authenticated can read voice notes" on storage.objects;
create policy "authenticated can read voice notes"
  on storage.objects for select to authenticated
  using (bucket_id = 'land-lead-voice-notes');

drop policy if exists "authenticated can upload voice notes" on storage.objects;
create policy "authenticated can upload voice notes"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'land-lead-voice-notes');

drop policy if exists "authenticated can delete voice notes" on storage.objects;
create policy "authenticated can delete voice notes"
  on storage.objects for delete to authenticated
  using (bucket_id = 'land-lead-voice-notes');

create table if not exists public.land_lead_voice_notes (
  id uuid primary key default gen_random_uuid(),
  lead_id text not null,
  storage_path text not null,
  duration_ms integer not null default 0,
  transcript text not null default '',
  logged_by uuid,
  logged_by_name text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists land_lead_voice_notes_lead_idx
  on public.land_lead_voice_notes (lead_id, created_at desc);

alter table public.land_lead_voice_notes enable row level security;
drop policy if exists "authenticated read voice notes" on public.land_lead_voice_notes;
create policy "authenticated read voice notes"
  on public.land_lead_voice_notes for select to authenticated using (true);
drop policy if exists "authenticated add voice notes" on public.land_lead_voice_notes;
create policy "authenticated add voice notes"
  on public.land_lead_voice_notes for insert to authenticated with check (true);

-- What a voice note is about: follow_up, owner_meeting, site_visit,
-- management, other ('' for notes recorded before this existed).
alter table public.land_lead_voice_notes
  add column if not exists topic text not null default '';
