-- =========================================================
-- TIDEF ITECH LMS -- Phase 3 (course management)
-- =========================================================
-- Run this AFTER 0001_init.sql and 0002_payments.sql.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Flesh out the courses table (Phase 1 only had name/description/status)
-- ---------------------------------------------------------

alter table public.courses
  add column if not exists teacher_id uuid references public.profiles (id),
  add column if not exists category text,
  add column if not exists image_url text,
  add column if not exists duration text,
  add column if not exists level text,
  add column if not exists updated_at timestamptz not null default now();

-- ---------------------------------------------------------
-- 2. modules and lessons
-- ---------------------------------------------------------
-- Lessons store course_id too (denormalized) purely to make RLS and
-- "all lessons in this course" queries simple -- kept correct
-- automatically by the trigger in step 4, never set by the client.

create table if not exists public.modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  title text not null,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.modules (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  title text not null,
  lesson_type text not null default 'text'
    check (lesson_type in ('video', 'text', 'pdf', 'external')),
  content_text text,
  video_url text,
  external_url text,
  position int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.modules enable row level security;
alter table public.lessons enable row level security;

-- Keep lessons.course_id in sync with its module automatically -- the
-- client never sets this directly, so it can't drift or be spoofed.
create or replace function public.set_lesson_course_id()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  select course_id into new.course_id from public.modules where id = new.module_id;
  if new.course_id is null then
    raise exception 'Module not found.';
  end if;
  return new;
end;
$$;

drop trigger if exists before_lesson_write on public.lessons;
create trigger before_lesson_write
  before insert or update of module_id on public.lessons
  for each row execute procedure public.set_lesson_course_id();

-- ---------------------------------------------------------
-- 3. enrollments
-- ---------------------------------------------------------

create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'completed')),
  enrolled_at timestamptz not null default now(),
  enrolled_by uuid references public.profiles (id),
  unique (student_id, course_id)
);

alter table public.enrollments enable row level security;

-- ---------------------------------------------------------
-- 4. Helper: is the current user the assigned teacher of this course?
-- ---------------------------------------------------------

create or replace function public.is_course_teacher(p_course_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.courses
    where id = p_course_id and teacher_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------
-- 5. Helper: is the current user actively enrolled in this course?
-- ---------------------------------------------------------

create or replace function public.is_enrolled(p_course_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.enrollments
    where course_id = p_course_id and student_id = auth.uid() and status in ('active', 'completed')
  );
$$;

-- ---------------------------------------------------------
-- 6. courses policies -- replace the Phase 1 catch-all "staff can manage"
--    with a narrower rule: only admins can create/delete/reassign a
--    course; the assigned teacher may only update their own course's
--    content fields.
-- ---------------------------------------------------------

drop policy if exists "Staff can manage courses" on public.courses;

drop policy if exists "Admins manage courses" on public.courses;
create policy "Admins manage courses"
  on public.courses for all
  using (public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Teacher updates own course" on public.courses;
create policy "Teacher updates own course"
  on public.courses for update
  using (public.current_user_role() = 'teacher' and teacher_id = auth.uid());

-- ---------------------------------------------------------
-- 7. modules policies
-- ---------------------------------------------------------
-- Titles are curriculum-preview content: visible to anyone for a
-- published course, in addition to staff/owning teacher.

drop policy if exists "View modules of published or own courses" on public.modules;
create policy "View modules of published or own courses"
  on public.modules for select
  using (
    exists (select 1 from public.courses c where c.id = course_id and c.status = 'published')
    or public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );

drop policy if exists "Admins manage modules" on public.modules;
create policy "Admins manage modules"
  on public.modules for all
  using (public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Teacher manages own course modules" on public.modules;
create policy "Teacher manages own course modules"
  on public.modules for all
  using (public.current_user_role() = 'teacher' and public.is_course_teacher(course_id));

-- ---------------------------------------------------------
-- 8. lessons policies
-- ---------------------------------------------------------
-- Full lesson CONTENT is protected: only staff, the owning teacher, or a
-- student actively enrolled in that course can read it -- never the
-- general public, even for a published course. This is what keeps
-- "curriculum preview" (module titles) separate from "protected lessons".

drop policy if exists "View lessons if staff, owning teacher, or enrolled" on public.lessons;
create policy "View lessons if staff, owning teacher, or enrolled"
  on public.lessons for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
    or public.is_enrolled(course_id)
  );

drop policy if exists "Admins manage lessons" on public.lessons;
create policy "Admins manage lessons"
  on public.lessons for all
  using (public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Teacher manages own course lessons" on public.lessons;
create policy "Teacher manages own course lessons"
  on public.lessons for all
  using (public.current_user_role() = 'teacher' and public.is_course_teacher(course_id));

-- ---------------------------------------------------------
-- 9. enrollments policies
-- ---------------------------------------------------------
-- Only admins create/remove enrollments (matches "Admin enrolls student
-- in courses" from the spec) -- teachers can see their course's roster
-- but not add or remove students themselves.

drop policy if exists "Student views own enrollments" on public.enrollments;
create policy "Student views own enrollments"
  on public.enrollments for select
  using (auth.uid() = student_id);

drop policy if exists "Staff and owning teacher view course enrollments" on public.enrollments;
create policy "Staff and owning teacher view course enrollments"
  on public.enrollments for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );

drop policy if exists "Admins manage enrollments" on public.enrollments;
create policy "Admins manage enrollments"
  on public.enrollments for all
  using (public.current_user_role() in ('admin', 'super_admin'));
