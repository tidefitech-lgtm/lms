-- =========================================================
-- TIDEF ITECH LMS -- Phase 5 (assignments & projects)
-- =========================================================
-- Run this AFTER 0001-0004.
-- =========================================================

-- ---------------------------------------------------------
-- 1. assignments
-- ---------------------------------------------------------

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  title text not null,
  instructions text,
  attachment_path text,
  max_marks numeric not null default 100,
  due_at timestamptz,
  allow_resubmission boolean not null default true,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.assignments enable row level security;

drop policy if exists "View assignments if staff, owning teacher, or enrolled" on public.assignments;
create policy "View assignments if staff, owning teacher, or enrolled"
  on public.assignments for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
    or public.is_enrolled(course_id)
  );

drop policy if exists "Admins manage assignments" on public.assignments;
create policy "Admins manage assignments"
  on public.assignments for all
  using (public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Teacher manages own course assignments" on public.assignments;
create policy "Teacher manages own course assignments"
  on public.assignments for all
  using (public.current_user_role() = 'teacher' and public.is_course_teacher(course_id));

-- ---------------------------------------------------------
-- 2. submissions -- one row per (assignment, student). All writes go
--    through the two functions below, never direct table access, so
--    the resubmission and grading rules can't be bypassed from the
--    client.
-- ---------------------------------------------------------

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  content_text text,
  file_path text,
  attempt_number int not null default 1,
  status text not null default 'submitted' check (status in ('submitted', 'graded')),
  grade numeric,
  feedback text,
  graded_by uuid references public.profiles (id),
  graded_at timestamptz,
  submitted_at timestamptz not null default now(),
  unique (assignment_id, student_id)
);

alter table public.submissions enable row level security;

drop policy if exists "Student views own submission" on public.submissions;
create policy "Student views own submission"
  on public.submissions for select
  using (auth.uid() = student_id);

drop policy if exists "Staff and owning teacher view submissions" on public.submissions;
create policy "Staff and owning teacher view submissions"
  on public.submissions for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );
-- No INSERT/UPDATE policy at all -- submit_assignment() and
-- grade_submission() (SECURITY DEFINER, below) are the only path in.

