# Buddy — Project Context for Claude Code

> **This document is the single source of truth for all Claude Code sessions working on this project.**
> It is automatically loaded at the start of every conversation. Keep it current.

**Last updated:** 2026-03-27

---

## What is Buddy?

A desktop companion app that shows a floating animated owl on your screen. It detects when you're working, shows your friends' owls when they're online, and lets you wave, chat, and call each other. Think "coworking presence" — ambient awareness without meetings or scheduling.

**Creator:** Sarah Gilmore (macOS developer, indie project)
**Repo:** https://github.com/Bridge-Innovation/Buddy (public)
**Website:** https://getbuddy.vercel.app
**Backend:** https://buddy-presence.sarahgilmore.workers.dev

---

## Current Version

**macOS:** v1.1.0 (released, signed + notarized, distributed via GitHub Releases)
**Windows:** v1.1.0 (Tauri 2 app scaffolded and feature-complete, not yet built/released)
**Version source of truth:** `/VERSION` file at repo root

---

## Repository Structure

```
Buddy/
  Buddy/                        # macOS app (Swift/SwiftUI)
    BuddyApp.swift              # @main, MenuBarExtra with settings UI
    AppDelegate.swift            # Lifecycle, Sparkle updater, event processing, FaceTime notifications
    CompanionPanel.swift         # Floating transparent NSPanel for user's owl
    CompanionView.swift          # SwiftUI owl animations (blink, breathe, wave, availability dot)
    FriendAvatarView.swift       # Friend owl rendering, context menu, chat bubbles
    FriendPanelManager.swift     # Creates/positions/animates friend owl windows
    ChatManager.swift            # Chat window lifecycle, message routing
    ChatView.swift               # Chat UI (speech bubbles, warm-cream design)
    PresenceManager.swift        # REST + SSE client, all API calls, polling
    ActivityMonitor.swift        # IOKit idle time detection (120s idle, 600s asleep)
    BuddyState.swift             # State enum + notification names
    CharacterTheme.swift         # Character definitions, frame sequences
    AppSettings.swift            # UserDefaults wrapper
    Info.plist                   # Sparkle config (SUFeedURL, SUPublicEDKey)
    Assets.xcassets/             # App icon + owl image assets
    Owl Illustrations/           # Source PNGs (16 frames)
  Buddy.xcodeproj/              # Xcode project (SPM: Sparkle 2)

  buddy-windows/                # Windows app (Tauri 2: Rust + TypeScript)
    src-tauri/
      tauri.conf.json            # Window config (transparent, always-on-top)
      Cargo.toml                 # Rust deps (tauri, windows crate for idle detection)
      src/main.rs                # Tauri entry point
      src/lib.rs                 # Library entry point
      src/idle.rs                # GetLastInputInfo() idle detection
      resources/                 # Bundled owl PNGs
      icons/                     # App icon
      capabilities/default.json  # Tauri permissions
    src/
      main.ts                    # App init, wires everything together
      types.ts                   # Shared TypeScript types
      presence.ts                # REST + SSE client (mirrors PresenceManager.swift)
      idle-monitor.ts            # Polls Rust idle command, same thresholds as macOS
      settings.ts                # tauri-plugin-store persistence
      companion.ts               # Owl sprite animations
      theme.ts                   # Character frame sequences
      tray.ts                    # System tray icon
      tray-menu.ts               # Settings popup logic
      friend-panel.ts            # Multi-window friend management
      friend.ts                  # Friend owl window logic
      chat.ts                    # Chat window logic
      friend.css, chat.css, style.css
    index.html                   # Companion owl window
    tray-menu.html               # Settings popup
    friend.html                  # Friend owl template
    chat.html                    # Chat window template
    package.json, vite.config.ts, tsconfig.json

  worker/                        # Cloudflare Worker (shared backend)
    src/index.js                 # All API endpoints + Durable Object for SSE
    wrangler.toml                # KV + Durable Object bindings
    package.json

  shared/
    owls/                        # Platform-independent owl PNGs (16 files)

  website/                       # Landing page (Vercel)
    index.html                   # Download buttons (Mac + Windows, platform-detected)
    appcast.xml                  # Sparkle update feed (macOS)
    update.json                  # Tauri updater manifest (Windows)
    images/                      # Website owl images

  .github/workflows/
    release.yml                  # Orchestrator: tag-triggered, parallel Mac+Windows builds
    release-mac.yml              # Build, sign, notarize DMG, Sparkle signature
    release-windows.yml          # Build Tauri NSIS installer

  releases/                      # Local DMG builds
  VERSION                        # Single version for both platforms (currently 1.1.0)
```

