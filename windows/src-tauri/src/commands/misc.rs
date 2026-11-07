use std::os::windows::process::CommandExt;
use std::process::Command;

use tauri::AppHandle;

use crate::{integrations, log, shared::CREATE_NO_WINDOW};

/// User home as a String — used when a task has no session folder yet.
fn home_dir() -> Option<String> {
    std::env::var("USERPROFILE").ok().filter(|s| !s.is_empty())
}

/// Project folder to hand to the agent: the task's session folder when it
/// exists, otherwise the user's home so the app still opens somewhere sane.
fn launch_dir(path: Option<String>) -> Option<String> {
    if let Some(p) = path.as_deref().filter(|p| !p.is_empty()) {
        let candidate = std::path::Path::new(p);
        if candidate.exists() && candidate.is_dir() {
            return Some(p.to_string());
        }
        if candidate.exists() {
            if let Some(parent) = candidate.parent() {
                return Some(parent.to_string_lossy().to_string());
            }
            return Some(p.to_string());
        }
    }
    home_dir()
}

/// Well-known desktop-app locations for each coding agent, so the click works
/// even when the CLI was installed without touching PATH.
fn known_desktop_paths(stem: &str) -> Vec<std::path::PathBuf> {
    let mut out = Vec::new();
    let local = std::env::var("LOCALAPPDATA")
        .ok()
        .map(std::path::PathBuf::from);
    let appdata = std::env::var("APPDATA").ok().map(std::path::PathBuf::from);
    let push = |base: Option<&std::path::Path>, rel: &str, out: &mut Vec<std::path::PathBuf>| {
        if let Some(b) = base {
            out.push(b.join(rel));
        }
    };
    match stem {
        "code" | "claude" | "claude-code" => {
            out.push(std::path::PathBuf::from(
                r"C:\Program Files\Microsoft VS Code\Code.exe",
            ));
            push(
                local.as_deref(),
                r"Programs\Microsoft VS Code\Code.exe",
                &mut out,
            );
            // Claude Desktop (separate from VS Code).
            push(local.as_deref(), r"AnthropicClaude\Claude.exe", &mut out);
            push(appdata.as_deref(), r"Claude\Claude.exe", &mut out);
            out.push(std::path::PathBuf::from(
                r"C:\Program Files\Claude\Claude.exe",
            ));
        }
        "codex" => {
            push(local.as_deref(), r"Programs\Codex\Codex.exe", &mut out);
            push(appdata.as_deref(), r"Codex\Codex.exe", &mut out);
            out.push(std::path::PathBuf::from(
                r"C:\Program Files\Codex\Codex.exe",
            ));
            out.push(std::path::PathBuf::from(
                r"C:\Program Files\Codex\codex.exe",
            ));
        }
        "opencode" => {
            push(
                local.as_deref(),
                r"Programs\OpenCode\OpenCode.exe",
                &mut out,
            );
            push(appdata.as_deref(), r"OpenCode\OpenCode.exe", &mut out);
            out.push(std::path::PathBuf::from(
                r"C:\Program Files\OpenCode\OpenCode.exe",
            ));
        }
        "zcode" => {
            push(local.as_deref(), r"Programs\Zcode\Zcode.exe", &mut out);
            push(appdata.as_deref(), r"Zcode\Zcode.exe", &mut out);
            out.push(std::path::PathBuf::from(
                r"C:\Program Files\Zcode\Zcode.exe",
            ));
        }
        _ => {}
    }
    out
}

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
    let dir = launch_dir(path.clone());
    if let Some(code) = find_on_path("code") {
        let mut cmd = Command::new(code);
        if let Some(p) = dir.as_deref() {
            cmd.arg(p);
        }
        if cmd.creation_flags(CREATE_NO_WINDOW).spawn().is_ok() {
            log::line("open_in_vscode: launched VS Code");
            return true;
        }
        log::line("open_in_vscode: code spawn failed");
    } else {
        log::line("open_in_vscode: code not on PATH, trying Code.exe");
        for candidate in known_desktop_paths("code") {
            if candidate.is_file() {
                let mut cmd = Command::new(candidate);
                if let Some(p) = dir.as_deref() {
                    cmd.arg(p);
                }
                if cmd.creation_flags(CREATE_NO_WINDOW).spawn().is_ok() {
                    log::line("open_in_vscode: launched Code.exe");
                    return true;
                }
            }
        }
        log::line("open_in_vscode: no VS Code found");
    }
    if let Some(p) = dir.as_deref() {
        let _ = Command::new("explorer").arg(p).spawn();
        log::line("open_in_vscode: fell back to Explorer");
        return false;
    }
    false
}

