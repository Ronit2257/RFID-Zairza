function doPost(e) {
  // Lock to avoid race conditions when two cards tap simultaneously
  const lock = LockService.getScriptLock();

  // Wait up to 10 seconds for concurrent requests to clear
  if (!lock.tryLock(10000)) {
    return ContentService.createTextOutput("ERROR: Server busy, try again").setMimeType(ContentService.MimeType.TEXT);
  }

  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    // Case-insensitive or trimmed tab lookup to avoid accidental naming mismatches
    const sheet = ss.getSheetByName("Zairza Attendance");
    if (!sheet) {
      return ContentService.createTextOutput("ERROR: Sheet 'Zairza Attendance' not found").setMimeType(ContentService.MimeType.TEXT);
    }

    // Safely extract parameters (supports both URL-encoded and raw JSON)
    let p = e.parameter;
    if ((!p || !p.id) && e.postData && e.postData.contents) {
      p = JSON.parse(e.postData.contents);
    }

    const id = p.id;
    if (!id) {
      return ContentService.createTextOutput("ERROR: Missing ID parameter").setMimeType(ContentService.MimeType.TEXT);
    }

    // 1. Ultra-fast in-memory Cache check (<10ms)
    const cache = CacheService.getScriptCache();
    if (cache.get(id)) {
      return ContentService.createTextOutput("DUPLICATE_SKIPPED").setMimeType(ContentService.MimeType.TEXT);
    }

    // 2. Fallback check: Inspect recent sheet entries (last 50 rows only, to keep it fast)
    const lastRow = sheet.getLastRow();
    if (lastRow > 1) {
      const checkRows = Math.min(lastRow - 1, 50);
      const startRow = lastRow - checkRows + 1;
      const recentIds = sheet.getRange(startRow, 1, checkRows, 1).getValues().flat();
      if (recentIds.indexOf(id) !== -1) {
        cache.put(id, "true", 21600); // 6 hours cache
        return ContentService.createTextOutput("DUPLICATE_SKIPPED").setMimeType(ContentService.MimeType.TEXT);
      }
    }

    // Append record (8 columns)
    sheet.appendRow([
      id,
      p.date   || "",
      p.time   || "",
      p.regNo  || "",
      p.name   || "",
      p.branch || "",
      p.action || "",
      p.uid    || ""
    ]);

    // Store in cache for 6 hours so retries are immediately skipped
    cache.put(id, "true", 21600);

    return ContentService.createTextOutput("SUCCESS").setMimeType(ContentService.MimeType.TEXT);

  } catch (err) {
    return ContentService.createTextOutput("ERROR: " + err.message).setMimeType(ContentService.MimeType.TEXT);
  } finally {
    lock.releaseLock();
  }
}

function doGet(e) {
  return ContentService.createTextOutput("Zairza Attendance Logger API is online and waiting for POST requests.");
}
