// =========================================================
// TIDEF ITECH LMS — Shared layout components (sidebar / topbar)
// =========================================================
import { logout } from "./auth.js";
import { getInitials } from "./utils.js";
import { ROLES } from "./config.js";
import { toDriveImageUrl } from "./google-drive.js";
const NAV_BY_ROLE = {
  [ROLES.STUDENT]: [
    { section: "Learning" },
    { href: "../student/dashboard.html", icon: "home", label: "Dashboard" },
    { href: "../student/courses.html", icon: "book-open", label: "My Courses" },
    {
      href: "../student/assignments.html",
      icon: "clipboard",
      label: "Assignments",
    },
    { href: "../student/projects.html", icon: "rocket", label: "Projects" },
    {
      href: "../student/quizzes.html",
      icon: "question-mark-circle",
      label: "Quizzes",
    },
    { href: "../student/exams.html", icon: "academic-cap", label: "Exams" },
    { href: "../student/live-classes.html", icon: "video-camera", label: "Live Classes" },
    { section: "Community" },
    {
      href: "../student/community.html",
      icon: "chat-bubble-left-right",
      label: "Community",
    },
    {
      href: "../student/questions.html",
      icon: "question-mark-circle",
      label: "Q&A",
    },
    {
      href: "../student/notifications.html",
      icon: "bell",
      label: "Notifications",
    },
    { href: "../student/bookmarks.html", icon: "bookmark", label: "Bookmarks" },
    { section: "Account" },
    { href: "../student/payment.html", icon: "credit-card", label: "Payment" },
    {
      href: "../student/id-card.html",
      icon: "identification",
      label: "Student ID Card",
    },
    {
      href: "../student/profile.html",
      icon: "identification",
      label: "My Profile",
    },
    {
      href: "../student/certificates.html",
      icon: "certificate",
      label: "Certificates",
    },
  ],
  [ROLES.TEACHER]: [
    { section: "Teaching" },
    { href: "../teacher/dashboard.html", icon: "home", label: "Dashboard" },
    { href: "../teacher/courses.html", icon: "book-open", label: "My Courses" },
    {
      href: "../teacher/assignments.html",
      icon: "clipboard",
      label: "Assignments",
    },
    { href: "../teacher/projects.html", icon: "rocket", label: "Projects" },
    { href: "../teacher/live-classes.html", icon: "video-camera", label: "Live Classes" },
    {
      href: "../teacher/quizzes.html",
      icon: "question-mark-circle",
      label: "Quizzes & Exams",
    },
    {
      href: "../teacher/questions.html",
      icon: "chat-bubble-left-right",
      label: "Q&A",
    },
  ],
  [ROLES.ADMIN]: [
    { section: "Overview" },
    { href: "../admin/dashboard.html", icon: "home", label: "Dashboard" },
    { href: "../admin/reports.html", icon: "chart-bar", label: "Reports" },
    { section: "Students" },
    { href: "../admin/students.html", icon: "users", label: "Students" },
    {
      href: "../admin/student-progress.html",
      icon: "chart-bar",
      label: "Student Progress",
      superAdminOnly: true,
    },
    {
      href: "../admin/payment-verification.html",
      icon: "credit-card",
      label: "Payment Verification",
    },
    { section: "Academics" },
    { href: "../admin/courses.html", icon: "book-open", label: "Courses" },
    {
      href: "../admin/assignments.html",
      icon: "clipboard",
      label: "Assignments",
    },
    { href: "../admin/projects.html", icon: "rocket", label: "Projects" },
    { href: "../admin/live-classes.html", icon: "video-camera", label: "Live Classes" },
    {
      href: "../admin/quizzes.html",
      icon: "question-mark-circle",
      label: "Quizzes & Exams",
    },
    { href: "../admin/teachers.html", icon: "academic-cap", label: "Teachers" },
    {
      href: "../admin/certificates.html",
      icon: "certificate",
      label: "Certificates",
    },
    { section: "System" },
    {
      href: "../admin/community.html",
      icon: "chat-bubble-left-right",
      label: "Community",
    },
    {
      href: "../admin/questions.html",
      icon: "question-mark-circle",
      label: "Q&A",
    },
    {
      href: "../admin/notifications.html",
      icon: "bell",
      label: "Notifications",
    },
    { href: "../admin/users.html", icon: "users", label: "Users & Roles" },
    {
      href: "../admin/activity-logs.html",
      icon: "clipboard-document-list",
      label: "Activity Logs",
    },
    { href: "../admin/settings.html", icon: "cog", label: "Settings" },
  ],
};
NAV_BY_ROLE[ROLES.SUPER_ADMIN] = NAV_BY_ROLE[ROLES.ADMIN];

