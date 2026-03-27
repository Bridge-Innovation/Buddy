// Presence API client + SSE — mirrors PresenceManager.swift

import type {
  BuddyState,
  FriendStatus,
  BuddyEvent,
  ChatMessage,
  FriendsResponse,
  EventsResponse,
  MessagesResponse,
  RegisterResponse,
  AddFriendResponse,
  GenericResponse,
} from './types';
import { BuddyEvents } from './types';

export class PresenceManager extends EventTarget {
  private baseURL: string;
  private _userId: string | null = null;
  private _friendCode: string | null = null;
  private _friends: FriendStatus[] = [];
  private _pendingEvents: BuddyEvent[] = [];
  private _incomingMessages: ChatMessage[] = [];

  private statusTimer: ReturnType<typeof setInterval> | null = null;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private eventSource: EventSource | null = null;
  private sseRetryCount = 0;
  private sseReconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly sseMaxRetryDelay = 60_000;

  get userId() { return this._userId; }
  get friendCode() { return this._friendCode; }
  get friends() { return this._friends; }
  get pendingEvents() { return this._pendingEvents; }
  get incomingMessages() { return this._incomingMessages; }

  constructor(baseURL = 'https://buddy-presence.sarahgilmore.workers.dev') {
    super();
    this.baseURL = baseURL;
  }

  // -- Lifecycle --

  start(userId?: string | null, friendCode?: string | null) {
    if (userId) this._userId = userId;
    if (friendCode) this._friendCode = friendCode;

    if (!this._userId) {
      this.register().then(() => {
        this.startStatusUpdates();
        this.startPolling();
        this.connectSSE();
      });
    } else {
      this.startStatusUpdates();
      this.startPolling();
      this.connectSSE();
    }
  }

  stop() {
    if (this.statusTimer) { clearInterval(this.statusTimer); this.statusTimer = null; }
    if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
    this.disconnectSSE();
  }

  // -- Registration --

  async register(displayName?: string): Promise<RegisterResponse | null> {
    const name = displayName || 'Buddy User';
    const resp = await this.post<RegisterResponse>('/register', { displayName: name });
    if (resp) {
      this._userId = resp.userId;
      this._friendCode = resp.friendCode;
    }
    return resp;
  }

  // -- Status heartbeat (60s) --

  private startStatusUpdates() {
    this.sendStatus();
    this.pollFriends();
    this.statusTimer = setInterval(() => {
      this.sendStatus();
      this.pollFriends();
    }, 60_000);
  }

  async sendStatus(
    activityState?: BuddyState,
    isAvailable?: boolean,
    characterType?: string,
  ) {
    if (!this._userId) return;
    await this.post<GenericResponse>('/status', {
      userId: this._userId,
      activityState: activityState ?? 'active',
      isAvailable: isAvailable ?? false,
      characterType: characterType ?? 'owl',
    });
  }

  // -- Polling (10s fallback) --

  private startPolling() {
    this.pollEvents();
    this.pollTimer = setInterval(() => this.pollEvents(), 10_000);
  }

  private async pollFriends() {
    if (!this._userId) return;
    const resp = await this.get<FriendsResponse>(`/friends?userId=${this._userId}`);
    if (resp) {
      this._friends = resp.friends;
      this.emit(BuddyEvents.FRIENDS_UPDATED, { friends: resp.friends });
    }
  }

  async getFriends(): Promise<FriendStatus[]> {
    if (!this._userId) return [];
    const resp = await this.get<FriendsResponse>(`/friends?userId=${this._userId}`);
    if (resp) {
      this._friends = resp.friends;
      this.emit(BuddyEvents.FRIENDS_UPDATED, { friends: resp.friends });
    }
    return this._friends;
  }

  private async pollEvents() {
    if (!this._userId) return;

    const [evResp, msgResp] = await Promise.all([
      this.get<EventsResponse>(`/events?userId=${this._userId}`),
      this.get<MessagesResponse>(`/messages?userId=${this._userId}`),
    ]);

    if (evResp && evResp.events.length > 0) {
      for (const event of evResp.events) {
        if (!this._pendingEvents.some(e => e.id === event.id)) {
          this._pendingEvents.push(event);
          this.emitBuddyEvent(event);
        }
      }
    }

    if (msgResp && msgResp.messages.length > 0) {
      for (const msg of msgResp.messages) {
        if (!this._incomingMessages.some(m => m.id === msg.id)) {
          this._incomingMessages.push(msg);
          this.emit(BuddyEvents.INCOMING_MESSAGE, { message: msg });
        }
      }
    }
  }

  async getEvents(): Promise<BuddyEvent[]> {
    if (!this._userId) return [];
    const resp = await this.get<EventsResponse>(`/events?userId=${this._userId}`);
    return resp?.events ?? [];
  }

  async getMessages(): Promise<ChatMessage[]> {
    if (!this._userId) return [];
    const resp = await this.get<MessagesResponse>(`/messages?userId=${this._userId}`);
    return resp?.messages ?? [];
  }

  // -- SSE Connection --

