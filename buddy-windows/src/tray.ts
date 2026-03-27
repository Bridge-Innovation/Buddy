// System tray — creates tray icon and toggles settings popup window

import { TrayIcon } from '@tauri-apps/api/tray';
import { WebviewWindow } from '@tauri-apps/api/webviewWindow';
import { resolveResource } from '@tauri-apps/api/path';

let trayMenuWindow: WebviewWindow | null = null;

export async function initTray() {
  const iconPath = await resolveResource('resources/owl_active_open.png');

  await TrayIcon.new({
    id: 'buddy-tray',
    icon: iconPath,
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
