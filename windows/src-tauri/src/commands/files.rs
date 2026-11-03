use crate::files::{self, DroppedFile};

/// Copies a dropped file into the inbox and reports its name back.
#[tauri::command]
pub(crate) fn ingest_file(path: String) -> Result<DroppedFile, String> {
    files::ingest(&path)
}