  private connectSSE() {
    if (!this._userId) return;
    this.disconnectSSE();

    const url = `${this.baseURL}/stream?userId=${this._userId}`;
    console.log('[Buddy] SSE connecting to', url);

    const es = new EventSource(url);
    this.eventSource = es;

    es.onopen = () => {
      console.log('[Buddy] SSE connected');
      this.sseRetryCount = 0;
    };

    es.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        this.handleSSEData(data);
      } catch {
        // ignore non-JSON messages (keepalive comments etc.)
      }
    };

    es.onerror = () => {
      console.log('[Buddy] SSE error, will reconnect');
      this.disconnectSSE();
      this.scheduleSSEReconnect();
    };
  }

  private disconnectSSE() {
    if (this.eventSource) {
      this.eventSource.close();
      this.eventSource = null;
    }
    if (this.sseReconnectTimer) {
      clearTimeout(this.sseReconnectTimer);
      this.sseReconnectTimer = null;
    }
  }

  private scheduleSSEReconnect() {
    this.sseRetryCount++;
    // Exponential backoff: 1s, 2s, 4s, 8s, ... capped at 60s
    const delay = Math.min(Math.pow(2, this.sseRetryCount - 1) * 1000, this.sseMaxRetryDelay);
    console.log(`[Buddy] SSE reconnecting in ${delay / 1000}s (attempt ${this.sseRetryCount})`);
    this.sseReconnectTimer = setTimeout(() => this.connectSSE(), delay);
  }

  private handleSSEData(data: { type: string; payload: unknown }) {
    if (data.type === 'event') {
      const event = data.payload as BuddyEvent;
      if (!this._pendingEvents.some(e => e.id === event.id)) {
        console.log(`[Buddy] SSE event: ${event.eventType} from ${event.fromDisplayName}`);
        this._pendingEvents.push(event);
        this.emitBuddyEvent(event);
      }
    } else if (data.type === 'message') {
      const msg = data.payload as ChatMessage;
      if (!this._incomingMessages.some(m => m.id === msg.id)) {
        console.log(`[Buddy] SSE message from ${msg.fromDisplayName}`);
        this._incomingMessages.push(msg);
        this.emit(BuddyEvents.INCOMING_MESSAGE, { message: msg });
      }
    }
  }

  private emitBuddyEvent(event: BuddyEvent) {
    if (event.eventType === 'wave') {
      this.emit(BuddyEvents.INCOMING_WAVE, { event });
      this.emit(BuddyEvents.FRIEND_WAVED, { fromUserId: event.fromUserId });
    } else if (event.eventType === 'call') {
      this.emit(BuddyEvents.INCOMING_CALL, {
        fromUserId: event.fromUserId,
        fromDisplayName: event.fromDisplayName,
      });
    }
  }

  // -- Public actions --

  async addFriend(friendCode: string): Promise<FriendStatus | null> {
    if (!this._userId) return null;
    const resp = await this.post<AddFriendResponse>('/friends/add', {
      userId: this._userId,
      friendCode: friendCode.toUpperCase(),
    });
    if (resp?.ok) {
      this.pollFriends();
      return resp.friend ?? null;
    }
    return null;
  }

  async removeFriend(friendId: string) {
    if (!this._userId) return;
    await this.post<GenericResponse>('/friends/remove', {
      userId: this._userId,
      friendId,
    });
    this._friends = this._friends.filter(f => f.userId !== friendId);
    this.emit(BuddyEvents.FRIENDS_UPDATED, { friends: this._friends });
  }

  async sendWave(toUserId: string) {
    if (!this._userId) return;
    await this.post<GenericResponse>('/events/send', {
      fromUserId: this._userId,
      toUserId,
      eventType: 'wave',
    });
  }

  async sendCallRequest(toUserId: string) {
    if (!this._userId) return;
    await this.post<GenericResponse>('/events/send', {
      fromUserId: this._userId,
      toUserId,
      eventType: 'call',
    });
  }

  async sendMessage(toUserId: string, message: string) {
    if (!this._userId) return;
    await this.post<GenericResponse>('/messages/send', {
      fromUserId: this._userId,
      toUserId,
      message,
    });
  }

  async updateProfile(displayName: string, facetimeContact: string) {
    if (!this._userId) return;
    await this.post<GenericResponse>('/profile/update', {
      userId: this._userId,
      displayName,
      facetimeContact,
    });
  }

  consumeEvent(eventId: string) {
    this._pendingEvents = this._pendingEvents.filter(e => e.id !== eventId);
  }

  consumeMessages(fromUserId: string): ChatMessage[] {
    const msgs = this._incomingMessages.filter(m => m.fromUserId === fromUserId);
    this._incomingMessages = this._incomingMessages.filter(m => m.fromUserId !== fromUserId);
    return msgs;
  }

  // -- Networking helpers --

  private async post<T>(path: string, body: Record<string, unknown>): Promise<T | null> {
    try {
      const resp = await fetch(`${this.baseURL}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      return await resp.json() as T;
    } catch (err) {
      console.error(`[Buddy] POST ${path} failed:`, err);
      return null;
    }
  }

  private async get<T>(path: string): Promise<T | null> {
    try {
      const resp = await fetch(`${this.baseURL}${path}`);
      return await resp.json() as T;
    } catch (err) {
      console.error(`[Buddy] GET ${path} failed:`, err);
      return null;
    }
  }

  // -- Event emitter helper --

  private emit(type: string, detail: Record<string, unknown>) {
    this.dispatchEvent(new CustomEvent(type, { detail }));
  }
}
