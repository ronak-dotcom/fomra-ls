-- Applied directly to production on 2026-11-09 (safe to re-run).
--
-- Two RLS gaps left by the August lockdown, both hitting individual
-- employee logins (current_access_role() = 'executive'):
--
-- 1. notifications: the only policy allowed INSERT when the audience was
--    'employee' or the sender's own email. Every executive -> management /
--    approver notification (rename, field-change, drop and site-visit
--    approval requests) was rejected with 403. Sending now works for any
--    signed-in user; each row records its sender, and the sender may read
--    back only what they sent (the app's insert().select() needs that).
--    Reading anyone else's notifications is unchanged.
--
-- 2. device_tokens: PushService upserts (INSERT ... ON CONFLICT DO UPDATE),
--    which RLS checks against the SELECT policy too — admin-only — so no
--    employee device had registered for push since mid-September. Each
--    token now records its owner, and a user may read only their own.
--    api/push.js reads tokens with the service role and is unaffected.
--
-- Verified as Saurabh (executive) in a rolled-back transaction before
-- applying: both writes fail before, succeed after; he sees only his own
-- token and none of management's notifications.

alter table notifications add column if not exists created_by_email text default lower(public.current_user_email());
drop policy if exists "authenticated can send notifications" on notifications;
create policy "authenticated can send notifications" on notifications
  for insert to authenticated with check (true);
drop policy if exists "senders can read their own sent notifications" on notifications;
create policy "senders can read their own sent notifications" on notifications
  for select to authenticated
  using (created_by_email is not null and created_by_email = lower(public.current_user_email()));

alter table device_tokens add column if not exists owner_id uuid default auth.uid();
drop policy if exists "users can read their own device_tokens" on device_tokens;
create policy "users can read their own device_tokens" on device_tokens
  for select to authenticated using (owner_id = auth.uid());
