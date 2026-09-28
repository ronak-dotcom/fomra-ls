-- Run this in your Supabase SQL Editor (safe to re-run).
--
-- Property reviews by the Reporting Manager / Head / Management on a lead.
-- Each row records one review: who reviewed it, when, a note, and the date
-- the property should be reviewed next. The latest row drives the "Property
-- Review" card on Lead Detail; older rows are kept as the review history.
--
-- Access: anyone who can see the lead (can_access_lead, same rule as the
-- other lead-child tables) can read its reviews. Only a manager/admin tier
-- account may record one — an executive can see that their lead was
-- reviewed and when it is due next, but cannot mark it reviewed themselves.

CREATE TABLE IF NOT EXISTS lead_reviews (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id           TEXT NOT NULL,
  reviewed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_by       TEXT NOT NULL DEFAULT '',          -- reviewer's name
  reviewed_by_email TEXT NOT NULL DEFAULT '',
  reviewer_role     TEXT NOT NULL DEFAULT '',          -- Management / Head / Reporting Manager
  notes             TEXT NOT NULL DEFAULT '',
  next_review_date  DATE,                              -- when to review again (optional)
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lead_reviews_lead
  ON lead_reviews(lead_id, reviewed_at DESC);
CREATE INDEX IF NOT EXISTS idx_lead_reviews_next
  ON lead_reviews(next_review_date);

ALTER TABLE lead_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "lead-scoped read of lead_reviews" ON lead_reviews;
CREATE POLICY "lead-scoped read of lead_reviews" ON lead_reviews
  FOR SELECT TO authenticated
  USING (public.can_access_lead(lead_id));

DROP POLICY IF EXISTS "managers record lead_reviews" ON lead_reviews;
CREATE POLICY "managers record lead_reviews" ON lead_reviews
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_lead(lead_id)
    AND public.current_access_role() IN ('admin', 'manager')
  );

DROP POLICY IF EXISTS "managers edit lead_reviews" ON lead_reviews;
CREATE POLICY "managers edit lead_reviews" ON lead_reviews
  FOR UPDATE TO authenticated
  USING (
    public.can_access_lead(lead_id)
    AND public.current_access_role() IN ('admin', 'manager')
  )
  WITH CHECK (
    public.can_access_lead(lead_id)
    AND public.current_access_role() IN ('admin', 'manager')
  );

DROP POLICY IF EXISTS "admins delete lead_reviews" ON lead_reviews;
CREATE POLICY "admins delete lead_reviews" ON lead_reviews
  FOR DELETE TO authenticated
  USING (public.current_access_role() = 'admin');
