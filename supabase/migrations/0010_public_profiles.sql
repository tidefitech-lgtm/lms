-- =========================================================
-- TIDEF ITECH LMS -- Public author profiles for Community
-- =========================================================
-- Exposes only fields that are safe to show beside community posts.

create or replace function public.get_public_profiles(p_profile_ids uuid[])
returns table (
  id uuid,
  full_name text,
  role text
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.role
  from public.profiles p
  where p.id = any(p_profile_ids)
    and public.is_approved_member();
$$;

revoke execute on function public.get_public_profiles(uuid[]) from public;
grant execute on function public.get_public_profiles(uuid[]) to authenticated;
