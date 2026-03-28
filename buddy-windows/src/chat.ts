// Chat window — one per friend conversation
// Receives friend data via URL params, uses Tauri events for messaging

import { listen, emit } from '@tauri-apps/api/event';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';
import type { ChatMessage } from './types';

// Parse friend info from URL params
const params = new URLSearchParams(window.location.search);
const friendId = params.get('friendId') ?? '';
const friendName = params.get('displayName') ?? '';
const myUserId = params.get('myUserId') ?? '';

// DOM refs
const headerName = document.getElementById('header-name')!;
const messagesContainer = document.getElementById('messages')!;
const messageInput = document.getElementById('message-input') as HTMLInputElement;
const sendBtn = document.getElementById('send-btn') as HTMLButtonElement;

// State
const messages: ChatMessage[] = [];

// Initialize
headerName.textContent = `Chat with ${friendName}`;
document.title = `Chat with ${friendName}`;

// -- Rendering --

function renderMessage(msg: ChatMessage) {
  const isMe = msg.fromUserId === myUserId;

  const row = document.createElement('div');
  row.className = `message-row ${isMe ? 'sent' : 'received'}`;

  const bubble = document.createElement('div');
  bubble.className = 'message-bubble';
  bubble.textContent = msg.message;

  const time = document.createElement('div');
  time.className = 'message-time';
  time.textContent = formatTime(msg.timestamp);

  const wrapper = document.createElement('div');
  wrapper.appendChild(bubble);
  wrapper.appendChild(time);

  row.appendChild(wrapper);
  messagesContainer.appendChild(row);

  // Auto-scroll to bottom
  requestAnimationFrame(() => {
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
  });
}

function formatTime(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}

// -- Sending --

async function sendMessage() {
  const text = messageInput.value.trim();
  if (!text) return;

  messageInput.value = '';
  sendBtn.disabled = true;

  // Create local message
  const msg: ChatMessage = {
    id: crypto.randomUUID(),
    fromUserId: myUserId,
    fromDisplayName: 'Me',
    toUserId: friendId,
    message: text,
    timestamp: Date.now(),
  };

  messages.push(msg);
  renderMessage(msg);

  // Send via presence manager (through main window)
  await emit('buddy-send-message', { toUserId: friendId, message: text });
}

messageInput.addEventListener('input', () => {
  sendBtn.disabled = messageInput.value.trim().length === 0;
});

messageInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
});

sendBtn.addEventListener('click', () => sendMessage());

// -- Receiving --

listen<{ message: ChatMessage }>('buddy-message-received', (event) => {
  const msg = event.payload.message;
  if (msg.fromUserId === friendId) {
    // Avoid duplicates
    if (!messages.some(m => m.id === msg.id)) {
      messages.push(msg);
      renderMessage(msg);
    }
  }
});

// Load any pending messages that arrived before the window opened
listen<{ messages: ChatMessage[] }>(`buddy-chat-history-${friendId}`, (event) => {
  for (const msg of event.payload.messages) {
    if (!messages.some(m => m.id === msg.id)) {
      messages.push(msg);
      renderMessage(msg);
    }
  }
});

// Notify main window that chat is open (so it can clear unread, send history)
emit('buddy-chat-opened', { friendId });

// Close button
document.getElementById('close-btn')!.addEventListener('click', async () => {
  await getCurrentWebviewWindow().close();
});

// Focus the input
messageInput.focus();
