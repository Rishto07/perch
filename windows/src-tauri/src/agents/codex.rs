// Codex hooks merge/uninstall — same backup/diff/fingerprint guarantees as
// Claude Code. Codex's schema adds a "matcher" field per hook group.

use serde_json::Value;

use crate::hooks::{self, HookPreview};
use crate::settings;

use super::paths::codex_settings_path;
use super::AgentStatus;

fn codex_hook_command(event: &str) -> String {
    let exe = settings::hook_exe_path().to_string_lossy().replace('\\', "/");
    format!("\"{exe}\" {event} codex")
}

fn codex_merged(existing: &Value) -> Value {
    hooks::merged_core(existing, &|event| codex_hook_command(event), Some(""))
}

pub(super) fn codex_status() -> AgentStatus {
    let path = codex_settings_path();
    let installed = hooks::read_json_file(&path)
        .ok()
        .and_then(|v| {
            v.get("hooks").and_then(Value::as_object).map(|hooks| {
                hooks
                    .values()
                    .filter_map(Value::as_array)
                    .flatten()
                    .any(crate::hooks::entry_is_ours)
            })
        })
        .unwrap_or(false);
    let cli = crate::find_on_path("codex").is_some();
    AgentStatus {
        id: "codex",
        name: "Codex",
        cli_detected: cli,
        installed,
        settings_path: path.to_string_lossy().to_string(),
        hook_ready: settings::hook_exe_path().exists(),
        detail: if installed {
            "Hooked in — Codex sessions show up in the island.".into()
        } else if cli {
            "Codex CLI found. Install the hooks to light up its pill.".into()
        } else {
            "Codex CLI not on PATH. Install it, then come back.".into()
        },
        can_auto: true,
    }
}

pub(super) fn codex_preview(install: bool) -> Result<HookPreview, String> {
    let path = codex_settings_path();
    let current = hooks::read_json_file(&path)?;
    let next = if install {
        codex_merged(&current)
    } else {
        hooks::without_ours(&current)
    };
    Ok(HookPreview {
        diff: hooks::unified_diff(&hooks::pretty_json(&current), &hooks::pretty_json(&next)),
        backup: hooks::backup_of(&path).to_string_lossy().to_string(),
        settings_path: path.to_string_lossy().to_string(),
        fingerprint: hooks::current_fingerprint(&path),
    })
}

pub(super) fn codex_write(install: bool, fingerprint: &str) -> Result<String, String> {
    let path = codex_settings_path();
    let current = hooks::read_json_file(&path)?;
    if hooks::current_fingerprint(&path) != fingerprint {
        return Err(format!(
            "{} changed since the preview. Nothing was written — review the new diff.",
            path.display()
        ));
    }
    let backup = hooks::backup_of(&path);
    if path.exists() {
        std::fs::copy(&path, &backup).map_err(|e| format!("backup failed: {e}"))?;
    }
    let next = if install {
        codex_merged(&current)
    } else {
        hooks::without_ours(&current)
    };
    let mut text = hooks::pretty_json(&next);
    text.push('\n');
    hooks::write_atomic(&path, &text)?;
    Ok(backup.to_string_lossy().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_merge_keeps_foreign_hooks_and_marks_ours() {
        let existing = serde_json::json!({
            "model": "gpt-5",
            "hooks": {
                "PreToolUse": [
                    { "matcher": "^Bash$", "hooks": [{ "type": "command", "command": "other-tool.exe" }] }
                ]
            }
        });
        let after = codex_merged(&existing);
        assert_eq!(after["model"], "gpt-5");
        let pre = after["hooks"]["PreToolUse"].as_array().unwrap();
        assert!(pre.iter().any(|e| serde_json::to_string(e).unwrap().contains("other-tool.exe")));
        assert!(pre.iter().any(crate::hooks::entry_is_ours));
        let ours: Vec<&Value> = pre.iter().filter(|e| crate::hooks::entry_is_ours(e)).collect();
        assert_eq!(ours.len(), 1);
        assert!(serde_json::to_string(ours[0]).unwrap().contains("codex"));
        // Removing ours restores the original.
        assert_eq!(hooks::without_ours(&after), existing);
    }
}
