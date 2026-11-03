// App-wide shared state and the one cross-cutting constant.

use std::sync::Mutex;

use crate::{island::PollGate, settings::Settings};

/// Keeps spawned helpers from flashing a console window.
pub(crate) const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub struct Shared {
    pub settings: Mutex<Settings>,
    pub gate: std::sync::Arc<PollGate>,
}