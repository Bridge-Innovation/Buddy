// System tray is now set up from Rust (main.rs) for reliability.
// This file is kept as a no-op in case it's imported.

export async function initTray() {
  // Tray is handled by Rust — nothing to do here
  console.log('[Buddy] Tray managed by Rust backend');
}
