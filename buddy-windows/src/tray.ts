// System tray — creates tray icon and toggles settings popup window

import { TrayIcon } from '@tauri-apps/api/tray';
import { WebviewWindow } from '@tauri-apps/api/webviewWindow';
import { defaultWindowIcon } from '@tauri-apps/api/app';

let trayMenuWindow: WebviewWindow | null = null;

export async function initTray() {
  // Use the app's default icon (icons/icon.png from tauri.conf.json)
  const icon = await defaultWindowIcon();

  await TrayIcon.new({
    id: 'buddy-tray',
    icon: icon ?? undefined,
    tooltip: 'Buddy',
    action: async (event) => {
      if (event.type === 'Click') {
        toggleTrayMenu();
      }
    },
  });
}

async function toggleTrayMenu() {
  trayMenuWindow = await WebviewWindow.getByLabel('tray-menu');

  if (!trayMenuWindow) return;

  const visible = await trayMenuWindow.isVisible();
  if (visible) {
    await trayMenuWindow.hide();
  } else {
    await trayMenuWindow.show();
    await trayMenuWindow.setFocus();
  }
}
