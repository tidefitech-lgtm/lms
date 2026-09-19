// =========================================================
// TIDEF ITECH LMS — Assignments (Phase 5)
// =========================================================
// Submitting and grading go through Postgres functions (submit_assignment /
// grade_submission), not direct table writes — see
// supabase/migrations/0005_assignments.sql. That's what makes the
// resubmission rule and the "grade can't exceed max marks" check hold
// regardless of what the client sends.
// =========================================================

import { supabase } from "./supabase.js";

// ---------- Assignments (teacher/admin manage; everyone enrolled can read) ----------

export async function getCourseAssignments(courseId) {
  const { data, error } = await supabase
    .from("assignments")
    .select("*")
    .eq("course_id", courseId)
    .order("due_at", { ascending: true, nullsFirst: false });
  if (error) throw error;
  return data || [];
}

export async function getAssignment(id) {
  const { data, error } = await supabase.from("assignments").select("*, courses(name)").eq("id", id).single();
  if (error) throw error;
  return data;
}

export async function createAssignment(assignment) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("assignments")
    .insert({ ...assignment, created_by: user?.id })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateAssignment(id, patch) {
  const { error } = await supabase
    .from("assignments")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

export async function deleteAssignment(id) {
  const { error } = await supabase.from("assignments").delete().eq("id", id);
  if (error) throw error;
}

/** Every assignment across every course a teacher/admin can see, for a combined "all my assignments" list. */
export async function getAssignmentsForCourses(courseIds) {
  if (courseIds.length === 0) return [];
  const { data, error } = await supabase
    .from("assignments")
    .select("*, courses(name)")
    .in("course_id", courseIds)
    .order("due_at", { ascending: true, nullsFirst: false });
  if (error) throw error;
  return data || [];
}

// ---------- Submissions ----------

/** Roster of submissions for one assignment (staff/owning teacher only, per RLS). */
export async function getAssignmentSubmissions(assignmentId) {
  const { data, error } = await supabase
    .from("submissions")
    .select("*, profiles!student_id(full_name, student_id)")
    .eq("assignment_id", assignmentId)
    .order("submitted_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** The current student's own submission for one assignment, if any. */
export async function getMySubmission(assignmentId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from("submissions")
    .select("*")
    .eq("assignment_id", assignmentId)
    .eq("student_id", user.id)
    .maybeSingle();
  if (error) return null;
  return data;
}

export async function submitAssignment(assignmentId, { contentText, filePath }) {
  const { error } = await supabase.rpc("submit_assignment", {
    p_assignment_id: assignmentId,
    p_content_text: contentText || null,
    p_file_path: filePath || null,
  });
  if (error) throw error;
}

export async function gradeSubmission(submissionId, grade, feedback) {
  const { error } = await supabase.rpc("grade_submission", {
    p_submission_id: submissionId,
    p_grade: grade,
    p_feedback: feedback || null,
  });
  if (error) throw error;
}
