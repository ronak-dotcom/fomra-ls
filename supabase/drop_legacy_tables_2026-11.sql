-- Remove three tables left over from the first version of the app. All were
-- empty (0 rows) on 2026-11-12, referenced only each other and profiles, and
-- no app code, function, view or trigger used them (the app uses
-- land_leads, land_lead_site_visits and lead_follow_ups instead).
drop table if exists public.site_visits;
drop table if exists public.tasks;
drop table if exists public.leads;
