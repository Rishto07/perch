// One-click setup for every coding agent.
//
// Claude Code keeps its own module (hooks/); this one covers the rest:
// Codex (hooks.json merge, same backup/diff/fingerprint guarantees) and
// OpenCode (plugin file + opencode.json registration). Zcode and anything
// without a hooks API are status-only: the UI shows the wrapper command.
//
// The rule from CLAUDE.md applies to every file here: read, dated backup,
// merge without touching anybody else's entries, show the diff, and write
// only after an explicit click with a matching fingerprint.

use serde::Serialize;

use crate::hooks::HookPreview;
use crate::settings;

mod codex;
mod detect;
pub(crate) mod monitor;
mod opencode;
mod paths;

use codex::{codex_preview, codex_status, codex_write};
use opencode::{opencode_preview, opencode_status, opencode_write};

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AgentStatus {
    pub id: &'static str,
    pub name: &'static str,
    pub cli_detected: bool,
    pub installed: bool,
    pub settings_path: String,
    pub hook_ready: bool,
    pub detail: String,
    /// False means the UI shows a manual hint instead of Install buttons.
    pub can_auto: bool,
    /// True when the agent's CLI is currently running (process monitoring).
    pub process_active: bool,
    /// How sessions arrive: "native hooks", "plugin", or "process monitoring".
    pub integration_method: &'static str,
}

/// Live process scan for the island.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AgentProcessState {
    pub detected: Vec<(String, Vec<detect::DetectedProcess>)>,
}

pub fn status() -> Vec<AgentStatus> {
    let running = detect::detect_agents();
    let mut list = vec![
        codex_status(),
        opencode_status(),
        wrapper_status("zcode", "Zcode", "zcode"),
        wrapper_status("zed", "Zed", "zed"),
        wrapper_status("generic", "Anything else", "perch"),
    ];
    for st in &mut list {
        let active = match st.id {
            "codex" => running.iter().any(|(a, _)| a == "codex"),
            "opencode" => running.iter().any(|(a, _)| a == "opencode"),
            "zcode" => running.iter().any(|(a, _)| a == "zcode"),
            "zed" => running.iter().any(|(a, _)| a == "zed"),
            _ => false,
        };
        st.process_active = active;
        st.integration_method = match st.id {
            "codex" | "opencode" => {
                if st.installed {
                    "native hooks"
                } else {
                    "process monitoring"
                }
            }
            "zcode" | "zed" => "process monitoring",
            _ => st.integration_method,
        };
    }
    list
}

/// Live process scan for the island (used by the agent monitor).
pub fn detect_agents() -> AgentProcessState {
    AgentProcessState {
        detected: detect::detect_agents(),
    }
}

/// Refresh `process_active` / `cli_detected` from a live process scan.
pub fn refresh_statuses() -> Vec<AgentStatus> {
    let running: Vec<String> = detect::detect_agents()
        .into_iter()
        .map(|(agent, _)| agent)
        .collect();
    let mut list = status();
    for st in &mut list {
        let active = match st.id {
            "codex" => running.iter().any(|a| a == "codex"),
            "opencode" => running.iter().any(|a| a == "opencode"),
            "zcode" => running.iter().any(|a| a == "zcode"),
            "zed" => running.iter().any(|a| a == "zed"),
            _ => false,
        };
        st.process_active = active;
        st.integration_method = match st.id {
            "codex" | "opencode" => {
                if st.installed {
                    "native hooks"
                } else {
                    "process monitoring"
                }
            }
            "zcode" | "zed" => "process monitoring",
            _ => st.integration_method,
        };
    }
    list
}

pub fn preview(agent: &str, install: bool) -> Result<HookPreview, String> {
    match agent {
        "codex" => codex_preview(install),
        "opencode" => opencode_preview(install),
        _ => Err(format!("{agent} has no automatic setup — see the hint.")),
    }
}

pub fn write(agent: &str, install: bool, fingerprint: &str) -> Result<String, String> {
    match agent {
        "codex" => codex_write(install, fingerprint),
        "opencode" => opencode_write(install, fingerprint),
        _ => Err(format!("{agent} has no automatic setup — see the hint.")),
    }
}

fn wrapper_status(id: &'static str, name: &'static str, cli: &str) -> AgentStatus {
    let detected = crate::find_on_path(cli).is_some();
    AgentStatus {
        id,
        name,
        cli_detected: detected,
        installed: false,
        settings_path: String::new(),
        hook_ready: settings::hook_exe_path().exists(),
        detail: "No hooks API — wrap its command so Perch can watch. Example: perch-run -Agent zcode -- zcode …".into(),
        can_auto: false,
        process_active: detected,
        integration_method: "process monitoring",
    }
}
