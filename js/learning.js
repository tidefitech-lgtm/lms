// =========================================================
// TIDEF ITECH LMS — Learning (Phase 4)
// =========================================================
// Video completion is deliberately NOT something this file can fake —
// record_video_progress (in supabase/migrations/0004_learning.sql) only
// marks a lesson complete once ~90% of its duration has actually been
// watched. Opening a lesson is never enough on its own.
// =========================================================

import { supabase } from "./supabase.js";

/** Map of lesson_id -> progress row, for every lesson the student has touched in this course. */
export async function getProgressForCourse(courseId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return {};
  const { data, error } = await supabase
    .from("lesson_progress")
    .select("*")
    .eq("student_id", user.id)
    .eq("course_id", courseId);
  if (error) return {};
  const map = {};
  (data || []).forEach((row) => (map[row.lesson_id] = row));
  return map;
}

/** Report video playback progress (called periodically while playing, and on pause/end). */
export async function recordVideoProgress(lessonId, secondsWatched, durationSeconds) {
  const { error } = await supabase.rpc("record_video_progress", {
    p_lesson_id: lessonId,
    p_seconds_watched: secondsWatched,
    p_duration_seconds: durationSeconds ?? null,
  });
  if (error) throw error;
}

/** Manually mark a non-video lesson complete. */
export async function markLessonComplete(lessonId) {
  const { error } = await supabase.rpc("mark_lesson_complete", { p_lesson_id: lessonId });
  if (error) throw error;
}

/** Compute { completed, total, percent } for a course from an already-fetched curriculum + progress map. */
export function computeCourseProgress(modules, progressMap) {
  const lessons = modules.flatMap((m) => m.lessons);
  const total = lessons.length;
  const completed = lessons.filter((l) => progressMap[l.id]?.status === "completed").length;
  const percent = total > 0 ? Math.round((completed / total) * 100) : 0;
  return { completed, total, percent };
}

// ---------- Notes ----------

export async function getNote(lessonId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from("notes")
    .select("*")
    .eq("student_id", user.id)
    .eq("lesson_id", lessonId)
    .maybeSingle();
  if (error) return null;
  return data;
}

export async function saveNote(lessonId, content) {
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase
    .from("notes")
    .upsert(
      { student_id: user.id, lesson_id: lessonId, content, updated_at: new Date().toISOString() },
      { onConflict: "student_id,lesson_id" }
    );
  if (error) throw error;
}

// ---------- Bookmarks ----------

export async function isBookmarked(lessonId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return false;
  const { data, error } = await supabase
    .from("bookmarks")
    .select("id")
    .eq("student_id", user.id)
    .eq("lesson_id", lessonId)
    .maybeSingle();
  if (error) return false;
  return !!data;
}

export async function toggleBookmark(lessonId) {
  const { data: { user } } = await supabase.auth.getUser();
  const already = await isBookmarked(lessonId);
  if (already) {
    const { error } = await supabase
      .from("bookmarks")
      .delete()
      .eq("student_id", user.id)
      .eq("lesson_id", lessonId);
    if (error) throw error;
    return false;
  }
  const { error } = await supabase.from("bookmarks").insert({ student_id: user.id, lesson_id: lessonId });
  if (error) throw error;
  return true;
}

/** All of a student's bookmarked lessons, with lesson + course names for display. */
export async function getMyBookmarks() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("bookmarks")
    .select("*, lessons(title, lesson_type), courses(name)")
    .eq("student_id", user.id)
    .order("created_at", { ascending: false });
  if (error) return [];
  return data || [];
}

// ---------- YouTube helpers ----------

/** Pull an 11-character YouTube video ID out of any common URL format. */
export function extractYouTubeId(url = "") {
  const match = url.match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?v=|embed\/|shorts\/))([\w-]{11})/);
  return match ? match[1] : null;
}
