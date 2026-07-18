# Changelog

All notable changes to GlanceNote are documented here, in reverse chronological order.

GlanceNote is an independent personal project, unaffiliated with any university or institution.

---

## [1.0.3] — 2026-07-17 (Unreleased)

Motion & interaction polish pass, guided by Apple's fluid-interface principles (feedback on press, materialize instead of hard-cut, spatial consistency, Reduce Motion support) and design-engineering craft rules (strong ease-out curves, sub-300 ms UI timing, never enter from `scale(0)`).

### Added

**Panel materialize / dematerialize (`NotePanel.swift`)**

Floating panels no longer hard-cut with `orderFront`/`orderOut`. On open, a panel fades in while rising 8 pt into place (180 ms, strong ease-out `cubic-bezier(0.23, 1, 0.32, 1)`); on close it reverses the same path faster (130 ms) — enter and exit share one spatial path. When *Reduce Motion* is on, both collapse to a plain cross-fade with no positional movement. The exit animation restores pre-exit geometry after `orderOut` so the autosaved frame never drifts.

**`PressableButtonStyle` (`NoteCardView.swift`)**

Shared press feedback for all small controls: label scales down (0.85–0.92) the instant the pointer goes down, 120 ms ease-out. Applied to the panel close button, color swatches, glass swatch, S/M/L size pills, the popover “+” button, and the row pin button.

**Menu bar popover (`MenuBarController.swift`)**

- Row hover highlight (6 % primary, 100 ms) so the list responds to the pointer.
- Pin icon morphs `pin` ⇄ `pin.fill` in place via `.contentTransition(.symbolEffect(.replace))`.
- Right-click context menu per row: Pin/Unpin and **Delete** (closes the floating panel first, then deletes the model). Deleting notes was previously impossible from the UI.
- Empty state (“No Notes — Click + to create a floating note.”) replaces the blank scroll area on first launch.
- Row insertion/removal animates (200 ms ease-out) instead of teleporting.

### Changed

