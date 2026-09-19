// =========================================================
// TIDEF ITECH LMS — Quizzes & Exams (Phase 6)
// =========================================================
// Taking and submitting an attempt goes entirely through RPC
// (start_attempt / submit_attempt / get_attempt_questions /
// get_attempt_review) — see supabase/migrations/0006_quizzes.sql. The
// client never receives which option is correct until after grading,
// and never has a direct write path to attempts/answers at all.
// =========================================================

import { supabase } from "./supabase.js";

// ---------- Assessment CRUD (staff/owning teacher) ----------

export async function getCourseAssessments(courseId, kind) {
  const { data, error } = await supabase
    .from("assessments")
    .select("*")
    .eq("course_id", courseId)
    .eq("kind", kind)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function getAssessmentsForCourses(courseIds, kind) {
  if (courseIds.length === 0) return [];
  const { data, error } = await supabase
    .from("assessments")
    .select("*, courses(name)")
    .in("course_id", courseIds)
    .eq("kind", kind)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function getAssessment(id) {
  const { data, error } = await supabase.from("assessments").select("*, courses(name)").eq("id", id).single();
  if (error) throw error;
  return data;
}

export async function createAssessment(assessment) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("assessments")
    .insert({ ...assessment, created_by: user?.id })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateAssessment(id, patch) {
  const { error } = await supabase
    .from("assessments")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

export async function deleteAssessment(id) {
  const { error } = await supabase.from("assessments").delete().eq("id", id);
  if (error) throw error;
}

// ---------- Question authoring (staff/owning teacher — full data incl. correct answers) ----------

export async function getQuestionsForEditing(assessmentId) {
  const { data, error } = await supabase
    .from("questions")
    .select("*, question_options(*)")
    .eq("assessment_id", assessmentId)
    .order("position");
  if (error) throw error;
  (data || []).forEach((q) => q.question_options.sort((a, b) => a.position - b.position));
  return data || [];
}

export async function createQuestion(assessmentId, { questionText, questionType, points, position }) {
  const { data, error } = await supabase
    .from("questions")
    .insert({ assessment_id: assessmentId, question_text: questionText, question_type: questionType, points, position })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateQuestion(id, patch) {
  const { error } = await supabase.from("questions").update(patch).eq("id", id);
  if (error) throw error;
}

export async function deleteQuestion(id) {
  const { error } = await supabase.from("questions").delete().eq("id", id);
  if (error) throw error;
}

export async function createOption(questionId, { optionText, isCorrect, position }) {
  const { data, error } = await supabase
    .from("question_options")
    .insert({ question_id: questionId, option_text: optionText, is_correct: isCorrect, position })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateOption(id, patch) {
  const { error } = await supabase.from("question_options").update(patch).eq("id", id);
  if (error) throw error;
}

export async function deleteOption(id) {
  const { error } = await supabase.from("question_options").delete().eq("id", id);
  if (error) throw error;
}

// ---------- Taking an attempt (student) ----------

export async function startAttempt(assessmentId) {
  const { data, error } = await supabase.rpc("start_attempt", { p_assessment_id: assessmentId });
  if (error) throw error;
  return data; // attempt id
}

export async function getAttemptQuestions(assessmentId) {
  const { data, error } = await supabase.rpc("get_attempt_questions", { p_assessment_id: assessmentId });
  if (error) throw error;
  return data || [];
}

export async function getAttempt(attemptId) {
  const { data, error } = await supabase.from("assessment_attempts").select("*").eq("id", attemptId).single();
  if (error) throw error;
  return data;
}

export async function submitAttempt(attemptId, answers, auto = false) {
  const { error } = await supabase.rpc("submit_attempt", {
    p_attempt_id: attemptId,
    p_answers: answers,
    p_auto: auto,
  });
  if (error) throw error;
}

export async function getAttemptReview(attemptId) {
  const { data, error } = await supabase.rpc("get_attempt_review", { p_attempt_id: attemptId });
  if (error) throw error;
  return data || [];
}

/** A student's own past attempts at one assessment, most recent first. */
export async function getMyAttempts(assessmentId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("assessment_attempts")
    .select("*")
    .eq("assessment_id", assessmentId)
    .eq("student_id", user.id)
    .order("attempt_number", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** Every attempt at one assessment, for the teacher/admin gradebook view. */
export async function getAssessmentAttempts(assessmentId) {
  const { data, error } = await supabase
    .from("assessment_attempts")
    .select("*, profiles(full_name, student_id)")
    .eq("assessment_id", assessmentId)
    .order("submitted_at", { ascending: false, nullsFirst: true });
  if (error) throw error;
  return data || [];
}
