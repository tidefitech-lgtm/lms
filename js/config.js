// =========================================================
// TIDEF ITECH LMS — App-wide constants
// (Backend: Supabase — Postgres + Auth + Storage)
// =========================================================

export const APP_NAME = "TIDEF ITECH LMS";
export const STUDENT_ID_PREFIX = "TIDEF";

export const ROLES = Object.freeze({
  SUPER_ADMIN: "super_admin",
  ADMIN: "admin",
  TEACHER: "teacher",
  STUDENT: "student",
});

export const ACCOUNT_STATUS = Object.freeze({
  PENDING: "pending", // just registered, not yet approved
  APPROVED: "approved", // admin approved, has course access
  SUSPENDED: "suspended",
  REJECTED: "rejected",
});

export const PAYMENT_STATUS = Object.freeze({
  NOT_SUBMITTED: "not_submitted",
  PENDING_VERIFICATION: "pending_verification",
  CONFIRMED: "confirmed",
  REJECTED: "rejected",
});

export const ENROLLMENT_STATUS = Object.freeze({
  INACTIVE: "inactive",
  ACTIVE: "active",
  COMPLETED: "completed",
});

export function appPath(path) {
  const pageDirectory = window.location.pathname.slice(
    0,
    window.location.pathname.lastIndexOf("/") + 1,
  );
  const isNestedPage = /\/(admin|student|teacher)\/$/.test(pageDirectory);
  return `${isNestedPage ? "../" : "./"}${path}`;
}

// Where a signed-in user of each role should land after login
export const ROLE_HOME_PAGE = Object.freeze({
  [ROLES.SUPER_ADMIN]: appPath("admin/dashboard.html"),
  [ROLES.ADMIN]: appPath("admin/dashboard.html"),
  [ROLES.TEACHER]: appPath("teacher/dashboard.html"),
  [ROLES.STUDENT]: appPath("student/dashboard.html"),
});

// Public marketing site (outside the LMS) — used for the "Back to website" link
export const MARKETING_SITE_URL = "https://www.tidefitech.com";
