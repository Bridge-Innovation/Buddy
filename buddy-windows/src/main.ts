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
  const { emit } = await import('@tauri-apps/api/event');

  // Initialize companion UI (only in companion window)
  const { initCompanion } = await import('./companion');
  await initCompanion();

  // Initialize friend panel manager (creates windows for online friends)
  const { FriendPanelManager } = await import('./friend-panel');
  const friendPanels = new FriendPanelManager(presence);
  friendPanels.start();

  // -- Bridge tray-menu events to the single PresenceManager --

  // When tray-menu requests current state, send it friends + status
  listen('tray-request-state', async () => {
    await emit('tray-friends-update', { friends: presence.friends });
    await emit('tray-status-update', { state: idleMonitor.state });
  });

  // When friends list updates, forward to tray-menu
  presence.addEventListener(BuddyEvents.FRIENDS_UPDATED, ((ev: CustomEvent) => {
    emit('tray-friends-update', { friends: ev.detail.friends });
  }) as EventListener);

  // Forward idle state changes to tray-menu
  idleMonitor.addEventListener(BuddyEvents.STATE_CHANGED, ((ev: CustomEvent) => {
    emit('tray-status-update', { state: ev.detail.newState });
  }) as EventListener);

  // Handle tray-menu actions via the single PresenceManager
  listen<{ friendCode: string }>('tray-add-friend', async (ev) => {
    await presence.addFriend(ev.payload.friendCode);
  });

  listen<{ displayName: string }>('tray-update-profile', async (ev) => {
    const contact = await settings.getFacetimeContact();
    await presence.updateProfile(ev.payload.displayName, contact);
  });

  listen<{ isAvailable: boolean }>('tray-update-availability', async (ev) => {
    idleMonitor.isAvailableToCowork = ev.payload.isAvailable;
    await presence.sendStatus(idleMonitor.state, ev.payload.isAvailable, idleMonitor.characterType);
  });

}).catch(err => console.error('[Buddy] Init failed:', err));
