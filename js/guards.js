// =========================================================
// TIDEF ITECH LMS — Page Guards
// =========================================================
// Client-side guards give a fast, friendly redirect. They are NOT the
// security boundary — supabase/migrations/0001_init.sql (RLS policies +
// triggers) is the real enforcement layer, since a user can always
// disable JS or call the API directly.
// =========================================================

import { onAuthReady, logout } from "./auth.js";
import { ROLES, ROLE_HOME_PAGE } from "./config.js";

const LOGIN_PAGE = "/login.html";

function showGuardLoading() {
  const el = document.createElement("div");
  el.id = "guard-loading";
  el.className = "state-block";
  el.style.cssText = "position:fixed;inset:0;background:#f7f8fb;display:flex;align-items:center;justify-content:center;flex-direction:column;z-index:9999;";
  el.innerHTML = `<div class="spinner"></div><p style="margin-top:16px;">Loading your dashboard…</p>`;
  document.body.appendChild(el);
}

function hideGuardLoading() {
  document.getElementById("guard-loading")?.remove();
}

/**
 * Require a signed-in, email-confirmed user whose account is approved
 * (unless allowPending is set), and whose role is in allowedRoles.
 * Resolves with { user, profile } once checks pass; otherwise redirects.
 */
export function requireAuth({ allowedRoles = null, allowPending = false } = {}) {
  showGuardLoading();
  return new Promise((resolve) => {
    const unsubscribe = onAuthReady(({ user, profile }) => {
      unsubscribe();

      if (!user || !profile) {
        window.location.href = LOGIN_PAGE;
        return;
      }

      if (!user.email_confirmed_at) {
        window.location.href = `/verify-email.html?email=${encodeURIComponent(user.email)}`;
        return;
      }

      if (allowedRoles && !allowedRoles.includes(profile.role)) {
        window.location.href = ROLE_HOME_PAGE[profile.role] || LOGIN_PAGE;
        return;
      }

      if (
        profile.role === ROLES.STUDENT &&
        !allowPending &&
        profile.account_status !== "approved"
      ) {
        window.location.href = "/student/pending-approval.html";
        return;
      }

      if (profile.account_status === "suspended") {
        logout().then(() => (window.location.href = LOGIN_PAGE));
        return;
      }

      hideGuardLoading();
      resolve({ user, profile });
    });
  });
}

/** Redirect an already-signed-in user away from login/register pages. */
export function redirectIfAuthenticated() {
  const unsubscribe = onAuthReady(({ user, profile }) => {
    unsubscribe();
    if (user && profile) {
      window.location.href = ROLE_HOME_PAGE[profile.role] || "/student/dashboard.html";
    }
  });
}
