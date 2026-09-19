// =========================================================
// TIDEF ITECH LMS — Courses, Modules, Lessons, Enrollments (Phase 3)
// =========================================================
// RLS in supabase/migrations/0003_courses.sql is the real access
// boundary here — e.g. an admin-only insert on `courses` will simply
// fail with a policy error if a non-admin somehow calls it, regardless
// of what this file lets you attempt.
// =========================================================

import { supabase } from "./supabase.js";

// ---------- Courses ----------

/** List all courses (any status) — for admin/teacher management views. */
export async function getAllCourses() {
  const { data, error } = await supabase
    .from("courses")
    .select("*, teacher:profiles!teacher_id(full_name)")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** List courses assigned to the current teacher. */
export async function getTeacherCourses() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("courses")
    .select("*")
    .eq("teacher_id", user.id)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** Fetch one course by id. */
export async function getCourse(courseId) {
  const { data, error } = await supabase
    .from("courses")
    .select("*, teacher:profiles!teacher_id(full_name)")
    .eq("id", courseId)
    .single();
  if (error) throw error;
  return data;
}

export async function createCourse(course) {
  const { data, error } = await supabase.from("courses").insert(course).select().single();
  if (error) throw error;
  return data;
}

export async function updateCourse(courseId, patch) {
  const { error } = await supabase
    .from("courses")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", courseId);
  if (error) throw error;
}

export async function setCourseStatus(courseId, status) {
  return updateCourse(courseId, { status });
}

/** List every teacher, for the course-assignment dropdown. */
export async function getTeachers() {
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email")
    .eq("role", "teacher")
    .order("full_name");
  if (error) throw error;
  return data || [];
}

// ---------- Modules & Lessons ----------

/** Fetch a course's modules, each with its lessons, in position order. */
export async function getCurriculum(courseId) {
  const { data: modules, error: modErr } = await supabase
    .from("modules")
    .select("*")
    .eq("course_id", courseId)
    .order("position");
  if (modErr) throw modErr;

  const { data: lessons, error: lessErr } = await supabase
    .from("lessons")
    .select("*")
    .eq("course_id", courseId)
    .order("position");
  if (lessErr) throw lessErr;

  return (modules || []).map((m) => ({
    ...m,
    lessons: (lessons || []).filter((l) => l.module_id === m.id),
  }));
}

export async function createModule(courseId, title, position) {
  const { data, error } = await supabase
    .from("modules")
    .insert({ course_id: courseId, title, position })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateModule(moduleId, patch) {
  const { error } = await supabase.from("modules").update(patch).eq("id", moduleId);
  if (error) throw error;
}

export async function deleteModule(moduleId) {
  const { error } = await supabase.from("modules").delete().eq("id", moduleId);
  if (error) throw error;
}

export async function createLesson(moduleId, lesson, position) {
  const { data, error } = await supabase
    .from("lessons")
    .insert({ module_id: moduleId, position, ...lesson })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateLesson(lessonId, patch) {
  const { error } = await supabase.from("lessons").update(patch).eq("id", lessonId);
  if (error) throw error;
}

export async function deleteLesson(lessonId) {
  const { error } = await supabase.from("lessons").delete().eq("id", lessonId);
  if (error) throw error;
}

// ---------- Enrollments ----------

/** Roster for one course (admin / owning teacher only, per RLS). */
export async function getCourseEnrollments(courseId) {
  const { data, error } = await supabase
    .from("enrollments")
    .select("*, profiles!student_id(full_name, email, student_id)")
    .eq("course_id", courseId)
    .order("enrolled_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** Approved students not yet enrolled in the given course (client-side filtered). */
export async function getEnrollableStudents(courseId) {
  const [{ data: students, error: sErr }, enrollments] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, full_name, email, student_id")
      .eq("role", "student")
      .eq("account_status", "approved")
      .order("full_name"),
    getCourseEnrollments(courseId),
  ]);
  if (sErr) throw sErr;
  const enrolledIds = new Set(enrollments.map((e) => e.student_id));
  return (students || []).filter((s) => !enrolledIds.has(s.id));
}

export async function enrollStudent(courseId, studentId) {
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase
    .from("enrollments")
    .insert({ course_id: courseId, student_id: studentId, enrolled_by: user?.id });
  if (error) throw error;
}

export async function unenrollStudent(enrollmentId) {
  const { error } = await supabase.from("enrollments").delete().eq("id", enrollmentId);
  if (error) throw error;
}

/** A student's own enrolled courses. */
export async function getMyEnrolledCourses() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("enrollments")
    .select("*, courses(*)")
    .eq("student_id", user.id)
    .order("enrolled_at", { ascending: false });
  if (error) throw error;
  return data || [];
}
