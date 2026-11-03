// Small append-only log at %LOCALAPPDATA%\Perch\perch.log — the Windows
// equivalent of nbLog() in HookServer.swift. Nothing leaves the machine.

use std::io::Write;

use windows::Win32::System::SystemInformation::GetLocalTime;

use crate::settings;

pub fn line(message: impl AsRef<str>) {
    let t = unsafe { GetLocalTime() };
    let stamp = format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
        t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond
    );
    let dir = settings::local_dir();
    if std::fs::create_dir_all(&dir).is_err() {
        return;
    }
    let path = dir.join("perch.log");
    // Keep it from growing forever: past ~1 MB, rotate to perch.log.old
    // instead of deleting history outright.
    if std::fs::metadata(&path)
        .map(|m| m.len() > 1_000_000)
        .unwrap_or(false)
    {
        let rotated = dir.join("perch.log.old");
        let _ = std::fs::remove_file(&rotated);
        let _ = std::fs::rename(&path, &rotated);
    }
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(file, "{stamp} {}", message.as_ref());
    }
}