- **Preset resize** — replaced `setFrame(animate: true)` (AppKit's slow, linear-feeling default `animationResizeTime`) with an `NSAnimationContext`-driven resize: 280 ms, strong ease-out; instant under Reduce Motion.
- **Close button hover reveal** — now scales from 0.9 with opacity (never enters from nothing), 140 ms ease-out (was 120 ms ease-in-out opacity-only).
- **Color swatches** — converted from `onTapGesture` circles to real `Button`s: press feedback on pointer-down plus free keyboard/VoiceOver reachability. Selection-ring hand-off animates (150 ms) so choosing a color reads as the ring moving, not two blinks.
- **Paper tint** — picking a swatch cross-fades the background color (200 ms) instead of hard-cutting.
- **S/M/L pills reveal** — pills now also scale from 0.94 anchored at the trailing edge while fading in.
- **Pin toggle** — now persists via `context.save()` (previously relied on SwiftData autosave only).

---

## [1.0.2] — 2026-06-06 (Unreleased)

### Added

**Liquid Glass — floating note panels (macOS 26+)**

A glass swatch has been added to the left-hand color picker row in each floating note panel, sitting immediately after the five pastel swatches. Tapping it activates Liquid Glass mode; tapping any pastel swatch deactivates it. The two modes are mutually exclusive in the selection UI — `colorTag` is preserved silently when glass is active so the previous pastel choice is restored automatically on deactivation.

In glass mode:
- The entire background is handed to the macOS 26 Liquid Glass compositor via `.glassEffect(.clear, in: RoundedRectangle)`. `NotePanel` is already `isOpaque = false` with `backgroundColor = .clear`, giving the compositor an unobstructed path to the desktop.
- The forced-light `colorScheme` override is removed so the glass surface can handle its own vibrancy.
- Text colors switch to adaptive semantic values (`Color.primary`, `Color.secondary`) to remain readable over any wallpaper.
- Swatch selection rings go adaptive (`Color.primary` at opacity) for the same reason.
- The explicit card border is omitted — the glass specular edge provides sufficient silhouetting.

`NoteAppearanceModifier` (new `ViewModifier`) centralizes all appearance branching so `NoteCardView.body` stays readable. On macOS < 26 the modifier silently takes the pastel path regardless of preference state, so the toggle has no visible effect on older OS.

**Liquid Glass — menu bar popover (macOS 26+)**

A `sparkles.rectangle.stack` toggle in the popover header switches the popover surface between `.regularMaterial` and `.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))`. Preference persisted via `@AppStorage("isLiquidGlassEnabled")`. The `.fill` variant of the icon signals the active state. On macOS < 26 the `if #available` guard makes the glass path a no-op and the `.regularMaterial` background renders normally.

`MenuBarController` is now `@MainActor` to satisfy Swift 6 actor isolation requirements when accessing `PanelRegistry.shared`.

### Fixed

- `MenuBarController` — removed `popover.backgroundColor = .clear` (API does not exist on `NSPopover`).
- `MenuBarController` — replaced simulated glass workaround (ultraThinMaterial + white tint + specular strokeBorder) with native `.glassEffect`.
- `MenuBarController` — fixed `.primary.opacity(0.85)` type mismatch (`HierarchicalShapeStyle` not assignable to `some ShapeStyle`); changed to `Color.primary.opacity(0.85)`.

---

## [1.0.1] — 2026-06-05

### Added

- `README.md` — UI Overview section with side-by-side screenshot table.
- `CHANGELOG.md` — full revision history from v0.1.0 onward.
- `GlanceNote/Resources/popover_view.png` — menu bar popover screenshot.
- `GlanceNote/Resources/floating_panel.png` — floating note panel screenshot.
- GitHub release `v1.0.1` with `GlanceNote.zip` attached.

### Changed

**Forced-light "physical paper" appearance**

Notes now enforce a stable light-mode rendering profile regardless of system Dark Mode. A yellow note is always yellow with dark ink — like a physical sticky note.

- `VisualEffectView.makeNSView` pins `view.appearance = NSAppearance(named: .aqua)`, forcing the blur base to always composite in the Aqua colour space.
- `.environment(\.colorScheme, .light)` propagates a forced light scheme to all SwiftUI children, ensuring `.ultraThinMaterial` and system materials resolve to their light variants.
- All text replaced with hard-coded `Color.black` at varying opacities: body `0.85`, read-only `0.82`, placeholder `0.35`, timestamp `0.45`, S/M/L labels `0.50`.
- Pastel tint opacity restored from `0.45` → `0.55` (the reduction was a dark-mode concession; no longer needed with pinned appearance).
- Card border changed from `NSColor.separatorColor` to `Color.black.opacity(0.08)` — appearance-independent.
- Color swatch borders simplified from two-ring to single `Color.black` ring.

**Panel size presets and minimum size**

The previous S preset (155 pt) and minimum size (160 pt) were narrower than the toolbar chrome minimum (~215 pt), causing S/M/L buttons to be clipped when the panel was dragged to minimum width.

| Dimension | Before | After |
|---|---|---|
| `minimumSize` | 160 × 120 | 240 × 180 |
| S preset | 155 × 155 | 240 × 240 |
| M preset | 329 × 155 | 400 × 240 |
| L preset | 329 × 345 | 400 × 440 |

`NotePanel.minimumSize` is the single source of truth — `NSPanel.minSize`, the drag clamp in `ResizeHandleView.mouseDragged`, and the S preset width all reference it.

**macOS-only refactor**

Removed all iOS/iPadOS compatibility overhead:
- Deleted `GlanceNote/iOS/iOSRootView.swift`.
- Removed `#if os(macOS)` / `#else` / `#endif` blocks from `GlanceNoteApp.swift` and `NoteCardView.swift`.
- `@NSApplicationDelegateAdaptor`, `AppDelegate`, `Settings { EmptyView() }` scene, `VisualEffectView`, and the card border are now unconditional top-level declarations.
- `import AppKit` added explicitly to `NoteCardView.swift`.

---

## [0.1.3] — 2026-06-04

### Fixed
- `NotePanel.swift` — restored `.resizable` to the style mask. Its removal in 0.1.2 introduced a regression: AppKit does not reliably deliver the initial `mouseDown` to `ResizeHandleView` when the panel is not key, silently swallowing the first drag on an unfocused panel.

### Added
- `NotePanel.swift` — `ResizeHandleView.mouseUp(with:)` override. Persists the final frame via `saveFrame(usingName:)`, resets drag state, and returns without calling `super` to prevent the `.resizable` subsystem from committing its own transaction on mouse-up.
- `NotePanel.swift` — `NotePanel.mouseDown(with:)` override (Layer 1 of the event-routing fortress). Swallows edge-zone events that bypass `PanelContainerView.hitTest` due to floating-point rounding, blocking AppKit's resize machinery from engaging a parallel tracking session.

### Removed
- `generate_xcodeproj.py` — Python project-generation script. The `.xcodeproj` is committed directly and is the authoritative build configuration.

---

## [0.1.2] — 2026-06-04

### Fixed

**Bug 1 — Dual `NSStatusItem` / `NSViewBridgeErrorCanceled` crash**

`MenuBarExtra` and `MenuBarController` each created an `NSStatusItem`, producing two status bar icons and two responder paths. Clicking the SwiftUI-owned icon crashed with `NSViewBridgeErrorCanceled`.

Fix: replaced `MenuBarExtra` with `Settings { EmptyView() }`. `MenuBarController` is now the sole owner of the `NSStatusItem`.

**Bug 2 — Split-bar cursor flicker and frame shudder on resize** *(partially addressed; fully resolved in 0.1.3)*

With `.resizable` in the style mask, AppKit's resize subsystem raced with `ResizeHandleView.mouseDragged` when `PanelContainerView.hitTest` returned `nil` for inter-handle gaps, producing jitter and the split-bar cursor.

Attempted fix: removed `.resizable`. Eliminated the race but introduced a first-drag regression on unfocused panels.

---

## [0.1.1] — 2026-06-04

### Fixed

**Hit-testing conflict between resize handles and SwiftUI hover layer**

- **`PanelContainerView` (new).** `hitTest(_:)` override routes edge-zone events to `ResizeHandleView` or returns `nil`, preventing `NSHostingView`'s `NSTrackingArea` from consuming them.
- **`ResizeHandleView` cursor tracking rewritten.** `resetCursorRects()` replaced with `NSTrackingArea` (`.cursorUpdate` + `.mouseEnteredAndExited`). `acceptsFirstMouse(for:)` returns `true` for first-drag on unfocused panels.
- **`PanelChromeView` hover detector inset.** Padded inward by `edgeHandleThickness` before `.onHover`, leaving the outer 6 pt strip uncontested.
- **`edgeHandleThickness` constant.** Single `private let` at file scope keeps all three layers geometrically consistent.

---

## [0.1.0] — 2026-06-04

Initial release.

### Architecture

- `LSUIElement` accessory app — no Dock icon, no app switcher entry.
- `MenuBarController` owns the `NSStatusItem` and note-list popover.
- `PanelRegistry` (`@Observable`, `@MainActor`) maps `Note.id → NotePanelController`. Unlimited simultaneous panels. Restored from persisted `isPinned` set on launch.
- `SwiftData` store resolved from App Group container with local `~/Library/Application Support/GlanceNote/` fallback for Personal Team builds.
- `SharedDataClient` bridges note snapshots to the WidgetKit extension via App Group `UserDefaults`; calls `WidgetCenter.shared.reloadAllTimelines()` on every save.

### UI / UX

- `NSVisualEffectView` (`.hudWindow`, `.behindWindow`) + pastel color tint for frosted-glass panel surface.
- Corner radius 20 pt, content padding 16 pt.
- Toolbar trailing slot crossfades between timestamp (rest) and S/M/L preset pills (hover) via shared `ZStack` with `.spring(duration: 0.25)`.
- Auto-save debounced 500 ms via `.task(id: note.body)`. Color changes commit immediately. `onDisappear` flushes any pending save.
- `PanelChromeView` owns the close button only. `ResizeHandleView` instances are siblings of `NSHostingView` in a plain `NSView` container.

### Targets

| Target | Role |
|---|---|
| `GlanceNote` (macOS 14+) | Main app |
| `GlanceNoteWidget` | WidgetKit — `systemSmall`, `systemMedium`, `systemLarge` |
| `SharedKit` | `SharedDataClient`, `NoteSnapshot`, `NoteColor`, `Color(hex:)` |
