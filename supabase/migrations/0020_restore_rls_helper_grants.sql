-- RLS expressions call these SECURITY DEFINER helpers as the authenticated user.
-- Restore only the required signed-in EXECUTE grants; anonymous access stays revoked.
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_course_teacher(uuid) to authenticated;
grant execute on function public.is_enrolled(uuid) to authenticated;
grant execute on function public.is_approved_member() to authenticated;
