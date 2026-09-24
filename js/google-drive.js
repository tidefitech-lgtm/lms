import { GOOGLE_DRIVE_UPLOAD_URL } from "./config.js";

const MAX_PASSPORT_BYTES = 5 * 1024 * 1024;
const ALLOWED_PASSPORT_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);

/** Upload a passport image through the configured Google Apps Script web app. */
export async function uploadPassport(file, email) {
  if (!GOOGLE_DRIVE_UPLOAD_URL) {
    throw new Error("Google Drive upload is not configured yet.");
  }
  if (!ALLOWED_PASSPORT_TYPES.has(file.type)) {
    throw new Error("Upload a JPG, PNG, or WebP passport photograph.");
  }
  if (file.size > MAX_PASSPORT_BYTES) {
    throw new Error("Passport photograph must be 5 MB or smaller.");
  }

  const dataUrl = await readAsDataUrl(file);
  const response = await fetch(GOOGLE_DRIVE_UPLOAD_URL, {
    method: "POST",
    headers: { "Content-Type": "text/plain;charset=utf-8" },
    body: JSON.stringify({
      fileName: file.name,
      mimeType: file.type,
      data: dataUrl.split(",")[1],
      email,
    }),
  });

  if (!response.ok) throw new Error("Google Drive upload failed.");
  const result = await response.json();
  if (!result.url)
    throw new Error(result.error || "Google Drive upload failed.");
  return toDriveImageUrl(result.url);
}

/** Convert old Drive view links to an embeddable thumbnail URL. */
export function toDriveImageUrl(url) {
  if (!url) return null;
  const match = String(url).match(/(?:id=|\/d\/)([a-zA-Z0-9_-]+)/);
  return match
    ? `https://drive.google.com/thumbnail?id=${match[1]}&sz=w1000`
    : url;
}

function readAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () =>
      reject(new Error("Could not read the passport photograph."));
    reader.readAsDataURL(file);
  });
}
