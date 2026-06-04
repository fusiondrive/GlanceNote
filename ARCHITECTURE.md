# GlanceNote — System Architecture

## Overview

GlanceNote is a Widget-First note application for Apple platforms. The guiding principle is that
the note surface itself — not a traditional document window — is the primary UI primitive. On
macOS, each note lives in a frameless, always-on-top NSPanel that mirrors the visual footprint of
a WidgetKit widget. On iOS, notes are surfaced through a native SwiftUI list and the system widget
layer.

---

## Repository Layout

```
GlanceNote/
├── GlanceNote/                  # Main app target (macOS + iOS)
│   ├── App/                     # Entry points and lifecycle
│   ├── Model/                   # SwiftData schema and domain types
│   ├── Shared/                  # Platform-agnostic SwiftUI views
│   ├── macOS/                   # AppKit-bridged code, NSPanel, MenuBar
│   ├── iOS/                     # UIKit lifecycle, iOS-only views
│   └── Resources/               # Assets, plists, localizations
├── GlanceNoteWidget/            # WidgetKit extension (iOS + macOS)
├── SharedKit/                   # Swift package consumed by both targets
│   └── SharedDataClient.swift   # App Group I/O, shared model serialization
└── ARCHITECTURE.md
```

---

## 1. Data Layer — SwiftData

### Schema

```
Note
├── id: UUID                  (stable identity across devices)
├── body: String              (plain text; rich text deferred to v2)
├── colorTag: NoteColor       (enum: yellow, white, blue, green, pink)
├── isPinned: Bool            (controls always-on-top panel behavior)
├── createdAt: Date
├── modifiedAt: Date
└── widgetSlot: Int?          (1-based index; nil = not promoted to widget)
```

### Persistence stack

The main app initializes a single `ModelContainer` configured with:
- A `ModelConfiguration` using the **App Group container URL**
  (`group.com.yourteam.glancenote`) so that the WidgetKit extension can
  open the same SQLite store read-only.
- `isStoredInMemoryOnly: false` for production; `true` in `#Preview` blocks.

```
App Group container
└── Library/Application Support/glancenote.store  ← SwiftData SQLite
```

The WidgetKit extension opens the same store via a second `ModelContainer`
with `isReadOnly: true`. This eliminates the need for a serialization bridge
for the widget timeline; the widget fetches `Note` objects directly.

For cases where the extension must run before the main app has written to the
store (e.g., on first launch), `SharedDataClient` provides a lightweight
`UserDefaults(suiteName:)` fallback containing the top-N notes as JSON.

---

## 2. App Group Data Bridge

```
SharedKit/SharedDataClient
├── write(notes: [Note])      Called by main app after every save
│   └── encodes top-5 notes to JSON → UserDefaults(suiteName:)
│       then calls WidgetCenter.shared.reloadAllTimelines()
└── read() -> [NoteSnapshot]  Called by widget TimelineProvider
    └── decodes JSON from shared UserDefaults
        falls back to empty state if key absent
```

`NoteSnapshot` is a lightweight, Codable struct (no SwiftData dependency)
that the widget extension uses for rendering. It contains only the fields
required for display: `id`, `body`, `colorTag`, `modifiedAt`.

---

## 3. Platform Strategy

### Shared layer (`GlanceNote/Shared/`)

All business logic and the core note-rendering view (`NoteCardView`) live
here. Platform conditionals are expressed as Swift compiler flags
(`#if os(macOS)`) only at the leaf level of view composition — never in
data or logic code.

### macOS specifics (`GlanceNote/macOS/`)

| Component | Role |
|---|---|
| `MenuBarController` | Owns the `NSStatusItem`; presents the note picker popover |
| `NotePanel` | `NSPanel` subclass — frameless, floating, resizable |
| `FloatingNoteHostingView` | `NSHostingView<NoteCardView>` embedded in `NotePanel` |
| `ResizeHandle` | Transparent `NSView` overlays at panel edges; synthesizes `NSEvent` drag |

Entry point: `GlanceNoteApp` uses `MenuBarExtra` (macOS 13+) for the
status-bar presence. Each pinned note spawns an independent `NotePanel`
instance. There is no main application window (`LSUIElement = YES`).

### iOS specifics (`GlanceNote/iOS/`)

Standard `UIWindowSceneDelegate` lifecycle. Root view is a `NavigationStack`
containing a `NoteListView` → `NoteEditorView` hierarchy. The same
`NoteCardView` used on macOS is reused in the iOS widget configuration
preview.

---

## 4. WidgetKit Integration

The `GlanceNoteWidget` target vends three widget families:
- `systemSmall` — single note, body truncated to ~3 lines
- `systemMedium` — single note with full first paragraph
- `systemLarge` — two notes stacked

`TimelineProvider` produces a 15-minute refresh timeline during active
hours, falling back to `.never` reload policy when no notes are pinned to
a widget slot. The main app forces an immediate reload via
`WidgetCenter.shared.reloadTimelines(ofKind:)` on every note mutation.

---

## 5. Multi-Instance Model (macOS)

Each `Note` whose `isPinned == true` corresponds to exactly one live
`NotePanel`. A `PanelRegistry` (singleton, owned by `AppDelegate`) maps
`Note.id → NotePanel`. On launch, the registry reconstructs panels from
the persisted `isPinned` set. Panel frame (`origin + size`) is stored
back to the `Note` model so position survives restarts.

There is no architectural limit on the number of simultaneous panels.
`NSPanel` instances are lightweight; each holds one `NSHostingView`.

---

## 6. Key Design Constraints

1. **No traditional main window.** `LSUIElement = YES` in Info.plist.
   The application activates only transiently when a panel receives focus.

2. **Widget visual parity.** `NotePanel` default sizes are pinned to
   WidgetKit's documented point dimensions (small: 155×155, medium:
   329×155, large: 329×345 on a standard display). Users may resize freely
   beyond these anchors.

3. **App Group is the single source of truth for cross-target data.**
   No XPC service, no custom URL scheme for data handoff.

4. **SwiftData migrations are additive-only** in v1. No destructive schema
   changes. Version enum starts at `v1`.
