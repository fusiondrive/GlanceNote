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
/// Simulated Liquid Glass support:
///   When the toggle is on, LiquidGlassModifier layers ultraThinMaterial +
///   a white tint + a specular strokeBorder + drop shadow to fake the glass look.
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
        // background depends on glass state — NSPopover doesn't give us a
        // tinted surface for free, so we always provide one explicitly
        .background {
            if isLiquidGlassEnabled {
                ZStack {
                    // faking the glass refraction since the OS doesn't give it to us for free
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color.white.opacity(0.1))
                }
            } else {
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
                // pull text back slightly in glass mode — the frosted surface
                // generates bright specular edges and full-opacity text fights them
                .foregroundStyle(isLiquidGlassEnabled
                                 ? Color.primary.opacity(0.85)
                                 : Color.primary)

            Spacer()

            // glass toggle — always visible; .fill variant signals the active state
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

/// Simulates the Liquid Glass look using standard SwiftUI materials.
///
/// The background stack (ultraThinMaterial + white tint) is handled by the
/// parent — this modifier just layers the finishing touches: a specular
/// strokeBorder edge highlight and a soft floating shadow.
private struct LiquidGlassModifier: ViewModifier {

    let enabled: Bool

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    func body(content: Content) -> some View {
        if enabled {
            content
                // specular highlight — simulates light catching the edge of thick glass
                .overlay {
                    shape.strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }
                // soft shadow so the popover reads as floating off the menu bar
                .shadow(color: .black.opacity(0.15), radius: 15, y: 10)
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
