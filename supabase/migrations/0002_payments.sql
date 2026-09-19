-- =========================================================
-- TIDEF ITECH LMS — Phase 2 (payments & approval)
-- =========================================================
-- Run this AFTER 0001_init.sql, in Supabase Dashboard -> SQL Editor.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Allow a student to move their OWN payment_status from
--    not_submitted/rejected -> pending_verification (i.e. only the
--    "I Have Completed Payment" request itself). Every other privileged
--    field -- role, account_status, enrollment_status, student_id, or any
--    other payment_status transition (e.g. straight to 'confirmed') --
--    remains completely blocked for non-staff, exactly as in Phase 1.
-- ---------------------------------------------------------

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
     or new.enrollment_status <> old.enrollment_status
     or new.student_id is distinct from old.student_id
  then
    raise exception 'You are not allowed to change this field.';
  end if;

  if new.payment_status <> old.payment_status then
    if not (
      old.payment_status in ('not_submitted', 'rejected')
      and new.payment_status = 'pending_verification'
    ) then
      raise exception 'You are not allowed to change this field.';
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------
-- 2. Sequential Student ID generator: TIDEF-YYYY-0001, race-safe via
--    upsert (the ON CONFLICT DO UPDATE is atomic per row).
-- ---------------------------------------------------------

create table if not exists public.id_counters (
  year int primary key,
  last_number int not null default 0
);

alter table public.id_counters enable row level security;
-- No policies at all: this table is only ever touched by the
-- SECURITY DEFINER function below, never directly by any client.

create or replace function public.next_student_id()
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  yr int := extract(year from now())::int;
  next_num int;
begin
  insert into public.id_counters (year, last_number)
  values (yr, 1)
  on conflict (year) do update set last_number = public.id_counters.last_number + 1
  returning last_number into next_num;

  return 'TIDEF-' || yr || '-' || lpad(next_num::text, 4, '0');
end;
$$;

revoke execute on function public.next_student_id() from public;

-- ---------------------------------------------------------
-- 3. Student: submit "I Have Completed Payment"
-- ---------------------------------------------------------
-- Always inserts as pending_verification -- the student cannot pass any
-- other status in. Refuses a second submission while one is already
-- pending, or if payment is already confirmed.

create or replace function public.submit_payment_confirmation(
  p_course_id uuid,
  p_payment_reference text default null,
  p_payment_date date default null,
  p_payment_method text default null,
  p_student_note text default null
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_current_status text;
  v_new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select payment_status into v_current_status from public.profiles where id = auth.uid();

  if v_current_status = 'pending_verification' then
    raise exception 'You already have a payment confirmation awaiting review.';
  end if;
  if v_current_status = 'confirmed' then
    raise exception 'Your payment has already been confirmed.';
  end if;

  insert into public.payment_confirmations
    (student_id, course_id, payment_status, payment_reference, payment_date, payment_method, student_note)
  values
    (auth.uid(), p_course_id, 'pending_verification', p_payment_reference, p_payment_date, p_payment_method, p_student_note)
  returning id into v_new_id;

  update public.profiles
  set payment_status = 'pending_verification', updated_at = now()
  where id = auth.uid();

  return v_new_id;
end;
$$;

revoke execute on function public.submit_payment_confirmation(uuid, text, date, text, text) from public;
grant execute on function public.submit_payment_confirmation(uuid, text, date, text, text) to authenticated;

-- ---------------------------------------------------------
-- 4. Admin: confirm payment
-- ---------------------------------------------------------
-- Atomically: marks the confirmation record confirmed, approves the
-- student's account, activates enrollment, assigns a Student ID (only if
-- they don't already have one), writes the audit log entry, and creates
-- an in-app notification. All-or-nothing.

create or replace function public.admin_confirm_payment(
  p_confirmation_id uuid,
  p_admin_note text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  acting_role text := public.current_user_role();
  v_student_id uuid;
  v_prev_status text;
  v_admin_name text;
  v_student_code text;
begin
  if acting_role not in ('admin', 'super_admin') then
    raise exception 'Only an admin can confirm payments.';
  end if;

  select student_id, payment_status into v_student_id, v_prev_status
  from public.payment_confirmations
  where id = p_confirmation_id;

  if v_student_id is null then
    raise exception 'Payment confirmation not found.';
  end if;

  select full_name into v_admin_name from public.profiles where id = auth.uid();

  select student_id into v_student_code from public.profiles where id = v_student_id;
  if v_student_code is null then
    v_student_code := public.next_student_id();
  end if;

  update public.payment_confirmations
  set payment_status = 'confirmed',
      verified_by = auth.uid(),
      verified_at = now(),
      admin_note = p_admin_note
  where id = p_confirmation_id;

  update public.profiles
  set payment_status = 'confirmed',
      account_status = 'approved',
      enrollment_status = 'active',
      student_id = v_student_code,
      updated_at = now()
  where id = v_student_id;

  insert into public.payment_approval_logs (student_id, previous_status, new_status, admin_id, admin_name, note)
  values (v_student_id, v_prev_status, 'confirmed', auth.uid(), v_admin_name, p_admin_note);

  insert into public.notifications (user_id, title, body)
  values (
    v_student_id,
    'Payment confirmed',
    'Your payment has been verified. Your account is approved and your course access is now active. Your Student ID is ' || v_student_code || '.'
  );
end;
$$;

revoke execute on function public.admin_confirm_payment(uuid, text) from public;
grant execute on function public.admin_confirm_payment(uuid, text) to authenticated;

-- ---------------------------------------------------------
-- 5. Admin: reject payment
-- ---------------------------------------------------------
-- Requires a reason. Does NOT touch account_status or enrollment_status --
-- a rejected student stays exactly where they were, just with
-- payment_status reset so they can submit again.

create or replace function public.admin_reject_payment(
  p_confirmation_id uuid,
  p_admin_note text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  acting_role text := public.current_user_role();
  v_student_id uuid;
  v_prev_status text;
  v_admin_name text;
begin
  if acting_role not in ('admin', 'super_admin') then
    raise exception 'Only an admin can reject payments.';
  end if;
  if p_admin_note is null or length(trim(p_admin_note)) = 0 then
    raise exception 'A rejection reason is required.';
  end if;

  select student_id, payment_status into v_student_id, v_prev_status
  from public.payment_confirmations
  where id = p_confirmation_id;

  if v_student_id is null then
    raise exception 'Payment confirmation not found.';
  end if;

  select full_name into v_admin_name from public.profiles where id = auth.uid();

  update public.payment_confirmations
  set payment_status = 'rejected',
      verified_by = auth.uid(),
      verified_at = now(),
      admin_note = p_admin_note
  where id = p_confirmation_id;

  update public.profiles
  set payment_status = 'rejected', updated_at = now()
  where id = v_student_id;

  insert into public.payment_approval_logs (student_id, previous_status, new_status, admin_id, admin_name, note)
  values (v_student_id, v_prev_status, 'rejected', auth.uid(), v_admin_name, p_admin_note);

  insert into public.notifications (user_id, title, body)
  values (
    v_student_id,
    'Payment could not be verified',
    'We could not verify your last payment confirmation. Reason: ' || p_admin_note || '. Please check the details and submit a new confirmation once resolved.'
  );
end;
$$;

revoke execute on function public.admin_reject_payment(uuid, text) from public;
grant execute on function public.admin_reject_payment(uuid, text) to authenticated;
