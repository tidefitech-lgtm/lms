// =========================================================
// TIDEF ITECH LMS — Shared layout components (sidebar / topbar)
// =========================================================
import { logout } from "./auth.js";
import { getInitials } from "./utils.js";
import { ROLES } from "./config.js";

const NAV_BY_ROLE = {
  [ROLES.STUDENT]: [
    { section: "Learning" },
    { href: "/student/dashboard.html", icon: "🏠", label: "Dashboard" },
    { href: "/student/courses.html", icon: "📚", label: "My Courses" },
    { href: "/student/assignments.html", icon: "📝", label: "Assignments" },
    { href: "/student/projects.html", icon: "🚀", label: "Projects" },
    { href: "/student/quizzes.html", icon: "❓", label: "Quizzes" },
    { href: "/student/exams.html", icon: "🎓", label: "Exams" },
    { section: "Community" },
    { href: "/student/community.html", icon: "💬", label: "Community" },
    { href: "/student/questions.html", icon: "❔", label: "Q&A" },
    { href: "/student/notifications.html", icon: "🔔", label: "Notifications" },
    { href: "/student/bookmarks.html", icon: "🔖", label: "Bookmarks" },
    { section: "Account" },
    { href: "/student/payment.html", icon: "💳", label: "Payment" },
    { href: "/student/id-card.html", icon: "🪪", label: "Student ID Card" },
    { href: "/student/certificates.html", icon: "📜", label: "Certificates" },
    { href: "/student/profile.html", icon: "⚙️", label: "Profile" },
  ],
  [ROLES.TEACHER]: [
    { section: "Teaching" },
    { href: "/teacher/dashboard.html", icon: "🏠", label: "Dashboard" },
    { href: "/teacher/courses.html", icon: "📚", label: "My Courses" },
    { href: "/teacher/assignments.html", icon: "📝", label: "Assignments" },
    { href: "/teacher/projects.html", icon: "🚀", label: "Projects" },
    { href: "/teacher/quizzes.html", icon: "❓", label: "Quizzes & Exams" },
    { href: "/teacher/students.html", icon: "🧑‍🎓", label: "Students" },
    { href: "/teacher/questions.html", icon: "💬", label: "Q&A" },
  ],
  [ROLES.ADMIN]: [
    { section: "Overview" },
    { href: "/admin/dashboard.html", icon: "🏠", label: "Dashboard" },
    { href: "/admin/reports.html", icon: "📊", label: "Reports" },
    { section: "Students" },
    { href: "/admin/students.html", icon: "🧑‍🎓", label: "Students" },
    { href: "/admin/payment-verification.html", icon: "💳", label: "Payment Verification" },
    { section: "Academics" },
    { href: "/admin/courses.html", icon: "📚", label: "Courses" },
    { href: "/admin/assignments.html", icon: "📝", label: "Assignments" },
    { href: "/admin/projects.html", icon: "🚀", label: "Projects" },
    { href: "/admin/quizzes.html", icon: "❓", label: "Quizzes & Exams" },
    { href: "/admin/teachers.html", icon: "🧑‍🏫", label: "Teachers" },
    { href: "/admin/certificates.html", icon: "📜", label: "Certificates" },
    { section: "System" },
    { href: "/admin/community.html", icon: "💬", label: "Community" },
    { href: "/admin/questions.html", icon: "❔", label: "Q&A" },
    { href: "/admin/announcements.html", icon: "📢", label: "Announcements" },
    { href: "/admin/users.html", icon: "👥", label: "Users & Roles" },
    { href: "/admin/activity-logs.html", icon: "🗂️", label: "Activity Logs" },
    { href: "/admin/settings.html", icon: "⚙️", label: "Settings" },
  ],
};
NAV_BY_ROLE[ROLES.SUPER_ADMIN] = NAV_BY_ROLE[ROLES.ADMIN];

/** Render the full app shell chrome (sidebar + topbar) into the page. */
export function renderAppShell({ role, profile, pageTitle, activeHref }) {
  const items = NAV_BY_ROLE[role] || [];
  const navHtml = items
    .map((item) => {
      if (item.section) {
        return `<div class="nav-section-label">${item.section}</div>`;
      }
      const isActive = activeHref && item.href.endsWith(activeHref);
      return `<a class="nav-link${isActive ? " active" : ""}" href="${item.href}">
        <span aria-hidden="true">${item.icon}</span><span>${item.label}</span>
      </a>`;
    })
    .join("");

  const roleLabel = role.replace("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());
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
            ↩ Log out
          </button>
        </div>
      </aside>
      <div class="app-main">
        <header class="app-topbar">
          <div class="flex items-center gap-3">
            <button class="sidebar-toggle" id="sidebar-toggle" aria-label="Toggle menu">☰</button>
            <div class="page-title">${pageTitle}</div>
          </div>
          <div class="topbar-actions">
            <span class="badge badge-neutral">${roleLabel}</span>
            <div class="user-chip" title="${profile?.full_name || ""}">
              <div class="avatar">${
                profile?.profile_photo_url
                  ? `<img src="${profile.profile_photo_url}" alt="" />`
                  : initials
              }</div>
            </div>
          </div>
        </header>
        <main class="app-content" id="app-content"></main>
      </div>
    </div>
  `
  );

  document.getElementById("logout-btn").addEventListener("click", async () => {
    await logout();
    window.location.href = "/login.html";
  });

  document.getElementById("sidebar-toggle")?.addEventListener("click", () => {
    document.getElementById("app-sidebar").classList.toggle("open");
  });

  return document.getElementById("app-content");
}
