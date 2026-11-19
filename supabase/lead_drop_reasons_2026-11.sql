-- Drop reasons shared by everyone; only management (admin) can change them.
-- Hidden reasons (active = false) are not offered for new drops.
create table if not exists public.lead_drop_reasons (
  id text primary key,
  label text not null,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.lead_drop_reasons enable row level security;
create policy "drop reasons readable by staff" on public.lead_drop_reasons for select to authenticated using (true);
create policy "drop reasons added by management" on public.lead_drop_reasons for insert to authenticated with check (current_access_role() = 'admin');
create policy "drop reasons edited by management" on public.lead_drop_reasons for update to authenticated using (current_access_role() = 'admin') with check (current_access_role() = 'admin');
insert into public.lead_drop_reasons (id, label, sort_order) values
  ('owner_related_issues','Owner Related Issues',1),
  ('price_budget_mismatch','Price / Budget Mismatch',2),
  ('legal_document_issues','Legal & Document Issues',3),
  ('location_surrounding_issues','Location & Surrounding Issues',4),
  ('land_suitability_issues','Land Suitability Issues',5),
  ('negotiation_failed','Negotiation Failed',6),
  ('business_management_decision','Business / Management Decision',7),
  ('land_owner_meeting_pending_no_response','Land Owner Meeting Pending / No Response',8)
on conflict (id) do nothing;
