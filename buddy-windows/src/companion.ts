// Companion owl rendering — port of CompanionView.swift
// Runs in the companion window (index.html)

import { getTheme, type CharacterTheme } from './theme';
import { settings, idleMonitor, presence } from './main';
import { BuddyEvents, type BuddyState } from './types';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';

const BLINK_FRAME_MS = 80;
const WAVE_FRAME_MS = 120;
const BREATH_CYCLE_MS = 1750;
const DROWSY_HOLD_MS = 300;

let currentState: BuddyState = 'active';
let theme: CharacterTheme = getTheme('owl1');
let isWaving = false;

// DOM elements
let owlImg: HTMLImageElement;
let availabilityDot: HTMLElement;
let nameLabel: HTMLElement;

// Timers
let blinkTimer: ReturnType<typeof setTimeout> | null = null;
let breathTimer: ReturnType<typeof setInterval> | null = null;
let breathPhase = true; // true = inhale

export async function initCompanion() {
  owlImg = document.getElementById('owl-img') as HTMLImageElement;
  availabilityDot = document.getElementById('availability-dot')!;
  nameLabel = document.getElementById('name-label')!;

  // Load initial settings
  const characterType = await settings.getCharacterType();
  theme = getTheme(characterType);

  const displayName = await settings.getDisplayName();
  nameLabel.textContent = displayName || '';
  nameLabel.style.display = displayName ? 'block' : 'none';

  const owlSize = await settings.getOwlSize();
  applyOwlScale(owlSize);

  const isAvailable = await settings.getIsAvailableToCowork();
  updateAvailabilityDot(isAvailable && currentState === 'active');

  // Set initial frame
  owlImg.src = theme.blinkSequence.open;

  // Enable window dragging — start immediately on mousedown
  const container = document.getElementById('companion-container')!;
  container.addEventListener('mousedown', async (e) => {
    if (e.button === 0 && !(e.target as HTMLElement).closest('#companion-menu')) {
      e.preventDefault();
      await getCurrentWebviewWindow().startDragging();
    }
  });

  // Prevent text selection and focus outline
  container.addEventListener('selectstart', (e) => e.preventDefault());

  // Right-click context menu on companion owl
  setupContextMenu(container);

  // Start active blink loop
  startActiveMode();

  // Listen to state changes
  idleMonitor.addEventListener(BuddyEvents.STATE_CHANGED, ((ev: CustomEvent) => {
    const { newState } = ev.detail as { newState: BuddyState };
    switchState(newState);
  }) as EventListener);

  // Note: companion owl does NOT wave on incoming waves from friends.
  // Only the friend's owl panel plays the wave animation (matching macOS behavior).

  // Listen for settings changes via storage events or polling
  // We'll poll settings every 2s for changes from the tray menu window
  setInterval(async () => {
    const newCharType = await settings.getCharacterType();
    const newTheme = getTheme(newCharType);
    if (newTheme !== theme) {
      theme = newTheme;
      if (!isWaving) refreshFrame();
    }

    const newName = await settings.getDisplayName();
    nameLabel.textContent = newName || '';
    nameLabel.style.display = newName ? 'block' : 'none';

    const newSize = await settings.getOwlSize();
    applyOwlScale(newSize);

    const avail = await settings.getIsAvailableToCowork();
    updateAvailabilityDot(avail && currentState === 'active');
  }, 2000);
}

function applyOwlScale(size: number) {
  const scale = settings.owlScale(size);
  owlImg.style.transform = `scale(${scale})`;
  owlImg.style.transformOrigin = 'center bottom';
}

function updateAvailabilityDot(visible: boolean) {
  availabilityDot.style.opacity = visible ? '1' : '0';
}

function switchState(newState: BuddyState) {
  if (newState === currentState) return;
  currentState = newState;

  // Clear all animation timers
  clearTimers();

  switch (newState) {
    case 'active':
      startActiveMode();
      break;
    case 'idle':
      startIdleMode();
      break;
    case 'asleep':
      startAsleepMode();
      break;
  }

  // Update availability dot
  settings.getIsAvailableToCowork().then(avail => {
    updateAvailabilityDot(avail && currentState === 'active');
  });
}

function clearTimers() {
  if (blinkTimer) { clearTimeout(blinkTimer); blinkTimer = null; }
  if (breathTimer) { clearInterval(breathTimer); breathTimer = null; }
}

// -- Active mode: normal blink at 3-5s intervals --

function startActiveMode() {
  owlImg.classList.remove('breathing');
  owlImg.src = theme.blinkSequence.open;
  scheduleActiveBlink();
}

function scheduleActiveBlink() {
  const delay = 3000 + Math.random() * 2000; // 3-5s
  blinkTimer = setTimeout(async () => {
    if (currentState !== 'active' || isWaving) {
      scheduleActiveBlink();
      return;
    }
    await playBlink();
    scheduleActiveBlink();
  }, delay);
}