---

## Architecture

### Backend (Cloudflare Worker)
- **KV storage** for user data, friend lists, event/message queues
- **Durable Objects** (`UserChannel`) for real-time SSE push
- Endpoints: `/register`, `/status`, `/friends`, `/friends/add`, `/friends/remove`, `/profile/update`, `/events/send`, `/events`, `/messages/send`, `/messages`, `/stream` (SSE)
- Events written to KV AND pushed via Durable Object SSE — dual delivery for reliability
- Platform-agnostic: both Mac and Windows clients use the same API

### macOS App (Swift/SwiftUI)
- **Menu bar app** (LSUIElement) — no dock icon
- **Floating NSPanels** (borderless, transparent, always-on-top, all desktops) for owl characters
- **SSE primary** for real-time events, **10s polling fallback**
- **60s heartbeat** for status + friend list
- **IOKit** for idle time detection (HIDIdleTime)
- **Sparkle 2** for auto-updates (EdDSA signed, appcast on Vercel)
- **Developer ID signed + notarized** for distribution

### Windows App (Tauri 2: Rust + TypeScript)
- **Transparent Tauri windows** (WebView2) for owl characters
- **System tray** with popup settings window
- **EventSource** for SSE, same polling fallback
- **Rust** `GetLastInputInfo()` for idle detection
- **tauri-plugin-updater** for auto-updates (update.json on Vercel)
- **NSIS installer** for distribution

### Key Design Decisions
- **Separate native apps per platform** — macOS stays Swift/SwiftUI, Windows uses Tauri 2. No cross-platform rewrite.
- **Shared backend** — one Cloudflare Worker serves both platforms
- **Shared assets** — owl PNGs in `shared/owls/`, copied to each app's resources
- **Single VERSION file** — both platforms read from it for version parity
- **FaceTime on Mac, generic call links on Windows** — the `facetimeContact` field stores any URI

---

## Code Signing & Distribution

### macOS
- **Certificate:** Developer ID Application: Sarah Gilmore (TAQAF8W6WH)
- **Apple ID:** erroneous.george@gmail.com
- **Notarization credentials:** stored in Keychain as profile "notarytool"
- **Sparkle EdDSA public key:** `EmTyF44ZKGKbPmmXBHXL+usTQK/uMY1A3JlU0e5+evc=` (private key in Keychain)
- **Build command:**
  ```
  xcodebuild -project Buddy.xcodeproj -scheme Buddy -configuration Release build \
    CODE_SIGN_IDENTITY="Developer ID Application: Sarah Gilmore (TAQAF8W6WH)" \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=TAQAF8W6WH \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" -derivedDataPath /tmp/BuddyBuild
  ```
- **IMPORTANT:** After building, Sparkle framework binaries must be re-signed with Developer ID before notarization:
  ```
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" .../Sparkle.framework/Versions/B/XPCServices/Downloader.xpc
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" .../Sparkle.framework/Versions/B/XPCServices/Installer.xpc
  codesign --force --options runtime --timestamp --sign "$IDENTITY" .../Sparkle.framework/Versions/B/Autoupdate
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" .../Sparkle.framework/Versions/B/Updater.app
  codesign --force --options runtime --timestamp --sign "$IDENTITY" .../Sparkle.framework
  codesign --force --options runtime --timestamp --sign "$IDENTITY" Buddy.app
  ```
- **Sparkle sign_update tool:** located in DerivedData Sparkle artifacts

### Windows
- No code signing certificate yet (optional EV cert ~$300/yr to avoid SmartScreen)
- Build: `cd buddy-windows && npm run tauri build`
- Produces NSIS installer (.exe) + update zip (.nsis.zip)

### Vercel
- **Project:** getbuddy (ID: prj_88LeVclw1Db9DxQKHg3SjuI64Cs7)
- **Org:** team_IISuNcVFv40rW88YliJ5diZ4
- **SSO protection** tends to re-enable on new deployments — disable via API if downloads return 401
- **Must re-alias** after each deploy: `npx vercel alias set <deployment-url> getbuddy.vercel.app`

