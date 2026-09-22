-- =========================================================
-- TIDEF ITECH LMS -- Video watch-time tracking
-- =========================================================
-- Run this AFTER 0001-0011.

alter table public.lesson_progress
  add column if not exists video_watch_seconds numeric not null default 0,
  add column if not exists last_video_position numeric;

-- Existing rows only have furthest-position data. Use it as a baseline;
-- new playback reports accumulate separately from that snapshot.
update public.lesson_progress
set video_watch_seconds = video_seconds_watched
where video_watch_seconds = 0 and video_seconds_watched > 0;

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
  v_existing_watch numeric;
  v_last_position numeric;
  v_watch_delta numeric := 0;
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

  select video_seconds_watched, video_duration_seconds, video_watch_seconds, last_video_position
  into v_existing_max, v_duration, v_existing_watch, v_last_position
  from public.lesson_progress
  where student_id = auth.uid() and lesson_id = p_lesson_id;

  v_new_max := greatest(coalesce(v_existing_max, 0), coalesce(p_seconds_watched, 0));
  v_duration := coalesce(p_duration_seconds, v_duration);

  -- The player reports about every five seconds. Ignore large jumps so
  -- seeking does not inflate watch time, while allowing delayed reports.
  if v_last_position is not null
     and p_seconds_watched >= v_last_position
     and p_seconds_watched - v_last_position <= 30 then
    v_watch_delta := p_seconds_watched - v_last_position;
  end if;

  if v_duration is not null and v_duration > 0 and (v_new_max / v_duration) >= 0.9 then
    v_should_complete := true;
  end if;

  insert into public.lesson_progress (
    student_id, lesson_id, status, video_seconds_watched,
    video_duration_seconds, video_watch_seconds, last_video_position,
    completed_at, last_interacted_at
  )
  values (
    auth.uid(), p_lesson_id,
    case when v_should_complete then 'completed' else 'in_progress' end,
    v_new_max, v_duration, coalesce(v_watch_delta, 0), p_seconds_watched,
    case when v_should_complete then now() else null end,
    now()
  )
  on conflict (student_id, lesson_id) do update set
    video_seconds_watched = v_new_max,
    video_duration_seconds = v_duration,
    video_watch_seconds = coalesce(public.lesson_progress.video_watch_seconds, 0) + v_watch_delta,
    last_video_position = p_seconds_watched,
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
