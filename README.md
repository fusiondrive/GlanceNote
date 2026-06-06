# GlanceNote

A widget-first sticky note application for macOS. Each note lives in a frameless, always-on-top `NSPanel` that floats above all other windows and remains visible across all Spaces.

The application runs exclusively from the menu bar (`LSUIElement = YES`). There is no Dock icon and no entry in the application switcher.

---

## UI Overview

| Menu Bar Popover | Frameless Floating Note Panel |
| :---: | :---: |
| <img src="GlanceNote/Resources/popover_view.png" width="400" alt="Status Bar Interface"/> | <img src="GlanceNote/Resources/floating_panel.png" width="400" alt="Frameless Floating Note"/> |

---

## Features

- **LSUIElement architecture** — the application activates only transiently when a panel or popover receives focus; no persistent Dock presence or main window
- **Frameless floating panels** — borderless `NSPanel` windows at `.floating` window level, visible across all Spaces via `.canJoinAllSpaces`
- **Physical paper appearance** — pastel note surfaces (yellow, white, blue, green, pink) are locked to a forced-light rendering profile regardless of system Dark Mode; `NSVisualEffectView` is pinned to the Aqua appearance so the vibrancy blur is always a clean, bright frost, and all text uses hard-coded dark ink values
- **Edge-drag resize** — custom `ResizeHandleView` strips at all four edges handle the full drag lifecycle with a four-layer event-routing system that prevents AppKit's internal resize machinery from interfering; S / M / L preset buttons snap to named dimensions
- **Enforced minimum size** — panels cannot be dragged below 240×180 pt, the floor at which the bottom toolbar chrome (color swatches + size buttons) is guaranteed to fit without clipping
- **Debounced auto-save** — edits commit 500 ms after the last keystroke via SwiftUI's `task(id:)` cancellation mechanism; a synchronous save fires on panel close
- **Session restore** — pinned panels reopen at their saved position and size on next launch via per-note `NSWindow` frame autosave keys
- **WidgetKit integration** — notes promoted to a widget slot are written to a shared App Group `UserDefaults` store and trigger an immediate `WidgetCenter` timeline reload on every save
- **Color tags** — five tints composited over a forced-light `NSVisualEffectView` frosted-glass material

---

## Panel Size Presets

| Preset | Width | Height |
|---|---|---|
| S | 240 pt | 240 pt |
| M | 400 pt | 240 pt |
| L | 400 pt | 440 pt |
| Minimum | 240 pt | 180 pt |

The minimum width (240 pt) matches the S preset width and is the enforced floor for both `NSPanel.minSize` and the drag clamp in `ResizeHandleView.mouseDragged`.

---

## Requirements

| | Minimum |
|---|---|
| macOS | 14.0 Sonoma |
| Xcode | 15.0 |
| Swift | 5.9 |

A free Apple ID is sufficient for local development. The `ModelContainer` factory resolves the store path from the App Group container when available and falls back to `~/Library/Application Support/GlanceNote/` for Personal Team builds. Widget data sharing requires a paid Apple Developer Program membership with an App Group entitlement.

---

## Project Structure

```
GlanceNote/
├── GlanceNote/
│   ├── App/
│   │   └── GlanceNoteApp.swift       # Entry point; AppDelegate; pinned-panel restore
│   ├── Model/
│   │   └── Note.swift                # SwiftData schema; ModelContainer factory
│   ├── Shared/
│   │   └── NoteCardView.swift        # Note surface — panel and widget preview
│   ├── macOS/
│   │   ├── MenuBarController.swift   # NSStatusItem; note-list popover
│   │   ├── NotePanel.swift           # NSPanel subclass; ResizeHandleView; PanelContainerView
│   │   └── PanelRegistry.swift       # UUID → NotePanelController registry; open / close / restore
│   └── Resources/
│       ├── Info.plist                # LSUIElement = YES
│       ├── GlanceNote.entitlements
│       ├── popover_view.png          # Screenshot — menu bar popover
│       └── floating_panel.png        # Screenshot — floating note panel
├── GlanceNoteWidget/
│   └── GlanceNoteWidget.swift        # TimelineProvider; systemSmall / Medium / Large families
├── SharedKit/
│   └── SharedDataClient.swift        # App Group UserDefaults bridge; NoteSnapshot; NoteColor
├── ARCHITECTURE.md                   # Full subsystem design document
└── CHANGELOG.md                      # Revision history
```

---

## Architecture

### Data flow

```
Note (SwiftData)
    │  commitSave() — debounced 500 ms, immediate on color change or panel close
    ▼
SharedDataClient.write(snapshots:)
    │  JSON-encodes top-N NoteSnapshot values to UserDefaults(suiteName:)
    │  calls WidgetCenter.shared.reloadAllTimelines()
    ▼
GlanceNoteWidget — TimelineProvider
    │  reads NoteSnapshot array from shared UserDefaults
    ▼
Widget surface (Notification Center)
```

### macOS panel view hierarchy

```
NotePanel (NSPanel)
└── PanelContainerView              ← hit-test gate; routes edge events to handles
    ├── NSHostingView               ← SwiftUI tree: PanelChromeView → NoteCardView
    └── ResizeHandleView × 4       ← per-edge drag strips; own the full drag lifecycle
```

**AppKit hit-test isolation** is enforced through four coordinated layers:

| Layer | Location | Responsibility |
|---|---|---|
| 1 | `NotePanel.mouseDown(with:)` | Swallows edge-zone events that bypass hitTest due to floating-point rounding; forwards interior events to `super` so window dragging is unaffected |
| 2 | `PanelContainerView.hitTest(_:)` | Returns `ResizeHandleView` unconditionally for edge-zone hits; returns `nil` for unmatched edge points; normal result for interior |
| 3 | `ResizeHandleView` mouse handlers | `mouseDown`, `mouseDragged`, `mouseUp` each complete without calling `super`, preventing AppKit's `.resizable` subsystem from co-opting any part of the drag sequence |
| 4 | `PanelChromeView` hover detector | Inset by `edgeHandleThickness` (6 pt) so SwiftUI's `NSTrackingArea` never activates from edge-zone cursor movement |

See `ARCHITECTURE.md` for a complete breakdown of all subsystems.

---

## Building

1. Open `GlanceNote.xcodeproj` in Xcode.
2. Select the `GlanceNote` scheme.
3. In **Signing & Capabilities**, set your development team on both the `GlanceNote` and `GlanceNoteWidget` targets.
4. Build and run (`Cmd+R`).

The application does not open any window on launch. Look for the note icon in the menu bar.

**To enable widget data sharing:** add an App Group identifier (`group.com.yourteam.glancenote`) to both targets under Signing & Capabilities, then update `AppGroup.suiteName` in `SharedKit/SharedDataClient.swift` to match.

**Gatekeeper (distribution builds):** if running a build not signed with a Developer ID, right-click the application bundle in Finder and select **Open** to bypass the initial quarantine prompt.

---

## License

MIT