/// Open the agent's own desktop app at the project folder.
/// `agent` is the task id ("integration_codex" etc.) — the CLI name on PATH is
/// also accepted directly. NOT falling back to VS Code silently: the user asked
/// for the agent's app, so a missing agent now reports false (frontend shows
/// "not found") while logging exactly what was searched.
#[tauri::command]
pub(crate) fn open_agent(agent: String, path: Option<String>) -> bool {
    let binding = agent.trim().to_lowercase();
    // Claude/GUI agents delegate to VS Code handling (Claude Desktop is also
    // tried there via known paths).
    match binding.as_str() {
        "integration_claude" | "claude" | "claude-code" => {
            return open_in_vscode(path);
        }
        "integration_generic" | "generic" => {
            return open_in_vscode(path);
        }
        _ => {}
    }
    let stem: &str = match binding.as_str() {
        "integration_codex" | "codex" => "codex",
        "integration_opencode" | "opencode" => "opencode",
        "integration_zcode" | "zcode" => "zcode",
        _ => binding.as_str(),
    };
    let dir = launch_dir(path.clone());

    // 1) CLI on PATH (opencode/codex CLIs install shims here).
    if let Some(exe) = find_on_path(stem) {
        if spawn_agent_cli(&exe, dir.as_deref(), stem) {
            log::line(format!(
                "open_agent: launched {stem} via PATH {}",
                exe.display()
            ));
            return true;
        }
        log::line(format!("open_agent: {stem} on PATH failed to spawn"));
    }
    // 2) Known desktop-app locations (even without PATH).
    for candidate in known_desktop_paths(stem) {
        if candidate.is_file() {
            let mut cmd = Command::new(candidate.clone());
            if let Some(p) = dir.as_deref() {
                cmd.arg(p);
                cmd.current_dir(p);
            }
            if cmd.creation_flags(CREATE_NO_WINDOW).spawn().is_ok() {
                log::line(format!(
                    "open_agent: launched {stem} desktop {}",
                    candidate.display()
                ));
                return true;
            }
        }
    }
    log::line(format!(
        "open_agent: {stem} not found (PATH or known desktop paths); dir={dir:?}"
    ));
    false
}

/// Launch a CLI agent so its TUI actually gets a visible console:
/// prefer Windows Terminal (`wt -d <dir>`), else `cmd /c start` with its own
/// window. `CREATE_NO_WINDOW` would make TUIs exit silently.
fn spawn_agent_cli(exe: &std::path::Path, dir: Option<&str>, stem: &str) -> bool {
    // Prefer Windows Terminal when available — visible TUI in the project dir.
    if let Some(wt) = find_on_path("wt") {
        let mut cmd = Command::new(wt);
        cmd.arg("-d");
        cmd.arg(dir.unwrap_or("."));
        cmd.arg("-w");
        cmd.arg("0");
        cmd.arg(exe);
        if let Some(p) = dir {
            cmd.arg(p);
        }
        if cmd.spawn().is_ok() {
            log::line(format!("open_agent: {stem} via wt"));
            return true;
        }
        log::line(format!("open_agent: wt spawn failed for {stem}"));
    }
    // Fallback: PowerShell with a real window (NoExit keeps TUI alive).
    let mut cmd = Command::new("powershell.exe");
    cmd.arg("-NoExit");
    cmd.arg("-Command");
    // Only ever our fixed stem + project path — quote the path for PS.
    let ps_path = dir.unwrap_or(".").replace('\'', "''");
    cmd.arg(format!(
        "& '{}' '{}'",
        exe.to_string_lossy().replace('\'', "''"),
        ps_path
    ));
    if let Some(p) = dir {
        cmd.current_dir(p);
    }
    cmd.spawn().is_ok()
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
