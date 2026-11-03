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
}

pub fn status() -> Vec<AgentStatus> {
    vec![
        codex_status(),
        opencode_status(),
        wrapper_status("zcode", "Zcode", "zcode"),
        wrapper_status("generic", "Anything else", "perch"),
    ]
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
    }
}
