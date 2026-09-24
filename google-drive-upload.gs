const DRIVE_FOLDER_ID = "1_cjKLZ9zrg2BteOlYmsOT30uamSisT3L";

function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    if (!payload.data || !payload.mimeType || !payload.email) {
      return jsonResponse({ error: "Missing upload data." });
    }

    const bytes = Utilities.base64Decode(payload.data);
    const extension = (payload.mimeType.split("/")[1] || "jpg").replace(
      "jpeg",
      "jpg",
    );
    const fileName = `${sanitize(payload.email)}_${Date.now()}.${extension}`;
    const blob = Utilities.newBlob(bytes, payload.mimeType, fileName);
    const file = DriveApp.getFolderById(DRIVE_FOLDER_ID).createFile(blob);
    file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);

    return jsonResponse({
      url: `https://drive.google.com/thumbnail?id=${file.getId()}&sz=w1000`,
    });
  } catch (error) {
    return jsonResponse({ error: error.message });
  }
}

function sanitize(value) {
  return String(value)
    .replace(/[^a-z0-9._-]/gi, "_")
    .slice(0, 80);
}

function jsonResponse(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(
    ContentService.MimeType.JSON,
  );
}
