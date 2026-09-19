-- =========================================================
-- TIDEF ITECH LMS -- Phase 6 (quizzes & exams)
-- =========================================================
-- Run this AFTER 0001-0005.
--
-- Quizzes and exams share one schema (an "assessment" is either kind).
-- The critical security property: a student can NEVER read
-- question_options.is_correct through any query, direct or embedded --
-- questions are handed to the student via get_attempt_questions(),
-- which strips that column, and grading happens entirely inside
-- submit_attempt(), server-side, against the real table.
-- =========================================================

-- ---------------------------------------------------------
-- 1. assessments, questions, question_options
-- ---------------------------------------------------------

create table if not exists public.assessments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  kind text not null check (kind in ('quiz', 'exam')),
  title text not null,
  description text,
  time_limit_minutes int,
  max_attempts int not null default 1,
  passing_score numeric not null default 60,
  available_from timestamptz,
  available_until timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.assessments (id) on delete cascade,
  question_text text not null,
  question_type text not null check (question_type in ('single_choice', 'true_false', 'multi_select')),
  points numeric not null default 1,
  position int not null default 0
);

create table if not exists public.question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions (id) on delete cascade,
  option_text text not null,
  is_correct boolean not null default false,
  position int not null default 0
);

alter table public.assessments enable row level security;
alter table public.questions enable row level security;
alter table public.question_options enable row level security;

-- assessments: enrolled students can see the assessment shell
-- (title/time limit/attempts allowed) to decide whether to start it.
drop policy if exists "View assessments if staff, owning teacher, or enrolled" on public.assessments;
create policy "View assessments if staff, owning teacher, or enrolled"
  on public.assessments for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
    or public.is_enrolled(course_id)
  );

drop policy if exists "Admins manage assessments" on public.assessments;
create policy "Admins manage assessments"
  on public.assessments for all
  using (public.current_user_role() in ('admin', 'super_admin'));

drop policy if exists "Teacher manages own course assessments" on public.assessments;
create policy "Teacher manages own course assessments"
  on public.assessments for all
  using (public.current_user_role() = 'teacher' and public.is_course_teacher(course_id));

-- questions/question_options: staff/owning teacher ONLY. Students never
-- read these tables directly -- see get_attempt_questions() below.
drop policy if exists "Staff and owning teacher manage questions" on public.questions;
create policy "Staff and owning teacher manage questions"
  on public.questions for all
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher((select course_id from public.assessments where id = assessment_id))
  );

drop policy if exists "Staff and owning teacher manage options" on public.question_options;
create policy "Staff and owning teacher manage options"
  on public.question_options for all
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher((
      select a.course_id from public.assessments a
      join public.questions q on q.assessment_id = a.id
      where q.id = question_id
    ))
  );

-- ---------------------------------------------------------
-- 2. assessment_attempts, attempt_answers
-- ---------------------------------------------------------

create table if not exists public.assessment_attempts (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.assessments (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  attempt_number int not null default 1,
  time_limit_minutes int,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  status text not null default 'in_progress' check (status in ('in_progress', 'submitted', 'auto_submitted')),
  score numeric,
  max_score numeric,
  percentage numeric,
  passed boolean
);

create table if not exists public.attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.assessment_attempts (id) on delete cascade,
  question_id uuid not null references public.questions (id),
  selected_option_ids uuid[] not null default '{}',
  is_correct boolean,
  points_awarded numeric
);

alter table public.assessment_attempts enable row level security;
alter table public.attempt_answers enable row level security;

drop policy if exists "Student views own attempts" on public.assessment_attempts;
create policy "Student views own attempts"
  on public.assessment_attempts for select
  using (auth.uid() = student_id);

drop policy if exists "Staff and owning teacher view attempts" on public.assessment_attempts;
create policy "Staff and owning teacher view attempts"
  on public.assessment_attempts for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );

drop policy if exists "Student views own answers" on public.attempt_answers;
create policy "Student views own answers"
  on public.attempt_answers for select
  using (exists (select 1 from public.assessment_attempts a where a.id = attempt_id and a.student_id = auth.uid()));

drop policy if exists "Staff and owning teacher view answers" on public.attempt_answers;
create policy "Staff and owning teacher view answers"
  on public.attempt_answers for select
  using (exists (
    select 1 from public.assessment_attempts a
    where a.id = attempt_id
    and (public.current_user_role() in ('admin', 'super_admin') or public.is_course_teacher(a.course_id))
  ));
