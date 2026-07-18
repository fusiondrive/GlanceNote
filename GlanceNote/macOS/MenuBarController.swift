// GlanceNote/macOS/MenuBarController.swift
//
// Manages the NSStatusItem that serves as the sole entry point to GlanceNote
// on macOS. The popover it presents contains the full note list and controls
// for creating, pinning, and deleting notes.

import AppKit
import SwiftUI
import SwiftData

// @MainActor here because we touch PanelRegistry.shared (also @MainActor)
// and NSStatusBar directly — both want to be on the main thread anyway.
@MainActor
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
            button.image?.isTemplate = true  // adapts to light/dark menu bar
        }

        // --- Popover setup ---
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
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

/// Root SwiftUI view inside the menu bar popover.
///
/// Liquid Glass support (macOS 26+):
///   When the toggle is on, LiquidGlassModifier applies .glassEffect so the
///   system compositor handles the blur, refraction, and specular highlights.
///   When off, a standard .regularMaterial rectangle provides the normal
///   frosted-panel appearance.
private struct MenuBarPopoverView: View {

    @Environment(\.modelContext) private var context
    @Environment(PanelRegistry.self) private var registry

    @Query(sort: \Note.modifiedAt, order: .reverse)
    private var notes: [Note]

    @AppStorage("isLiquidGlassEnabled") private var isLiquidGlassEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            noteList
        }
        .frame(width: 300)
        // standard background when glass is off — need this because NSPopover
        // doesn't give us a tinted surface for free on all configurations
        .background {
            if !isLiquidGlassEnabled {
                Rectangle()
                    .fill(.regularMaterial)
            }
        }
        .modifier(LiquidGlassModifier(enabled: isLiquidGlassEnabled))
    }

    // MARK: Subviews

    private var header: some View {
        HStack {
            Text("GlanceNote")
                .font(.headline)
                // pull text back slightly in glass mode — the .clear refraction
                // generates bright specular edges and full-opacity text fights them
                .foregroundStyle(isLiquidGlassEnabled
                                 ? Color.primary.opacity(0.85)
                                 : Color.primary)

            Spacer()

            // glass toggle — .fill variant signals the active state, same
            // convention SF Symbols uses across the system
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
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var noteList: some View {
        if notes.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(notes) { note in
                        NoteRowView(note: note)
                        Divider()
                    }
                }
                // Rows slide/settle instead of teleporting when a note is
                // created or deleted.
                .animation(.easeOut(duration: 0.2), value: notes.count)
            }
        }
    }

    /// Wayfinding for first launch: an empty scroll area reads as broken,
    /// so answer "what is this and what do I do?" in place.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click + to create a floating note.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Applies the native macOS 26 Liquid Glass compositor to a view.
///
/// Guarded by @available so the modifier compiles cleanly against a
/// macOS 14 deployment target — on older OS versions it's a no-op.
/// The .clear glass style lets desktop content and refraction highlights
/// show through without any tint on top.
private struct LiquidGlassModifier: ViewModifier {

    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(
                        .clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            } else {
                // glass not available on this OS — fall through to the
                // .regularMaterial background the parent already provides
                content
            }
        } else {
            content
        }
    }
}

// MARK: - NoteRowView

private struct NoteRowView: View {

    @Environment(PanelRegistry.self) private var registry
    @Environment(\.modelContext) private var context
    @Bindable var note: Note

    @AppStorage("isLiquidGlassEnabled") private var isLiquidGlassEnabled = false

    /// Hover state for the row highlight. The highlight itself is nearly
    /// instant — hover feedback is seen constantly and must never lag the
    /// pointer.
    @State private var isHovering = false

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: note.colorTag.hexBackground))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))

            Text(note.body.isEmpty ? "Empty note" : note.body)
                .lineLimit(1)
                .foregroundStyle(note.body.isEmpty ? Color.secondary : Color.primary)
                // same slight pullback as the header when glass is active
                .opacity(isLiquidGlassEnabled ? 0.85 : 1)
                .font(.callout)

            Spacer()

            Button {
                togglePin()
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(note.isPinned ? Color.accentColor : Color.secondary)
                    // Morph pin → pin.fill in place instead of swapping glyphs.
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.85))
            .animation(.easeOut(duration: 0.15), value: note.isPinned)
            .help(note.isPinned ? "Unpin note" : "Pin note to desktop")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(Color.primary.opacity(isHovering ? 0.06 : 0))
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture {
            if !note.isPinned { togglePin() }
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin to Desktop") { togglePin() }
            Divider()
            Button("Delete", role: .destructive) { deleteNote() }
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
        try? context.save()
    }

    private func deleteNote() {
        // Close the floating panel first so no orphaned window survives
        // the model deletion.
        registry.close(noteID: note.id)
        context.delete(note)
        try? context.save()
    }
}
