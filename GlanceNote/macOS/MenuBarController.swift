// GlanceNote/macOS/MenuBarController.swift
//
// Manages the NSStatusItem that serves as the sole entry point to GlanceNote
// on macOS. The popover it presents contains the full note list and controls
// for creating, pinning, and deleting notes.
//
// Liquid Glass support (macOS 26+):
//   The NSPopover background is set to .clear at init so the SwiftUI layer
//   can own the entire visual surface. When the Liquid Glass toggle is off,
//   MenuBarPopoverView renders a standard window-material background itself.
//   When on, it applies .glassEffect and lets the compositor do its thing.

import AppKit
import SwiftUI
import SwiftData

final class MenuBarController {

    // MARK: Properties

    private var statusItem: NSStatusItem
    private var popover: NSPopover

    // Retain the event monitor so we can tear it down on deinit.
    private var eventMonitor: Any?

    // MARK: Init

    init(modelContext: ModelContext) {
        // --- Status item setup ---
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text",
                                   accessibilityDescription: "GlanceNote")
            button.image?.isTemplate = true  // Adapts to light/dark menu bar.
        }

        // --- Popover setup ---
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        // Clear the default opaque background so the SwiftUI content layer
        // can own the surface completely — needed for Liquid Glass to punch
        // through without the popover's own background blocking the refraction.
        popover.backgroundColor = .clear

        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView()
                .modelContext(modelContext)
                .environment(PanelRegistry.shared)
        )
        popover.contentSize = NSSize(width: 300, height: 440)

        // --- Wire up button action ---
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        // --- Close popover when user clicks elsewhere ---
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: Actions

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}

// MARK: - MenuBarPopoverView

/// The root SwiftUI view shown inside the menu bar popover.
/// Lists all notes and provides quick actions.
///
/// When Liquid Glass is enabled the view strips its own opaque background
/// and applies .glassEffect so the desktop content bleeds through cleanly.
/// When disabled it renders a standard window-material surface so the popover
/// still looks correct even though the NSPopover background is .clear.
private struct MenuBarPopoverView: View {

    @Environment(\.modelContext) private var context
    @Environment(PanelRegistry.self) private var registry

    @Query(sort: \Note.modifiedAt, order: .reverse)
    private var notes: [Note]

    // persisted across launches — flipping this is the whole feature
    @AppStorage("isLiquidGlassEnabled") private var isLiquidGlassEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            noteList
        }
        .frame(width: 300)
        // When glass is off we need to provide our own background because
        // the NSPopover's .backgroundColor is .clear. A thin material gives
        // us the standard frosted-panel look at zero extra cost.
        .background {
            if !isLiquidGlassEnabled {
                Rectangle()
                    .fill(.regularMaterial)
            }
        }
        // Glass path — gotta strip any default background first or the
        // refraction just paints over a solid surface and looks broken.
        .modifier(LiquidGlassModifier(enabled: isLiquidGlassEnabled))
    }

    // MARK: Subviews

    private var header: some View {
        HStack {
            Text("GlanceNote")
                .font(.headline)
                // pull the text back slightly in glass mode so it doesn't
                // fight the refraction highlights around the edges
                .foregroundStyle(isLiquidGlassEnabled ? .primary.opacity(0.85) : .primary)

            Spacer()

            // Liquid Glass toggle — lives here so it's always one tap away
            Toggle(isOn: $isLiquidGlassEnabled) {
                Image(systemName: isLiquidGlassEnabled
                      ? "sparkles.rectangle.stack.fill"
                      : "sparkles.rectangle.stack")
                    .symbolRenderingMode(.hierarchical)
                    .help(isLiquidGlassEnabled ? "Disable Liquid Glass" : "Enable Liquid Glass")
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)

            Button(action: createNote) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notes) { note in
                    NoteRowView(note: note)
                    Divider()
                }
            }
        }
    }

    // MARK: Actions

    private func createNote() {
        let note = Note()
        context.insert(note)
        try? context.save()

        let frame = NSRect(x: note.windowOriginX, y: note.windowOriginY,
                           width: note.windowWidth, height: note.windowHeight)
        note.isPinned = true
        registry.open(noteID: note.id, frame: frame) {
            NoteCardView(note: note)
        }
    }
}

// MARK: - LiquidGlassModifier

/// Encapsulates the conditional glass effect so the call site stays clean.
///
/// When enabled:
///   .glassEffect(.clear, in: RoundedRectangle) replaces the view's rendering
///   surface with the macOS 26 Liquid Glass compositor. The .clear style lets
///   desktop content and refraction highlights show through unobstructed.
///
/// When disabled: no-op — the parent provides its own .regularMaterial background.
private struct LiquidGlassModifier: ViewModifier {

    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                // The glass effect itself handles all the blur, refraction,
                // and specular highlights — we just pick the shape and style.
                .glassEffect(
                    .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        } else {
            content
        }
    }
}

// MARK: - NoteRowView

private struct NoteRowView: View {

    @Environment(PanelRegistry.self) private var registry
    @Bindable var note: Note

    @AppStorage("isLiquidGlassEnabled") private var isLiquidGlassEnabled = false

    var body: some View {
        HStack {
            // Color swatch
            Circle()
                .fill(Color(hex: note.colorTag.hexBackground))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))

            // Body preview
            Text(note.body.isEmpty ? "Empty note" : note.body)
                .lineLimit(1)
                .foregroundStyle(note.body.isEmpty ? .secondary : .primary)
                // same slight pullback as the header when glass is on
                .opacity(isLiquidGlassEnabled ? 0.85 : 1)
                .font(.callout)

            Spacer()

            // Pin / unpin toggle
            Button {
                togglePin()
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(note.isPinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if !note.isPinned { togglePin() }
        }
    }

    private func togglePin() {
        note.isPinned.toggle()
        if note.isPinned {
            let frame = NSRect(x: note.windowOriginX, y: note.windowOriginY,
                               width: note.windowWidth, height: note.windowHeight)
            registry.open(noteID: note.id, frame: frame) {
                NoteCardView(note: note)
            }
        } else {
            registry.close(noteID: note.id)
        }
    }
}