-- No INSERT/UPDATE policy on either table -- start_attempt() and
-- submit_attempt() (SECURITY DEFINER, below) are the only way in. This
-- is what makes "students must not be able to modify their results"
-- (spec section 26) hold structurally, not just by convention.

-- ---------------------------------------------------------
-- 3. Hand a student the questions WITHOUT correct answers
-- ---------------------------------------------------------

create or replace function public.get_attempt_questions(p_assessment_id uuid)
returns table (
  question_id uuid,
  question_text text,
  question_type text,
  points numeric,
  "position" int,
  options jsonb
)
language plpgsql
security definer set search_path = public
as $$
declare
  v_course_id uuid;
begin
  select course_id into v_course_id from public.assessments where id = p_assessment_id;
  if v_course_id is null then
    raise exception 'Assessment not found.';
  end if;
  if not public.is_enrolled(v_course_id) then
    raise exception 'You are not enrolled in this course.';
  end if;

  return query
  select
    q.id,
    q.question_text,
    q.question_type,
    q.points,
    q.position,
    (
      select jsonb_agg(jsonb_build_object('id', o.id, 'option_text', o.option_text, 'position', o.position) order by o.position)
      from public.question_options o
      where o.question_id = q.id
    ) as options
  from public.questions q
  where q.assessment_id = p_assessment_id
  order by q.position;
end;
$$;

revoke execute on function public.get_attempt_questions(uuid) from public;
grant execute on function public.get_attempt_questions(uuid) to authenticated;

-- ---------------------------------------------------------
-- 4. Start (or resume) an attempt
-- ---------------------------------------------------------
-- If there's an abandoned in-progress attempt whose time limit has
-- expired, it gets auto-submitted (scored on whatever was never
-- answered -- i.e. zero) before a new one is allowed. If there's an
-- in-progress attempt still within its time limit (or untimed), that
-- same attempt is resumed rather than starting a duplicate.

