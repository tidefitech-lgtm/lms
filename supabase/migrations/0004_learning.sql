-- =========================================================
-- TIDEF ITECH LMS -- Phase 4 (learning system)
-- =========================================================
-- Run this AFTER 0001, 0002, and 0003.
-- =========================================================

-- ---------------------------------------------------------
-- 1. lesson_progress
-- ---------------------------------------------------------
-- One row per (student, lesson). For video lessons this is a live
-- snapshot (furthest point reached, not a full event log) -- enough to
-- drive a progress bar and decide completion without the complexity of
-- a full watch-event history table. course_id is denormalized from the
-- lesson's module for simple per-course queries and is always set by
-- the trigger below, never by the client.

create table if not exists public.lesson_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id) on delete cascade,
  lesson_id uuid not null references public.lessons (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  status text not null default 'not_started'
    check (status in ('not_started', 'in_progress', 'completed')),
  video_seconds_watched numeric not null default 0,
  video_duration_seconds numeric,
  completed_at timestamptz,
  last_interacted_at timestamptz not null default now(),
  unique (student_id, lesson_id)
);

alter table public.lesson_progress enable row level security;

create or replace function public.set_progress_course_id()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  select course_id into new.course_id from public.lessons where id = new.lesson_id;
  if new.course_id is null then
    raise exception 'Lesson not found.';
  end if;
  return new;
end;
$$;

drop trigger if exists before_progress_write on public.lesson_progress;
create trigger before_progress_write
  before insert or update of lesson_id on public.lesson_progress
  for each row execute procedure public.set_progress_course_id();

drop policy if exists "Student manages own progress" on public.lesson_progress;
create policy "Student manages own progress"
  on public.lesson_progress for select
  using (auth.uid() = student_id);

drop policy if exists "Staff and owning teacher view progress" on public.lesson_progress;
create policy "Staff and owning teacher view progress"
  on public.lesson_progress for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );
-- No direct INSERT/UPDATE policy for students: all writes to this table
-- go through the SECURITY DEFINER functions below, which enforce the
-- "opening a video isn't completing it" rule structurally.

