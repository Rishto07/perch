// One-click setup for every coding agent.
//
// Claude Code keeps its own section (hooks.rs); this module covers the rest:
// Codex (hooks.json merge, same backup/diff/fingerprint guarantees) and
// OpenCode (plugin file + opencode.json registration). Zcode and anything
// without a hooks API are status-only: the UI shows the wrapper command.
//
// The rule from CLAUDE.md applies to every file here: read, dated backup,
// merge without touching anybody else's entries, show the diff, and write
// only after an explicit click with a matching fingerprint.

use serde::Serialize;
use serde_json::{json, Map, Value};
use std::path::PathBuf;

use crate::hooks::{self, HookPreview};
use crate::{log, settings};

/// The OpenCode plugin, mirrored from agents/opencode/perch.ts — keep in sync.
const OPENCODE_PLUGIN: &str = include_str!("../../../agents/opencode/perch.ts");

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

fn home() -> PathBuf {
    std::env::var_os("USERPROFILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn codex_settings_path() -> PathBuf {
    home().join(".codex").join("hooks.json")
}

fn opencode_dir() -> PathBuf {
    home().join(".config").join("opencode")
}

fn opencode_plugin_path() -> PathBuf {
    opencode_dir().join("plugins").join("perch.ts")
}

fn opencode_config_path() -> PathBuf {
    opencode_dir().join("opencode.json")
}

/// Reads a JSON settings file. Missing means "start from nothing"; anything
/// else unreadable is an error, never silently treated as empty.
fn read_json(path: &PathBuf) -> Result<Value, String> {
    match std::fs::read(path) {
        Ok(bytes) => {
            let text = bytes
                .strip_prefix(&[0xEF, 0xBB, 0xBF])
                .unwrap_or(&bytes);
            if text.iter().all(u8::is_ascii_whitespace) {
                return Ok(json!({}));
            }
            match serde_json::from_slice::<Value>(text) {
                Ok(v) if v.is_object() => Ok(v),
                Ok(_) => Err(format!(
                    "{} isn't a JSON object — Perch won't touch it.",
                    path.display()
                )),
                Err(err) => Err(format!(
                    "{} isn't valid JSON ({err}). Fix or move it, then try again — Perch won't overwrite it.",
                    path.display()
                )),
            }
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(json!({})),
        Err(err) => Err(format!("Can't read {}: {err}", path.display())),
    }
}

fn current_fingerprint(path: &PathBuf) -> String {
    match std::fs::read(path) {
        Ok(bytes) => hooks::fingerprint(&bytes),
        Err(_) => hooks::fingerprint(b""),
    }
}

fn stamp() -> String {
    // Second precision: two installs in the same minute must not share a backup.
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{secs}")
}

fn backup_of(path: &PathBuf) -> PathBuf {
    let name = format!(
        "{}-{}.bak-{}",
        path.file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "settings".into()),
        stamp(),
        path.extension()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default()
    );
    path.with_file_name(name)
}

/// Atomic write beside the target + rename, so a crash never leaves half a file.
fn write_atomic(path: &PathBuf, text: &str) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let temp = path.with_extension(format!("perch-{}", std::process::id()));
    std::fs::write(&temp, text.as_bytes()).map_err(|e| format!("write failed: {e}"))?;
    std::fs::rename(&temp, path).map_err(|e| {
        let _ = std::fs::remove_file(&temp);
        format!("write failed: {err}", err = e)
    })?;
    Ok(())
}

