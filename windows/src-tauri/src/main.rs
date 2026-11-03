// Perch runs without a console window: Pip is the whole UI.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    perch_lib::run()
}
