// GlanceNote/Model/Note.swift
//
// The canonical SwiftData model. This is the single source of truth for all
// note content on the main app side. The WidgetKit extension reads a
// projected subset via SharedDataClient rather than opening this store directly
// in order to avoid write-contention on the SQLite file.

import Foundation
import SwiftData

// MARK: - Note

@Model
final class Note {

    // MARK: Identity

    /// Stable identifier used as the key in PanelRegistry and NoteSnapshot.
    @Attribute(.unique) var id: UUID

    // MARK: Content

    var body: String
    var colorTag: NoteColor   // NoteColor is defined in SharedKit

    // MARK: Display state

    /// When true, a floating NotePanel is kept alive for this note on macOS.
    var isPinned: Bool

    /// 1-based slot index for widget promotion. nil = not shown in any widget.
    var widgetSlot: Int?

    // MARK: Window geometry (macOS only)
    //
    // Stored as raw Double pairs so they survive cross-platform round-trips.
    // The macOS layer converts these to NSRect; iOS ignores them entirely.

    var windowOriginX: Double
    var windowOriginY: Double
    var windowWidth: Double
    var windowHeight: Double

    // MARK: Timestamps

    var createdAt: Date
    var modifiedAt: Date

    // MARK: Init

    init(body: String = "",
         colorTag: NoteColor = .yellow,
         isPinned: Bool = false,
         widgetSlot: Int? = nil) {
        self.id = UUID()
        self.body = body
        self.colorTag = colorTag
        self.isPinned = isPinned
        self.widgetSlot = widgetSlot

        // Default panel size matches WidgetKit medium footprint.
        self.windowOriginX = 200
        self.windowOriginY = 400
        self.windowWidth = 329
        self.windowHeight = 155

        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

// MARK: - NoteSnapshot conversion

extension Note {
    /// Produces a lightweight snapshot suitable for writing to SharedDataClient.
    /// Only valid when widgetSlot != nil.
    func snapshot() -> NoteSnapshot? {
        guard let slot = widgetSlot else { return nil }
        return NoteSnapshot(
            id: id,
            body: body,
            colorTag: colorTag,
            modifiedAt: modifiedAt,
            widgetSlot: slot
        )
    }
}

// MARK: - ModelContainer factory

extension ModelContainer {
    /// Creates the production SwiftData container.
    ///
    /// Storage strategy (in priority order):
    ///   1. App Group shared container — used when the App Group entitlement is
    ///      provisioned (paid team or local entitlement override). Allows the
    ///      WidgetKit extension to read the same store.
    ///   2. Application Support local directory — fallback for free Personal Team
    ///      development builds where App Group provisioning is unavailable.
    ///
    /// iCloud / CloudKit sync is intentionally excluded; it requires a paid
    /// Apple Developer Program membership. Add a CloudKit-backed ModelConfiguration
    /// here once that membership is in place.
    static func glanceNoteContainer(readOnly: Bool = false) throws -> ModelContainer {
        let storeURL = resolvedStoreURL()

        // Ensure the parent directory exists before SwiftData tries to open the file.
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let config = ModelConfiguration(
            schema: Schema([Note.self]),
            url: storeURL,
            allowsSave: !readOnly
        )
        return try ModelContainer(for: Note.self, configurations: config)
    }

    /// Returns the store URL, preferring the shared App Group container and
    /// falling back to the app's own Application Support directory.
    private static func resolvedStoreURL() -> URL {
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.suiteName) {
            return groupURL
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("glancenote.store")
        }

        // Fallback: local Application Support (single-app access only).
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("GlanceNote", isDirectory: true)

        return appSupport.appendingPathComponent("glancenote.store")
    }
}