fn entry_is_ours(entry: &Value) -> bool {
    entry
        .get("hooks")
        .and_then(Value::as_array)
        .map(|hooks| {
            hooks.iter().any(|h| {
                h.get("command")
                    .and_then(Value::as_str)
                    .map(|c| c.contains("perch-hook"))
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

// ── Codex ───────────────────────────────────────────────────────────────────

fn codex_hook_command(event: &str) -> String {
    let exe = settings::hook_exe_path().to_string_lossy().replace('\\', "/");
    format!("\"{exe}\" {event} codex")
}

fn codex_merged(existing: &Value) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let mut hooks = root
        .get("hooks")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_else(Map::new);
    for (event, timeout) in hooks::HOOK_EVENTS {
        let mut list = hooks
            .get(*event)
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        list.retain(|entry| !entry_is_ours(entry));
        list.push(json!({
            "matcher": "",
            "hooks": [{
                "type": "command",
                "command": codex_hook_command(event),
                "timeout": timeout,
            }]
        }));
        hooks.insert((*event).to_string(), Value::Array(list));
    }
    root.insert("hooks".into(), Value::Object(hooks));
    Value::Object(root)
}

fn codex_without_ours(existing: &Value) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let Some(hooks) = root.get("hooks").and_then(Value::as_object).cloned() else {
        return Value::Object(root);
    };
    let mut out = Map::new();
    for (event, value) in hooks {
        match value.as_array() {
            Some(list) => {
                let kept: Vec<Value> =
                    list.iter().filter(|e| !entry_is_ours(e)).cloned().collect();
                if !kept.is_empty() {
                    out.insert(event, Value::Array(kept));
                }
            }
            None => {
                out.insert(event, value);
            }
        }
    }
    if out.is_empty() {
        root.remove("hooks");
    } else {
        root.insert("hooks".into(), Value::Object(out));
    }
    Value::Object(root)
}

fn codex_status() -> AgentStatus {
    let path = codex_settings_path();
    let installed = read_json(&path)
        .ok()
        .and_then(|v| {
            v.get("hooks").and_then(Value::as_object).map(|hooks| {
                hooks
                    .values()
                    .filter_map(Value::as_array)
                    .flatten()
                    .any(entry_is_ours)
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

fn codex_preview(install: bool) -> Result<HookPreview, String> {
    let path = codex_settings_path();
    let current = read_json(&path)?;
    let next = if install {
        codex_merged(&current)
    } else {
        codex_without_ours(&current)
    };
    Ok(HookPreview {
        diff: hooks::unified_diff(&hooks::pretty_json(&current), &hooks::pretty_json(&next)),
        backup: backup_of(&path).to_string_lossy().to_string(),
        settings_path: path.to_string_lossy().to_string(),
        fingerprint: current_fingerprint(&path),
    })
}

fn codex_write(install: bool, fingerprint: &str) -> Result<String, String> {
    let path = codex_settings_path();
    let current = read_json(&path)?;
    if current_fingerprint(&path) != fingerprint {
        return Err(format!(
            "{} changed since the preview. Nothing was written — review the new diff.",
            path.display()
        ));
    }
    let backup = backup_of(&path);
    if path.exists() {
        std::fs::copy(&path, &backup).map_err(|e| format!("backup failed: {e}"))?;
    }
    let next = if install {
        codex_merged(&current)
    } else {
        codex_without_ours(&current)
    };
    let mut text = hooks::pretty_json(&next);
    text.push('\n');
    write_atomic(&path, &text)?;
    Ok(backup.to_string_lossy().to_string())
}

// ── OpenCode ────────────────────────────────────────────────────────────────

/// True when opencode.json names our plugin in its `plugin` array.
fn opencode_registered(config: &Value) -> bool {
    config
        .get("plugin")
        .and_then(Value::as_array)
        .map(|plugins| {
            plugins.iter().any(|p| {
                p.as_str()
                    .map(|s| s.contains("perch"))
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

fn opencode_registered_config(config: &Value) -> Value {
    let mut root = config.as_object().cloned().unwrap_or_default();
    let mut plugins = root
        .get("plugin")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if !plugins.iter().any(|p| {
        p.as_str().map(|s| s.contains("perch")).unwrap_or(false)
    }) {
        plugins.push(json!("./plugins/perch.ts"));
    }
    root.insert("plugin".into(), Value::Array(plugins));
    Value::Object(root)
}

fn opencode_status() -> AgentStatus {
    let plugin_path = opencode_plugin_path();
    let plugin_current = std::fs::read(&plugin_path)
        .map(|b| b == OPENCODE_PLUGIN.as_bytes())
        .unwrap_or(false);
    let plugin_exists = plugin_path.exists();
    let registered = read_json(&opencode_config_path())
        .map(|c| opencode_registered(&c))
        .unwrap_or(false);
    let installed = plugin_current && registered;
    let cli = crate::find_on_path("opencode").is_some();
    AgentStatus {
        id: "opencode",
        name: "OpenCode",
        cli_detected: cli,
        installed,
        settings_path: opencode_config_path().to_string_lossy().to_string(),
        hook_ready: settings::hook_exe_path().exists(),
        detail: if installed {
            "Plugin active — OpenCode sessions show up in the island.".into()
        } else if plugin_exists && !plugin_current {
            "An older Perch plugin is there — reinstall to update it.".into()
        } else if cli {
            "OpenCode CLI found. Install the plugin to light up its pill.".into()
        } else {
            "OpenCode CLI not on PATH. The plugin still works if you use OpenCode.".into()
        },
        can_auto: true,
    }
}

fn opencode_preview(install: bool) -> Result<HookPreview, String> {
    let plugin_path = opencode_plugin_path();
    let config_path = opencode_config_path();
    let mut sections = Vec::new();
    if install {
        let plugin_now = std::fs::read(&plugin_path).unwrap_or_default();
        if plugin_now != OPENCODE_PLUGIN.as_bytes() {
            sections.push(format!(
                "Write {} ({} lines, the Perch plugin){}",
                plugin_path.display(),
                OPENCODE_PLUGIN.lines().count(),
                if plugin_path.exists() { " — backs up the old one first" } else { "" }
            ));
        }
        match read_json(&config_path) {
            Ok(config) if !opencode_registered(&config) => {
                let next = opencode_registered_config(&config);
                sections.push(hooks::unified_diff(
                    &hooks::pretty_json(&config),
                    &hooks::pretty_json(&next),
                ));
            }
            Ok(_) => {}
            Err(err) => {
                sections.push(format!(
                    "NOTE: {} — the plugin will be installed, but register it yourself in opencode.json: \"plugin\": [\"./plugins/perch.ts\"].",
                    err
                ));
            }
        }
        if sections.is_empty() {
            sections.push("No change.".into());
        }
    } else {
        sections.push(format!(
            "Remove {} and unregister it from {}.",
            plugin_path.display(),
            config_path.display()
        ));
    }
    Ok(HookPreview {
        diff: sections.join("\n"),
        backup: backup_of(&plugin_path).to_string_lossy().to_string(),
        settings_path: config_path.to_string_lossy().to_string(),
        fingerprint: format!(
            "{}:{}",
            current_fingerprint(&plugin_path),
            current_fingerprint(&config_path)
        ),
    })
}

fn backup_if_exists(path: &PathBuf) -> Result<Option<String>, String> {
    if path.exists() {
        let backup = backup_of(path);
        std::fs::copy(path, &backup).map_err(|e| format!("backup failed: {e}"))?;
        Ok(Some(backup.to_string_lossy().to_string()))
    } else {
        Ok(None)
    }
}

fn opencode_write(install: bool, fingerprint: &str) -> Result<String, String> {
    let plugin_path = opencode_plugin_path();
    let config_path = opencode_config_path();
    let expected = format!(
        "{}:{}",
        current_fingerprint(&plugin_path),
        current_fingerprint(&config_path)
    );
    if expected != fingerprint {
        return Err("Something changed since the preview. Nothing was written — review the new diff.".into());
    }
    let mut backups = Vec::new();
    if install {
        if let Some(b) = backup_if_exists(&plugin_path)? {
            backups.push(b);
        }
        write_atomic(&plugin_path, OPENCODE_PLUGIN)?;
        match read_json(&config_path) {
            Ok(config) if !opencode_registered(&config) => {
                if let Some(b) = backup_if_exists(&config_path)? {
                    backups.push(b);
                }
                let next = opencode_registered_config(&config);
                let mut text = hooks::pretty_json(&next);
                text.push('\n');
                write_atomic(&config_path, &text)?;
            }
            Ok(_) => {}
            Err(err) => {
                log::line(format!("opencode config left alone: {err}"));
            }
        }
    } else {
        if plugin_path.exists() {
            let _ = std::fs::remove_file(&plugin_path);
        }
        if let Ok(config) = read_json(&config_path) {
            let mut root = config.as_object().cloned().unwrap_or_default();
            if let Some(plugins) = root.get("plugin").and_then(Value::as_array).cloned() {
                let kept: Vec<Value> = plugins
                    .iter()
                    .filter(|p| {
                        !p.as_str().map(|s| s.contains("perch")).unwrap_or(false)
                    })
                    .cloned()
                    .collect();
                if kept.len() != plugins.len() {
                    if let Some(b) = backup_if_exists(&config_path)? {
                        backups.push(b);
                    }
                    if kept.is_empty() {
                        root.remove("plugin");
                    } else {
                        root.insert("plugin".into(), Value::Array(kept));
                    }
                    let mut text = hooks::pretty_json(&Value::Object(root));
                    text.push('\n');
                    write_atomic(&config_path, &text)?;
                }
            }
        }
    }
    Ok(backups.join(", "))
}

// ── Status-only agents ──────────────────────────────────────────────────────

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

// ── Public API ──────────────────────────────────────────────────────────────

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
        assert!(pre.iter().any(entry_is_ours));
        let ours: Vec<&Value> = pre.iter().filter(|e| entry_is_ours(e)).collect();
        assert_eq!(ours.len(), 1);
        assert!(serde_json::to_string(ours[0]).unwrap().contains("codex"));
        // Removing ours restores the original.
        assert_eq!(codex_without_ours(&after), existing);
    }

    #[test]
    fn opencode_registration_appends_without_touching_the_rest() {
        let config = serde_json::json!({ "model": "opus", "plugin": ["someone-else"] });
        let next = opencode_registered_config(&config);
        assert_eq!(next["model"], "opus");
        let plugins = next["plugin"].as_array().unwrap();
        assert_eq!(plugins.len(), 2);
        assert!(opencode_registered(&next));
        // Twice is still once.
        assert_eq!(opencode_registered_config(&next), next);
    }
}
