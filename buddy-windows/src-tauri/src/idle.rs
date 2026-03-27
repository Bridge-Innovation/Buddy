#[cfg(target_os = "windows")]
use std::mem;

/// Returns the number of seconds since the user's last input (keyboard/mouse).
/// On non-Windows platforms, returns 0 (for development on macOS).
#[tauri::command]
pub fn get_idle_seconds() -> u64 {
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
        use windows::Win32::System::SystemInformation::GetTickCount;

        let mut info = LASTINPUTINFO {
            cbSize: mem::size_of::<LASTINPUTINFO>() as u32,
            dwTime: 0,
        };

        unsafe {
            if GetLastInputInfo(&mut info).as_bool() {
                let tick_count = GetTickCount();
                return ((tick_count - info.dwTime) / 1000) as u64;
            }
        }
        0
    }

    #[cfg(not(target_os = "windows"))]
    {
        0 // Development stub for macOS
    }
}
