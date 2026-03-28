// Buddy Windows — main entry point
// Wires together presence, idle monitoring, and settings

import { PresenceManager } from './presence';
import { IdleMonitor } from './idle-monitor';
import { Settings } from './settings';
import { BuddyEvents } from './types';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';

/** Show a simple name prompt dialog on first launch */
async function promptForName(): Promise<string | null> {
  return new Promise((resolve) => {
    const overlay = document.createElement('div');
    overlay.style.cssText = `
      position: fixed; inset: 0; z-index: 9999;
      background: rgba(255, 248, 240, 0.95);
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      font-family: 'Nunito', sans-serif;
    `;
    overlay.innerHTML = `
      <div style="text-align: center; max-width: 240px;">
        <img src="/owls/owl_active_open.png" width="80" height="80" style="margin-bottom: 12px;">
        <h2 style="font-size: 18px; color: #5C4033; margin-bottom: 4px;">Welcome to Buddy!</h2>
        <p style="font-size: 13px; color: #8B7B6E; margin-bottom: 16px;">What should your friends see you as?</p>
        <input id="name-input" type="text" placeholder="Your name"
          style="width: 100%; padding: 8px 12px; border-radius: 8px;
          border: 2px solid #FFE8D6; font-family: inherit; font-size: 14px;
          outline: none; text-align: center; color: #4A3728;">
        <button id="name-submit"
          style="margin-top: 12px; padding: 8px 24px; border-radius: 20px;
          background: #E8985E; color: white; border: none; font-family: inherit;
          font-weight: 700; font-size: 14px; cursor: pointer;">
          Let's go!
        </button>
      </div>
    `;
    document.body.appendChild(overlay);

    const input = document.getElementById('name-input') as HTMLInputElement;
    const btn = document.getElementById('name-submit') as HTMLButtonElement;

    function submit() {
      const name = input.value.trim();
      overlay.remove();
      resolve(name || null);
    }

    btn.addEventListener('click', submit);
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
    input.focus();
  });
}

// Singleton instances for use by other modules (UI, tray, etc.)
export const settings = new Settings();
export const presence = new PresenceManager();
export const idleMonitor = new IdleMonitor();

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

  // 3. First launch — prompt for display name
  if (!userId && !displayName) {
    displayName = await promptForName();
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
