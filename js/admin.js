// =========================================================
// TIDEF ITECH LMS — Admin & Reporting (Phase 9)
// =========================================================
// Role changes and suspend/reactivate go through plain table updates —
// the Phase 1 trigger (protect_privileged_fields) already enforces that
// only a super_admin can change `role`, and that only staff can touch
// `account_status` at all. This file just adds an audit-log entry
// alongside each change; if that second call fails, the actual change
// still succeeded — the log is a record, not a gate.
// =========================================================

import { supabase } from "./supabase.js";

export async function logActivity(action, { targetType, targetId, details } = {}) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  let actorName = null;
  try {
    const { data } = await supabase.from("profiles").select("full_name").eq("id", user.id).single();
    actorName = data?.full_name || null;
  } catch { /* non-critical */ }

  await supabase.from("activity_logs").insert({
    actor_id: user.id,
    actor_name: actorName,
    action,
    target_type: targetType || null,
    target_id: targetId || null,
    details: details || null,
  });
}

export async function getActivityLogs(limit = 100) {
  const { data, error } = await supabase
    .from("activity_logs")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data || [];
}

// ---------- Users & roles ----------

export async function getAllUsers({ role, search } = {}) {
  let query = supabase.from("profiles").select("*").order("created_at", { ascending: false });
  if (role) query = query.eq("role", role);
  if (search) query = query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%,student_id.ilike.%${search}%`);
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

export async function updateUserRole(userId, newRole) {
  const { error } = await supabase.from("profiles").update({ role: newRole }).eq("id", userId);
  if (error) throw error;
  await logActivity("role_changed", { targetType: "user", targetId: userId, details: { newRole } });
}

export async function setAccountStatus(userId, newStatus) {
  const { error } = await supabase.from("profiles").update({ account_status: newStatus }).eq("id", userId);
  if (error) throw error;
  await logActivity("account_status_changed", { targetType: "user", targetId: userId, details: { newStatus } });
}

// ---------- Teachers ----------

export async function getTeachersWithCourses() {
  const { data: teachers, error } = await supabase.from("profiles").select("*").eq("role", "teacher").order("full_name");
  if (error) throw error;

  const { data: courses } = await supabase.from("courses").select("id, name, teacher_id").not("teacher_id", "is", null);
  const byTeacher = {};
  (courses || []).forEach((c) => {
    byTeacher[c.teacher_id] = byTeacher[c.teacher_id] || [];
    byTeacher[c.teacher_id].push(c);
  });

  return (teachers || []).map((t) => ({ ...t, courses: byTeacher[t.id] || [] }));
}

// ---------- Settings ----------

export async function getSettings() {
  const { data, error } = await supabase.from("settings").select("*");
  if (error) throw error;
  const map = {};
  (data || []).forEach((row) => (map[row.key] = row.value));
  return map;
}

export async function updateSetting(key, value) {
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase
    .from("settings")
    .upsert({ key, value, updated_at: new Date().toISOString(), updated_by: user?.id }, { onConflict: "key" });
  if (error) throw error;
  await logActivity("setting_updated", { targetType: "setting", details: { key, value } });
}

// ---------- Reports ----------

export async function getReportStats() {
  const [
    { count: totalStudents },
    { count: approvedStudents },
    { count: totalCourses },
    { count: publishedCourses },
    { count: totalCertificates },
    { data: enrollmentRows },
    { data: attemptRows },
    { data: submissionRows },
  ] = await Promise.all([
    supabase.from("profiles").select("*", { count: "exact", head: true }).eq("role", "student"),
    supabase.from("profiles").select("*", { count: "exact", head: true }).eq("role", "student").eq("account_status", "approved"),
    supabase.from("courses").select("*", { count: "exact", head: true }),
    supabase.from("courses").select("*", { count: "exact", head: true }).eq("status", "published"),
    supabase.from("certificates").select("*", { count: "exact", head: true }),
    supabase.from("enrollments").select("course_id, status, courses(name)"),
    supabase.from("assessment_attempts").select("passed, status").neq("status", "in_progress"),
    supabase.from("submissions").select("status"),
  ]);

  // Enrollment count per course.
  const enrollByCourse = {};
  (enrollmentRows || []).forEach((e) => {
    const name = e.courses?.name || "Unknown course";
    enrollByCourse[name] = enrollByCourse[name] || { total: 0, completed: 0 };
    enrollByCourse[name].total += 1;
    if (e.status === "completed") enrollByCourse[name].completed += 1;
  });

  const finishedAttempts = attemptRows || [];
  const passRate = finishedAttempts.length > 0
    ? Math.round((finishedAttempts.filter((a) => a.passed).length / finishedAttempts.length) * 100)
    : null;

  const gradedSubmissions = (submissionRows || []).filter((s) => s.status === "graded").length;
  const submissionGradeRate = (submissionRows || []).length > 0
    ? Math.round((gradedSubmissions / submissionRows.length) * 100)
    : null;

  return {
    totalStudents: totalStudents ?? 0,
    approvedStudents: approvedStudents ?? 0,
    totalCourses: totalCourses ?? 0,
    publishedCourses: publishedCourses ?? 0,
    totalCertificates: totalCertificates ?? 0,
    enrollByCourse,
    passRate,
    totalAttempts: finishedAttempts.length,
    submissionGradeRate,
    totalSubmissions: (submissionRows || []).length,
  };
}
