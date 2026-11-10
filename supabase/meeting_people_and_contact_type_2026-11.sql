-- Who was met at a land owner meeting, and who the lead's main contact is.
-- Applied to production 2026-11-10.

-- People met at this meeting: [{"name": "Ravi", "relation": "Son"}, ...].
-- relation is to the land owner (Land Owner, Agreement Holder / PoA, Son, ...).
alter table public.land_lead_meetings
  add column if not exists people_met jsonb not null default '[]'::jsonb;

-- Lead-level: is the main contact the owner, an agreement holder or a relative?
alter table public.land_leads
  add column if not exists contact_type text not null default '';
alter table public.land_leads
  add column if not exists contact_relation text not null default '';
