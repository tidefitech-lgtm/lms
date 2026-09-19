// =========================================================
// TIDEF ITECH LMS — Certificates (Phase 8)
// =========================================================
// Issuing a certificate goes through issue_certificate() (RPC), which
// checks the caller is an admin, generates a race-safe sequential
// number, and notifies the student, all as one transaction. Public
// verification goes through verify_certificate() (RPC, callable even
// signed out) and never exposes the certificate file itself.
// =========================================================

import { supabase } from "./supabase.js";

/** Completed enrollments across every course, for the admin's "eligible for certificate" shortlist. */
export async function getEligibleCompletions() {
  const [{ data: completions, error: cErr }, { data: certs, error: kErr }] = await Promise.all([
    supabase
      .from("enrollments")
      .select("student_id, course_id, profiles!student_id(full_name, student_id), courses(name)")
      .eq("status", "completed"),
    supabase.from("certificates").select("student_id, course_id"),
  ]);
  if (cErr) throw cErr;
  if (kErr) throw kErr;

  const issuedKeys = new Set((certs || []).map((c) => `${c.student_id}:${c.course_id}`));
  return (completions || []).filter((c) => !issuedKeys.has(`${c.student_id}:${c.course_id}`));
}

export async function getAllCertificates() {
  const { data, error } = await supabase
    .from("certificates")
    .select("*, profiles!student_id(full_name, student_id), courses(name)")
    .order("issued_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function issueCertificate({ studentId, courseId, filePath, notes }) {
  const { data, error } = await supabase.rpc("issue_certificate", {
    p_student_id: studentId,
    p_course_id: courseId,
    p_file_path: filePath,
    p_notes: notes || null,
  });
  if (error) throw error;
  return data;
}

export async function getMyCertificates() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("certificates")
    .select("*, courses(name)")
    .eq("student_id", user.id)
    .order("issued_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

/** Public verification — works even for a signed-out visitor. */
export async function verifyCertificate(certificateNumber) {
  const { data, error } = await supabase.rpc("verify_certificate", { p_certificate_number: certificateNumber.trim() });
  if (error) throw error;
  return data && data.length > 0 ? data[0] : null;
}