---

## Release Process

### Automated (once CI secrets are configured)
1. Bump `VERSION` file
2. `git tag v1.2.0 && git push origin main --tags`
3. GitHub Actions builds Mac + Windows in parallel, creates release, updates manifests, deploys website

### Manual (current process for macOS)
1. Bump version in `Buddy.xcodeproj/project.pbxproj` (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
2. Build with Developer ID signing (see command above)
3. Re-sign Sparkle binaries
4. Notarize: `xcrun notarytool submit ... --keychain-profile "notarytool" --wait`
5. Staple: `xcrun stapler staple Buddy.app`
6. Create DMG: `hdiutil create -volname "Buddy" -srcfolder ... -format UDZO Buddy.dmg`
7. Sign for Sparkle: `sign_update Buddy.dmg` → get edSignature + length
8. Update `website/appcast.xml` with new item (version, signature, length, pubDate)
9. Upload DMG to GitHub: `gh release create v1.2.0 Buddy.dmg --repo Bridge-Innovation/Buddy`
10. Deploy website: `npx vercel --prod --yes` then re-alias

### GitHub Secrets Needed for CI
| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE` | Base64-encoded Developer ID .p12 |
| `APPLE_CERTIFICATE_PASSWORD` | .p12 password |
| `APPLE_ID` | erroneous.george@gmail.com |
| `APPLE_ID_PASSWORD` | App-specific password |
| `APPLE_TEAM_ID` | TAQAF8W6WH |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key from Keychain |
| `VERCEL_TOKEN` | Vercel auth token |
| `VERCEL_ORG_ID` | team_IISuNcVFv40rW88YliJ5diZ4 |
| `VERCEL_PROJECT_ID` | prj_88LeVclw1Db9DxQKHg3SjuI64Cs7 |

---

## Project History

| Date | Milestone |
|---|---|
| 2026-03-25 | Initial commit: floating owl, activity monitoring, presence backend |
| 2026-03-26 | MVP: friend presence, waving, chat, FaceTime calling |
| 2026-03-27 | Website launched at getbuddy.vercel.app |
| 2026-03-27 | App icon added (was showing grey box) |
| 2026-03-27 | Developer ID signing + Apple notarization set up |
| 2026-03-27 | Sparkle 2 auto-update framework integrated |
| 2026-03-27 | v1.1.0: SSE real-time events (Durable Objects), FaceTime fix (caller initiates), UI polish (wave cutoff, name labels, owl sizing, subtle availability dot, chat speech bubbles) |
| 2026-03-27 | Windows version scaffolded (Tauri 2), CI/CD pipeline created, website updated with Windows download |

---

## Known Issues / TODO

- **Windows app not yet built** — Rust needs to be installed, first build needs to happen on Windows (or via CI)
- **GitHub Actions secrets not configured** — manual releases until then
- **No Windows code signing** — SmartScreen may warn users; EV cert recommended
- **Vercel SSO protection** — sometimes re-enables on deploy; check if downloads 401
- **`facetimeContact` field** — works but should eventually be renamed to `callLink` on the backend for platform neutrality

---

## Instructions for Future Claude Code Sessions

### Always do at the start of a session
- Read this file to understand the project state
- Check `VERSION` for current version number
- Run `git log --oneline -5` to see recent changes since this doc was last updated

### After making significant changes, UPDATE THIS DOCUMENT
This is critical. After every building session that changes the project, update:

1. **"Current Version"** section if version was bumped
2. **"Project History"** table with a one-line entry for what was done and the date
3. **"Known Issues / TODO"** — add new issues, remove resolved ones
4. **"Repository Structure"** if new files/directories were added
5. **"Architecture"** section if design decisions changed
6. **"Release Process"** if the workflow changed
7. **"Last updated"** date at the top

### How to update
```
Edit /Users/sarahgilmore/Developer/Buddy/CLAUDE.md
```
Keep entries concise. This document should be scannable, not exhaustive. Code-level details belong in the code itself, not here. This document is for **project-level context** that isn't obvious from reading the codebase.

### What NOT to put in this document
- Line-by-line code explanations (read the code)
- Git history (use `git log`)
- Debugging notes from a single session
- Temporary state or in-progress work
