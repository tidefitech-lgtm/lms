-- =========================================================
-- TIDEF ITECH LMS — Phase 1 schema (Supabase / Postgres)
-- =========================================================
-- Run this once in Supabase Dashboard → SQL Editor → New query → Run.
-- (Or via CLI: supabase db push, if you're using migrations locally.)
-- =========================================================

-- ---------------------------------------------------------
-- 1. profiles table
-- ---------------------------------------------------------
-- One row per user, keyed to auth.users. Role/status columns all have
-- hard-coded safe defaults and are populated ONLY by the trigger below —
-- there is no INSERT policy that lets a client write this table directly,
-- so a student cannot register themselves as approved, paid, or staff.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  email text,
  phone text,
  dob date,
  gender text,
  address text,

  role text not null default 'student'
    check (role in ('student', 'teacher', 'admin', 'super_admin')),

  student_id text unique, -- assigned by an admin-triggered function on approval (Phase 2)

  profile_photo_url text,
  interested_course_id uuid,

  account_status text not null default 'pending'
    check (account_status in ('pending', 'approved', 'suspended', 'rejected')),

  payment_status text not null default 'not_submitted'
    check (payment_status in ('not_submitted', 'pending_verification', 'confirmed', 'rejected')),

  enrollment_status text not null default 'inactive'
    check (enrollment_status in ('inactive', 'active', 'completed')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- ---------------------------------------------------------
-- 2. Auto-create a profile row when someone signs up
-- ---------------------------------------------------------
-- Reads only the safe, self-descriptive fields out of the signup metadata
-- (full_name, phone, dob, gender, address, interested_course_id) — it never
-- reads role/account_status/payment_status/student_id from anything the
-- client sent, so those columns always start at their table defaults.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, phone, dob, gender, address, interested_course_id)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.email,
    new.raw_user_meta_data ->> 'phone',
    nullif(new.raw_user_meta_data ->> 'dob', '')::date,
    new.raw_user_meta_data ->> 'gender',
    new.raw_user_meta_data ->> 'address',
    nullif(new.raw_user_meta_data ->> 'interested_course_id', '')::uuid
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------
-- 3. Helper: current user's role, without RLS recursion
-- ---------------------------------------------------------
-- SECURITY DEFINER lets this function read profiles even though the
-- caller's own SELECT policy hasn't been evaluated yet — avoids the
-- classic "policy on profiles that queries profiles" infinite loop.

create or replace function public.current_user_role()
returns text
language sql
security definer set search_path = public
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- ---------------------------------------------------------
-- 4. Guard against self-privilege-escalation on UPDATE
-- ---------------------------------------------------------
-- A student can update their own row (RLS policy below allows it), but
-- this trigger blocks any attempt — from the browser, curl, or anywhere
-- else — to change role/account_status/payment_status/enrollment_status/
-- student_id unless the actor is staff. Only a super_admin may change role.

create or replace function public.protect_privileged_fields()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  acting_role text := public.current_user_role();
begin
  if acting_role in ('admin', 'super_admin') then
    if acting_role <> 'super_admin' and new.role <> old.role then
      raise exception 'Only a super admin can change role.';
    end if;
    return new;
  end if;

  if new.role <> old.role
     or new.account_status <> old.account_status
     or new.payment_status <> old.payment_status
     or new.enrollment_status <> old.enrollment_status
     or new.student_id is distinct from old.student_id
  then
    raise exception 'You are not allowed to change this field.';
  end if;

  return new;
end;
$$;

drop trigger if exists before_profile_update on public.profiles;
create trigger before_profile_update
  before update on public.profiles
  for each row execute procedure public.protect_privileged_fields();

-- ---------------------------------------------------------
-- 5. RLS policies for profiles
-- ---------------------------------------------------------
-- No INSERT policy exists at all — profile rows can only be created by the
-- security-definer trigger above, never directly by a client.

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Staff can view all profiles" on public.profiles;
create policy "Staff can view all profiles"
  on public.profiles for select
  using (public.current_user_role() in ('admin', 'super_admin', 'teacher'));

drop policy if exists "Owner or staff can update profile" on public.profiles;
create policy "Owner or staff can update profile"
  on public.profiles for update
  using (auth.uid() = id or public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Super admin can delete profiles" on public.profiles;
create policy "Super admin can delete profiles"
  on public.profiles for delete
  using (public.current_user_role() = 'super_admin');

-- ---------------------------------------------------------
-- 6. courses table (used by the registration page's course dropdown;
--    fully built out in Phase 3)
-- ---------------------------------------------------------

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'archived')),
  created_at timestamptz not null default now()
);

