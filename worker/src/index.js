// Buddy Presence Server — Cloudflare Worker + KV + Durable Objects (SSE)

// --- Durable Object: UserChannel ---
// Holds open SSE connections for a given userId and pushes events/messages in real time.

export class UserChannel {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.connections = new Set();
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/connect") {
      return this.handleSSE(request);
    }

    if (url.pathname === "/push") {
      const data = await request.json();
      this.broadcast(data);
      return new Response("ok");
    }

    return new Response("not found", { status: 404 });
  }

  handleSSE(request) {
    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    const encoder = new TextEncoder();

    const conn = { writer, encoder, closed: false };
    this.connections.add(conn);

    // Send initial keepalive so the client knows the connection is live
    writer.write(encoder.encode(":ok\n\n")).catch(() => {});

    // Keepalive every 30s to prevent proxy/client timeouts
    const keepalive = setInterval(() => {
      if (conn.closed) {
        clearInterval(keepalive);
        return;
      }
      writer.write(encoder.encode(":keepalive\n\n")).catch(() => {
        conn.closed = true;
        this.connections.delete(conn);
        clearInterval(keepalive);
      });
    }, 30000);

    // Clean up when the client disconnects
    request.signal?.addEventListener("abort", () => {
      conn.closed = true;
      this.connections.delete(conn);
      clearInterval(keepalive);
      writer.close().catch(() => {});
    });

    return new Response(readable, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }

  broadcast(data) {
    const payload = `data: ${JSON.stringify(data)}\n\n`;
    for (const conn of this.connections) {
      if (conn.closed) {
        this.connections.delete(conn);
        continue;
      }
      conn.writer.write(conn.encoder.encode(payload)).catch(() => {
        conn.closed = true;
        this.connections.delete(conn);
      });
    }
  }
}

// --- Helper to get a user's Durable Object stub ---

function getUserChannel(env, userId) {
  const id = env.USER_CHANNEL.idFromName(userId);
  return env.USER_CHANNEL.get(id);
}

// --- Push to a user's SSE stream (best-effort, non-blocking) ---

async function pushToStream(env, userId, payload) {
  try {
    const stub = getUserChannel(env, userId);
    await stub.fetch(new Request("https://internal/push", {
      method: "POST",
      body: JSON.stringify(payload),
    }));
  } catch (e) {
    // SSE push is best-effort; KV is the fallback
    console.error("[SSE push failed]", e.message);
  }
}

// --- Main Worker ---

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // CORS headers for all responses
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    if (method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      let result;

      if (method === "GET" && path === "/stream") {
        result = await handleStream(url, env);
      } else if (method === "POST" && path === "/register") {
        result = await handleRegister(request, env);
      } else if (method === "POST" && path === "/status") {
        result = await handleStatus(request, env);
      } else if (method === "GET" && path === "/friends") {
        result = await handleGetFriends(url, env);
      } else if (method === "POST" && path === "/friends/add") {
        result = await handleAddFriend(request, env);
      } else if (method === "POST" && path === "/friends/remove") {
        result = await handleRemoveFriend(request, env);
      } else if (method === "POST" && path === "/profile/update") {
        result = await handleProfileUpdate(request, env);
      } else if (method === "POST" && path === "/events/send") {
        result = await handleSendEvent(request, env);
      } else if (method === "GET" && path === "/events") {
        result = await handleGetEvents(url, env);
      } else if (method === "POST" && path === "/messages/send") {
        result = await handleSendMessage(request, env);
      } else if (method === "GET" && path === "/messages") {
        result = await handleGetMessages(url, env);
      } else {
        result = json({ error: "Not found" }, 404);
      }

      // Attach CORS headers (skip for SSE — already has its own headers)
      if (!result.headers.get("Content-Type")?.includes("text/event-stream")) {
        for (const [key, value] of Object.entries(corsHeaders)) {
          result.headers.set(key, value);
        }
      }
      return result;
    } catch (err) {
      return json({ error: err.message }, 500);
    }
  },
};

