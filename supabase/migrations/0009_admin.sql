-- =========================================================
-- TIDEF ITECH LMS -- Phase 9 (admin & reporting)
-- =========================================================
-- Run this AFTER 0001-0008.
--
-- Most of what this phase needs (role changes, suspend/reactivate) is
-- already enforced by the Phase 1 trigger (protect_privileged_fields) --
-- an admin can already update account_status directly, and only a
-- super_admin can change role, purely through normal table updates.
-- This migration only adds what's genuinely new: an audit trail and a
-- small settings table.
-- =========================================================

-- ---------------------------------------------------------
-- 1. activity_logs -- an append-only audit trail of admin/teacher
--    actions (role changes, suspensions, certificate issuance, etc.)
-- ---------------------------------------------------------

create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (id),
  actor_name text,
  action text not null,
  target_type text,
  target_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);

alter table public.activity_logs enable row level security;

drop policy if exists "Staff view activity logs" on public.activity_logs;
create policy "Staff view activity logs"
  on public.activity_logs for select
  using (public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Authenticated users log own actions" on public.activity_logs;
create policy "Authenticated users log own actions"
  on public.activity_logs for insert
  with check (actor_id = auth.uid());

-- Immutable -- no update/delete policy at all, matching
-- payment_approval_logs from Phase 2.

-- ---------------------------------------------------------
-- 2. settings -- simple key/value store for site-wide settings
-- ---------------------------------------------------------

create table if not exists public.settings (
  key text primary key,
  value text,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id)
);

alter table public.settings enable row level security;

drop policy if exists "Anyone signed in can read settings" on public.settings;
create policy "Anyone signed in can read settings"
  on public.settings for select
  using (auth.role() = 'authenticated');

drop policy if exists "Admins manage settings" on public.settings;
create policy "Admins manage settings"
  on public.settings for all
  using (public.current_user_role() in ('admin', 'super_admin'));

insert into public.settings (key, value) values
  ('site_name', 'TIDEF ITECH LMS'),
  ('support_phone', '+234 902 777 2815'),
  ('support_email', 'info@tidefitech.com')
on conflict (key) do nothing;
