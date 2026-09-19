// =========================================================
// TIDEF ITECH LMS — Shared utilities
// =========================================================

/** Show a toast notification. type: 'success' | 'error' | 'info' */
export function showToast(message, type = "info", duration = 4500) {
  let region = document.getElementById("toast-region");
  if (!region) {
    region = document.createElement("div");
    region.id = "toast-region";
    document.body.appendChild(region);
  }
  const toast = document.createElement("div");
  toast.className = `toast ${type}`;
  toast.setAttribute("role", "status");
  toast.textContent = message;
  region.appendChild(toast);
  setTimeout(() => toast.remove(), duration);
}

/** Toggle a button between idle and loading state. */
export function setButtonLoading(button, isLoading, loadingText = "Please wait…") {
  if (!button) return;
  if (isLoading) {
    button.dataset.originalText = button.dataset.originalText || button.innerHTML;
    button.disabled = true;
    button.innerHTML = `<span class="spinner" style="width:16px;height:16px;border-width:2px;"></span> ${loadingText}`;
  } else {
    button.disabled = false;
    if (button.dataset.originalText) button.innerHTML = button.dataset.originalText;
  }
}

/** Show a field-level error message under an input. */
export function setFieldError(inputEl, message) {
  clearFieldError(inputEl);
  if (!message) return;
  inputEl.classList.add("is-error");
  const err = document.createElement("div");
  err.className = "error-text";
  err.textContent = message;
  err.dataset.errorFor = inputEl.id;
  inputEl.insertAdjacentElement("afterend", err);
}

export function clearFieldError(inputEl) {
  inputEl.classList.remove("is-error");
  const next = inputEl.nextElementSibling;
  if (next && next.classList.contains("error-text")) next.remove();
}

export function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export function isValidPhone(phone) {
  return /^\+?[0-9\s-]{7,15}$/.test(phone);
}

/** Map raw Supabase Auth error messages to friendlier text. */
export function friendlyAuthError(error) {
  const msg = (error?.message || "").toLowerCase();
  if (msg.includes("already registered") || msg.includes("already exists")) {
    return "An account with this email already exists. Try logging in instead.";
  }
  if (msg.includes("invalid login credentials")) {
    return "Incorrect email or password.";
  }
  if (msg.includes("email not confirmed")) {
    return "Please verify your email first — check your inbox for the link.";
  }
  if (msg.includes("password") && msg.includes("6 characters")) {
    return "Your password should be at least 8 characters.";
  }
  if (msg.includes("rate limit") || msg.includes("too many")) {
    return "Too many attempts. Please wait a moment and try again.";
  }
  if (msg.includes("network")) {
    return "Network error. Check your connection and try again.";
  }
  if (msg.includes("user is disabled") || msg.includes("banned")) {
    return "This account has been suspended. Contact TIDEF ITECH support.";
  }
  return error?.message || "Something went wrong. Please try again.";
}

/** Format a Firestore Timestamp (or Date) into a readable string. */
export function formatDate(value, opts = {}) {
  if (!value) return "—";
  const date = typeof value.toDate === "function" ? value.toDate() : new Date(value);
  return date.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    ...opts,
  });
}

export function formatDateTime(value) {
  if (!value) return "—";
  const date = typeof value.toDate === "function" ? value.toDate() : new Date(value);
  return date.toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** Get initials from a full name, for avatar fallback. */
export function getInitials(fullName = "") {
  const parts = fullName.trim().split(/\s+/);
  if (parts.length === 0 || !parts[0]) return "?";
  return (parts[0][0] + (parts[1]?.[0] || "")).toUpperCase();
}

/** Simple query-string helper. */
export function getQueryParam(name) {
  return new URLSearchParams(window.location.search).get(name);
}

/** Escape user-provided text before inserting into innerHTML. */
export function escapeHtml(str = "") {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}