// --- Helpers ---

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function generateUUID() {
  return crypto.randomUUID();
}

function generateFriendCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no ambiguous chars
  let code = "";
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  for (let i = 0; i < 6; i++) {
    code += chars[bytes[i] % chars.length];
  }
  return code;
}

async function getUser(env, userId) {
  const data = await env.KV.get(`user:${userId}`, "json");
  return data;
}

async function putUser(env, user) {
  await env.KV.put(`user:${user.userId}`, JSON.stringify(user));
}

// --- Handlers ---

async function handleStream(url, env) {
  const userId = url.searchParams.get("userId");
  if (!userId) {
    return json({ error: "userId required" }, 400);
  }

  // Proxy the request to the user's Durable Object for SSE
  const stub = getUserChannel(env, userId);
  return stub.fetch(new Request("https://internal/connect", {
    headers: { "Upgrade": "websocket" },
    signal: undefined,
  }));
}

async function handleRegister(request, env) {
  const body = await request.json().catch(() => ({}));
  const displayName = body.displayName || "Buddy";
  const characterType = body.characterType || "owl";
  const facetimeContact = body.facetimeContact || "";

  const userId = generateUUID();
  const friendCode = generateFriendCode();

  const user = {
    userId,
    displayName,
    friendCode,
    characterType,
    facetimeContact,
    activityState: "active",
    isAvailable: false,
    lastSeen: Date.now(),
    friends: [],
  };

  await putUser(env, user);

  // Index friend code -> userId for lookup
  await env.KV.put(`friendcode:${friendCode}`, userId);

  return json({ userId, friendCode, displayName });
}

async function handleStatus(request, env) {
  const body = await request.json();
  const { userId, activityState, isAvailable, characterType } = body;

  if (!userId) return json({ error: "userId required" }, 400);

  const user = await getUser(env, userId);
  if (!user) return json({ error: "User not found" }, 404);

  if (activityState) user.activityState = activityState;
  if (isAvailable !== undefined) user.isAvailable = isAvailable;
  if (characterType) user.characterType = characterType;
  user.lastSeen = Date.now();

  await putUser(env, user);

  return json({ ok: true });
}

async function handleGetFriends(url, env) {
  const userId = url.searchParams.get("userId");
  if (!userId) return json({ error: "userId required" }, 400);

  const user = await getUser(env, userId);
  if (!user) return json({ error: "User not found" }, 404);

  const PRESENCE_TIMEOUT_MS = 2 * 60 * 1000; // 2 minutes
  const now = Date.now();

  const friends = [];
  for (const friendId of user.friends) {
    const friend = await getUser(env, friendId);
    if (friend && (now - friend.lastSeen) < PRESENCE_TIMEOUT_MS) {
      friends.push({
        userId: friend.userId,
        displayName: friend.displayName,
        characterType: friend.characterType,
        activityState: friend.activityState,
        isAvailable: friend.isAvailable,
        lastSeen: friend.lastSeen,
        facetimeContact: friend.facetimeContact || "",
      });
    }
  }

  return json({ friends });
}

async function handleAddFriend(request, env) {
  const body = await request.json();
  const { userId, friendCode } = body;

  if (!userId || !friendCode) {
    return json({ error: "userId and friendCode required" }, 400);
  }

  // Look up friend by code
  const friendId = await env.KV.get(`friendcode:${friendCode}`);
  if (!friendId) return json({ error: "Invalid friend code" }, 404);

  if (friendId === userId) {
    return json({ error: "Cannot add yourself" }, 400);
  }

  const user = await getUser(env, userId);
  const friend = await getUser(env, friendId);
  if (!user || !friend) return json({ error: "User not found" }, 404);

  // Mutual add
  if (!user.friends.includes(friendId)) {
    user.friends.push(friendId);
    await putUser(env, user);
  }
  if (!friend.friends.includes(userId)) {
    friend.friends.push(userId);
    await putUser(env, friend);
  }

  return json({
    ok: true,
    friend: {
      userId: friend.userId,
      displayName: friend.displayName,
      characterType: friend.characterType,
      activityState: friend.activityState,
      isAvailable: friend.isAvailable,
    },
  });
}

