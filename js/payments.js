// =========================================================
// TIDEF ITECH LMS — Payments (Phase 2)
// =========================================================
// All writes here go through Postgres functions (RPC), not direct
// table writes. That's what makes "confirm payment" atomic -- the
// confirmation record, the student's profile, the audit log, and the
// notification all update together or not at all. See
// supabase/migrations/0002_payments.sql for the actual logic.
// =========================================================

import { supabase } from "./supabase.js";

/** Student: submit "I Have Completed Payment". */
export async function submitPaymentConfirmation({ courseId, paymentReference, paymentDate, paymentMethod, studentNote }) {
  const { data, error } = await supabase.rpc("submit_payment_confirmation", {
    p_course_id: courseId || null,
    p_payment_reference: paymentReference || null,
    p_payment_date: paymentDate || null,
    p_payment_method: paymentMethod || null,
    p_student_note: studentNote || null,
  });
  if (error) throw error;
  return data;
}

/** Student: fetch their own most recent payment confirmation, if any. */
export async function getMyLatestPaymentConfirmation() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from("payment_confirmations")
    .select("*, courses(name)")
    .eq("student_id", user.id)
    .order("submitted_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) return null;
  return data;
}

/** Admin: list payment confirmations awaiting review, oldest first. */
export async function getPendingPaymentConfirmations() {
  const { data, error } = await supabase
    .from("payment_confirmations")
    .select("*, profiles!student_id(full_name, email, phone, student_id), courses(name)")
    .eq("payment_status", "pending_verification")
    .order("submitted_at", { ascending: true });

  if (error) throw error;
  return data || [];
}

/** Admin: list recently reviewed confirmations (confirmed or rejected). */
export async function getRecentReviewedConfirmations(limit = 10) {
  const { data, error } = await supabase
    .from("payment_confirmations")
    .select("*, profiles!student_id(full_name, student_id), courses(name)")
    .in("payment_status", ["confirmed", "rejected"])
    .order("verified_at", { ascending: false })
    .limit(limit);

  if (error) throw error;
  return data || [];
}

/** Admin: confirm a payment. */
export async function confirmPayment(confirmationId, adminNote) {
  const { error } = await supabase.rpc("admin_confirm_payment", {
    p_confirmation_id: confirmationId,
    p_admin_note: adminNote || null,
  });
  if (error) throw error;
}

/** Admin: reject a payment. adminNote (a reason) is required. */
export async function rejectPayment(confirmationId, adminNote) {
  const { error } = await supabase.rpc("admin_reject_payment", {
    p_confirmation_id: confirmationId,
    p_admin_note: adminNote,
  });
  if (error) throw error;
}
