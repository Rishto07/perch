use crate::{agents, hooks::HookPreview};

#[tauri::command]
pub(crate) fn agents_status() -> Vec<agents::AgentStatus> {
    agents::status()
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
