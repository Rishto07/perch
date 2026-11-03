use crate::{commands::misc::open_url, secrets};

/// The island may only ask whether a key exists — never read it.
#[tauri::command]
pub(crate) fn secret_present(key: String) -> bool {
    secrets::present(&key)
}

#[tauri::command]
pub(crate) fn secret_set(key: String, value: String) -> Result<(), String> {
    secrets::set(&key, &value)
}

#[tauri::command]
pub(crate) fn secret_clear(key: String) -> Result<(), String> {
    secrets::clear(&key)
}

/// Opens the configured n8n instance — the URL lives in the Credential Manager.
#[tauri::command]
pub(crate) fn open_n8n() {
    if let Some(url) = secrets::get("n8n-url") {
        open_url(url);
    }
}
