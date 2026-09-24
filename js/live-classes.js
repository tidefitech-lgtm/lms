import { supabase } from "./supabase.js";

export async function getLiveClasses({ courseIds = null, upcomingOnly = false } = {}) {
  let query = supabase
    .from("live_classes")
    .select("*, courses(name), profiles!teacher_id(full_name)")
    .order("starts_at", { ascending: true });
  if (courseIds) query = query.in("course_id", courseIds);
  if (upcomingOnly) query = query.gte("starts_at", new Date().toISOString());
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

export async function createLiveClass(values) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("live_classes")
    .insert({ ...values, created_by: user.id })
    .select("*, courses(name), profiles!teacher_id(full_name)")
    .single();
  if (error) throw error;
  return data;
}

export async function deleteLiveClass(id) {
  const { error } = await supabase.from("live_classes").delete().eq("id", id);
  if (error) throw error;
}

export function meetingEmbedUrl(url) {
  try {
    const parsed = new URL(url);
    if (parsed.hostname === "meet.google.com") return parsed.href;
    if (parsed.hostname.endsWith("zoom.us")) return parsed.href;
    return null;
  } catch {
    return null;
  }
}
