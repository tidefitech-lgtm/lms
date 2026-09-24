// =========================================================
// TIDEF ITECH LMS — Authentication (Supabase)
// =========================================================
// Registration only ever sends safe, self-descriptive fields as signup
// metadata (full_name, phone, dob, gender, address, interested_course_id,
// passport_url).
// The public.profiles row itself is created server-side by a Postgres
// trigger (see supabase/migrations/0001_init.sql) that ignores anything
// else the client might try to send — role/account_status/payment_status/
// student_id always start at their column defaults, no matter what.
// =========================================================

import { supabase } from "./supabase.js";

/**
 * Register a new student account.
 * @param {Object} data - fullName, email, phone, password, dob, gender, address, courseId, passportUrl
 */
export async function registerStudent(data) {
  const {
    email,
    password,
    fullName,
    phone,
    dob,
    gender,
    address,
    courseId,
    passportUrl,
  } = data;

  const options = {
    data: {
      full_name: fullName,
      email,
      phone: phone || null,
      dob: dob || null,
      gender: gender || null,
      address: address || null,
      interested_course_id: courseId || null,
      passport_url: passportUrl || null,
    },
  };
  const { data: signUpData, error } = await supabase.auth.signUp({
    email,
    password,
    options,
  });

  if (error) throw error;
  return signUpData.user;
}

/** Log in with email + password. Throws if the email isn't confirmed yet. */
export async function login(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw error;
  return data.user;
}

/** Log out the current user. */
export async function logout() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

/** Resend the signup email OTP. */
export async function resendSignupOtp(email) {
  const { error } = await supabase.auth.resend({ type: "signup", email });
  if (error) throw error;
}

/** Verify a signup email OTP. */
export async function verifySignupOtp(email, token) {
  const { data, error } = await supabase.auth.verifyOtp({
    email,
    token,
    type: "signup",
  });
  if (error) throw error;
  return data.user;
}

/** Check whether an email is already registered before signup. */
export async function emailExists(email) {
  const { data, error } = await supabase.rpc("email_exists", {
    p_email: email,
  });
  if (error) throw error;
  return data === true;
}

/** Send a password-reset email; landing page is reset-password.html. */
export async function requestPasswordReset(email) {
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: new URL("../reset-password.html", import.meta.url).href,
  });
  if (error) throw error;
}

/** Set a new password (used on reset-password.html, after the reset link signs the user in). */
export async function setNewPassword(newPassword) {
  const { error } = await supabase.auth.updateUser({ password: newPassword });
  if (error) throw error;
}

/** Fetch the profiles row for a given user id. */
export async function getUserProfile(uid) {
  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", uid)
    .single();
  if (error) return null;
  return data;
}

/**
 * Ask the Supabase server directly whether we currently have a
 * signed-in, email-confirmed user. Unlike getSession() (which reads the
 * local token), getUser() always round-trips to the server, so it's the
 * right call after an email OTP has created a session.
 */
export async function getFreshUser() {
  const { data, error } = await supabase.auth.getUser();
  if (error) return null;
  return data.user;
}

/**
 * Subscribe to auth state. Callback receives { user, profile } or
 * { user: null, profile: null } when signed out. Fires once immediately
 * with the current state, then again on every change.
 */
export function onAuthReady(callback) {
  async function emit(user) {
    if (!user) {
      callback({ user: null, profile: null });
      return;
    }
    const profile = await getUserProfile(user.id);
    callback({ user, profile });
  }

  supabase.auth
    .getSession()
    .then(({ data: { session } }) => emit(session?.user || null));

  const { data: listener } = supabase.auth.onAuthStateChange(
    (_event, session) => {
      emit(session?.user || null);
    },
  );

  return () => listener.subscription.unsubscribe();
}
