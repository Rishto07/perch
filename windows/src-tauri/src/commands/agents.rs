use crate::{agents, hooks::HookPreview};

#[tauri::command]
pub(crate) fn agents_status() -> Vec<agents::AgentStatus> {
    agents::status()
}

/// Live process scan for the island. Reports which watched agent CLIs are
/// currently running — used to mark pills "Session active" without hooks.
#[tauri::command]
pub(crate) fn agent_process_scan() -> agents::AgentProcessState {
    agents::detect_agents()
}

/// Diff for a Codex/OpenCode install or removal — same preview rule as Claude.
#[tauri::command]
pub(crate) fn agents_preview(agent: String, install: bool) -> Result<HookPreview, String> {
    agents::preview(&agent, install)
}

/// Only ever called from an explicit click in the settings window.
#[tauri::command]
pub(crate) fn agents_apply(
    agent: String,
    install: bool,
    fingerprint: String,
) -> Result<String, String> {
    agents::write(&agent, install, &fingerprint)
}
