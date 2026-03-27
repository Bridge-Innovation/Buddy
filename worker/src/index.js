// Buddy Presence Server — Cloudflare Worker + KV

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

      if (method === "POST" && path === "/register") {
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

      // Attach CORS headers
      for (const [key, value] of Object.entries(corsHeaders)) {
        result.headers.set(key, value);
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

  // Index friend code → userId for lookup
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

  // Append to recipient's event queue
  const eventsKey = `events:${toUserId}`;
  const existing = (await env.KV.get(eventsKey, "json")) || [];
  existing.push(event);
  await env.KV.put(eventsKey, JSON.stringify(existing));

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

  const messagesKey = `messages:${toUserId}`;
  const existing = (await env.KV.get(messagesKey, "json")) || [];
  existing.push(msg);
  await env.KV.put(messagesKey, JSON.stringify(existing));

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
