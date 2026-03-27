// Tray menu settings popup — port of BuddyApp.swift MenuBarExtra

import { Settings } from './settings';
import { PresenceManager } from './presence';
import { IdleMonitor } from './idle-monitor';
import { BuddyEvents, type FriendStatus, type BuddyState } from './types';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { exit } from '@tauri-apps/plugin-process';

const settings = new Settings();
const presence = new PresenceManager();
const idleMonitor = new IdleMonitor();

// State icons
const stateIcons: Record<BuddyState, string> = {
  active: '\u{1F7E2}',  // green circle
  idle: '\u{1F7E1}',    // yellow circle
  asleep: '\u{1F534}',  // red circle
};

const friendStateColors: Record<string, string> = {
  active: '#34c759',
  idle: '#ffcc00',
  asleep: '#8e8e93',
};

async function init() {
  await settings.init();

  const userId = await settings.getUserId();
  const friendCode = await settings.getFriendCode();
  presence.start(userId, friendCode);
  idleMonitor.start();

  // Wire idle → presence
  idleMonitor.addEventListener(BuddyEvents.STATE_CHANGED, ((ev: CustomEvent) => {
    const { newState } = ev.detail;
    presence.sendStatus(newState, idleMonitor.isAvailableToCowork, idleMonitor.characterType);
    updateStatusDisplay(newState);
  }) as EventListener);

  // Populate UI
  await populateUI();

  // Update friends list on changes
  presence.addEventListener(BuddyEvents.FRIENDS_UPDATED, ((ev: CustomEvent) => {
    renderFriends(ev.detail.friends as FriendStatus[]);
  }) as EventListener);

  // Close popup when it loses focus
  const win = getCurrentWindow();
  win.onFocusChanged(({ payload: focused }) => {
    if (!focused) win.hide();
  });
}

async function populateUI() {
  // Status
  updateStatusDisplay(idleMonitor.state);

  // Display name
  const nameInput = document.getElementById('display-name') as HTMLInputElement;
  nameInput.value = await settings.getDisplayName();
  nameInput.addEventListener('change', async () => {
    await settings.setDisplayName(nameInput.value);
    await presence.updateProfile(nameInput.value, await settings.getFacetimeContact());
  });

  // Friend code
  const codeEl = document.getElementById('friend-code')!;
  const code = await settings.getFriendCode();
  codeEl.textContent = code ?? '------';

  document.getElementById('copy-code-btn')!.addEventListener('click', () => {
    if (code) navigator.clipboard.writeText(code);
  });

  // Available to cowork
  const availToggle = document.getElementById('available-toggle') as HTMLInputElement;
  availToggle.checked = await settings.getIsAvailableToCowork();
  availToggle.addEventListener('change', async () => {
    await settings.setIsAvailableToCowork(availToggle.checked);
    idleMonitor.isAvailableToCowork = availToggle.checked;
    presence.sendStatus(idleMonitor.state, availToggle.checked, idleMonitor.characterType);
  });

  // Character picker
  const charSelect = document.getElementById('character-select') as HTMLSelectElement;
  const currentChar = await settings.getCharacterType();
  charSelect.value = currentChar === 'owl2' ? 'owl2' : 'owl1';
  charSelect.addEventListener('change', async () => {
    await settings.setCharacterType(charSelect.value);
    idleMonitor.characterType = charSelect.value;
  });

  // Owl size
  const sizeSelect = document.getElementById('size-select') as HTMLSelectElement;
  sizeSelect.value = String(await settings.getOwlSize());
  sizeSelect.addEventListener('change', async () => {
    await settings.setOwlSize(Number(sizeSelect.value));
  });

  // Add friend
  const addInput = document.getElementById('add-friend-input') as HTMLInputElement;
  const addBtn = document.getElementById('add-friend-btn') as HTMLButtonElement;
  addInput.addEventListener('input', () => {
    addBtn.disabled = addInput.value.length !== 6;
  });
  addBtn.addEventListener('click', async () => {
    const friendCodeVal = addInput.value;
    addInput.value = '';
    addBtn.disabled = true;
    await presence.addFriend(friendCodeVal);
  });

  // Check for updates (placeholder)
  document.getElementById('check-updates-btn')!.addEventListener('click', () => {
    // Will integrate with tauri-plugin-updater later
    console.log('[Buddy] Check for updates clicked');
  });

  // Quit
  document.getElementById('quit-btn')!.addEventListener('click', async () => {
    await exit(0);
  });

  // Initial friends load
  const friends = await presence.getFriends();
  renderFriends(friends);
}

function updateStatusDisplay(state: BuddyState) {
  const statusIcon = document.getElementById('status-icon')!;
  const statusLabel = document.getElementById('status-label')!;
  statusIcon.textContent = stateIcons[state] ?? stateIcons.active;
  statusLabel.textContent = state.charAt(0).toUpperCase() + state.slice(1);
}

function renderFriends(friends: FriendStatus[]) {
  const list = document.getElementById('friends-list')!;
  const section = document.getElementById('friends-section')!;

  if (friends.length === 0) {
    section.style.display = 'none';
    return;
  }

  section.style.display = 'block';
  list.innerHTML = '';

  for (const friend of friends) {
    const row = document.createElement('div');
    row.className = 'friend-row';

    const dot = document.createElement('span');
    dot.className = 'friend-dot';
    dot.style.backgroundColor = friend.isAvailable
      ? '#34c759'
      : (friendStateColors[friend.activityState] ?? '#8e8e93');

    const name = document.createElement('span');
    name.className = 'friend-name';
    name.textContent = friend.displayName;

    const status = document.createElement('span');
    status.className = 'friend-status';
    status.textContent = friend.activityState;

    row.appendChild(dot);
    row.appendChild(name);
    row.appendChild(status);
    list.appendChild(row);
  }
}

init().catch(err => console.error('[Buddy] Tray menu init failed:', err));
