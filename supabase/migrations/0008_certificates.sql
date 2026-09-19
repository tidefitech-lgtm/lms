-- =========================================================
-- TIDEF ITECH LMS -- Phase 8 (certificates)
-- =========================================================
-- Run this AFTER 0001-0007.
--
-- Certificates are issued manually by an Admin/Super Admin once a
-- student has completed a course -- this is not automatic. "Completed"
-- already exists as enrollments.status (set automatically back in
-- Phase 4 once every lesson is finished), so the admin UI just
-- surfaces completed-but-not-yet-certified enrollments as a shortlist.
-- =========================================================

-- ---------------------------------------------------------
-- 1. certificates
-- ---------------------------------------------------------

create table if not exists public.certificates (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  certificate_number text not null unique,
  file_path text not null,
  notes text,
  issued_by uuid references public.profiles (id),
  issued_at timestamptz not null default now(),
  unique (student_id, course_id)
);

alter table public.certificates enable row level security;

drop policy if exists "Student views own certificates" on public.certificates;
create policy "Student views own certificates"
  on public.certificates for select
  using (auth.uid() = student_id);

drop policy if exists "Staff and owning teacher view certificates" on public.certificates;
create policy "Staff and owning teacher view certificates"
  on public.certificates for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );

drop policy if exists "Admins manage certificates" on public.certificates;
create policy "Admins manage certificates"
  on public.certificates for all
  using (public.current_user_role() in ('admin', 'super_admin'));

-- ---------------------------------------------------------
-- 2. Sequential certificate numbers: TIDEF-CERT-YYYY-0001
-- ---------------------------------------------------------

create table if not exists public.cert_counters (
  year int primary key,
  last_number int not null default 0
);

alter table public.cert_counters enable row level security;
-- No policies -- only touched by issue_certificate() below.

create or replace function public.next_certificate_number()
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  yr int := extract(year from now())::int;
  next_num int;
begin
  insert into public.cert_counters (year, last_number)
  values (yr, 1)
  on conflict (year) do update set last_number = public.cert_counters.last_number + 1
  returning last_number into next_num;

  return 'TIDEF-CERT-' || yr || '-' || lpad(next_num::text, 4, '0');
end;
$$;

revoke execute on function public.next_certificate_number() from public;

-- ---------------------------------------------------------
-- 3. Issue a certificate (admin-only, atomic: row + number + notification)
-- ---------------------------------------------------------

create or replace function public.issue_certificate(
  p_student_id uuid,
  p_course_id uuid,
  p_file_path text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_cert_number text;
  v_course_name text;
  v_new_id uuid;
begin
  if public.current_user_role() not in ('admin', 'super_admin') then
    raise exception 'Only an admin can issue certificates.';
  end if;

  select name into v_course_name from public.courses where id = p_course_id;
  if v_course_name is null then
    raise exception 'Course not found.';
  end if;

  v_cert_number := public.next_certificate_number();

  insert into public.certificates (student_id, course_id, certificate_number, file_path, notes, issued_by)
  values (p_student_id, p_course_id, v_cert_number, p_file_path, p_notes, auth.uid())
  returning id into v_new_id;

  insert into public.notifications (user_id, title, body)
  values (p_student_id, 'Certificate issued', 'Your certificate for ' || v_course_name || ' is ready. Certificate number: ' || v_cert_number || '.');

  return v_new_id;
end;
$$;

revoke execute on function public.issue_certificate(uuid, uuid, text, text) from public;
grant execute on function public.issue_certificate(uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------
-- 4. Public certificate verification -- callable by ANYONE, even
--    signed out, since an employer checking a certificate won't have
--    an LMS account. Returns only what's needed to confirm
--    authenticity: no file, no contact info, nothing sensitive.
-- ---------------------------------------------------------

create or replace function public.verify_certificate(p_certificate_number text)
returns table (
  certificate_number text,
  student_name text,
  course_name text,
  issued_at timestamptz
)
language sql
security definer set search_path = public
stable
as $$
  select c.certificate_number, p.full_name, co.name, c.issued_at
  from public.certificates c
  join public.profiles p on p.id = c.student_id
  join public.courses co on co.id = c.course_id
  where c.certificate_number = p_certificate_number;
$$;

revoke execute on function public.verify_certificate(text) from public;
grant execute on function public.verify_certificate(text) to anon, authenticated;

-- ---------------------------------------------------------
-- 5. Storage bucket for certificate files
-- ---------------------------------------------------------
-- Path convention: certificates/{student_id}/{filename}
-- Not publicly readable -- verify_certificate() above deliberately
-- does not expose the file, only confirms authenticity.

insert into storage.buckets (id, name, public)
values ('certificates', 'certificates', false)
on conflict (id) do nothing;

drop policy if exists "Admins upload certificates" on storage.objects;
create policy "Admins upload certificates"
  on storage.objects for insert
  with check (bucket_id = 'certificates' and public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Owner and staff read certificates" on storage.objects;
create policy "Owner and staff read certificates"
  on storage.objects for select
  using (
    bucket_id = 'certificates'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.current_user_role() in ('admin', 'super_admin')
    )
  );
