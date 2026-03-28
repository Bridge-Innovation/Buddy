// Buddy Windows — main entry point
// Wires together presence, idle monitoring, and settings

import { PresenceManager } from './presence';
import { IdleMonitor } from './idle-monitor';
import { Settings } from './settings';
import { BuddyEvents } from './types';
import { WebviewWindow } from '@tauri-apps/api/webviewWindow';
import { listen } from '@tauri-apps/api/event';

// Singleton instances for use by other modules (UI, tray, etc.)
export const settings = new Settings();
export const presence = new PresenceManager();
export const idleMonitor = new IdleMonitor();

/** Show the welcome window and wait for the user to enter their name */
async function showWelcomeWindow(): Promise<string> {
  return new Promise(async (resolve) => {
    // Listen for the welcome-complete event before creating the window
    const unlisten = await listen<{ displayName: string }>('welcome-complete', (event) => {
      unlisten();
      resolve(event.payload.displayName);
    });

    // Create and show the welcome window
    const welcome = new WebviewWindow('welcome', {
      url: 'welcome.html',
      title: 'Welcome to Buddy',
      width: 320,
      height: 420,
      center: true,
      decorations: true,
      transparent: false,
      resizable: false,
      alwaysOnTop: true,
      skipTaskbar: false,
    });

    // If the user closes the window without submitting, resolve with empty
    welcome.once('tauri://destroyed', () => {
      unlisten();
      resolve('');
    });
  });
}

async function init() {
  console.log('[Buddy] Windows app starting');

  // 1. Load settings
  await settings.init();

  const userId = await settings.getUserId();
  let displayName = await settings.getDisplayName();
  const characterType = await settings.getCharacterType();
  const isAvailable = await settings.getIsAvailableToCowork();

  // 2. Configure idle monitor
  idleMonitor.characterType = characterType;
  idleMonitor.isAvailableToCowork = isAvailable;

  // 3. First launch — show welcome window for display name
  if (!userId && !displayName) {
    displayName = await showWelcomeWindow();
    if (displayName) {
      await settings.setDisplayName(displayName);
    }
  }

  // 4. Register or restore credentials, then start presence
  if (!userId) {
    const resp = await presence.register(displayName || undefined);
    if (resp) {
      await settings.setUserId(resp.userId);
      await settings.setFriendCode(resp.friendCode);
      if (!displayName) {
        await settings.setDisplayName(resp.displayName);
      }
    }
  }

  const storedUserId = await settings.getUserId();
  const storedCode = await settings.getFriendCode();
  presence.start(storedUserId, storedCode);

  // 5. Start idle monitor
  idleMonitor.start();

  // 6. Wire idle state changes to presence status updates
  idleMonitor.addEventListener(BuddyEvents.STATE_CHANGED, ((ev: CustomEvent) => {
    const { newState } = ev.detail;
    console.log(`[Buddy] State changed to: ${newState}`);
    presence.sendStatus(newState, idleMonitor.isAvailableToCowork, idleMonitor.characterType);
  }) as EventListener);

  console.log('[Buddy] Initialized — userId:', storedUserId?.slice(0, 8) ?? '(new)');
}

init().then(async () => {
  // Initialize companion UI (only in companion window)
  const { initCompanion } = await import('./companion');
  await initCompanion();

  // Initialize system tray (from JS — fallback if Rust tray doesn't work)
  try {
    const { initTray } = await import('./tray');
    await initTray();
  } catch (err) {
    console.warn('[Buddy] Tray init failed (may be handled by Rust):', err);
  }

  // Initialize friend panel manager (creates windows for online friends)
  const { FriendPanelManager } = await import('./friend-panel');
  const friendPanels = new FriendPanelManager(presence);
  friendPanels.start();
}).catch(err => console.error('[Buddy] Init failed:', err));
