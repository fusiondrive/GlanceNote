// SharedKit/SharedDataClient.swift
//
// Lightweight data bridge between the main app and the WidgetKit extension.
// Both targets link this file. It owns all reads and writes to the shared
// App Group UserDefaults, acting as a thin serialization layer on top of
// the canonical SwiftData store.

import Foundation
import SwiftUI
import WidgetKit

// MARK: - Constants

public enum AppGroup {
    /// The App Group identifier registered in both target entitlements.
    public static let suiteName = "group.com.yourteam.glancenote"

    /// UserDefaults key for the serialized top-N note snapshots.
    public static let snapshotsKey = "pinned_note_snapshots"

    /// Maximum number of notes written to the shared defaults.
    /// Widgets display at most this many notes across all families.
    public static let maxSlots = 5
}

// MARK: - NoteSnapshot

/// A lightweight, Codable projection of a Note used by the widget extension.
/// Contains only the fields required for rendering; no SwiftData dependency.
public struct NoteSnapshot: Codable, Identifiable, Equatable {
    public let id: UUID
    public let body: String
    public let colorTag: NoteColor
    public let modifiedAt: Date
    public let widgetSlot: Int   // 1-based

    public init(id: UUID, body: String, colorTag: NoteColor,
                modifiedAt: Date, widgetSlot: Int) {
        self.id = id
        self.body = body
        self.colorTag = colorTag
        self.modifiedAt = modifiedAt
        self.widgetSlot = widgetSlot
    }
}

// MARK: - NoteColor

/// The accent color options for a note surface.
/// Kept in SharedKit so both the main app and the widget can reference it.
public enum NoteColor: String, Codable, CaseIterable {
    case yellow, white, blue, green, pink

    /// The canonical background color for each variant.
    /// Defined here as hex strings; SwiftUI Color extensions live in the app target.
    public var hexBackground: String {
        switch self {
        case .yellow: return "#FFFDE7"
        case .white:  return "#FFFFFF"
        case .blue:   return "#E3F2FD"
        case .green:  return "#E8F5E9"
        case .pink:   return "#FCE4EC"
        }
    }
}

// MARK: - SharedDataClient

public final class SharedDataClient {

    public static let shared = SharedDataClient()

    private let defaults: UserDefaults

    private init() {
        // Prefer the shared App Group suite so the WidgetKit extension can read
        // the same defaults. Falls back to standard UserDefaults when the App
        // Group entitlement is not provisioned (e.g., free Personal Team builds).
        self.defaults = UserDefaults(suiteName: AppGroup.suiteName) ?? .standard
    }

    // MARK: Writing (main app only)

    /// Serializes the provided snapshots to the shared UserDefaults and
    /// triggers a WidgetKit timeline reload.
    ///
    /// Call this after every mutation to the SwiftData store that affects
    /// pinned or widget-slotted notes.
    ///
    /// - Parameter snapshots: Notes to surface in widgets. Capped at
    ///   `AppGroup.maxSlots`; caller should pass notes sorted by `widgetSlot`.
    public func write(snapshots: [NoteSnapshot]) {
        let capped = Array(snapshots.prefix(AppGroup.maxSlots))
        do {
            let encoded = try JSONEncoder().encode(capped)
            defaults.set(encoded, forKey: AppGroup.snapshotsKey)
        } catch {
            // A failed write degrades gracefully: the widget will show stale
            // content until the next successful write.
            assertionFailure("SharedDataClient write failed: \(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Reading (widget extension and main app)

    /// Returns the most recently written note snapshots.
    /// Returns an empty array if no data has been written yet.
    public func read() -> [NoteSnapshot] {
        guard let data = defaults.data(forKey: AppGroup.snapshotsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([NoteSnapshot].self, from: data)
        } catch {
            return []
        }
    }
}

// MARK: - Color + hex

/// Initializes a SwiftUI Color from a 6-digit CSS hex string (e.g., "#FFFDE7").
/// Defined in SharedKit so both the app target and the WidgetKit extension can use it.
public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >>  8) & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}