const ICON_PATHS = {
  "academic-cap":
    '<path d="M12 14.25 3.75 9 12 3.75 20.25 9 12 14.25Z"/><path d="M6.75 11.25v4.5c2.88 2.25 7.62 2.25 10.5 0v-4.5M20.25 9v6"/>',
  bell: '<path d="M14.25 18.75a2.25 2.25 0 0 1-4.5 0M5.25 16.5h13.5l-1.5-2.25V9a5.25 5.25 0 0 0-10.5 0v5.25L5.25 16.5Z"/>',
  "book-open":
    '<path d="M4.5 5.25A2.25 2.25 0 0 1 6.75 3h3.75v15H6.75a2.25 2.25 0 0 0-2.25 2.25V5.25ZM19.5 5.25A2.25 2.25 0 0 0 17.25 3H13.5v15h3.75a2.25 2.25 0 0 1 2.25 2.25V5.25Z"/>',
  bookmark:
    '<path d="M6.75 4.5A1.5 1.5 0 0 1 8.25 3h7.5a1.5 1.5 0 0 1 1.5 1.5v16.125L12 17.25l-5.25 3.375V4.5Z"/>',
  "chat-bubble-left-right":
    '<path d="M7.5 15.75h-.75a3 3 0 0 1-3-3v-5.25a3 3 0 0 1 3-3h10.5a3 3 0 0 1 3 3v5.25a3 3 0 0 1-3 3h-3.75l-3 3v-3H7.5Z"/><path d="M7.5 9h.008M10.5 9h.008M13.5 9h.008"/>',
  certificate:
    '<path d="M9 3.75h6l2.25 2.25v12L15 20.25H9l-2.25-2.25V6L9 3.75Z"/><path d="m10 12 1.5 1.5L14.25 10M9 7.5h6"/>',
  "chart-bar":
    '<path d="M4.5 19.5V12h3v7.5h-3ZM10.5 19.5V6h3v13.5h-3ZM16.5 19.5V3h3v16.5h-3Z"/>',
  "clipboard-document-list":
    '<path d="M9 5.25h6M9 9h6M9 12.75h3M6.75 3.75h10.5A1.5 1.5 0 0 1 18.75 5.25v13.5a1.5 1.5 0 0 1-1.5 1.5H6.75a1.5 1.5 0 0 1-1.5-1.5V5.25a1.5 1.5 0 0 1 1.5-1.5Z"/>',
  clipboard:
    '<path d="M9 4.5h6M9 4.5A1.5 1.5 0 0 0 10.5 6h3A1.5 1.5 0 0 0 15 4.5M6.75 3.75h10.5a1.5 1.5 0 0 1 1.5 1.5v14.25H5.25V5.25a1.5 1.5 0 0 1 1.5-1.5Z"/>',
  cog: '<path d="m12 8.25.75 1.5 1.65.24-1.2 1.17.28 1.65L12 12.03l-1.48.78.28-1.65-1.2-1.17 1.65-.24.75-1.5Z"/><path d="M12 3.75a8.25 8.25 0 1 0 0 16.5 8.25 8.25 0 0 0 0-16.5Z"/>',
  "credit-card":
    '<path d="M3.75 6.75h16.5v10.5H3.75V6.75Z"/><path d="M3.75 10.5h16.5M7.5 15h3"/>',
  home: '<path d="m3.75 10.5 8.25-6.75 8.25 6.75v8.25a1.5 1.5 0 0 1-1.5 1.5H5.25a1.5 1.5 0 0 1-1.5-1.5V10.5Z"/><path d="M9.75 20.25v-6h4.5v6"/>',
  identification:
    '<path d="M5.25 4.5h13.5a1.5 1.5 0 0 1 1.5 1.5v12a1.5 1.5 0 0 1-1.5 1.5H5.25a1.5 1.5 0 0 1-1.5-1.5V6a1.5 1.5 0 0 1 1.5-1.5Z"/><path d="M8.25 9.75a2.25 2.25 0 1 0 4.5 0 2.25 2.25 0 0 0-4.5 0ZM7.5 16.5a4.5 4.5 0 0 1 6 0M15.75 9h1.5M15.75 12h1.5"/>',
  "question-mark-circle":
    '<circle cx="12" cy="12" r="8.25"/><path d="M9.75 9.25a2.25 2.25 0 1 1 3.75 1.67c-.83.72-1.5 1.08-1.5 2.33M12 16.5h.008"/>',
  rocket:
    '<path d="M14.25 5.25c2.25-1.5 4.5-1.5 4.5-1.5s0 2.25-1.5 4.5l-6.75 6.75-3.75-3.75 7.5-6Z"/><path d="m7.5 11.25-3 1.5 3.75 3.75 1.5-3M12 16.5l-.75 3.75-3-3M15.75 8.25h.008"/>',
  users:
    '<path d="M15.75 19.5v-1.125A3.375 3.375 0 0 0 12.375 15h-4.5A3.375 3.375 0 0 0 4.5 18.375V19.5M10.125 11.25a3.375 3.375 0 1 0 0-6.75 3.375 3.375 0 0 0 0 6.75ZM15.75 5.25a3.375 3.375 0 0 1 0 6.75M18.75 19.5v-1.125a3.375 3.375 0 0 0-2.25-3.18"/>',
  "video-camera":
    '<rect x="3.75" y="6.75" width="11.25" height="10.5" rx="1.5"/><path d="m15 10.125 5.25-3v9.75l-5.25-3"/>',
  "arrow-left-on-rectangle":
    '<path d="M13.5 8.25 17.25 12l-3.75 3.75M17.25 12H3.75M15 4.5h3.75A1.5 1.5 0 0 1 20.25 6v12a1.5 1.5 0 0 1-1.5 1.5H15"/>',
  "bars-3": '<path d="M4.5 6.75h15M4.5 12h15M4.5 17.25h15"/>',
};

