// Friend Panel Manager — creates/destroys transparent Tauri windows for each online friend
// Mirrors FriendPanelManager.swift behavior

import { WebviewWindow } from '@tauri-apps/api/webviewWindow';
import { emit, listen } from '@tauri-apps/api/event';
import { currentMonitor } from '@tauri-apps/api/window';
import { open } from '@tauri-apps/plugin-shell';
import type { FriendStatus, ChatMessage } from './types';
import { BuddyEvents } from './types';
import { PresenceManager } from './presence';

const PANEL_WIDTH = 160;
const PANEL_HEIGHT = 200;
const PANEL_SPACING = 20;
const PANEL_BOTTOM_MARGIN = 20;
const PANEL_RIGHT_MARGIN = 40;

export class FriendPanelManager {
  private panels = new Map<string, WebviewWindow>();
  private chatWindows = new Map<string, WebviewWindow>();
  private presence: PresenceManager;
  private chatHistory = new Map<string, ChatMessage[]>();

  constructor(presence: PresenceManager) {
    this.presence = presence;
  }

  start() {
    // Listen for friend list updates from presence manager
    this.presence.addEventListener(BuddyEvents.FRIENDS_UPDATED, ((ev: CustomEvent) => {
      const { friends } = ev.detail as { friends: FriendStatus[] };
      this.syncPanels(friends);
    }) as EventListener);

    // Listen for incoming waves
    this.presence.addEventListener(BuddyEvents.INCOMING_WAVE, ((ev: CustomEvent) => {
      const { event } = ev.detail;
      emit('buddy-wave-received', { fromUserId: event.fromUserId });
    }) as EventListener);

    // Listen for incoming messages — route to chat window or friend panel
    this.presence.addEventListener(BuddyEvents.INCOMING_MESSAGE, ((ev: CustomEvent) => {
      const { message } = ev.detail as { message: ChatMessage };
      // Store in history
      if (!this.chatHistory.has(message.fromUserId)) {
        this.chatHistory.set(message.fromUserId, []);
      }
      this.chatHistory.get(message.fromUserId)!.push(message);

      // Broadcast to all windows (friend panels + chat windows will filter by friendId)
      emit('buddy-message-received', { message });
    }) as EventListener);

    // Listen for incoming calls
    this.presence.addEventListener(BuddyEvents.INCOMING_CALL, ((ev: CustomEvent) => {
      const { fromUserId, fromDisplayName } = ev.detail;
      emit('buddy-call-received', { fromUserId, fromDisplayName });
    }) as EventListener);

    // Listen for action events from friend windows
    listen<{ toUserId: string }>('buddy-send-wave', async (event) => {
      await this.presence.sendWave(event.payload.toUserId);
    });

    listen<{ toUserId: string; message: string }>('buddy-send-message', async (event) => {
      await this.presence.sendMessage(event.payload.toUserId, event.payload.message);
    });

    listen<{ toUserId: string }>('buddy-send-call', async (event) => {
      await this.presence.sendCallRequest(event.payload.toUserId);
    });

    listen<{ friendId: string }>('buddy-remove-friend', async (event) => {
      await this.presence.removeFriend(event.payload.friendId);
    });

    // Listen for chat open requests
    listen<{ friendId: string; displayName: string }>('buddy-open-chat', (event) => {
      this.openChatWindow(event.payload.friendId, event.payload.displayName);
    });

    // Listen for chat opened events (from chat windows)
    listen<{ friendId: string }>('buddy-chat-opened', (event) => {
      const fId = event.payload.friendId;
      // Send any pending history
      const history = this.chatHistory.get(fId) ?? [];
      if (history.length > 0) {
        emit(`buddy-chat-history-${fId}`, { messages: history });
      }
      // Notify friend panel to clear unread
      emit('buddy-chat-opened', { friendId: fId });
    });

    // Initial sync
    if (this.presence.friends.length > 0) {
      this.syncPanels(this.presence.friends);
    }
  }

