// Friend owl window — loaded in each friend's transparent window
// Receives friend data via URL params, listens for events via Tauri event system

import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';
import { listen, emit } from '@tauri-apps/api/event';
import type { FriendStatus, ChatMessage, CallLink } from './types';
import { parseCallLinks } from './types';

// Enable dragging on the friend window
let dragTimeout: ReturnType<typeof setTimeout> | null = null;
document.addEventListener('mousedown', (e) => {
  if (e.button === 0 && !(e.target as HTMLElement).closest('#context-menu')) {
    dragTimeout = setTimeout(async () => {
      await getCurrentWebviewWindow().startDragging();
    }, 150);
  }
});
document.addEventListener('mouseup', () => {
  if (dragTimeout) { clearTimeout(dragTimeout); dragTimeout = null; }
});

// Parse friend data from URL params
const params = new URLSearchParams(window.location.search);
const friendId = params.get('friendId') ?? '';
const friendName = params.get('displayName') ?? '';
const characterType = params.get('characterType') ?? 'owl';
const activityState = params.get('activityState') ?? 'active';
const isAvailable = params.get('isAvailable') === 'true';
const facetimeContact = params.get('facetimeContact') ?? '';

// DOM refs
const owlSprite = document.getElementById('owl-sprite') as HTMLImageElement;
const nameText = document.getElementById('name-text')!;
const availabilityDot = document.getElementById('availability-dot')!;
const owlContainer = document.getElementById('owl-container')!;
const bubblesContainer = document.getElementById('bubbles')!;
const contextMenu = document.getElementById('context-menu')!;

// State
let currentState = activityState;
let currentAvailable = isAvailable;
let hasUnreadMessage = false;
let hasMissedCall = false;
let chatBubbleTimeout: ReturnType<typeof setTimeout> | null = null;

// Sprite paths — use the resource path pattern
function spriteForState(state: string): string {
  switch (state) {
    case 'idle': return '/owls/owl_active_half.png';
    case 'asleep': return '/owls/owl_asleep_out.png';
    default: return '/owls/owl_active_open.png';
  }
}

// Blink frames for animation
const blinkFrames: Record<string, string[]> = {
  active: [
    '/owls/owl_active_open.png',
    '/owls/owl_active_half.png',
    '/owls/owl_active_closed.png',
    '/owls/owl_active_half.png',
    '/owls/owl_active_open.png',
  ],
  idle: ['/owls/owl_active_half.png'],
  asleep: [
    '/owls/owl_asleep_out.png',
    '/owls/owl_asleep_in.png',
    '/owls/owl_asleep_out.png',
  ],
};

const waveFrames = [
  '/owls/owl_wave_low.png',
  '/owls/owl_wave_med.png',
  '/owls/owl_wave_high.png',
  '/owls/owl_wave_med.png',
  '/owls/owl_wave_low.png',
];

// Initialize display
nameText.textContent = friendName;
owlSprite.src = spriteForState(currentState);
updateAvailability(currentAvailable);

// Blink animation loop
let blinkTimer: ReturnType<typeof setTimeout> | null = null;
let isAnimating = false;

function scheduleBlink() {
  const delay = 3000 + Math.random() * 4000; // 3-7 seconds
  blinkTimer = setTimeout(async () => {
    if (!isAnimating) {
      await playFrames(blinkFrames[currentState] ?? blinkFrames.active, 120);
    }
    scheduleBlink();
  }, delay);
}

// Breathing for asleep state
let breathTimer: ReturnType<typeof setInterval> | null = null;
function startBreathing() {
  if (breathTimer) return;
  breathTimer = setInterval(async () => {
    if (!isAnimating && currentState === 'asleep') {
      await playFrames(blinkFrames.asleep, 800);
    }
  }, 3000);
}

function stopBreathing() {
  if (breathTimer) { clearInterval(breathTimer); breathTimer = null; }
}

async function playFrames(frames: string[], interval: number) {
  if (isAnimating || frames.length === 0) return;
  isAnimating = true;
  for (const frame of frames) {
    owlSprite.src = frame;
    await sleep(interval);
  }
  owlSprite.src = spriteForState(currentState);
  isAnimating = false;
}

async function playWaveAnimation() {
  owlContainer.classList.add('waving');
  await playFrames(waveFrames, 100);
  owlContainer.classList.remove('waving');
}

function updateAvailability(available: boolean) {
  currentAvailable = available;
  if (available) {
    availabilityDot.classList.remove('hidden');
    owlContainer.classList.add('available');
  } else {
    availabilityDot.classList.add('hidden');
    owlContainer.classList.remove('available');
  }
}

function updateState(state: string) {
  currentState = state;
  owlSprite.src = spriteForState(state);
  if (state === 'asleep') {
    startBreathing();
  } else {
    stopBreathing();
  }
}

// -- Bubble overlays --

