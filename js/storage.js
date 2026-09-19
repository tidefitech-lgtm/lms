// =========================================================
// TIDEF ITECH LMS — Storage helpers
// =========================================================
// All LMS buckets are private, so we store the storage PATH in the
// database (never a public URL) and mint a short-lived signed URL only
// when something actually needs to be downloaded or previewed.
// =========================================================

import { supabase } from "./supabase.js";

/** Upload a file, returning its storage path. Path is scoped under the given prefix (usually the uploader's own uid or a course id, per each bucket's storage policy). */
export async function uploadFile(bucket, prefix, file) {
  const safeName = file.name.replace(/[^\w.\-]+/g, "_");
  const path = `${prefix}/${Date.now()}_${safeName}`;
  const { error } = await supabase.storage.from(bucket).upload(path, file, { upsert: false });
  if (error) throw error;
  return path;
}

/** Generate a temporary (1 hour) signed URL for a stored file. */
export async function getSignedUrl(bucket, path, expiresIn = 3600) {
  if (!path) return null;
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, expiresIn);
  if (error) return null;
  return data.signedUrl;
}

/** The original filename portion of a storage path (strips the timestamp prefix we add on upload). */
export function fileNameFromPath(path = "") {
  const parts = path.split("/");
  const last = parts[parts.length - 1] || path;
  return last.replace(/^\d+_/, "");
}
