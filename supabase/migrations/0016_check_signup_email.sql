-- =========================================================
-- TIDEF ITECH LMS -- Signup email availability check
-- =========================================================
-- Run this AFTER 0001-0015.

create or replace function public.email_exists(p_email text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from auth.users
    where lower(email) = lower(trim(p_email))
  );
$$;

revoke execute on function public.email_exists(text) from public;
grant execute on function public.email_exists(text) to anon, authenticated;