async function playBlink() {
  const frames = theme.blinkSequence.frames;
  // Play frames: open, half, closed, half (skip last open — we restore it after)
  for (let i = 1; i < frames.length - 1; i++) {
    owlImg.src = frames[i];
    await sleep(BLINK_FRAME_MS);
  }
  owlImg.src = frames[0]; // back to open
}

// -- Idle mode: drowsy slow blink (half-closed base, blink to closed) --

function startIdleMode() {
  owlImg.classList.remove('breathing');
  owlImg.src = theme.idleImages.baseImage;
  scheduleDrowsyBlink();
}

function scheduleDrowsyBlink() {
  const delay = 4000 + Math.random() * 1000; // 4-5s
  blinkTimer = setTimeout(async () => {
    if (currentState !== 'idle' || isWaving) {
      scheduleDrowsyBlink();
      return;
    }
    // Close eyes briefly
    owlImg.src = theme.idleImages.closedImage;
    await sleep(DROWSY_HOLD_MS);
    owlImg.src = theme.idleImages.baseImage;
    scheduleDrowsyBlink();
  }, delay);
}

// -- Asleep mode: breathing crossfade between inhale/exhale --

function startAsleepMode() {
  breathPhase = true;
  owlImg.src = theme.asleepBreathing.inhaleImage;
  owlImg.classList.add('breathing');
  breathTimer = setInterval(() => {
    breathPhase = !breathPhase;
    owlImg.src = breathPhase
      ? theme.asleepBreathing.inhaleImage
      : theme.asleepBreathing.exhaleImage;
  }, BREATH_CYCLE_MS);
}

// -- Wave animation --

async function playWave() {
  if (isWaving) return;
  isWaving = true;

  const frames = theme.waveFrames;
  for (const frame of frames) {
    owlImg.src = frame;
    await sleep(WAVE_FRAME_MS);
  }

  isWaving = false;
  refreshFrame();
}

function refreshFrame() {
  switch (currentState) {
    case 'active':
      owlImg.src = theme.blinkSequence.open;
      break;
    case 'idle':
      owlImg.src = theme.idleImages.baseImage;
      break;
    case 'asleep':
      owlImg.src = breathPhase
        ? theme.asleepBreathing.inhaleImage
        : theme.asleepBreathing.exhaleImage;
      break;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// -- Right-click context menu --

function setupContextMenu(container: HTMLElement) {
  // Create the menu element
  const menu = document.createElement('div');
  menu.id = 'companion-menu';
  menu.style.cssText = `
    position: fixed; display: none; z-index: 100;
    background: rgba(30, 30, 30, 0.95); backdrop-filter: blur(12px);
    border: 1px solid rgba(255,255,255,0.1); border-radius: 8px;
    padding: 4px; min-width: 160px;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    font-family: 'Nunito', sans-serif;
  `;

  const items = [
    { label: 'Settings', action: 'settings' },
    { label: 'Wave', action: 'wave' },
    { label: '---' },
    { label: 'Quit Buddy', action: 'quit', danger: true },
  ];

  for (const item of items) {
    if (item.label === '---') {
      const hr = document.createElement('hr');
      hr.style.cssText = 'border: none; border-top: 1px solid rgba(255,255,255,0.1); margin: 4px 0;';
      menu.appendChild(hr);
      continue;
    }
    const btn = document.createElement('button');
    btn.textContent = item.label;
    btn.dataset.action = item.action;
    btn.style.cssText = `
      display: block; width: 100%; padding: 6px 12px; border: none;
      background: transparent; color: ${item.danger ? '#f87171' : 'white'};
      font-family: inherit; font-size: 13px; text-align: left;
      border-radius: 4px; cursor: pointer;
    `;
    btn.addEventListener('mouseenter', () => { btn.style.background = 'rgba(255,255,255,0.1)'; });
    btn.addEventListener('mouseleave', () => { btn.style.background = 'transparent'; });
    menu.appendChild(btn);
  }

  document.body.appendChild(menu);

  container.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    menu.style.display = 'block';
    // Measure actual menu size after display
    const menuRect = menu.getBoundingClientRect();
    const x = Math.max(0, Math.min(e.clientX, window.innerWidth - menuRect.width - 4));
    const y = Math.max(0, Math.min(e.clientY, window.innerHeight - menuRect.height - 4));
    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;
  });

  document.addEventListener('click', () => { menu.style.display = 'none'; });

  menu.addEventListener('click', async (e) => {
    const target = e.target as HTMLElement;
    const action = target.dataset.action;
    menu.style.display = 'none';

    switch (action) {
      case 'settings': {
        // Open or show the tray-menu settings window
        const { WebviewWindow } = await import('@tauri-apps/api/webviewWindow');
        const win = await WebviewWindow.getByLabel('tray-menu');
        if (win) { await win.show(); await win.setFocus(); }
        break;
      }
      case 'wave':
        playWave();
        break;
      case 'quit': {
        const { exit } = await import('@tauri-apps/plugin-process');
        await exit(0);
        break;
      }
    }
  });
}
