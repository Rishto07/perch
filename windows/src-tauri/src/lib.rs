// Perch for Windows - app wiring. The Tauri commands live in `commands/`.

mod commands;

mod agents;
mod claude;
mod files;
mod hooks;
mod integrations;
mod island;
mod log;
mod pipe;
mod secrets;
mod settings;
mod settings_window;
mod shared;
mod tray;
mod win_user;

use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use tauri::Emitter;
use tauri_plugin_autostart::MacosLauncher;

use crate::claude::Chat;
use crate::island::PollGate;
use crate::pipe::Pending;

pub(crate) use commands::misc::find_on_path;
pub(crate) use shared::Shared;

use settings_window::create_settings_window;

pub fn run() {
    let loaded = settings::load();
    let gate = Arc::new(PollGate::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            let _ = app.emit_to(island::WINDOW_LABEL, "tray", "open".to_string());
        }))
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .manage(Shared {
            settings: Mutex::new(loaded.clone()),
            gate: gate.clone(),
        })
        .manage(Pending::default())
        .manage(Chat::default())
        .invoke_handler(tauri::generate_handler![
            commands::settings::boot,
            commands::settings::save_settings,
            commands::settings::set_collapsed,
            commands::settings::set_island_rect,
            commands::settings::focus_window,
            commands::settings::reposition,
            commands::misc::open_url,
            commands::misc::open_in_vscode,
            commands::settings::quit_app,
            commands::hooks::hooks_status,
            commands::hooks::hooks_preview,
            commands::hooks::hooks_apply,
            commands::agents::agents_status,
            commands::agents::agents_preview,
            commands::agents::agents_apply,
            commands::approval::approval_decision,
            commands::approval::approval_ack,
            commands::approval::approval_decline,
            commands::misc::log_line,
            commands::chat::chat_send,
            commands::chat::chat_reset,
            commands::files::ingest_file,
            commands::secrets::secret_present,
            commands::secrets::secret_set,
            commands::secrets::secret_clear,
            commands::misc::refresh_integration,
            commands::secrets::open_n8n,
            commands::settings::open_settings_window,
            commands::settings::set_paused,
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            tray::build(&handle)?;
            // Before the island: see create_settings_window.
            create_settings_window(&handle);

            if let Some(win) = island::window(&handle) {
                island::make_non_activating(&win);
                island::apply_geometry(&handle, &loaded.screen, false);
                let _ = win.show();
            }
            gate.collapsed.store(false, Ordering::Relaxed);
            gate.set_active(true);
            island::spawn_cursor_poll(handle.clone(), gate.clone());

            log::line(format!(
                "--- Perch {} started ---",
                env!("CARGO_PKG_VERSION")
            ));
            hooks::ensure_hook_exe(&handle);
            pipe::start(handle.clone());
            integrations::start(handle.clone());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Perch");
}
