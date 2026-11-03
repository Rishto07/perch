// Shared low-level helpers for the installers: dated backups, fingerprints,
// atomic writes and pretty printing.

use std::path::{Path, PathBuf};

use serde_json::Value;
use windows::Win32::System::SystemInformation::GetLocalTime;

pub(crate) fn pretty(v: &Value) -> String {
    serde_json::to_string_pretty(v).unwrap_or_default()
}

/// The exact same file Perch would write — the diff the user sees is what hits
/// the disk.
pub(crate) fn pretty_json(v: &Value) -> String {
    pretty(v)
}

/// Down to the second, so two installs in the same minute don't share a backup.
fn stamp() -> String {
    let t = unsafe { GetLocalTime() };
    format!(
        "{:04}{:02}{:02}-{:02}{:02}{:02}",
        t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond
    )
}

/// `<name>.bak-<stamp>` beside the original, e.g. `perch.ts.bak-20261103-143052`.
/// One naming scheme for every backup Perch takes.
pub(crate) fn backup_of(path: &Path) -> PathBuf {
    let file_name = path.file_name().unwrap_or_default().to_string_lossy();
    path.with_file_name(format!("{file_name}.bak-{}", stamp()))
}

pub(crate) fn current_fingerprint(path: &Path) -> String {
    match std::fs::read(path) {
        Ok(bytes) => crate::hooks::fingerprint(&bytes),
        Err(_) => crate::hooks::fingerprint(b""),
    }
}
/// Atomic write beside the target + rename, so a crash never leaves half a file.
pub(crate) fn write_atomic(path: &Path, text: &str) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let temp = path.with_file_name(format!(
        "{}.perch-{}",
        path.file_name().unwrap_or_default().to_string_lossy(),
        std::process::id()
    ));
    std::fs::write(&temp, text.as_bytes()).map_err(|e| format!("write failed: {e}"))?;
    std::fs::rename(&temp, path).map_err(|e| {
        let _ = std::fs::remove_file(&temp);
        format!("write failed: {e}")
    })?;
    Ok(())
}
