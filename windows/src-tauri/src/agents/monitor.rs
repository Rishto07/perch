// Background agent process monitor.
//
// Scans the process list every few seconds and emits `agent-monitor` to the
// island so a pill can show "Session active" even when its native hook never
// fired (Codex/Zcode/Zed have no hooks API; Claude/OpenCode use native hooks
// and only fall back to this when nothing has arrived).
//
// This is process monitoring, not event monitoring: it can tell you an agent
// CLI is running, never what it is doing. The UI labels it accordingly.

use std::thread;
use std::time::Duration;

use tauri::{AppHandle, Emitter};

use crate::agents;
use crate::log;

/// How often the process list is scanned. Long enough to be free, short enough
/// that a freshly started agent shows up quickly.
const SCAN_INTERVAL: Duration = Duration::from_secs(5);

pub fn start(app: AppHandle) {
    thread::spawn(move || loop {
        thread::sleep(SCAN_INTERVAL);
        // Best-effort: if the island window is collapsed we still scan (an
        // agent may be running and the user may hover to peek). The scan is
        // cheap (one tasklist call) and the UI only acts on changes.
        let state = agents::detect_agents();
        if let Err(err) = app.emit("agent-monitor", &state) {
            log::line(format!("agent-monitor: emit failed: {err}"));
        }
    });
}
