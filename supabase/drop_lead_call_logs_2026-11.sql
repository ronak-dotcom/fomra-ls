-- The team doesn't log calls in the app (0 rows ever); the Calls feature was
-- removed. Apply only after the app version without it is live — older
-- builds read this table when a lead page opens.
drop table if exists public.lead_call_logs;
