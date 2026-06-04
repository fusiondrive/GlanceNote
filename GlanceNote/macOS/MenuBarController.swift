// GlanceNote/macOS/MenuBarController.swift
//
// Manages the NSStatusItem that serves as the sole entry point to GlanceNote
// on macOS. The popover it presents contains the full note list and controls
// for creating, pinning, and deleting notes.

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
private struct MenuBarPopoverView: View {

    @Environment(\.modelContext) private var context
    @Environment(PanelRegistry.self) private var registry

    @Query(sort: \Note.modifiedAt, order: .reverse)
    private var notes: [Note]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            noteList
        }
        .frame(width: 300)
    }

    // MARK: Subviews

    private var header: some View {
        HStack {
            Text("GlanceNote")
                .font(.headline)
            Spacer()
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

// MARK: - NoteRowView

private struct NoteRowView: View {

    @Environment(PanelRegistry.self) private var registry
    @Bindable var note: Note

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
