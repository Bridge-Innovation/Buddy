// Tray menu settings popup — reads settings from shared store,
// communicates with companion window via Tauri events (NOT its own PresenceManager)

import { Settings } from './settings';
import type { FriendStatus, BuddyState } from './types';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { emit, listen } from '@tauri-apps/api/event';
import { exit } from '@tauri-apps/plugin-process';

const settings = new Settings();

const friendStateColors: Record<string, string> = {
  active: '#34c759',
  idle: '#ffcc00',
  asleep: '#8e8e93',
};

async function init() {
  await settings.init();

  await populateUI();

  // Listen for friends list updates from the companion window
  await listen<{ friends: FriendStatus[] }>('tray-friends-update', (ev) => {
    renderFriends(ev.payload.friends);
  });

  // Listen for status updates
  await listen<{ state: BuddyState }>('tray-status-update', (ev) => {
    updateStatusDisplay(ev.payload.state);
  });

  // Close popup when it loses focus
  const win = getCurrentWindow();
  win.onFocusChanged(({ payload: focused }) => {
    if (!focused) win.hide();
  });

  // Request current state from companion
  await emit('tray-request-state', {});
}

async function populateUI() {
  // Display name — read from shared settings store
  const nameInput = document.getElementById('display-name') as HTMLInputElement;
  nameInput.value = await settings.getDisplayName();
  nameInput.addEventListener('change', async () => {
    const name = nameInput.value.trim();
    await settings.setDisplayName(name);
    // Tell the companion to update the profile on the server
    await emit('tray-update-profile', { displayName: name });
  });

  // Friend code — read from shared settings store
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
    await emit('tray-update-availability', { isAvailable: availToggle.checked });
  });

  // Character picker
  const charSelect = document.getElementById('character-select') as HTMLSelectElement;
  const currentChar = await settings.getCharacterType();
  charSelect.value = currentChar === 'owl2' ? 'owl2' : 'owl1';
  charSelect.addEventListener('change', async () => {
    await settings.setCharacterType(charSelect.value);
  });

  // Owl size
  const sizeSelect = document.getElementById('size-select') as HTMLSelectElement;
  sizeSelect.value = String(await settings.getOwlSize());
  sizeSelect.addEventListener('change', async () => {
    await settings.setOwlSize(Number(sizeSelect.value));
  });

  // Add friend — tell the companion to do it (it has the PresenceManager)
  const addInput = document.getElementById('add-friend-input') as HTMLInputElement;
  const addBtn = document.getElementById('add-friend-btn') as HTMLButtonElement;
  addInput.addEventListener('input', () => {
    addBtn.disabled = addInput.value.length !== 6;
  });
  addBtn.addEventListener('click', async () => {
    const friendCode = addInput.value.trim();
    addInput.value = '';
    addBtn.disabled = true;
    await emit('tray-add-friend', { friendCode });
  });

  // Check for updates
  document.getElementById('check-updates-btn')!.addEventListener('click', () => {
    console.log('[Buddy] Check for updates');
  });

  // Quit
  document.getElementById('quit-btn')!.addEventListener('click', async () => {
    await exit(0);
  });

  // Status display
  updateStatusDisplay('active');
}

function updateStatusDisplay(state: BuddyState) {
  const icons: Record<string, string> = { active: '\u{1F7E2}', idle: '\u{1F7E1}', asleep: '\u{1F534}' };
  const statusIcon = document.getElementById('status-icon')!;
  const statusLabel = document.getElementById('status-label')!;
  statusIcon.textContent = icons[state] ?? icons.active;
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
