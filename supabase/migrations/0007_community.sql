-- =========================================================
-- TIDEF ITECH LMS -- Phase 7 (community: Q&A + general discussion)
-- =========================================================
-- Run this AFTER 0001-0006.
--
-- Two separate features, matching the spec's two sections:
--   - qa_threads / qa_replies: course- and lesson-scoped Q&A (spec 23)
--   - posts / post_comments / post_likes: a platform-wide community
--     feed, not tied to a course (spec 24)
-- =========================================================

-- ---------------------------------------------------------
-- 1. Course/lesson Q&A
-- ---------------------------------------------------------

create table if not exists public.qa_threads (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  lesson_id uuid references public.lessons (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text,
  attachment_path text,
  is_resolved boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.qa_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.qa_threads (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  attachment_path text,
  is_accepted boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.qa_threads enable row level security;
alter table public.qa_replies enable row level security;

drop policy if exists "View threads if staff, owning teacher, or enrolled" on public.qa_threads;
create policy "View threads if staff, owning teacher, or enrolled"
  on public.qa_threads for select
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
    or public.is_enrolled(course_id)
  );

drop policy if exists "Enrolled or staff can ask" on public.qa_threads;
create policy "Enrolled or staff can ask"
  on public.qa_threads for insert
  with check (
    author_id = auth.uid()
    and (
      public.current_user_role() in ('admin', 'super_admin')
      or public.is_course_teacher(course_id)
      or public.is_enrolled(course_id)
    )
  );

drop policy if exists "Author edits own thread" on public.qa_threads;
create policy "Author edits own thread"
  on public.qa_threads for update
  using (author_id = auth.uid());

drop policy if exists "Staff and owning teacher moderate threads" on public.qa_threads;
create policy "Staff and owning teacher moderate threads"
  on public.qa_threads for all
  using (
    public.current_user_role() in ('admin', 'super_admin')
    or public.is_course_teacher(course_id)
  );

drop policy if exists "View replies if staff, owning teacher, or enrolled" on public.qa_replies;
create policy "View replies if staff, owning teacher, or enrolled"
  on public.qa_replies for select
  using (exists (
    select 1 from public.qa_threads t
    where t.id = thread_id
    and (
      public.current_user_role() in ('admin', 'super_admin')
      or public.is_course_teacher(t.course_id)
      or public.is_enrolled(t.course_id)
    )
  ));

drop policy if exists "Enrolled or staff can reply" on public.qa_replies;
create policy "Enrolled or staff can reply"
  on public.qa_replies for insert
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.qa_threads t
      where t.id = thread_id
      and (
        public.current_user_role() in ('admin', 'super_admin')
        or public.is_course_teacher(t.course_id)
        or public.is_enrolled(t.course_id)
      )
    )
  );

drop policy if exists "Author edits own reply" on public.qa_replies;
create policy "Author edits own reply"
  on public.qa_replies for update
  using (author_id = auth.uid());

drop policy if exists "Staff and owning teacher moderate replies" on public.qa_replies;
create policy "Staff and owning teacher moderate replies"
  on public.qa_replies for all
  using (exists (
    select 1 from public.qa_threads t
    where t.id = thread_id
    and (public.current_user_role() in ('admin', 'super_admin') or public.is_course_teacher(t.course_id))
  ));

drop policy if exists "Author deletes own thread" on public.qa_threads;
create policy "Author deletes own thread"
  on public.qa_threads for delete
  using (author_id = auth.uid());

drop policy if exists "Author deletes own reply" on public.qa_replies;
create policy "Author deletes own reply"
  on public.qa_replies for delete
  using (author_id = auth.uid());