async function handleRemoveFriend(request, env) {
  const body = await request.json();
  const { userId, friendId } = body;

  if (!userId || !friendId) {
    return json({ error: "userId and friendId required" }, 400);
  }

  const user = await getUser(env, userId);
  const friend = await getUser(env, friendId);
  if (!user) return json({ error: "User not found" }, 404);

  // Mutual remove
  user.friends = user.friends.filter((id) => id !== friendId);
  await putUser(env, user);

  if (friend) {
    friend.friends = friend.friends.filter((id) => id !== userId);
    await putUser(env, friend);
  }

  return json({ ok: true });
}

async function handleProfileUpdate(request, env) {
  const body = await request.json();
  const { userId, displayName, facetimeContact } = body;

  if (!userId) return json({ error: "userId required" }, 400);

  const user = await getUser(env, userId);
  if (!user) return json({ error: "User not found" }, 404);

  if (displayName !== undefined) user.displayName = displayName;
  if (facetimeContact !== undefined) user.facetimeContact = facetimeContact;

  await putUser(env, user);

  return json({ ok: true });
}

async function handleSendEvent(request, env) {
  const body = await request.json();
  const { fromUserId, toUserId, eventType } = body;

  if (!fromUserId || !toUserId || !eventType) {
    return json({ error: "fromUserId, toUserId, and eventType required" }, 400);
  }

  const fromUser = await getUser(env, fromUserId);
  if (!fromUser) return json({ error: "Sender not found" }, 404);

  const event = {
    id: generateUUID(),
    fromUserId,
    fromDisplayName: fromUser.displayName,
    toUserId,
    eventType,
    timestamp: Date.now(),
  };

  // Write to KV (fallback for offline clients)
  const eventsKey = `events:${toUserId}`;
  const existing = (await env.KV.get(eventsKey, "json")) || [];
  existing.push(event);
  await env.KV.put(eventsKey, JSON.stringify(existing));

  // Push to SSE stream (real-time fast path)
  await pushToStream(env, toUserId, { type: "event", payload: event });

  return json({ ok: true, eventId: event.id });
}

async function handleGetEvents(url, env) {
  const userId = url.searchParams.get("userId");
  if (!userId) return json({ error: "userId required" }, 400);

  const eventsKey = `events:${userId}`;
  const events = (await env.KV.get(eventsKey, "json")) || [];

  // Clear after reading
  if (events.length > 0) {
    await env.KV.delete(eventsKey);
  }

  return json({ events });
}

async function handleSendMessage(request, env) {
  const body = await request.json();
  const { fromUserId, toUserId, message } = body;

  if (!fromUserId || !toUserId || !message) {
    return json({ error: "fromUserId, toUserId, and message required" }, 400);
  }

  const fromUser = await getUser(env, fromUserId);
  if (!fromUser) return json({ error: "Sender not found" }, 404);

  const msg = {
    id: generateUUID(),
    fromUserId,
    fromDisplayName: fromUser.displayName,
    toUserId,
    message,
    timestamp: Date.now(),
  };

  // Write to KV (fallback)
  const messagesKey = `messages:${toUserId}`;
  const existing = (await env.KV.get(messagesKey, "json")) || [];
  existing.push(msg);
  await env.KV.put(messagesKey, JSON.stringify(existing));

  // Push to SSE stream (real-time fast path)
  await pushToStream(env, toUserId, { type: "message", payload: msg });

  return json({ ok: true, messageId: msg.id });
}

async function handleGetMessages(url, env) {
  const userId = url.searchParams.get("userId");
  if (!userId) return json({ error: "userId required" }, 400);

  const messagesKey = `messages:${userId}`;
  const messages = (await env.KV.get(messagesKey, "json")) || [];

  if (messages.length > 0) {
    await env.KV.delete(messagesKey);
  }

  return json({ messages });
}
