let deferredInstallPrompt = null;

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

  prompt.querySelector("[data-pwa-install]").addEventListener("click", async () => {
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
    navigator.serviceWorker.register("./sw.js").catch(() => {});
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
