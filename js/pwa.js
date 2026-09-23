let deferredInstallPrompt = null;

const COOKIE_NOTICE_KEY = "tidef-cookie-notice-dismissed";

function showCookieNotice() {
  if (localStorage.getItem(COOKIE_NOTICE_KEY)) return;

  const notice = document.createElement("aside");
  notice.className = "cookie-notice";
  notice.setAttribute("role", "dialog");
  notice.setAttribute("aria-label", "Essential storage notice");
  notice.innerHTML = `
    <div>
      <strong>Essential storage notice</strong>
      <p>This website uses essential browser storage to keep you signed in, protect your account, and remember app settings. We do not use advertising or analytics cookies.</p>
    </div>
    <button class="btn btn-primary btn-sm" type="button" data-cookie-dismiss>Got it</button>
  `;
  document.body.appendChild(notice);

  notice.querySelector("[data-cookie-dismiss]").addEventListener("click", () => {
    localStorage.setItem(COOKIE_NOTICE_KEY, "1");
    notice.remove();
  });
}

if (document.body) showCookieNotice();

const appRoot = new URL("../", import.meta.url);
if (!document.querySelector('link[rel="manifest"]')) {
  const manifestLink = document.createElement("link");
  manifestLink.rel = "manifest";
  manifestLink.href = new URL("manifest.webmanifest", appRoot).href;
  document.head.appendChild(manifestLink);
}

function createInstallPrompt() {
  const prompt = document.createElement("aside");
  prompt.className = "pwa-install-prompt";
  prompt.setAttribute("role", "dialog");
  prompt.setAttribute("aria-label", "Install TIDEF ITECH LMS");
  prompt.innerHTML = `
    <div class="pwa-install-copy">
      <strong>Install TIDEF ITECH LMS</strong>
      <span>Keep your learning space one tap away.</span>
    </div>
    <div class="pwa-install-actions">
      <button class="btn btn-primary btn-sm" type="button" data-pwa-install>Install</button>
      <button class="pwa-install-dismiss" type="button" data-pwa-dismiss aria-label="Dismiss install prompt">&times;</button>
    </div>
  `;
  document.body.appendChild(prompt);

  prompt
    .querySelector("[data-pwa-install]")
    .addEventListener("click", async () => {
      if (!deferredInstallPrompt) return;
      deferredInstallPrompt.prompt();
      await deferredInstallPrompt.userChoice;
      deferredInstallPrompt = null;
      prompt.remove();
    });

  prompt.querySelector("[data-pwa-dismiss]").addEventListener("click", () => {
    sessionStorage.setItem("tidef-pwa-install-dismissed", "1");
    prompt.remove();
  });
}

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register(new URL("sw.js", appRoot), { scope: appRoot.pathname })
      .catch(() => {});
  });
}

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  if (!sessionStorage.getItem("tidef-pwa-install-dismissed")) {
    createInstallPrompt();
  }
});

window.addEventListener("appinstalled", () => {
  deferredInstallPrompt = null;
  document.querySelector(".pwa-install-prompt")?.remove();
});
