// Buddy shared types — mirrors Swift models and worker API shapes

// Activity state enum matching BuddyState.swift
export type BuddyState = 'active' | 'idle' | 'asleep';

// Friend status from GET /friends
export interface FriendStatus {
  userId: string;
  displayName: string;
  characterType: string;
  activityState: string;
  isAvailable: boolean;
  lastSeen: number;
  facetimeContact?: string;
}

// Event from GET /events or SSE
export interface BuddyEvent {
  id: string;
  fromUserId: string;
  fromDisplayName: string;
  toUserId: string;
  eventType: string; // "wave" | "call"
  timestamp: number;
}

// Chat message from GET /messages or SSE
export interface ChatMessage {
  id: string;
  fromUserId: string;
  fromDisplayName: string;
  toUserId: string;
  message: string;
  timestamp: number;
}

// API response types matching worker shapes
export interface FriendsResponse {
  friends: FriendStatus[];
}

export interface EventsResponse {
  events: BuddyEvent[];
}

export interface MessagesResponse {
  messages: ChatMessage[];
}

export interface RegisterResponse {
  userId: string;
  friendCode: string;
  displayName: string;
}

export interface AddFriendResponse {
  ok: boolean;
  friend?: FriendStatus;
}

export interface GenericResponse {
  ok?: boolean;
  error?: string;
}

// Call link for multi-method calling
export interface CallLink {
  label: string;
  url: string;
}

export function parseCallLinks(contactString: string | null | undefined): CallLink[] {
  if (!contactString) return [];
  // Try JSON array format
  if (contactString.startsWith('[')) {
    try { return JSON.parse(contactString) as CallLink[]; } catch {}
  }
  // Legacy: single string — auto-migrate
  if (contactString.includes('@') || /^\+?\d/.test(contactString)) {
    return [{ label: 'FaceTime', url: `facetime://${contactString}` }];
  }
  if (contactString.startsWith('https://wa.me')) {
    return [{ label: 'WhatsApp', url: contactString }];
  }
  return [{ label: 'Call', url: contactString }];
}

// Event names matching NSNotification.Name equivalents
export const BuddyEvents = {
  INCOMING_WAVE: 'buddyIncomingWave',
  FRIEND_WAVED: 'buddyFriendWaved',
  INCOMING_MESSAGE: 'buddyIncomingMessage',
  OPEN_CHAT: 'buddyOpenChat',
  FRIEND_WAVE_RECEIVED: 'buddyFriendWaveReceived',
  INCOMING_CALL: 'buddyIncomingCall',
  FRIENDS_UPDATED: 'buddyFriendsUpdated',
  STATE_CHANGED: 'buddyStateChanged',
} as const;
