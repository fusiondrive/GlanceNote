# GlanceNote

A widget-first sticky note app for macOS and iOS. Each note lives in a frameless, always-on-top panel that mirrors the exact visual footprint of a WidgetKit widget — so what you see floating on your desktop is what appears on your Home Screen.

---

## Features

- **Frameless floating panels** — borderless `NSPanel` windows that stay above all other apps, visible across all Spaces
- **Menu bar only** — no Dock icon, no app switcher entry; the status bar icon is the sole entry point on macOS
- **Widget parity** — default panel sizes are pinned to WidgetKit system family dimensions (small 155×155, medium 329×155, large 329×345)
- **Edge-drag resize** — drag any of the four panel edges to resize freely; S / M / L preset buttons snap back to widget dimensions
- **Color tags** — five background tints (yellow, white, blue, green, pink) with frosted-glass material overlay
- **Debounced auto-save** — edits are committed 500 ms after the last keystroke via SwiftUI's `task(id:)` mechanism; a final save fires on panel close
- **Session restore** — pinned panels reopen at their saved position and size on next launch
- **WidgetKit integration** — widget slots promote notes to the Home Screen / Notification Center; the timeline refreshes on every save
- **iOS companion** — full note list and editor using the same shared view layer

---

## Requirements

| | Minimum |
|---|---|
| macOS | 14.0 Sonoma |
| iOS | 17.0 |
| Xcode | 15.0 |
| Swift | 5.9 |

A free Apple ID is sufficient for local development. An App Group entitlement (paid Apple Developer Program membership) is required to enable widget data sharing and cross-target store access; the app falls back to a local `Application Support` store otherwise.

---

## Project Structure

```
GlanceNote/
├── GlanceNote/
│   ├── App/
│   │   └── GlanceNoteApp.swift       # Entry point; AppDelegate; session restore
│   ├── Model/
│   │   └── Note.swift                # SwiftData schema; ModelContainer factory
│   ├── Shared/
│   │   └── NoteCardView.swift        # Core note surface (macOS panel, iOS, widget preview)
│   ├── macOS/
│   │   ├── MenuBarController.swift   # NSStatusItem; note-list popover
│   │   ├── NotePanel.swift           # NSPanel; ResizeHandleView; PanelContainerView
│   │   └── PanelRegistry.swift       # UUID → NotePanelController map; open/close/restore
│   ├── iOS/
│   │   └── iOSRootView.swift         # NavigationStack root; note list and editor
│   └── Resources/
│       ├── Info.plist                # LSUIElement = YES (macOS)
│       └── GlanceNote.entitlements
├── GlanceNoteWidget/
│   └── GlanceNoteWidget.swift        # TimelineProvider; small/medium/large families
├── SharedKit/
│   └── SharedDataClient.swift        # App Group UserDefaults bridge; NoteSnapshot; NoteColor
└── ARCHITECTURE.md                   # Full system design document
```

---

## Architecture Summary

### Data flow

```
Note (SwiftData)
    │  commitSave() on every edit
    ▼
SharedDataClient.write(snapshots:)
    │  encodes top-N notes to UserDefaults(suiteName:)
    │  calls WidgetCenter.shared.reloadAllTimelines()
    ▼
GlanceNoteWidget TimelineProvider
    │  reads NoteSnapshot array from shared UserDefaults
    ▼
Widget surface (Home Screen / Notification Center)
```

### macOS panel hierarchy

```
NotePanel (NSPanel)
└── PanelContainerView          ← hit-test gate; routes edge events to handles
    ├── NSHostingView           ← SwiftUI tree (PanelChromeView → NoteCardView)
    └── ResizeHandleView × 4   ← per-edge drag strips; own the full resize lifecycle
```

`PanelContainerView.hitTest` ensures that pointer events in the outer 6 pt edge strip always reach `ResizeHandleView`, preventing SwiftUI's internal tracking areas from consuming them. `NotePanel.mouseDown(with:)` swallows any edge-zone events that fall through due to floating-point rounding, blocking AppKit's built-in resize machinery from engaging in parallel.

See `ARCHITECTURE.md` for a full breakdown of all subsystems.

---

## Building

1. Open `GlanceNote.xcodeproj` in Xcode.
2. Select the `GlanceNote` scheme.
3. Set the development team in the target's Signing & Capabilities tab.
4. Build and run (`Cmd+R`).

The app appears in the menu bar only. No window opens on launch.

To run on a device or enable widget sharing, add an App Group (`group.com.yourteam.glancenote`) to both the `GlanceNote` and `GlanceNoteWidget` targets and update the suite name in `SharedDataClient.swift`.

---

## License

MIT