alter table public.courses enable row level security;

drop policy if exists "Anyone can view published courses" on public.courses;
create policy "Anyone can view published courses"
  on public.courses for select
  using (status = 'published');

drop policy if exists "Staff can view all courses" on public.courses;
create policy "Staff can view all courses"
  on public.courses for select
  using (public.current_user_role() in ('admin', 'super_admin', 'teacher'));

drop policy if exists "Staff can manage courses" on public.courses;
create policy "Staff can manage courses"
  on public.courses for all
  using (public.current_user_role() in ('admin', 'super_admin', 'teacher'));

-- ---------------------------------------------------------
-- 7. Tables reserved for Phase 2 (payments) — created now so RLS is in
--    place from day one, even though no UI writes to them yet.
-- ---------------------------------------------------------

create table if not exists public.payment_confirmations (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid references public.courses (id),
  payment_status text not null default 'pending_verification'
    check (payment_status in ('pending_verification', 'confirmed', 'rejected')),
  payment_reference text,
  payment_date date,
  payment_method text,
  student_note text,
  submitted_at timestamptz not null default now(),
  verified_by uuid references public.profiles (id),
  verified_at timestamptz,
  admin_note text
);

alter table public.payment_confirmations enable row level security;

drop policy if exists "Students view own payment confirmations" on public.payment_confirmations;
create policy "Students view own payment confirmations"
  on public.payment_confirmations for select
  using (auth.uid() = student_id or public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Students create own pending confirmation" on public.payment_confirmations;
create policy "Students create own pending confirmation"
  on public.payment_confirmations for insert
  with check (auth.uid() = student_id and payment_status = 'pending_verification');

drop policy if exists "Only staff can verify or reject payments" on public.payment_confirmations;
create policy "Only staff can verify or reject payments"
  on public.payment_confirmations for update
  using (public.current_user_role() in ('admin', 'super_admin'));

create table if not exists public.payment_approval_logs (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id),
  previous_status text,
  new_status text,
  admin_id uuid references public.profiles (id),
  admin_name text,
  note text,
  created_at timestamptz not null default now()
);

alter table public.payment_approval_logs enable row level security;

drop policy if exists "Staff can view audit logs" on public.payment_approval_logs;
create policy "Staff can view audit logs"
  on public.payment_approval_logs for select
  using (public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Staff can write audit logs" on public.payment_approval_logs;
create policy "Staff can write audit logs"
  on public.payment_approval_logs for insert
  with check (public.current_user_role() in ('admin', 'super_admin'));

-- ---------------------------------------------------------
-- 8. notifications table (skeleton for later phases)
-- ---------------------------------------------------------

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.notifications enable row level security;

drop policy if exists "Users view own notifications" on public.notifications;
create policy "Users view own notifications"
  on public.notifications for select
  using (auth.uid() = user_id);

drop policy if exists "Users mark own notifications read" on public.notifications;
create policy "Users mark own notifications read"
  on public.notifications for update
  using (auth.uid() = user_id);

drop policy if exists "Staff can create notifications" on public.notifications;
create policy "Staff can create notifications"
  on public.notifications for insert
  with check (public.current_user_role() in ('admin', 'super_admin', 'teacher'));

-- ---------------------------------------------------------
-- 9. Storage bucket + policies for profile photos
-- ---------------------------------------------------------
-- Path convention: profile-photos/{uid}/{filename}

insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do nothing;

drop policy if exists "Users upload own profile photo" on storage.objects;
create policy "Users upload own profile photo"
  on storage.objects for insert
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users update own profile photo" on storage.objects;
create policy "Users update own profile photo"
  on storage.objects for update
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete own profile photo" on storage.objects;
create policy "Users delete own profile photo"
  on storage.objects for delete
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Signed-in users can view profile photos" on storage.objects;
create policy "Signed-in users can view profile photos"
  on storage.objects for select
  using (bucket_id = 'profile-photos' and auth.role() = 'authenticated');
