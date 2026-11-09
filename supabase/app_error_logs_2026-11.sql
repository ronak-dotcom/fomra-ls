-- Applied directly to production on 2026-11-09 (safe to re-run).
--
-- In-app error log. The Flutter app (ErrorLogService) records failed logins,
-- every error toast/dialog shown to a user, failed actions it catches (e.g.
-- drop-request submit) and uncaught crashes, with who / when / screen / the
-- real database or auth message. Viewed in Settings -> Error Log.
--
-- Anyone may INSERT, including anon: login failures happen before sign-in.
-- Column length checks bound what a single row can hold. Only admins can
-- read or delete. Verified in a rolled-back transaction: anon and an
-- executive can write, the executive reads 0 rows, management reads them.

create table if not exists public.app_error_logs (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  user_id     uuid default auth.uid(),
  user_email  text not null default '',
  user_name   text not null default '',
  source      text not null default 'app' check (char_length(source) <= 40),
  action      text not null default '' check (char_length(action) <= 120),
  screen      text not null default '' check (char_length(screen) <= 300),
  error_type  text not null default '' check (char_length(error_type) <= 120),
  message     text not null default '' check (char_length(message) <= 2000),
  details     text not null default '' check (char_length(details) <= 4000),
  stack       text not null default '' check (char_length(stack) <= 6000),
  platform    text not null default '' check (char_length(platform) <= 60),
  app_build   text not null default '' check (char_length(app_build) <= 60)
);
create index if not exists idx_app_error_logs_created on public.app_error_logs (created_at desc);
create index if not exists idx_app_error_logs_user on public.app_error_logs (lower(user_email), created_at desc);

alter table public.app_error_logs enable row level security;

drop policy if exists "anyone can report app errors" on public.app_error_logs;
create policy "anyone can report app errors" on public.app_error_logs
  for insert to anon, authenticated with check (true);

drop policy if exists "admin can read app errors" on public.app_error_logs;
create policy "admin can read app errors" on public.app_error_logs
  for select to authenticated using (public.current_access_role() = 'admin');

drop policy if exists "admin can delete app errors" on public.app_error_logs;
create policy "admin can delete app errors" on public.app_error_logs
  for delete to authenticated using (public.current_access_role() = 'admin');

grant insert on public.app_error_logs to anon, authenticated;
grant select, delete on public.app_error_logs to authenticated;