-- Only the original asker or staff/owning teacher can accept an answer,
-- and it atomically un-accepts any previously accepted reply on the
-- same thread so there's only ever one accepted answer.
create or replace function public.accept_reply(p_reply_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_thread_id uuid;
  v_thread_author uuid;
  v_course_id uuid;
begin
  select r.thread_id, t.author_id, t.course_id
  into v_thread_id, v_thread_author, v_course_id
  from public.qa_replies r join public.qa_threads t on t.id = r.thread_id
  where r.id = p_reply_id;

  if v_thread_id is null then
    raise exception 'Reply not found.';
  end if;
  if auth.uid() <> v_thread_author
     and public.current_user_role() not in ('admin', 'super_admin')
     and not public.is_course_teacher(v_course_id)
  then
    raise exception 'Only the person who asked, or a course teacher/admin, can accept an answer.';
  end if;

  update public.qa_replies set is_accepted = false where thread_id = v_thread_id;
  update public.qa_replies set is_accepted = true where id = p_reply_id;
  update public.qa_threads set is_resolved = true where id = v_thread_id;
end;
$$;

revoke execute on function public.accept_reply(uuid) from public;
grant execute on function public.accept_reply(uuid) to authenticated;

-- ---------------------------------------------------------
-- 2. Platform-wide community: posts, comments, likes
-- ---------------------------------------------------------
-- Not tied to a course -- any signed-in, approved member (student,
-- teacher, or admin) can participate.

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  attachment_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.post_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);

alter table public.posts enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_likes enable row level security;

-- Anyone with an approved account (any role) can read and post.
create or replace function public.is_approved_member()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
    and (role in ('teacher', 'admin', 'super_admin') or (role = 'student' and account_status = 'approved'))
  );
$$;

drop policy if exists "Approved members read posts" on public.posts;
create policy "Approved members read posts"
  on public.posts for select
  using (public.is_approved_member());

drop policy if exists "Approved members create posts" on public.posts;
create policy "Approved members create posts"
  on public.posts for insert
  with check (author_id = auth.uid() and public.is_approved_member());

drop policy if exists "Author edits own post" on public.posts;
create policy "Author edits own post"
  on public.posts for update
  using (author_id = auth.uid());

drop policy if exists "Author or staff deletes post" on public.posts;
create policy "Author or staff deletes post"
  on public.posts for delete
  using (author_id = auth.uid() or public.current_user_role() in ('admin', 'super_admin', 'teacher'));

drop policy if exists "Approved members read comments" on public.post_comments;
create policy "Approved members read comments"
  on public.post_comments for select
  using (public.is_approved_member());

drop policy if exists "Approved members create comments" on public.post_comments;
create policy "Approved members create comments"
  on public.post_comments for insert
  with check (author_id = auth.uid() and public.is_approved_member());

drop policy if exists "Author or staff deletes comment" on public.post_comments;
create policy "Author or staff deletes comment"
  on public.post_comments for delete
  using (author_id = auth.uid() or public.current_user_role() in ('admin', 'super_admin', 'teacher'));

drop policy if exists "Approved members read likes" on public.post_likes;
create policy "Approved members read likes"
  on public.post_likes for select
  using (public.is_approved_member());

drop policy if exists "Approved members like posts" on public.post_likes;
create policy "Approved members like posts"
  on public.post_likes for insert
  with check (user_id = auth.uid() and public.is_approved_member());

drop policy if exists "Users remove own like" on public.post_likes;
create policy "Users remove own like"
  on public.post_likes for delete
  using (user_id = auth.uid());

-- ---------------------------------------------------------
-- 3. Storage bucket for Q&A / community attachments
-- ---------------------------------------------------------
-- Path convention: community-files/{user_id}/{filename}

insert into storage.buckets (id, name, public)
values ('community-files', 'community-files', false)
on conflict (id) do nothing;

drop policy if exists "Users upload own community files" on storage.objects;
create policy "Users upload own community files"
  on storage.objects for insert
  with check (bucket_id = 'community-files' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Signed-in users read community files" on storage.objects;
create policy "Signed-in users read community files"
  on storage.objects for select
  using (bucket_id = 'community-files' and auth.role() = 'authenticated');
