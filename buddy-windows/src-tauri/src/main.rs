#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod idle;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .invoke_handler(tauri::generate_handler![idle::get_idle_seconds])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
