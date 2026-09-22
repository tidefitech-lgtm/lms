const supportNumber = "2349027772815";
const message = encodeURIComponent(
  "Hello TIDEF ITECH, I need more information about the LMS.",
);

if (!document.querySelector(".whatsapp-float")) {
  const link = document.createElement("a");
  link.className = "whatsapp-float";
  link.href = `https://wa.me/${supportNumber}?text=${message}`;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  link.setAttribute("aria-label", "Contact TIDEF ITECH on WhatsApp");
  link.title = "Contact TIDEF ITECH on WhatsApp";
  link.innerHTML = `
    <span class="whatsapp-float-icon" aria-hidden="true">
      <svg viewBox="0 0 24 24" role="img">
        <path d="M20.5 3.5A11.8 11.8 0 0 0 12.1 0C5.6 0 .3 5.3.3 11.8c0 2.1.6 4.2 1.7 6L.2 24l6.4-1.7a11.8 11.8 0 0 0 5.5 1.4h.1c6.5 0 11.8-5.3 11.8-11.8 0-3.2-1.3-6.2-3.5-8.4Zm-8.4 18.2h-.1c-1.7 0-3.4-.5-4.8-1.3l-.3-.2-3.8 1 1-3.7-.2-.4a9.8 9.8 0 0 1-1.5-5.2C2.4 6.5 6.8 2 12.2 2c2.6 0 5.1 1 6.9 2.9a9.7 9.7 0 0 1 2.9 6.9c0 5.4-4.5 9.9-9.9 9.9Zm5.4-7.4c-.3-.2-1.8-.9-2.1-1-.3-.1-.5-.2-.7.2-.2.3-.8 1-.9 1.2-.2.2-.3.2-.6.1-1.6-.8-2.6-1.4-3.6-3.2-.3-.5.3-.5.8-1.7.1-.2.1-.4 0-.6-.1-.2-.7-1.7-.9-2.3-.2-.6-.5-.5-.7-.5h-.6c-.2 0-.6.1-.9.4-.3.3-1.2 1.2-1.2 2.9s1.2 3.4 1.4 3.6c.2.2 2.4 3.7 5.8 5.1.8.3 1.5.5 2 .6.8.2 1.6.2 2.2.1.7-.1 1.8-.7 2-1.4.3-.7.3-1.3.2-1.4-.1-.2-.3-.3-.6-.4Z" />
      </svg>
    </span>
    <span class="whatsapp-float-label">Chat with TIDEF ITECH</span>
  `;
  document.body.appendChild(link);
}
