// =========================================================
// TIDEF ITECH LMS — Community (Phase 7)
// =========================================================

import { supabase } from "./supabase.js";

// ---------- Q&A ----------

export async function getCourseThreads(courseId) {
  const { data, error } = await supabase
    .from("qa_threads")
    .select("*, profiles!author_id(full_name), lessons(title)")
    .eq("course_id", courseId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function getThreadsForCourses(courseIds) {
  if (courseIds.length === 0) return [];
  const { data, error } = await supabase
    .from("qa_threads")
    .select("*, profiles!author_id(full_name), courses(name), lessons(title)")
    .in("course_id", courseIds)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function getThread(id) {
  const { data, error } = await supabase
    .from("qa_threads")
    .select("*, profiles!author_id(full_name), courses(name), lessons(title)")
    .eq("id", id)
    .single();
  if (error) throw error;
  return data;
}

export async function getReplies(threadId) {
  const { data, error } = await supabase
    .from("qa_replies")
    .select("*, profiles!author_id(full_name, role)")
    .eq("thread_id", threadId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function createThread({
  courseId,
  lessonId,
  title,
  body,
  attachmentPath,
}) {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("qa_threads")
    .insert({
      course_id: courseId,
      lesson_id: lessonId || null,
      author_id: user.id,
      title,
      body: body || null,
      attachment_path: attachmentPath || null,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function createReply({ threadId, body, attachmentPath }) {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { error } = await supabase
    .from("qa_replies")
    .insert({
      thread_id: threadId,
      author_id: user.id,
      body,
      attachment_path: attachmentPath || null,
    });
  if (error) throw error;
}

export async function acceptReply(replyId) {
  const { error } = await supabase.rpc("accept_reply", { p_reply_id: replyId });
  if (error) throw error;
}

export async function deleteThread(id) {
  const { error } = await supabase.from("qa_threads").delete().eq("id", id);
  if (error) throw error;
}

export async function deleteReply(id) {
  const { error } = await supabase.from("qa_replies").delete().eq("id", id);
  if (error) throw error;
}

// ---------- Community posts ----------

export async function getPosts(limit = 30) {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("posts")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;

  const posts = data || [];
  const authorIds = [
    ...new Set(posts.map((post) => post.author_id).filter(Boolean)),
  ];
  const { data: publicProfiles, error: profileError } = await supabase.rpc(
    "get_public_profiles",
    { p_profile_ids: authorIds },
  );
  if (profileError) throw profileError;
  const profilesById = new Map(
    (publicProfiles || []).map((profile) => [profile.id, profile]),
  );

  const withMeta = await Promise.all(
    posts.map(async (p) => {
      const [{ count: likeCount }, myLike, { count: commentCount }] =
        await Promise.all([
          supabase
            .from("post_likes")
            .select("*", { count: "exact", head: true })
            .eq("post_id", p.id),
          user
            ? supabase
                .from("post_likes")
                .select("id")
                .eq("post_id", p.id)
                .eq("user_id", user.id)
                .maybeSingle()
            : { data: null },
          supabase
            .from("post_comments")
            .select("*", { count: "exact", head: true })
            .eq("post_id", p.id),
        ]);
      return {
        ...p,
        profiles: profilesById.get(p.author_id) || null,
        likeCount: likeCount ?? 0,
        likedByMe: !!myLike?.data,
        commentCount: commentCount ?? 0,
      };
    }),
  );
  return withMeta;
}

export async function createPost({ body, attachmentPath }) {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { error } = await supabase
    .from("posts")
    .insert({
      author_id: user.id,
      body,
      attachment_path: attachmentPath || null,
    });
  if (error) throw error;
}

export async function deletePost(id) {
  const { error } = await supabase.from("posts").delete().eq("id", id);
  if (error) throw error;
}

export async function getComments(postId) {
  const { data, error } = await supabase
    .from("post_comments")
    .select("*")
    .eq("post_id", postId)
    .order("created_at", { ascending: true });
  if (error) throw error;

  const comments = data || [];
  const authorIds = [
    ...new Set(comments.map((comment) => comment.author_id).filter(Boolean)),
  ];
  const { data: publicProfiles, error: profileError } = await supabase.rpc(
    "get_public_profiles",
    { p_profile_ids: authorIds },
  );
  if (profileError) throw profileError;
  const profilesById = new Map(
    (publicProfiles || []).map((profile) => [profile.id, profile]),
  );

  return comments.map((comment) => ({
    ...comment,
    profiles: profilesById.get(comment.author_id) || null,
  }));
}

export async function createComment(postId, body) {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { error } = await supabase
    .from("post_comments")
    .insert({ post_id: postId, author_id: user.id, body });
  if (error) throw error;
}

export async function deleteComment(id) {
  const { error } = await supabase.from("post_comments").delete().eq("id", id);
  if (error) throw error;
}

export async function toggleLike(postId) {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: existing } = await supabase
    .from("post_likes")
    .select("id")
    .eq("post_id", postId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (existing) {
    const { error } = await supabase
      .from("post_likes")
      .delete()
      .eq("id", existing.id);
    if (error) throw error;
    return false;
  }
  const { error } = await supabase
    .from("post_likes")
    .insert({ post_id: postId, user_id: user.id });
  if (error) throw error;
  return true;
}
