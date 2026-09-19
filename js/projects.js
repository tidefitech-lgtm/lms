// =========================================================
// TIDEF ITECH LMS — Projects (Phase 5)
// =========================================================

import { supabase } from "./supabase.js";

/** The current student's own projects, most recent first. */
export async function getMyProjects() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("projects")
    .select("*, courses(name)")
    .eq("student_id", user.id)
    .order("submitted_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** All projects submitted for a course (staff/owning teacher only, per RLS). */
export async function getCourseProjects(courseId) {
  const { data, error } = await supabase
    .from("projects")
    .select("*, profiles!student_id(full_name, student_id)")
    .eq("course_id", courseId)
    .order("submitted_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** All projects across several courses (for a teacher/admin "all projects" view). */
export async function getProjectsForCourses(courseIds) {
  if (courseIds.length === 0) return [];
  const { data, error } = await supabase
    .from("projects")
    .select("*, profiles!student_id(full_name, student_id), courses(name)")
    .in("course_id", courseIds)
    .order("submitted_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function submitProject({ projectId, courseId, title, description, filePath, githubUrl, liveUrl, screenshotPaths }) {
  const { data, error } = await supabase.rpc("submit_project", {
    p_project_id: projectId || null,
    p_course_id: courseId,
    p_title: title,
    p_description: description || null,
    p_file_path: filePath || null,
    p_github_url: githubUrl || null,
    p_live_url: liveUrl || null,
    p_screenshot_paths: screenshotPaths || [],
  });
  if (error) throw error;
  return data;
}

export async function gradeProject(projectId, grade, feedback) {
  const { error } = await supabase.rpc("grade_project", {
    p_project_id: projectId,
    p_grade: grade,
    p_feedback: feedback || null,
  });
  if (error) throw error;
}
