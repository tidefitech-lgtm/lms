-- =========================================================
-- TIDEF ITECH LMS -- Recalculate completion when lessons change
-- =========================================================
-- Run this AFTER 0001-0012.

-- Repair any existing enrollment that is marked complete but has
-- incomplete lessons, then remove certificates for those enrollments.
with stale_completions as (
  select e.student_id, e.course_id
  from public.enrollments e
  where e.status = 'completed'
    and exists (
      select 1
      from public.lessons l
      where l.course_id = e.course_id
        and not exists (
          select 1
          from public.lesson_progress lp
          where lp.student_id = e.student_id
            and lp.lesson_id = l.id
            and lp.status = 'completed'
        )
    )
)
update public.enrollments e
set status = 'active'
from stale_completions s
where e.student_id = s.student_id and e.course_id = s.course_id;

delete from public.certificates c
where exists (
  select 1
  from public.enrollments e
  where e.student_id = c.student_id
    and e.course_id = c.course_id
    and e.status <> 'completed'
);

-- A new lesson makes every previously completed enrollment incomplete.
create or replace function public.reset_course_completion_on_new_lesson()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.enrollments
  set status = 'active'
  where course_id = new.course_id and status = 'completed';

  delete from public.certificates
  where course_id = new.course_id;

  return new;
end;
$$;

drop trigger if exists after_lesson_created_reset_completion on public.lessons;
create trigger after_lesson_created_reset_completion
after insert on public.lessons
for each row execute procedure public.reset_course_completion_on_new_lesson();

-- Completion must be true at the moment a certificate is issued.
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

  if not exists (
    select 1 from public.enrollments
    where student_id = p_student_id
      and course_id = p_course_id
      and status = 'completed'
  ) then
    raise exception 'The student has not completed this course.';
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
