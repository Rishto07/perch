// OpenCode plugin installer + uninstaller. Writes the plugin file and
// registers it in opencode.json — the same backup/diff/fingerprint guarantees
// as every other installer.

use serde_json::{json, Value};

use crate::hooks::{self, HookPreview};
use crate::log;

use super::paths::{opencode_config_path, opencode_plugin_path};
use super::AgentStatus;

/// The OpenCode plugin, mirrored from agents/opencode/perch.ts — keep in sync.
const OPENCODE_PLUGIN: &str = include_str!("../../../../agents/opencode/perch.ts");

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

pub(super) fn opencode_status() -> AgentStatus {
    let plugin_path = opencode_plugin_path();
    let plugin_current = std::fs::read(&plugin_path)
        .map(|b| b == OPENCODE_PLUGIN.as_bytes())
        .unwrap_or(false);
    let plugin_exists = plugin_path.exists();
    let registered = hooks::read_json_file(&opencode_config_path())
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
        hook_ready: crate::settings::hook_exe_path().exists(),
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

pub(super) fn opencode_preview(install: bool) -> Result<HookPreview, String> {
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
                if plugin_path.exists() {
                    " — backs up the old one first"
                } else {
                    ""
                }
            ));
        }
        match hooks::read_json_file(&config_path) {
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
        backup: hooks::backup_of(&plugin_path).to_string_lossy().to_string(),
        settings_path: config_path.to_string_lossy().to_string(),
        fingerprint: format!(
            "{}:{}",
            hooks::current_fingerprint(&plugin_path),
            hooks::current_fingerprint(&config_path)
        ),
    })
}

fn backup_if_exists(path: &std::path::PathBuf) -> Result<Option<String>, String> {
    if path.exists() {
        let backup = hooks::backup_of(path);
        std::fs::copy(path, &backup).map_err(|e| format!("backup failed: {e}"))?;
        Ok(Some(backup.to_string_lossy().to_string()))
    } else {
        Ok(None)
    }
}

pub(super) fn opencode_write(install: bool, fingerprint: &str) -> Result<String, String> {
    let plugin_path = opencode_plugin_path();
    let config_path = opencode_config_path();
    let expected = format!(
        "{}:{}",
        hooks::current_fingerprint(&plugin_path),
        hooks::current_fingerprint(&config_path)
    );
    if expected != fingerprint {
        return Err("Something changed since the preview. Nothing was written — review the new diff.".into());
    }
    let mut backups = Vec::new();
    if install {
        if let Some(b) = backup_if_exists(&plugin_path)? {
            backups.push(b);
        }
        hooks::write_atomic(&plugin_path, OPENCODE_PLUGIN)?;
        match hooks::read_json_file(&config_path) {
            Ok(config) if !opencode_registered(&config) => {
                if let Some(b) = backup_if_exists(&config_path)? {
                    backups.push(b);
                }
                let next = opencode_registered_config(&config);
                let mut text = hooks::pretty_json(&next);
                text.push('\n');
                hooks::write_atomic(&config_path, &text)?;
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
        if let Ok(config) = hooks::read_json_file(&config_path) {
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
                    hooks::write_atomic(&config_path, &text)?;
                }
            }
        }
    }
    Ok(backups.join(", "))
}

#[cfg(test)]
mod tests {
    use super::*;

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