function showIndicatorBubble(emoji: string, x: number, y: number, duration = 3000) {
  const el = document.createElement('div');
  el.className = 'bubble indicator-bubble';
  el.textContent = emoji;
  el.style.left = `${x}px`;
  el.style.top = `${y}px`;
  bubblesContainer.appendChild(el);

  setTimeout(() => {
    el.classList.add('fade-out');
    setTimeout(() => el.remove(), 400);
  }, duration);
}

function showChatBubble(text: string) {
  // Remove existing chat/speech bubbles
  bubblesContainer.querySelectorAll('.speech-bubble, .small-speech-bubble').forEach(el => el.remove());
  if (chatBubbleTimeout) { clearTimeout(chatBubbleTimeout); chatBubbleTimeout = null; }

  const el = document.createElement('div');
  el.className = 'bubble speech-bubble';
  el.innerHTML = `<span class="speech-text">${escapeHtml(text)}</span><div class="speech-tail"></div>`;
  el.style.left = '50%';
  el.style.top = '5px';
  el.style.transform = 'translateX(-50%)';
  el.onclick = () => openChat();
  bubblesContainer.appendChild(el);

  hasUnreadMessage = true;

  // After 20 seconds, collapse to small speech bubble indicator
  chatBubbleTimeout = setTimeout(() => {
    el.classList.add('fade-out');
    setTimeout(() => {
      el.remove();
      showUnreadIndicator();
    }, 400);
  }, 20000);
}

function showUnreadIndicator() {
  if (!hasUnreadMessage) return;
  if (bubblesContainer.querySelector('.small-speech-bubble')) return;

  const el = document.createElement('div');
  el.className = 'bubble small-speech-bubble';
  el.innerHTML = `<span>\u{1F4AC}</span><div class="speech-tail-small"></div>`;
  el.style.left = '15px';
  el.style.top = '30px';
  el.style.cursor = 'pointer';
  el.style.pointerEvents = 'auto';
  el.onclick = () => openChat();
  bubblesContainer.appendChild(el);
}

function showMissedCallIndicator() {
  if (!hasMissedCall) return;
  if (bubblesContainer.querySelector('.missed-call-indicator')) return;

  const el = document.createElement('div');
  el.className = 'bubble small-speech-bubble missed-call-indicator';
  el.innerHTML = `<span>\u{1F4DE}</span><div class="speech-tail-small"></div>`;
  el.style.right = '15px';
  el.style.top = '30px';
  bubblesContainer.appendChild(el);
}

function clearUnread() {
  hasUnreadMessage = false;
  hasMissedCall = false;
  bubblesContainer.querySelectorAll('.speech-bubble, .small-speech-bubble, .missed-call-indicator').forEach(el => el.remove());
}

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// -- Actions --

async function doWave() {
  await emit('buddy-send-wave', { toUserId: friendId });
  showIndicatorBubble('\u{1F44B}', 90, 30);
}

function openChat() {
  clearUnread();
  emit('buddy-open-chat', { friendId, displayName: friendName });
}

function convertToAppProtocol(url: string): string {
  // Convert WhatsApp web links to desktop app protocol
  const waMatch = url.match(/^https:\/\/wa\.me\/(\+?\d+)/);
  if (waMatch) {
    return `whatsapp://send?phone=${waMatch[1]}`;
  }
  return url;
}

async function doCall() {
  let links = parseCallLinks(facetimeContact);

  // Filter out FaceTime on Windows
  links = links.filter(l => !l.url.startsWith('facetime://'));

  // Convert web URLs to app protocols where possible
  links = links.map(l => ({ ...l, url: convertToAppProtocol(l.url) }));

  if (links.length === 0) {
    showToast('No compatible call links for this friend');
    return;
  }

  if (links.length === 1) {
    const { open } = await import('@tauri-apps/plugin-shell');
    await open(links[0].url);
  } else {
    showCallPicker(links);
  }

  await emit('buddy-send-call', { toUserId: friendId });
}

function showCallPicker(links: CallLink[]) {
  // Remove any existing picker
  document.querySelector('.call-picker')?.remove();

  const picker = document.createElement('div');
  picker.className = 'call-picker';
  picker.style.cssText = `
    position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);
    background: rgba(30,30,30,0.95); backdrop-filter: blur(12px);
    border: 1px solid rgba(255,255,255,0.1); border-radius: 10px;
    padding: 8px; min-width: 160px; z-index: 200;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    pointer-events: auto;
  `;

  for (const link of links) {
    const btn = document.createElement('button');
    btn.textContent = link.label;
    btn.style.cssText = `
      display: block; width: 100%; padding: 8px 14px; border: none;
      background: transparent; color: white; font-family: 'Nunito', sans-serif;
      font-size: 14px; text-align: left; border-radius: 6px; cursor: pointer;
    `;
    btn.addEventListener('mouseenter', () => btn.style.background = 'rgba(255,255,255,0.1)');
    btn.addEventListener('mouseleave', () => btn.style.background = 'transparent');
    btn.addEventListener('click', async () => {
      picker.remove();
      const { open } = await import('@tauri-apps/plugin-shell');
      await open(link.url);
    });
    picker.appendChild(btn);
  }

  document.body.appendChild(picker);

  // Close picker on click outside
  setTimeout(() => {
    document.addEventListener('click', function handler(e) {
      if (!picker.contains(e.target as Node)) {
        picker.remove();
        document.removeEventListener('click', handler);
      }
    });
  }, 100);
}

