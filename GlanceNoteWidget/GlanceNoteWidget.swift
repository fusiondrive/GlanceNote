// GlanceNoteWidget/GlanceNoteWidget.swift
//
// WidgetKit extension entry point.
// Vends small, medium, and large widget families.
// Data is read exclusively from SharedDataClient (App Group UserDefaults)
// to avoid opening the SwiftData store from an extension context.

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct NoteWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [NoteSnapshot]  // Up to AppGroup.maxSlots items
}

// MARK: - TimelineProvider

struct NoteWidgetProvider: TimelineProvider {

    private let client = SharedDataClient.shared

    // MARK: Placeholder

    func placeholder(in context: Context) -> NoteWidgetEntry {
        NoteWidgetEntry(
            date: Date(),
            snapshots: [
                NoteSnapshot(id: UUID(),
                             body: "Buy oat milk\nCall dentist",
                             colorTag: .yellow,
                             modifiedAt: Date(),
                             widgetSlot: 1)
            ]
        )
    }

    // MARK: Snapshot (widget gallery preview)

    func getSnapshot(in context: Context, completion: @escaping (NoteWidgetEntry) -> Void) {
        let entry = NoteWidgetEntry(date: Date(), snapshots: client.read())
        completion(entry)
    }

    // MARK: Timeline

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteWidgetEntry>) -> Void) {
        let snapshots = client.read()
        let entry = NoteWidgetEntry(date: Date(), snapshots: snapshots)

        // Refresh every 15 minutes during typical use.
        // The main app will force-reload via WidgetCenter on every note save,
        // so this interval is a fallback for background consistency only.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget View

struct NoteWidgetView: View {

    let entry: NoteWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .systemLarge:
                largeView
            default:
                smallView
            }
        }
        // WidgetKit clips to the system-defined corner radius automatically.
        .containerBackground(for: .widget) {
            primaryBackgroundColor
        }
    }

    // MARK: Family layouts

    private var smallView: some View {
        NoteSnapshotView(snapshot: entry.snapshots.first)
            .padding(12)
    }

    private var mediumView: some View {
        NoteSnapshotView(snapshot: entry.snapshots.first, multiline: true)
            .padding(12)
    }

    private var largeView: some View {
        VStack(spacing: 0) {
            NoteSnapshotView(snapshot: entry.snapshots.first, multiline: true)
                .padding(12)
            if entry.snapshots.count > 1 {
                Divider()
                NoteSnapshotView(snapshot: entry.snapshots[1], multiline: true)
                    .padding(12)
            }
        }
    }

    // MARK: Helpers

    private var primaryBackgroundColor: Color {
        Color(hex: entry.snapshots.first?.colorTag.hexBackground ?? NoteColor.yellow.hexBackground)
    }
}

// MARK: - NoteSnapshotView

/// Renders a single NoteSnapshot in a non-interactive, widget-safe way.
private struct NoteSnapshotView: View {

    let snapshot: NoteSnapshot?
    var multiline: Bool = false

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.body.isEmpty ? "Empty note" : snapshot.body)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(multiline ? nil : 3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(snapshot.modifiedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("No notes pinned to widget")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Widget Configuration

struct GlanceNoteWidget: Widget {
    let kind = "GlanceNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoteWidgetProvider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("GlanceNote")
        .description("See your pinned notes at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct GlanceNoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlanceNoteWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    GlanceNoteWidget()
} timeline: {
    NoteWidgetEntry(date: .now, snapshots: [
        NoteSnapshot(id: UUID(), body: "Buy oat milk\nCall dentist", colorTag: .yellow, modifiedAt: .now, widgetSlot: 1)
    ])
}

#Preview("Medium", as: .systemMedium) {
    GlanceNoteWidget()
} timeline: {
    NoteWidgetEntry(date: .now, snapshots: [
        NoteSnapshot(id: UUID(), body: "Architecture review at 3pm.\nPrepare questions for team.", colorTag: .blue, modifiedAt: .now, widgetSlot: 1)
    ])
}
