-- =========================================================
-- TIDEF ITECH LMS -- Notification delivery
-- =========================================================
-- Run this AFTER 0001-0010.

-- Staff can review notifications without changing the student's read state.
drop policy if exists "Staff view all notifications" on public.notifications;
create policy "Staff view all notifications"
  on public.notifications for select
  using (public.current_user_role() in ('admin', 'super_admin'));

-- Create one in-app notification for every student when a course is added.
create or replace function public.notify_students_of_new_course()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.notifications (user_id, title, body)
  select p.id,
    'New course added',
    'A new course, ' || new.name || ', has been added to TIDEF ITECH LMS.'
  from public.profiles p
  where p.role = 'student';
  return new;
end;
$$;

drop trigger if exists after_course_created_notify_students on public.courses;
create trigger after_course_created_notify_students
after insert on public.courses
for each row execute procedure public.notify_students_of_new_course();

revoke execute on function public.notify_students_of_new_course() from public;