function showCallBackOption() {
  // Don't show if there's already a call-back button
  if (bubblesContainer.querySelector('.call-back-btn')) return;

  const el = document.createElement('div');
  el.className = 'bubble call-back-btn';
  el.innerHTML = `<span style="cursor:pointer;pointer-events:auto;font-size:11px;background:rgba(30,30,30,0.9);color:white;padding:4px 10px;border-radius:8px;font-family:'Nunito',sans-serif;">Call back</span>`;
  el.style.cssText = 'position:absolute;left:50%;top:55px;transform:translateX(-50%);pointer-events:auto;cursor:pointer;';
  el.onclick = () => {
    el.remove();
    hasMissedCall = false;
    bubblesContainer.querySelectorAll('.missed-call-indicator').forEach(e => e.remove());
    doCall();
  };
  bubblesContainer.appendChild(el);
}

async function doHide() {
  await emit('buddy-hide-friend', { friendId });
}

async function doRemove() {
  await emit('buddy-remove-friend', { friendId });
}

function showToast(message: string) {
  const existing = document.querySelector('.toast');
  if (existing) existing.remove();

  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = message;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 3000);
}

// -- Context menu --

owlContainer.addEventListener('contextmenu', (e) => {
  e.preventDefault();
  contextMenu.classList.remove('hidden');
  contextMenu.style.left = `${Math.min(e.clientX, window.innerWidth - 160)}px`;
  contextMenu.style.top = `${Math.min(e.clientY, window.innerHeight - 140)}px`;
});

document.addEventListener('click', () => {
  contextMenu.classList.add('hidden');
});

contextMenu.addEventListener('click', (e) => {
  const target = e.target as HTMLElement;
  const action = target.dataset.action;
  contextMenu.classList.add('hidden');

  switch (action) {
    case 'wave': doWave(); break;
    case 'chat': openChat(); break;
    case 'call': doCall(); break;
    case 'hide': doHide(); break;
    case 'remove': doRemove(); break;
  }
});

// Single click = bounce
owlContainer.addEventListener('click', () => {
  owlContainer.classList.remove('bouncing');
  // Force reflow
  void owlContainer.offsetWidth;
  owlContainer.classList.add('bouncing');
  setTimeout(() => owlContainer.classList.remove('bouncing'), 350);
});

// Double click = wave
let clickCount = 0;
let clickTimer: ReturnType<typeof setTimeout> | null = null;
owlContainer.addEventListener('click', () => {
  clickCount++;
  if (clickCount === 1) {
    clickTimer = setTimeout(() => { clickCount = 0; }, 300);
  } else if (clickCount === 2) {
    if (clickTimer) clearTimeout(clickTimer);
    clickCount = 0;
    doWave();
  }
});

// -- Tauri event listeners --

// Friend status update (state, availability changes)
listen<{ friend: FriendStatus }>(`buddy-friend-updated-${friendId}`, (event) => {
  const f = event.payload.friend;
  updateState(f.activityState);
  updateAvailability(f.isAvailable);
  nameText.textContent = f.displayName;
});

// Wave received from this friend — play animation only (no emoji).
// The emoji is shown locally when YOU wave at them (in doWave), matching macOS behavior.
listen<{ fromUserId: string }>('buddy-wave-received', (event) => {
  if (event.payload.fromUserId === friendId) {
    playWaveAnimation();
  }
});

// Chat message received from this friend
listen<{ message: ChatMessage }>('buddy-message-received', (event) => {
  const msg = event.payload.message;
  if (msg.fromUserId === friendId) {
    showChatBubble(msg.message);
  }
});

// Call received from this friend
listen<{ fromUserId: string; fromDisplayName: string }>('buddy-call-received', (event) => {
  if (event.payload.fromUserId === friendId) {
    showIndicatorBubble('\u{1F4DE}', 60, 25, 3000);
    hasMissedCall = true;
    // After call bubble fades, show "Call back" option
    setTimeout(() => {
      showMissedCallIndicator();
      showCallBackOption();
    }, 3500);
  }
});

// Chat opened for this friend — clear unread
listen<{ friendId: string }>('buddy-chat-opened', (event) => {
  if (event.payload.friendId === friendId) {
    clearUnread();
  }
});

// Start blink loop
scheduleBlink();
if (currentState === 'asleep') startBreathing();

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}
