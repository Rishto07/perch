use std::os::windows::process::CommandExt;
use std::process::Command;

use tauri::AppHandle;

use crate::{integrations, log, shared::CREATE_NO_WINDOW};

#[tauri::command]
pub(crate) fn open_url(url: String) {
    if !(url.starts_with("http://") || url.starts_with("https://")) {
        return;
    }
    let _ = Command::new("rundll32.exe")
        .args(["url.dll,FileProtocolHandler", &url])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn();
}

/// "Open terminal" opens the working folder in VS Code when `code` is on PATH,
/// and falls back to Explorer otherwise.
#[tauri::command]
pub(crate) fn open_in_vscode(path: Option<String>) -> bool {
    // No `cmd /C` anywhere near this. The path is a project folder chosen by
    // whoever is using Claude Code, and cmd would happily read `&`, `^` and `%`
    // in a folder name as syntax. Finding the launcher ourselves and handing the
    // path over as a separate argument keeps it a path.
    if let Some(code) = find_on_path("code") {
        let mut cmd = Command::new(code);
        if let Some(p) = path.as_deref().filter(|p| !p.is_empty()) {
            cmd.arg(p);
        }
        if cmd.creation_flags(CREATE_NO_WINDOW).spawn().is_ok() {
            return true;
        }
    }
    if let Some(p) = path.as_deref().filter(|p| !p.is_empty()) {
        let _ = Command::new("explorer").arg(p).spawn();
    }
    false
}

/// Open the agent's own desktop app at the project folder.
/// `agent` is the task id ("integration_codex" etc.) — the CLI name on PATH is
/// also accepted directly. Falls back to VS Code/Explorer so the click never
/// looks dead when the agent isn't installed.
#[tauri::command]
pub(crate) fn open_agent(agent: String, path: Option<String>) -> bool {
    let binding = agent.trim().to_lowercase();
    let stem = match binding.as_str() {
        "integration_claude" | "claude" | "claude-code" => {
            return open_in_vscode(path);
        }
        "integration_codex" | "codex" => "codex",
        "integration_opencode" | "opencode" => "opencode",
        "integration_zcode" | "zcode" => "zcode",
        "integration_generic" | "generic" => {
            return open_in_vscode(path);
        }
        _ => binding.as_str(),
    };
    if let Some(exe) = find_on_path(stem) {
        let mut cmd = Command::new(exe);
        if let Some(p) = path.as_deref().filter(|p| !p.is_empty()) {
            // Desktop TUIs / apps accept a folder as their first arg.
            cmd.arg(p);
            cmd.current_dir(p);
        }
        if cmd.creation_flags(CREATE_NO_WINDOW).spawn().is_ok() {
            return true;
        }
    }
    open_in_vscode(path)
}

/// Our own `where`: walks %PATH% against %PATHEXT%, no shell involved.
/// Rust quotes arguments correctly for `.cmd`/`.bat` targets since 1.77, so
/// spawning `code.cmd` directly is safe.
pub(crate) fn find_on_path(stem: &str) -> Option<std::path::PathBuf> {
    let exts = std::env::var("PATHEXT").unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".into());
    let dirs = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&dirs) {
        for ext in exts.split(';').filter(|e| !e.is_empty()) {
            let candidate = dir.join(format!("{stem}{}", ext.to_lowercase()));
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

/// Refresh buttons in the integration cards.
#[tauri::command]
pub(crate) async fn refresh_integration(app: AppHandle, id: String) {
    integrations::poll_once(app, &id).await;
}

/// Lets the island write to the same log as the Rust side.
#[tauri::command]
pub(crate) fn log_line(message: String) {
    log::line(format!("ui  {message}"));
}
