-- Restrict SECURITY DEFINER functions at the API privilege boundary.
-- This changes EXECUTE grants only; function bodies and existing data are untouched.

-- Internal helpers, triggers, counters, and RLS helpers must never be called
-- directly through /rest/v1/rpc by anonymous or signed-in clients.
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.current_user_role() from public;
revoke execute on function public.protect_privileged_fields() from public;
revoke execute on function public.next_student_id() from public;
revoke execute on function public.set_lesson_course_id() from public;
revoke execute on function public.is_course_teacher(uuid) from public;
revoke execute on function public.is_enrolled(uuid) from public;
revoke execute on function public.set_progress_course_id() from public;
revoke execute on function public.recalculate_course_progress(uuid, uuid) from public;
revoke execute on function public.next_certificate_number() from public;
revoke execute on function public.is_approved_member() from public;
revoke execute on function public.notify_students_of_new_course() from public;
revoke execute on function public.reset_course_completion_on_new_lesson() from public;

-- These functions are intentionally callable by signed-in LMS users.
revoke execute on function public.accept_reply(uuid) from public;
revoke execute on function public.admin_confirm_payment(uuid, text) from public;
revoke execute on function public.admin_reject_payment(uuid, text) from public;
revoke execute on function public.get_attempt_questions(uuid) from public;
revoke execute on function public.get_attempt_review(uuid) from public;
revoke execute on function public.get_public_profiles(uuid[]) from public;
revoke execute on function public.grade_project(uuid, numeric, text) from public;
revoke execute on function public.grade_submission(uuid, numeric, text) from public;
revoke execute on function public.issue_certificate(uuid, uuid, text, text) from public;
revoke execute on function public.mark_lesson_complete(uuid) from public;
revoke execute on function public.record_video_progress(uuid, numeric, numeric) from public;
revoke execute on function public.start_attempt(uuid) from public;
revoke execute on function public.submit_assignment(uuid, text, text) from public;
revoke execute on function public.submit_attempt(uuid, jsonb, boolean) from public;
revoke execute on function public.submit_payment_confirmation(uuid, text, date, text, text) from public;
revoke execute on function public.submit_project(uuid, uuid, text, text, text, text, text, text[]) from public;

grant execute on function public.accept_reply(uuid) to authenticated;
grant execute on function public.admin_confirm_payment(uuid, text) to authenticated;
grant execute on function public.admin_reject_payment(uuid, text) to authenticated;
grant execute on function public.get_attempt_questions(uuid) to authenticated;
grant execute on function public.get_attempt_review(uuid) to authenticated;
grant execute on function public.get_public_profiles(uuid[]) to authenticated;
grant execute on function public.grade_project(uuid, numeric, text) to authenticated;
grant execute on function public.grade_submission(uuid, numeric, text) to authenticated;
grant execute on function public.issue_certificate(uuid, uuid, text, text) to authenticated;
grant execute on function public.mark_lesson_complete(uuid) to authenticated;
grant execute on function public.record_video_progress(uuid, numeric, numeric) to authenticated;
grant execute on function public.start_attempt(uuid) to authenticated;
grant execute on function public.submit_assignment(uuid, text, text) to authenticated;
grant execute on function public.submit_attempt(uuid, jsonb, boolean) to authenticated;
grant execute on function public.submit_payment_confirmation(uuid, text, date, text, text) to authenticated;
grant execute on function public.submit_project(uuid, uuid, text, text, text, text, text, text[]) to authenticated;

-- These two endpoints are intentionally public:
-- email_exists is used before signup; verify_certificate is an employer-facing check.
revoke execute on function public.email_exists(text) from public;
revoke execute on function public.verify_certificate(text) from public;
grant execute on function public.email_exists(text) to anon, authenticated;
grant execute on function public.verify_certificate(text) to anon, authenticated;
