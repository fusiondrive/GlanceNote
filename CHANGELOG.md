# Changelog

All notable changes to GlanceNote are documented here, in reverse chronological order.

---

## [Unreleased]

### Changed
- `NotePanel.swift` — four-layer event-routing fortress to eliminate AppKit split-bar cursor leakage:
  - **Layer 1 (new): `NotePanel.mouseDown(with:)` override.** With `.resizable` in the style mask, `NSPanel.mouseDown` independently scans the event location against the window border before the view hit-test result is considered. When `PanelContainerView.hitTest` returns `nil` at a floating-point rounding boundary of the 6 pt edge strip, the event bypasses the view hierarchy and reaches the window, where `NSPanel.mouseDown` engages its own resize-tracking session — producing the split-bar cursor and frame shudder. The new override converts the event location into content-view coordinates, detects edge-zone events, and swallows them before forwarding to `super`. Interior events are forwarded normally; window dragging (`isMovableByWindowBackground`) is unaffected.
  - **Layer 2 (existing): `PanelContainerView.hitTest`.** Unchanged. Routes the vast majority of edge-zone hits to `ResizeHandleView`, preventing `NSHostingView`'s internal `NSTrackingArea` from consuming them. Layer 1 covers only the rounding-boundary misses that hitTest cannot catch.
  - **Layer 3 (existing): `ResizeHandleView` mouse handlers.** `mouseDown`, `mouseDragged`, and `mouseUp` each own their frame math and return without calling `super`. The `.resizable` capability bit is present but AppKit's resize machinery is never invoked.
  - **Layer 4 (existing): `PanelChromeView` hover detector.** Inset by `edgeHandleThickness` so SwiftUI's hover tracking area never activates from edge-zone movement.
- `NotePanel.swift` — file-level comment block updated to document all four defensive layers as a unified architecture reference.

---

## [0.1.3] — 2026-06-04

### Fixed
- `NotePanel.swift` — restored `.resizable` to the `NotePanel` style mask after its removal in 0.1.2 introduced a regression: without it, `AppKit` does not reliably deliver the initial `mouseDown` to `ResizeHandleView` when the panel is not key, silently swallowing the first drag gesture on an unfocused panel.

### Added
- `NotePanel.swift` — `ResizeHandleView.mouseUp(with:)` override. Persists the final panel frame via `saveFrame(usingName:)`, resets `dragOrigin` and `initialFrame` to zero, and returns without calling `super` to prevent the `.resizable` subsystem from committing its own resize transaction on mouse-up.
- `NotePanel.swift` — explicit `// No super call` comments on all three `ResizeHandleView` drag handlers (`mouseDown`, `mouseDragged`, `mouseUp`) documenting that the omission is intentional, not an oversight.

### Removed
- `generate_xcodeproj.py` — Python project-generation script removed from the repository. The `.xcodeproj` is now committed directly and is the authoritative build configuration.

---

## [0.1.2] — 2026-06-04

### Fixed

**Bug 1 — Dual `NSStatusItem` / `NSViewBridgeErrorCanceled` crash**

`MenuBarExtra` was declared in the SwiftUI `App` scene body while `MenuBarController` simultaneously created its own `NSStatusItem` via `NSStatusBar.system.statusItem(withLength:)`. This produced two status bar icons backed by two independent responder paths. Clicking the SwiftUI-owned icon attempted a `ViewBridge` operation on a stale port, crashing with `NSViewBridgeErrorCanceled`.

Fix: replaced `MenuBarExtra` with `Settings { EmptyView() }` in `GlanceNoteApp.body`. This satisfies the `App` protocol's `Scene` requirement and keeps the run loop alive without creating any `NSStatusItem`. `MenuBarController` is now the sole, authoritative owner of the status bar icon and the note-list popover.

**Bug 2 — Split-bar cursor flicker and frame-commit shuddering on resize** *(partially addressed; fully resolved in 0.1.3)*

With `.resizable` in the style mask, `AppKit`'s window-resize subsystem could claim edge mouse events for its own resize session when `PanelContainerView.hitTest` returned `nil` for inter-handle gaps. This ran concurrently with `ResizeHandleView.mouseDragged`, causing both paths to mutate the window frame from different origins, producing visible jitter and the split-bar cursor.

Attempted fix: removed `.resizable` from `NotePanel`'s style mask. Eliminated the competing resize session, but introduced a first-drag regression on unfocused panels (see 0.1.3).

---

## [0.1.1] — 2026-06-04

### Fixed

**Hit-testing conflict between resize handles and SwiftUI hover layer**

