// Path registry for the one-click agent setup.

use std::path::PathBuf;

pub(crate) fn home() -> PathBuf {
    std::env::var_os("USERPROFILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

pub(crate) fn codex_settings_path() -> PathBuf {
    home().join(".codex").join("hooks.json")
}

pub(crate) fn opencode_dir() -> PathBuf {
    home().join(".config").join("opencode")
}

pub(crate) fn opencode_plugin_path() -> PathBuf {
    opencode_dir().join("plugins").join("perch.ts")
}

pub(crate) fn opencode_config_path() -> PathBuf {
    opencode_dir().join("opencode.json")
}