  stop() {
    for (const [id, panel] of this.panels) {
      panel.close();
    }
    this.panels.clear();
    for (const [id, win] of this.chatWindows) {
      win.close();
    }
    this.chatWindows.clear();
  }

  private async syncPanels(friends: FriendStatus[]) {
    const currentFriendIds = new Set(friends.map(f => f.userId));
    const existingIds = new Set(this.panels.keys());

    // Remove panels for friends that went offline
    for (const id of existingIds) {
      if (!currentFriendIds.has(id)) {
        const panel = this.panels.get(id);
        if (panel) {
          // Animate out would be nice but just close for now
          panel.close();
          this.panels.delete(id);
        }
      }
    }

    // Create panels for new online friends
    let index = 0;
    for (const friend of friends) {
      if (!existingIds.has(friend.userId)) {
        await this.createFriendPanel(friend, this.panels.size);
      } else {
        // Update existing panel's friend data
        emit(`buddy-friend-updated-${friend.userId}`, { friend });
      }
      index++;
    }
  }

  private async createFriendPanel(friend: FriendStatus, index: number) {
    const pos = await this.positionForPanel(index);
    const label = `friend-${friend.userId.slice(0, 8)}`;

    // Build URL with friend data as query params
    const params = new URLSearchParams({
      friendId: friend.userId,
      displayName: friend.displayName,
      characterType: friend.characterType,
      activityState: friend.activityState,
      isAvailable: String(friend.isAvailable),
      facetimeContact: friend.facetimeContact ?? '',
    });

    try {
      const panel = new WebviewWindow(label, {
        url: `friend.html?${params.toString()}`,
        title: friend.displayName,
        width: PANEL_WIDTH,
        height: PANEL_HEIGHT,
        x: pos.x,
        y: pos.y,
        transparent: true,
        decorations: false,
        alwaysOnTop: true,
        skipTaskbar: true,
        resizable: false,
      });

      // Track close
      panel.onCloseRequested(() => {
        this.panels.delete(friend.userId);
      });

      this.panels.set(friend.userId, panel);
      console.log(`[FPM] Created panel for ${friend.displayName} at (${pos.x}, ${pos.y})`);
    } catch (err) {
      console.error(`[FPM] Failed to create panel for ${friend.displayName}:`, err);
    }
  }

  private async positionForPanel(index: number): Promise<{ x: number; y: number }> {
    try {
      const monitor = await currentMonitor();
      if (monitor) {
        const screen = monitor.size;
        const x = screen.width - PANEL_RIGHT_MARGIN - PANEL_WIDTH - index * (PANEL_WIDTH + PANEL_SPACING);
        const y = screen.height - PANEL_BOTTOM_MARGIN - PANEL_HEIGHT;
        return { x: Math.max(0, x), y: Math.max(0, y) };
      }
    } catch {
      // fallback
    }
    return { x: 400 + index * (PANEL_WIDTH + PANEL_SPACING), y: 100 };
  }

  async openChatWindow(friendId: string, displayName: string) {
    // If already open, focus it
    const existing = this.chatWindows.get(friendId);
    if (existing) {
      try {
        await existing.setFocus();
        return;
      } catch {
        // Window may have been closed externally
        this.chatWindows.delete(friendId);
      }
    }

    const label = `chat-${friendId.slice(0, 8)}`;
    const params = new URLSearchParams({
      friendId,
      displayName,
      myUserId: this.presence.userId ?? '',
    });

    try {
      const chatWin = new WebviewWindow(label, {
        url: `chat.html?${params.toString()}`,
        title: `Chat with ${displayName}`,
        width: 320,
        height: 480,
        decorations: true,
        transparent: false,
        alwaysOnTop: true,
        resizable: true,
        minWidth: 240,
        minHeight: 300,
      });

      chatWin.onCloseRequested(() => {
        this.chatWindows.delete(friendId);
      });

      this.chatWindows.set(friendId, chatWin);
      console.log(`[FPM] Opened chat with ${displayName}`);
    } catch (err) {
      console.error(`[FPM] Failed to open chat with ${displayName}:`, err);
    }
  }
}