Three coordinated changes to `NotePanel.swift`:

- **`PanelContainerView` (new class).** Custom `NSView` subclass that overrides `hitTest(_:)`. Pointer events in the outer 6 pt edge strip are routed exclusively to the `ResizeHandleView` covering that strip, or returned `nil` to bubble to the window. This prevents `NSHostingView`'s internally registered `NSTrackingArea` from consuming edge-zone events that belong to resize.

- **`ResizeHandleView` — cursor tracking rewritten.** Replaced `resetCursorRects()` (unreliable on borderless panels; silently invalidated by SwiftUI layout cycles) with an `NSTrackingArea` using `.activeAlways | .cursorUpdate | .mouseEnteredAndExited | .inVisibleRect`. `cursorUpdate(with:)`, `mouseEntered(with:)`, and `mouseExited(with:)` set the directional cursor directly, independently of SwiftUI's cursor-rect lifecycle. `acceptsFirstMouse(for:)` returns `true` so the first drag on an unfocused panel works without a preceding activation click.

- **`PanelChromeView` — inset hover detector.** Replaced the full-`ZStack` `.onHover` with a `Rectangle().fill(Color.clear).contentShape(Rectangle())` padded inward by `edgeHandleThickness` before `.onHover` is applied. SwiftUI therefore registers its `NSTrackingArea` only for the interior region, leaving the outer 6 pt strip uncontested. `.allowsHitTesting(false)` on the detector view ensures gestures still reach content beneath it.

- **`edgeHandleThickness` constant (new).** Single `private let edgeHandleThickness: CGFloat = 6` at file scope keeps all three layers geometrically consistent. Previously the value was duplicated as a local literal in each site.

---

## [0.1.0] — 2026-06-04

Initial release.

### Architecture

- `LSUIElement` accessory app — no Dock icon, no app switcher entry. The menu bar icon is the sole entry point on macOS.
- `MenuBarController` owns the `NSStatusItem` and presents a `NSPopover` containing `MenuBarPopoverView` (note list, create, pin/unpin actions).
- `PanelRegistry` (singleton, `@Observable`, `@MainActor`) maps `Note.id → NotePanelController`. Supports an unlimited number of simultaneous floating panels. Restored from the persisted `isPinned` set on every launch.
- `SwiftData` store resolved from the App Group container (`group.com.yourteam.glancenote`) with a local `~/Library/Application Support/GlanceNote/` fallback for free Personal Team builds that cannot provision App Groups.
- `SharedDataClient` encodes pinned-note `NoteSnapshot` arrays to `UserDefaults(suiteName:)` and calls `WidgetCenter.shared.reloadAllTimelines()` on every save, bridging the main app to the `GlanceNoteWidget` extension without XPC or a custom URL scheme.

### UI / UX

- `NoteCardView` uses `NSVisualEffectView` (`.hudWindow`, `.behindWindow`) tinted with the note accent color for a frosted-glass panel surface on macOS; falls back to a plain tinted `Color` on iOS.
- Corner radius (20 pt) and content padding (16 pt) match the WidgetKit system widget container specification for visual parity between panels and widgets.
- Toolbar trailing slot crossfades between a dimmed timestamp (at rest, 0.45 opacity) and S / M / L size-preset pills (on hover) via a shared `ZStack` with `.spring(duration: 0.25)` — zero layout shift.
- Size controls injected through `PanelResizeActionKey: EnvironmentKey` so `NoteCardView` stays decoupled from AppKit. `nil` default value suppresses the controls in iOS and WidgetKit preview contexts automatically.
- `PanelChromeView` owns only the close button (top-right corner, hover-gated with `.easeInOut(duration: 0.12)` fade). `ResizeHandleView` instances are siblings of `NSHostingView` inside a plain `NSView` container, satisfying AppKit's restriction against subviewing into `NSHostingView`.
- Auto-save debounced 500 ms via `.task(id: note.body)` — the task is cancelled and restarted on every keystroke; the final in-flight task is cancelled and a synchronous save is committed in `.onDisappear`. Color-tag changes bypass the debounce and commit immediately.

### Targets

| Target | Platform | Role |
|---|---|---|
| `GlanceNote` | macOS 14+, iOS 17+ | Main app |
| `GlanceNoteWidget` | macOS 14+, iOS 17+ | WidgetKit extension — `systemSmall`, `systemMedium`, `systemLarge` |
| `SharedKit` | Both | `SharedDataClient`, `NoteSnapshot`, `NoteColor`, `Color(hex:)` extension |
