-- Land owner profile, captured when a Land Owner meeting is logged.
-- Owner type lives in the existing owner_occupation column (a key such as
-- 'farmer'); these two add where the owner lives and who decides on selling.
alter table public.land_leads add column if not exists owner_lives text not null default '';
alter table public.land_leads add column if not exists owner_decision text not null default '';
