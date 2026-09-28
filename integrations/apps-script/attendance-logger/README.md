# Existing attendance writer

Code.gs archives the Apps Script supplied by the project owner. It has not been deployed or changed to serve the mobile application. The existing GET returns a health message, not attendance JSON. Keep the current deployment URL and POST behavior intact.

The copied lookup comment mentions case-insensitive/trimmed matching, but the actual code uses the exact tab name `Zairza Attendance`; configure the new reader to match the actual name.
