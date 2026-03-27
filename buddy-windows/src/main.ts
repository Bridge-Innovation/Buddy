// Buddy Windows — main entry point
// Wires together presence, idle monitoring, and settings

import { PresenceManager } from './presence';
import { IdleMonitor } from './idle-monitor';
import { Settings } from './settings';
import { BuddyEvents } from './types';

// Singleton instances for use by other modules (UI, tray, etc.)
export const settings = new Settings();
export const presence = new PresenceManager();
export const idleMonitor = new IdleMonitor();

async function init() {
  console.log('[Buddy] Windows app starting');

  // 1. Load settings
  await settings.init();

  const userId = await settings.getUserId();
  const displayName = await settings.getDisplayName();
  const characterType = await settings.getCharacterType();
  const isAvailable = await settings.getIsAvailableToCowork();

  // 2. Configure idle monitor
  idleMonitor.characterType = characterType;
  idleMonitor.isAvailableToCowork = isAvailable;

  // 3. Register or restore credentials, then start presence
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

  // 4. Start idle monitor
  idleMonitor.start();

  // 5. Wire idle state changes to presence status updates
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

  // Initialize system tray
  const { initTray } = await import('./tray');
  await initTray();

  // Initialize friend panel manager (creates windows for online friends)
  const { FriendPanelManager } = await import('./friend-panel');
  const friendPanels = new FriendPanelManager(presence);
  friendPanels.start();
}).catch(err => console.error('[Buddy] Init failed:', err));
