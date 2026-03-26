# Buddy — Status

**Last updated:** 25 March 2026

---

## Right Now

Phase 1 complete. Phase 2 backend and networking substantially complete. All character art for MVP is drawn and integrated.

**What's working:**
- Floating transparent owl on desktop with full animation system: blinking, drowsy idle, asleep with breathing + floating z's, wave gesture on click, available glow
- Activity detection driving state transitions with smooth crossfades
- Cloudflare Worker deployed at `https://buddy-presence.sarahgilmore.workers.dev` — all endpoints tested and working
- PresenceManager in app: registers on first launch, sends heartbeats every 30s, polls friends/events every 5s
- Friend management: add by code, friend list in menu bar dropdown
- Menu bar shows friend code, friends list, available toggle

**What's left for testing with Tyler:**
- Friend avatars appearing on the desktop (Step 3)
- Wave events triggering visual animations (Step 4)
- Tyler cloning and building the project on his Mac

---

## Next Steps

### Claude Code — friend avatars and wave events (Step 3 & 4)

**Step 3: Friend avatars on desktop**

> When a friend comes online (their status shows active or idle in the friends poll), spawn their avatar as a separate floating NSPanel on the desktop — same transparent, borderless, always-on-top setup as the user's own character. Use the same owl images for now.
>
> Position friend avatars along the bottom of the screen or near the menu bar area. Each friend gets their own panel.
>
> The friend's avatar should reflect their current state — use the same animation system (blinking when active, drowsy when idle, asleep breathing when asleep, green glow when available).
>
> When a friend goes offline (lastSeen older than 2 minutes, or they disappear from the friends list), remove their avatar panel from the desktop.
>
> Show the friend's display name in small text below their avatar.

**Step 4: Wave interaction over the network**

> Wire up the wave event system end-to-end:
>
> 1. Double-clicking a friend's avatar on the desktop calls PresenceManager.sendWave(to: friendId)
> 2. When the events poll returns a wave event, trigger the wave animation on the user's own owl character (the same low → med → high → med → high → med → low sequence) and play a subtle system sound (NSSound.beep() or a custom short sound)
> 3. After receiving a wave, show a small visual indicator on the friend's avatar who waved (a small chat bubble or heart that fades after a few seconds) so the user knows who waved
> 4. Consume the event after displaying it so it doesn't repeat

### Also fix
- Owl display size — panel needs to increase to compensate for canvas change from 500px to 800px
- Presence timeout — if a user's lastSeen is older than 2 minutes, treat them as offline on the friends endpoint

### To test with Tyler
1. Push project to GitHub
2. Tyler clones and builds in Xcode
3. Both launch, share friend codes, add each other
4. Test: seeing each other's owls, waving, availability indicators

---

## Known Issues

- Only the active state has real character art — idle, asleep, and available are still using placeholder or active images
- No networking yet — app is purely local
- Tyler will need to clone and build the project from Xcode to test

---

## Session Log

### Session 2 — 25 March 2026
- Phase 1 app shell complete: floating transparent panel, activity detection, menu bar dropdown, state machine all working
- Explored character design in Midjourney: hamster and owl directions
- Chose owl as primary character
- Hand-drew owl from scratch in Affinity Designer on iPad with separated body parts on layers
- Created three blink frames (open, half, closed) and integrated into app
- Owl is live on desktop with blinking animation
- Updated interaction model: friends' avatars appear on your desktop, double-click to wave, escalate to chat/call
- Mapped out Phase 2 backend requirements for testing between Sarah and Tyler
- Updated all project docs to reflect new interaction model and FaceTime for MVP calls

### Session 1 — 24 March 2026
- Defined product concept: desktop companion character for coworking presence
- Decided on tech stack: native macOS SwiftUI + AppKit hybrid
- Created four character states: active, idle, asleep, available
- Created project documents: PRODUCT, ROADMAP, STATUS, ARCHITECTURE
- Created character concept visualization showing the four states
- Ready to begin Phase 1 development