create or replace function public.start_attempt(p_assessment_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_course_id uuid;
  v_time_limit int;
  v_max_attempts int;
  v_existing record;
  v_attempt_count int;
  v_new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select course_id, time_limit_minutes, max_attempts
  into v_course_id, v_time_limit, v_max_attempts
  from public.assessments where id = p_assessment_id;

  if v_course_id is null then
    raise exception 'Assessment not found.';
  end if;
  if not public.is_enrolled(v_course_id) then
    raise exception 'You are not enrolled in this course.';
  end if;

  select * into v_existing from public.assessment_attempts
  where assessment_id = p_assessment_id and student_id = auth.uid() and status = 'in_progress'
  order by started_at desc limit 1;

  if v_existing.id is not null then
    if v_existing.time_limit_minutes is not null
       and now() > v_existing.started_at + (v_existing.time_limit_minutes || ' minutes')::interval
    then
      -- Abandoned past its time limit -- close it out at zero and fall through to start a fresh one.
      update public.assessment_attempts
      set status = 'auto_submitted', submitted_at = now(), score = 0, max_score = 0, percentage = 0, passed = false
      where id = v_existing.id;
    else
      return v_existing.id; -- resume
    end if;
  end if;

  select count(*) into v_attempt_count from public.assessment_attempts
  where assessment_id = p_assessment_id and student_id = auth.uid() and status <> 'in_progress';

  if v_attempt_count >= v_max_attempts then
    raise exception 'You have used all % of your attempts for this assessment.', v_max_attempts;
  end if;

  insert into public.assessment_attempts (assessment_id, student_id, course_id, attempt_number, time_limit_minutes)
  values (p_assessment_id, auth.uid(), v_course_id, v_attempt_count + 1, v_time_limit)
  returning id into v_new_id;

  return v_new_id;
end;
$$;

revoke execute on function public.start_attempt(uuid) from public;
grant execute on function public.start_attempt(uuid) to authenticated;

-- ---------------------------------------------------------
-- 5. Submit and grade an attempt
-- ---------------------------------------------------------
-- p_answers is a jsonb array like:
--   [{"question_id": "...", "selected_option_ids": ["...", "..."]}, ...]
-- Grading is all-or-nothing per question: a multi_select question is
-- only correct if the selected set exactly matches the correct set.

create or replace function public.submit_attempt(p_attempt_id uuid, p_answers jsonb, p_auto boolean default false)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_attempt record;
  v_assessment record;
  v_answer jsonb;
  v_question_id uuid;
  v_selected uuid[];
  v_correct uuid[];
  v_points numeric;
  v_is_correct boolean;
  v_total_score numeric := 0;
  v_max_score numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select * into v_attempt from public.assessment_attempts where id = p_attempt_id;
  if v_attempt.id is null or v_attempt.student_id <> auth.uid() then
    raise exception 'Attempt not found.';
  end if;
  if v_attempt.status <> 'in_progress' then
    raise exception 'This attempt has already been submitted.';
  end if;

  select * into v_assessment from public.assessments where id = v_attempt.assessment_id;

  -- Grade every question in the assessment (unanswered ones score 0).
  for v_question_id, v_points in
    select id, points from public.questions where assessment_id = v_attempt.assessment_id
  loop
    v_max_score := v_max_score + v_points;

    select array_agg(id order by id) into v_correct
    from public.question_options where question_id = v_question_id and is_correct = true;

    v_selected := '{}';
    for v_answer in select * from jsonb_array_elements(coalesce(p_answers, '[]'::jsonb))
    loop
      if (v_answer->>'question_id')::uuid = v_question_id then
        select array_agg((elem)::uuid order by (elem)::uuid)
        into v_selected
        from jsonb_array_elements_text(coalesce(v_answer->'selected_option_ids', '[]'::jsonb)) as elem;
        exit;
      end if;
    end loop;

    v_is_correct := (coalesce(v_selected, '{}') = coalesce(v_correct, '{}'));

    insert into public.attempt_answers (attempt_id, question_id, selected_option_ids, is_correct, points_awarded)
    values (p_attempt_id, v_question_id, coalesce(v_selected, '{}'), v_is_correct, case when v_is_correct then v_points else 0 end);

    if v_is_correct then
      v_total_score := v_total_score + v_points;
    end if;
  end loop;

  update public.assessment_attempts
  set status = case when p_auto then 'auto_submitted' else 'submitted' end,
      submitted_at = now(),
      score = v_total_score,
      max_score = v_max_score,
      percentage = case when v_max_score > 0 then round((v_total_score / v_max_score) * 100, 1) else 0 end,
      passed = case when v_max_score > 0 then (v_total_score / v_max_score) * 100 >= v_assessment.passing_score else false end
  where id = p_attempt_id;

  return p_attempt_id;
end;
$$;

revoke execute on function public.submit_attempt(uuid, jsonb, boolean) from public;
grant execute on function public.submit_attempt(uuid, jsonb, boolean) to authenticated;

-- ---------------------------------------------------------
-- 6. Review a finished attempt (correct answers included -- safe,
--    since it's already graded and only the owner or staff can call it)
-- ---------------------------------------------------------

create or replace function public.get_attempt_review(p_attempt_id uuid)
returns table (
  question_id uuid,
  question_text text,
  question_type text,
  points numeric,
  selected_option_ids uuid[],
  correct_option_ids uuid[],
  is_correct boolean,
  points_awarded numeric,
  options jsonb
)
language plpgsql
security definer set search_path = public
as $$
declare
  v_attempt record;
begin
  select * into v_attempt from public.assessment_attempts where id = p_attempt_id;
  if v_attempt.id is null then
    raise exception 'Attempt not found.';
  end if;
  if v_attempt.status = 'in_progress' then
    raise exception 'This attempt has not been submitted yet.';
  end if;
  if v_attempt.student_id <> auth.uid()
     and public.current_user_role() not in ('admin', 'super_admin')
     and not public.is_course_teacher(v_attempt.course_id)
  then
    raise exception 'You do not have permission to view this attempt.';
  end if;

  return query
  select
    q.id, q.question_text, q.question_type, q.points,
    aa.selected_option_ids,
    (select array_agg(o.id order by o.id) from public.question_options o where o.question_id = q.id and o.is_correct = true),
    aa.is_correct,
    aa.points_awarded,
    (select jsonb_agg(jsonb_build_object('id', o.id, 'option_text', o.option_text, 'position', o.position) order by o.position)
     from public.question_options o where o.question_id = q.id)
  from public.questions q
  join public.attempt_answers aa on aa.question_id = q.id and aa.attempt_id = p_attempt_id
  order by q.position;
end;
$$;

revoke execute on function public.get_attempt_review(uuid) from public;
grant execute on function public.get_attempt_review(uuid) to authenticated;