function renderIcon(name, className = "nav-icon") {
  return `<svg class="${className}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON_PATHS[name] || ICON_PATHS.home}</svg>`;
}

/** Render the full app shell chrome (sidebar + topbar) into the page. */
export function renderAppShell({ role, profile, pageTitle, activeHref }) {
  const items = NAV_BY_ROLE[role] || [];
  const navHtml = items
    .filter((item) => !item.superAdminOnly || role === ROLES.SUPER_ADMIN)
    .map((item) => {
      if (item.section) {
        return `<div class="nav-section-label">${item.section}</div>`;
      }
      const isActive = activeHref && item.href.endsWith(activeHref);
      return `<a class="nav-link${isActive ? " active" : ""}" href="${item.href}">
        ${renderIcon(item.icon)}<span>${item.label}</span>
      </a>`;
    })
    .join("");

  const roleLabel = role
    .replace("_", " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
  const initials = getInitials(profile?.full_name);

  document.body.insertAdjacentHTML(
    "afterbegin",
    `
    <div class="app-shell">
      <aside class="app-sidebar" id="app-sidebar">
        <div class="brand">
          <img src="https://www.tidefitech.com/img/Capture-removebg-preview.png" alt="TIDEF ITECH" />
          <span>TIDEF ITECH LMS</span>
        </div>
        <nav>${navHtml}</nav>
        <div class="sidebar-footer">
          <button class="btn btn-ghost btn-block" id="logout-btn" style="color:#fff;justify-content:flex-start;">
            ${renderIcon("arrow-left-on-rectangle", "action-icon")} Log out
          </button>
        </div>
      </aside>
      <div class="app-main">
        <header class="app-topbar">
          <div class="flex items-center gap-3">
            <button class="sidebar-toggle" id="sidebar-toggle" aria-label="Toggle menu">${renderIcon("bars-3", "action-icon")}</button>
            <div class="page-title">${pageTitle}</div>
          </div>
          <div class="topbar-actions">
            <span class="badge badge-neutral">${roleLabel}</span>
            <div class="user-chip" title="${profile?.full_name || ""}">
              <div class="avatar">${
                profile?.profile_photo_url
                  ? `<img src="${toDriveImageUrl(profile.profile_photo_url)}" alt="" />`
                  : initials
              }</div>
            </div>
          </div>
        </header>
        <main class="app-content" id="app-content"></main>
      </div>
    </div>
  `,
  );

  document.getElementById("logout-btn").addEventListener("click", async () => {
    await logout();
    window.location.href = "../login.html";
  });

  document.getElementById("sidebar-toggle")?.addEventListener("click", () => {
    document.getElementById("app-sidebar").classList.toggle("open");
  });

  return document.getElementById("app-content");
}
