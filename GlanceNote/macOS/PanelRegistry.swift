// GlanceNote/macOS/PanelRegistry.swift
//
// Singleton that owns all live NotePanelController instances.
// It is the authoritative mapping between Note.id values and visible panels.
// AppDelegate holds a strong reference to the shared instance.

import AppKit
import SwiftUI
import SwiftData

@Observable @MainActor
final class PanelRegistry {

    static let shared = PanelRegistry()

    // MARK: State

    /// Active panels keyed by Note UUID.
    private(set) var panels: [UUID: NotePanelController] = [:]

    private init() {}

    // MARK: Public interface

    /// Opens a floating panel for the given note, or brings the existing one
    /// to the front if a panel is already live.
    func open<Content: View>(noteID: UUID,
                              frame: NSRect,
                              @ViewBuilder content: () -> Content) {
        if let existing = panels[noteID] {
            existing.show()
            return
        }

        let controller = NotePanelController(
            noteID: noteID,
            frame: frame,
            onClose: { [weak self] in self?.close(noteID: noteID) },
            content: content
        )
        panels[noteID] = controller
        controller.show()
    }

    /// Closes and removes the panel for the given note ID.
    func close(noteID: UUID) {
        panels[noteID]?.close()
        panels.removeValue(forKey: noteID)
    }

    /// Closes all panels. Called on app termination.
    func closeAll() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
    }

    // MARK: Persistence helpers

    /// Reconstructs panels for all notes that were pinned in the previous
    /// session. Called once from AppDelegate after the ModelContext is ready.
    func restorePinnedPanels(from notes: [Note], environment: some View) {
        for note in notes where note.isPinned {
            let frame = NSRect(
                x: note.windowOriginX,
                y: note.windowOriginY,
                width: note.windowWidth,
                height: note.windowHeight
            )
            open(noteID: note.id, frame: frame) {
                // NoteCardView is defined in Shared/; referenced here by name.
                // The environment carries the ModelContext so edits propagate.
                NoteCardView(note: note)
            }
        }
    }

    /// Persists the current panel frame back to the note model.
    /// Call this in response to NSWindowDidMove / NSWindowDidResize notifications.
    func persistFrame(for noteID: UUID, to note: Note) {
        guard let controller = panels[noteID] else { return }
        let frame = controller.panel.frame
        note.windowOriginX = frame.origin.x
        note.windowOriginY = frame.origin.y
        note.windowWidth   = frame.size.width
        note.windowHeight  = frame.size.height
        note.modifiedAt = Date()
    }
}
