// Generic CLI-process detection for coding agents.
//
// Not every agent exposes hooks. For Codex, Zcode, Zed (and anything else in
// AGENT_PROCESSES) this module reports *process monitoring*: which CLIs are
// currently running, so the island can show "Session active" instead of
// "Waiting for session…" when a native hook never fires.
//
// This is deliberately conservative: it only reads the process list through
// `tasklist` (no injection, no memory scraping) and reports what it can see.
// It never claims tool-level events.

use serde::Serialize;
use std::os::windows::process::CommandExt;

use crate::log;

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct DetectedProcess {
    /// Process id (informational only).
    pub pid: u32,
    /// Executable name, e.g. "codex.exe".
    pub name: String,
    /// How many instances are running right now.
    pub count: u32,
}

/// agent tag → executable stems that mean "this agent is running".
/// Keep this list to executables we actually want to watch.
pub const AGENT_PROCESSES: &[(&str, &[&str])] = &[
    ("claude", &["claude.exe", "claude.cmd", "claude"]),
    ("codex", &["codex.exe", "codex.cmd", "codex", "chatgpt.exe"]),
    ("opencode", &["opencode.exe", "opencode.cmd", "opencode"]),
    ("zcode", &["zcode.exe", "zcode"]),
    ("zed", &["zed.exe", "zed"]),
];

/// One `tasklist` row: `Image Name, PID, Session Name, Session#, Mem Usage`.
/// We only read the image name; the rest is parsed defensively.
fn parse_tasklist(stdout: &str) -> Vec<(String, u32)> {
    let mut rows = Vec::new();
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        // Image Name is the first comma-separated field.
        let name = trimmed.split(',').next().unwrap_or("").trim().to_string();
        if name.is_empty() {
            continue;
        }
        // The second field is the PID (decimal). Anything else is ignored.
        let pid = trimmed
            .split(',')
            .nth(1)
            .and_then(|p| p.trim().parse::<u32>().ok())
            .unwrap_or(0);
        rows.push((name, pid));
    }
    rows
}

/// Enumerate running processes. Uses `tasklist /FO CSV /NH` (no header) so the
/// output is stable across locales that quote differently.
pub fn list_processes() -> Vec<(String, u32)> {
    let output = std::process::Command::new("tasklist")
        .args(["/FO", "CSV", "/NH"])
        .creation_flags(crate::shared::CREATE_NO_WINDOW)
        .output();
    match output {
        Ok(out) if out.status.success() => parse_tasklist(&String::from_utf8_lossy(&out.stdout)),
        Ok(out) => {
            log::line(format!(
                "agent_detect: tasklist failed (code {:?})",
                out.status.code()
            ));
            Vec::new()
        }
        Err(err) => {
            log::line(format!("agent_detect: tasklist could not run: {err}"));
            Vec::new()
        }
    }
}

/// Which of the watched agent CLIs are currently running.
pub fn detect_agents() -> Vec<(String, Vec<DetectedProcess>)> {
    let processes = list_processes();
    let mut found: Vec<(String, Vec<DetectedProcess>)> = Vec::new();
    for (agent, stems) in AGENT_PROCESSES {
        let mut matched: Vec<DetectedProcess> = Vec::new();
        for stem in stems.iter() {
            let mut count = 0u32;
            let mut first_pid = 0u32;
            for (name, pid) in &processes {
                if name.eq_ignore_ascii_case(stem) {
                    count += 1;
                    if first_pid == 0 {
                        first_pid = *pid;
                    }
                }
            }
            if count > 0 {
                matched.push(DetectedProcess {
                    pid: first_pid,
                    name: stem.to_string(),
                    count,
                });
            }
        }
        if !matched.is_empty() {
            found.push((agent.to_string(), matched));
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tasklist_csv_parses_image_name_and_pid() {
        let sample = "codex.exe,1234,Console,1,12,345 K\r\nopencode.exe,5678,Console,1,9,999 K\r\n";
        let rows = parse_tasklist(sample);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0], ("codex.exe".to_string(), 1234));
        assert_eq!(rows[1], ("opencode.exe".to_string(), 5678));
    }

    #[test]
    fn tasklist_tolerates_bad_lines() {
        let sample = "\r\nnot,a,real,process\r\ncodex.exe,42,Console,1,1,1 K\r\n";
        let rows = parse_tasklist(sample);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[1], ("codex.exe".to_string(), 42));
    }
}
