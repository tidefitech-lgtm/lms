-- Scheduled live classes for Google Meet and Zoom.
create table if not exists public.live_classes (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  teacher_id uuid not null references public.profiles (id),
  created_by uuid not null references public.profiles (id),
  title text not null,
  description text,
  provider text not null check (provider in ('google_meet', 'zoom')),
  meeting_url text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

alter table public.live_classes enable row level security;

create index if not exists live_classes_course_starts_idx
  on public.live_classes (course_id, starts_at);

drop policy if exists "Members view enrolled live classes" on public.live_classes;
create policy "Members view enrolled live classes"
  on public.live_classes for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
    or public.is_enrolled(course_id)
  );

drop policy if exists "Admins and course teachers create live classes" on public.live_classes;
create policy "Admins and course teachers create live classes"
  on public.live_classes for insert
  with check (
    public.current_user_role() in ('admin', 'super_admin')
    or (
      public.current_user_role() = 'teacher'
      and teacher_id = auth.uid()
      and public.is_course_teacher(course_id)
    )
  );

drop policy if exists "Admins and owning teachers update live classes" on public.live_classes;
create policy "Admins and owning teachers update live classes"
  on public.live_classes for update
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or (teacher_id = auth.uid() and public.is_course_teacher(course_id))
  );

drop policy if exists "Admins and owning teachers delete live classes" on public.live_classes;
create policy "Admins and owning teachers delete live classes"
  on public.live_classes for delete
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or (teacher_id = auth.uid() and public.is_course_teacher(course_id))
  );

create or replace function public.notify_students_of_course_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.name is distinct from old.name
     or new.description is distinct from old.description
     or new.status is distinct from old.status
     or new.updated_at is distinct from old.updated_at
  then
    insert into public.notifications (user_id, title, body)
    select e.student_id,
      'Course updated',
      'There is a new update in ' || new.name || '.'
    from public.enrollments e
    where e.course_id = new.id
      and e.status in ('active', 'completed');
  end if;
  return new;
end;
$$;

drop trigger if exists after_course_updated_notify_students on public.courses;
create trigger after_course_updated_notify_students
after update on public.courses
for each row execute procedure public.notify_students_of_course_update();

create or replace function public.notify_students_of_live_class()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  course_name text;
  notification_title text;
  notification_body text;
begin
  select name into course_name from public.courses where id = new.course_id;
  notification_title := case when tg_op = 'INSERT' then 'New live class scheduled' else 'Live class updated' end;
  notification_body := new.title || ' for ' || coalesce(course_name, 'your course') ||
    ' starts at ' || to_char(new.starts_at at time zone 'UTC', 'DD Mon YYYY HH24:MI') || ' UTC.';

  insert into public.notifications (user_id, title, body)
  select e.student_id, notification_title, notification_body
  from public.enrollments e
  where e.course_id = new.course_id
    and e.status in ('active', 'completed');
  return new;
end;
$$;

drop trigger if exists after_live_class_created_notify_students on public.live_classes;
create trigger after_live_class_created_notify_students
after insert or update on public.live_classes
for each row execute procedure public.notify_students_of_live_class();

revoke execute on function public.notify_students_of_course_update() from public;
revoke execute on function public.notify_students_of_live_class() from public;

-- Enable foreground/browser alerts for the notification center. Background
-- Web Push still requires a VAPID sender or push provider.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