create or replace function public.submit_assignment(
  p_assignment_id uuid,
  p_content_text text default null,
  p_file_path text default null
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_course_id uuid;
  v_allow_resubmission boolean;
  v_existing record;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select course_id, allow_resubmission into v_course_id, v_allow_resubmission
  from public.assignments where id = p_assignment_id;

  if v_course_id is null then
    raise exception 'Assignment not found.';
  end if;
  if not public.is_enrolled(v_course_id) then
    raise exception 'You are not enrolled in this course.';
  end if;

  select * into v_existing from public.submissions
  where assignment_id = p_assignment_id and student_id = auth.uid();

  if v_existing.id is not null and v_existing.status = 'graded' and not v_allow_resubmission then
    raise exception 'This assignment does not allow resubmission after grading.';
  end if;

  if v_existing.id is null then
    insert into public.submissions (assignment_id, student_id, content_text, file_path)
    values (p_assignment_id, auth.uid(), p_content_text, p_file_path)
    returning id into v_id;
  else
    update public.submissions
    set content_text = p_content_text,
        file_path = p_file_path,
        status = 'submitted',
        grade = null,
        feedback = null,
        graded_by = null,
        graded_at = null,
        attempt_number = v_existing.attempt_number + 1,
        submitted_at = now()
    where id = v_existing.id
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke execute on function public.submit_assignment(uuid, text, text) from public;
grant execute on function public.submit_assignment(uuid, text, text) to authenticated;

create or replace function public.grade_submission(
  p_submission_id uuid,
  p_grade numeric,
  p_feedback text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  acting_role text := public.current_user_role();
  v_course_id uuid;
  v_student_id uuid;
  v_max_marks numeric;
  v_assignment_title text;
begin
  select s.course_id, s.student_id, a.max_marks, a.title
  into v_course_id, v_student_id, v_max_marks, v_assignment_title
  from public.submissions s
  join public.assignments a on a.id = s.assignment_id
  where s.id = p_submission_id;

  if v_course_id is null then
    raise exception 'Submission not found.';
  end if;
  if not (acting_role in ('admin', 'super_admin') or public.is_course_teacher(v_course_id)) then
    raise exception 'You do not have permission to grade this submission.';
  end if;
  if p_grade < 0 or p_grade > v_max_marks then
    raise exception 'Grade must be between 0 and %.', v_max_marks;
  end if;

  update public.submissions
  set grade = p_grade, feedback = p_feedback, status = 'graded', graded_by = auth.uid(), graded_at = now()
  where id = p_submission_id;

  insert into public.notifications (user_id, title, body)
  values (v_student_id, 'Assignment graded', v_assignment_title || ' has been graded: ' || p_grade || '/' || v_max_marks || '.');
end;
$$;

revoke execute on function public.grade_submission(uuid, numeric, text) from public;
grant execute on function public.grade_submission(uuid, numeric, text) to authenticated;

-- ---------------------------------------------------------
-- 3. projects -- students submit directly (no teacher-created shell
--    needed), can resubmit any time before grading, teacher/admin grade.
-- ---------------------------------------------------------

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text,
  file_path text,
  github_url text,
  live_url text,
  screenshot_paths text[] not null default '{}',
  status text not null default 'submitted' check (status in ('submitted', 'graded')),
  grade numeric,
  feedback text,
  graded_by uuid references public.profiles (id),
  graded_at timestamptz,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.projects enable row level security;

drop policy if exists "Student views own projects" on public.projects;
create policy "Student views own projects"
  on public.projects for select
  using (auth.uid() = student_id);

drop policy if exists "Staff and owning teacher view projects" on public.projects;
create policy "Staff and owning teacher view projects"
  on public.projects for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );

create or replace function public.submit_project(
  p_project_id uuid, -- pass null to create a new project
  p_course_id uuid,
  p_title text,
  p_description text default null,
  p_file_path text default null,
  p_github_url text default null,
  p_live_url text default null,
  p_screenshot_paths text[] default '{}'
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_owner uuid;
  v_status text;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;
  if not public.is_enrolled(p_course_id) then
    raise exception 'You are not enrolled in this course.';
  end if;

  if p_project_id is not null then
    select student_id, status into v_owner, v_status from public.projects where id = p_project_id;
    if v_owner is null or v_owner <> auth.uid() then
      raise exception 'Project not found.';
    end if;

    update public.projects
    set title = p_title, description = p_description, file_path = p_file_path,
        github_url = p_github_url, live_url = p_live_url, screenshot_paths = p_screenshot_paths,
        status = 'submitted', grade = null, feedback = null, graded_by = null, graded_at = null,
        submitted_at = now(), updated_at = now()
    where id = p_project_id
    returning id into v_id;
  else
    insert into public.projects (course_id, student_id, title, description, file_path, github_url, live_url, screenshot_paths)
    values (p_course_id, auth.uid(), p_title, p_description, p_file_path, p_github_url, p_live_url, p_screenshot_paths)
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke execute on function public.submit_project(uuid, uuid, text, text, text, text, text, text[]) from public;
grant execute on function public.submit_project(uuid, uuid, text, text, text, text, text, text[]) to authenticated;

create or replace function public.grade_project(
  p_project_id uuid,
  p_grade numeric,
  p_feedback text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  acting_role text := public.current_user_role();
  v_course_id uuid;
  v_student_id uuid;
  v_title text;
begin
  select course_id, student_id, title into v_course_id, v_student_id, v_title
  from public.projects where id = p_project_id;

  if v_course_id is null then
    raise exception 'Project not found.';
  end if;
  if not (acting_role in ('admin', 'super_admin') or public.is_course_teacher(v_course_id)) then
    raise exception 'You do not have permission to grade this project.';
  end if;

  update public.projects
  set grade = p_grade, feedback = p_feedback, status = 'graded', graded_by = auth.uid(), graded_at = now()
  where id = p_project_id;

  insert into public.notifications (user_id, title, body)
  values (v_student_id, 'Project graded', v_title || ' has been graded.');
end;
$$;

revoke execute on function public.grade_project(uuid, numeric, text) from public;
grant execute on function public.grade_project(uuid, numeric, text) to authenticated;

-- ---------------------------------------------------------
-- 4. Storage buckets for assignment/submission/project files
-- ---------------------------------------------------------

insert into storage.buckets (id, name, public) values
  ('assignment-files', 'assignment-files', false),
  ('submission-files', 'submission-files', false),
  ('project-files', 'project-files', false)
on conflict (id) do nothing;

-- assignment-files: path convention assignment-files/{course_id}/{filename}
-- Only the course's admin/teacher can upload; any signed-in user can read
-- (matches the profile-photos precedent from Phase 1 -- fine-grained
-- per-course read control lives at the database-row level, not the raw
-- file object).
drop policy if exists "Staff upload assignment files" on storage.objects;
create policy "Staff upload assignment files"
  on storage.objects for insert
  with check (
    bucket_id = 'assignment-files'
    and (
      public.current_user_role() in ('admin', 'super_admin')
      or public.is_course_teacher(((storage.foldername(name))[1])::uuid)
    )
  );

drop policy if exists "Signed-in users read assignment files" on storage.objects;
create policy "Signed-in users read assignment files"
  on storage.objects for select
  using (bucket_id = 'assignment-files' and auth.role() = 'authenticated');

-- submission-files: path convention submission-files/{student_id}/{filename}
drop policy if exists "Students upload own submission files" on storage.objects;
create policy "Students upload own submission files"
  on storage.objects for insert
  with check (bucket_id = 'submission-files' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Signed-in users read submission files" on storage.objects;
create policy "Signed-in users read submission files"
  on storage.objects for select
  using (bucket_id = 'submission-files' and auth.role() = 'authenticated');

-- project-files: path convention project-files/{student_id}/{filename}
drop policy if exists "Students upload own project files" on storage.objects;
create policy "Students upload own project files"
  on storage.objects for insert
  with check (bucket_id = 'project-files' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Signed-in users read project files" on storage.objects;
create policy "Signed-in users read project files"
  on storage.objects for select
  using (bucket_id = 'project-files' and auth.role() = 'authenticated');