-- ---------------------------------------------------------
-- 2. Recalculate a course's completion % for a student, and promote
--    their enrollment to 'completed' once every lesson is done.
--    (Only ever promotes forward -- doesn't un-complete an enrollment
--    if new lessons are added later; that's a deliberate choice.)
-- ---------------------------------------------------------

create or replace function public.recalculate_course_progress(p_student_id uuid, p_course_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_total int;
  v_completed int;
begin
  select count(*) into v_total from public.lessons where course_id = p_course_id;

  select count(*) into v_completed
  from public.lesson_progress
  where student_id = p_student_id and course_id = p_course_id and status = 'completed';

  if v_total > 0 and v_completed >= v_total then
    update public.enrollments
    set status = 'completed'
    where student_id = p_student_id and course_id = p_course_id and status <> 'completed';
  end if;
end;
$$;

revoke execute on function public.recalculate_course_progress(uuid, uuid) from public;

-- ---------------------------------------------------------
-- 3. Video progress reporting
-- ---------------------------------------------------------
-- Called every few seconds while a video plays, and once on pause/end.
-- Tracks the FURTHEST point reached (never regresses on seek-back), and
-- only marks 'completed' once at least 90% of the video's duration has
-- actually been watched -- opening the lesson is never enough on its
-- own, matching the spec's explicit rule.

create or replace function public.record_video_progress(
  p_lesson_id uuid,
  p_seconds_watched numeric,
  p_duration_seconds numeric default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_course_id uuid;
  v_existing_max numeric;
  v_new_max numeric;
  v_duration numeric;
  v_should_complete boolean := false;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select course_id into v_course_id from public.lessons where id = p_lesson_id;
  if v_course_id is null then
    raise exception 'Lesson not found.';
  end if;
  if not public.is_enrolled(v_course_id) then
    raise exception 'You are not enrolled in this course.';
  end if;

  select video_seconds_watched, video_duration_seconds
  into v_existing_max, v_duration
  from public.lesson_progress
  where student_id = auth.uid() and lesson_id = p_lesson_id;

  v_new_max := greatest(coalesce(v_existing_max, 0), coalesce(p_seconds_watched, 0));
  v_duration := coalesce(p_duration_seconds, v_duration);

  if v_duration is not null and v_duration > 0 and (v_new_max / v_duration) >= 0.9 then
    v_should_complete := true;
  end if;

  insert into public.lesson_progress (student_id, lesson_id, status, video_seconds_watched, video_duration_seconds, completed_at, last_interacted_at)
  values (
    auth.uid(), p_lesson_id,
    case when v_should_complete then 'completed' else 'in_progress' end,
    v_new_max, v_duration,
    case when v_should_complete then now() else null end,
    now()
  )
  on conflict (student_id, lesson_id) do update set
    video_seconds_watched = v_new_max,
    video_duration_seconds = v_duration,
    status = case
      when public.lesson_progress.status = 'completed' then 'completed'
      when v_should_complete then 'completed'
      else 'in_progress'
    end,
    completed_at = case
      when public.lesson_progress.completed_at is not null then public.lesson_progress.completed_at
      when v_should_complete then now()
      else null
    end,
    last_interacted_at = now();

  perform public.recalculate_course_progress(auth.uid(), v_course_id);
end;
$$;

revoke execute on function public.record_video_progress(uuid, numeric, numeric) from public;
grant execute on function public.record_video_progress(uuid, numeric, numeric) to authenticated;

-- ---------------------------------------------------------
-- 4. Manual completion for non-video lessons (text/pdf/external) --
--    there's no passive watch signal for these, so the student marks
--    them done explicitly. Deliberately refuses this for video lessons,
--    which can only complete via record_video_progress above.
-- ---------------------------------------------------------

create or replace function public.mark_lesson_complete(p_lesson_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_course_id uuid;
  v_type text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select course_id, lesson_type into v_course_id, v_type from public.lessons where id = p_lesson_id;
  if v_course_id is null then
    raise exception 'Lesson not found.';
  end if;
  if v_type = 'video' then
    raise exception 'Video lessons complete automatically based on watch progress.';
  end if;
  if not public.is_enrolled(v_course_id) then
    raise exception 'You are not enrolled in this course.';
  end if;

  insert into public.lesson_progress (student_id, lesson_id, status, completed_at, last_interacted_at)
  values (auth.uid(), p_lesson_id, 'completed', now(), now())
  on conflict (student_id, lesson_id) do update set
    status = 'completed',
    completed_at = coalesce(public.lesson_progress.completed_at, now()),
    last_interacted_at = now();

  perform public.recalculate_course_progress(auth.uid(), v_course_id);
end;
$$;

revoke execute on function public.mark_lesson_complete(uuid) from public;
grant execute on function public.mark_lesson_complete(uuid) to authenticated;

-- ---------------------------------------------------------
-- 5. Notes -- private to the student, tied to a lesson
-- ---------------------------------------------------------

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id) on delete cascade,
  lesson_id uuid not null references public.lessons (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  content text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, lesson_id)
);

alter table public.notes enable row level security;

drop trigger if exists before_note_write on public.notes;
create trigger before_note_write
  before insert or update of lesson_id on public.notes
  for each row execute procedure public.set_progress_course_id();

drop policy if exists "Student manages own notes" on public.notes;
create policy "Student manages own notes"
  on public.notes for all
  using (auth.uid() = student_id)
  with check (auth.uid() = student_id);

-- ---------------------------------------------------------
-- 6. Bookmarks -- private to the student, tied to a lesson
-- ---------------------------------------------------------

create table if not exists public.bookmarks (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id) on delete cascade,
  lesson_id uuid not null references public.lessons (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (student_id, lesson_id)
);

alter table public.bookmarks enable row level security;

drop trigger if exists before_bookmark_write on public.bookmarks;
create trigger before_bookmark_write
  before insert or update of lesson_id on public.bookmarks
  for each row execute procedure public.set_progress_course_id();

drop policy if exists "Student manages own bookmarks" on public.bookmarks;
create policy "Student manages own bookmarks"
  on public.bookmarks for all
  using (auth.uid() = student_id)
  with check (auth.uid() = student_id);
