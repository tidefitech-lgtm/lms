-- =========================================================
-- TIDEF ITECH LMS -- Preserve issued certificates
-- =========================================================
-- Run this AFTER 0013_recalculate_completion.sql.

-- Restore certificate-backed enrollments if migration 0013 changed them.
update public.enrollments e
set status = 'completed'
where exists (
  select 1
  from public.certificates c
  where c.student_id = e.student_id
    and c.course_id = e.course_id
)
and e.status <> 'completed';

-- New lessons only reset students who do not already have a certificate.
create or replace function public.reset_course_completion_on_new_lesson()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.enrollments e
  set status = 'active'
  where e.course_id = new.course_id
    and e.status = 'completed'
    and not exists (
      select 1
      from public.certificates c
      where c.student_id = e.student_id
        and c.course_id = e.course_id
    );

  return new;
end;
$$;

drop trigger if exists after_lesson_created_reset_completion on public.lessons;
create trigger after_lesson_created_reset_completion
after insert on public.lessons
for each row execute procedure public.reset_course_completion_on_new_lesson();
