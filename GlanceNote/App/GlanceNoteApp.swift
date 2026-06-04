// GlanceNote/App/GlanceNoteApp.swift
//
// App entry point. On macOS the application is entirely menu-bar driven;
// there is no main window (LSUIElement = YES in Info.plist).
// On iOS the standard scene lifecycle runs a NavigationStack root.

import SwiftUI
import SwiftData

@main
struct GlanceNoteApp: App {

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    // The ModelContainer is initialized once here and injected into the
    // environment so every SwiftUI view and the AppDelegate can share it.
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer.glanceNoteContainer()
        } catch {
            // In a shipping app this would surface a user-facing error.
            // During development, a crash with a clear message is preferable.
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        // Settings is used as a structural no-op to satisfy the SwiftUI App
        // protocol's requirement for at least one Scene declaration.
        //
        // MenuBarExtra is intentionally absent. Declaring it alongside
        // MenuBarController (which creates its own NSStatusItem imperatively)
        // produces two status bar icons and two independent responder paths,
        // causing an NSViewBridgeErrorCanceled crash when the SwiftUI-owned
        // icon is clicked.
        //
        // MenuBarController, instantiated in AppDelegate, is the sole owner
        // of the NSStatusItem and the note-list popover.
        Settings {
            EmptyView()
        }
        #else
        WindowGroup {
            iOSRootView()
                .modelContainer(container)
        }
        #endif
    }
}

// MARK: - AppDelegate (macOS)

#if os(macOS)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Remove the app from the Dock and application switcher.
        NSApp.setActivationPolicy(.accessory)

        // Build the menu bar controller, passing it a context for data access.
        let context = ModelContext(try! ModelContainer.glanceNoteContainer())
        menuBarController = MenuBarController(modelContext: context)

        // Restore panels for notes that were pinned in the previous session.
        restorePinnedPanels(context: context)
    }

    func applicationWillTerminate(_ notification: Notification) {
        PanelRegistry.shared.closeAll()
    }

    // MARK: Private

    private func restorePinnedPanels(context: ModelContext) {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        guard let notes = try? context.fetch(descriptor) else { return }

        for note in notes {
            let frame = NSRect(
                x: note.windowOriginX, y: note.windowOriginY,
                width: note.windowWidth, height: note.windowHeight
            )
            PanelRegistry.shared.open(noteID: note.id, frame: frame) {
                NoteCardView(note: note)
                    .modelContext(context)
            }
        }
    }
}
#endif
