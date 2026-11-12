-- One tag per "Save" of the Add Lead form, so a save sent twice (first reply
-- lost on a weak signal, or queued offline and retried) can't create a
-- duplicate lead. The app looks the tag up before creating.
alter table public.land_leads add column if not exists client_ref text;
create unique index if not exists land_leads_client_ref_key
  on public.land_leads (client_ref) where client_ref is not null;
