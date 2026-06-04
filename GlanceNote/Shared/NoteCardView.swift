// GlanceNote/Shared/NoteCardView.swift
//
// Primary rendering surface for a single note.
// Contexts of use:
//   1. macOS floating NotePanel  — full editing, debounced auto-save, widget sync
//   2. iOS NoteEditorView sheet  — full editing
//   3. WidgetKit preview         — read-only snapshot (isReadOnly = true)
//
// Visual specification: corner radius, padding, and proportions mirror the
// system WidgetKit container so the panel and the widget feel identical.

import SwiftUI
import SwiftData

// MARK: - NoteCardView

struct NoteCardView: View {

    @Bindable var note: Note

    /// When true, the view renders in a static, non-interactive mode.
    /// The WidgetKit TimelineProvider sets this to true.
    var isReadOnly: Bool = false

    @Environment(\.modelContext) private var context
    /// Populated by PanelChromeView when running inside a floating NotePanel.
    /// Nil in all other contexts (iOS, WidgetKit previews).
    @Environment(\.panelResizeAction) private var onResize

    /// Tracks cursor presence for the toolbar hover transition (macOS only).
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .onHover { isHovered = $0 }
        // task(id:) cancels and restarts whenever note.body changes, giving a
        // natural 500 ms debounce with zero manual Task management. The task is
        // also cancelled automatically when the view disappears.
        .task(id: note.body) {
            guard !isReadOnly else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
                commitSave()
            } catch {
                // Cancellation is normal — body changed again before the
                // delay elapsed. No action required.
            }
        }
        .onDisappear {
            // Commit immediately on disappear so edits made in the last
            // 500 ms are not lost when the panel is closed.
            if !isReadOnly { commitSave() }
        }
    }

    // MARK: - Background

    /// Layered background: system material for depth, note color tint on top.
    /// On macOS the material blends with desktop content behind the panel.
    /// On iOS it falls back to a plain tinted surface.
    @ViewBuilder
    private var background: some View {
        #if os(macOS)
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color(hex: note.colorTag.hexBackground).opacity(0.55)
        }
        .ignoresSafeArea()
        #else
        Color(hex: note.colorTag.hexBackground)
            .ignoresSafeArea()
        #endif
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if isReadOnly {
            readOnlyBody
        } else {
            editableBody
        }
    }

    // MARK: - Read-only body

    private var readOnlyBody: some View {
        Text(note.body.isEmpty ? "Empty note" : note.body)
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundStyle(
                note.body.isEmpty
                    ? AnyShapeStyle(Color.secondary)
                    : AnyShapeStyle(Color.primary.opacity(0.82))
            )
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Layout.contentPadding)
    }

    // MARK: - Editable body

    private var editableBody: some View {
        VStack(spacing: 0) {
            TextEditor(text: $note.body)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.88))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                // Bottom padding reserves space for the color toolbar.
                .padding(.horizontal, Layout.contentPadding)
                .padding(.top, Layout.contentPadding)
                .padding(.bottom, Layout.toolbarHeight)

            colorToolbar
        }
    }

    // MARK: - Color toolbar

    /// Bottom toolbar: color swatches on the left, an animated trailing slot
    /// on the right that crossfades between the timestamp (at rest) and size
    /// preset controls (on hover, when running inside a NotePanel).
    private var colorToolbar: some View {
        HStack(spacing: 6) {
            ForEach(NoteColor.allCases, id: \.self) { color in
                colorSwatch(color)
            }
            Spacer()
            trailingSlot
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.bottom, 10)
        .frame(height: Layout.toolbarHeight)
    }

    /// Shared trailing position: timestamp dims and S/M/L pills fade in on hover.
    /// Both layers occupy the same ZStack frame so the layout never shifts.
    private var trailingSlot: some View {
        ZStack(alignment: .trailing) {
            // Timestamp — always present, dimmed at rest, hidden on hover.
            Text(note.modifiedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .opacity(isHovered && onResize != nil ? 0 : 0.45)

            // Size preset bar — visible only when a resize action is available
            // and the cursor is inside the panel.
            if let resize = onResize {
                SizePresetBar(onResize: resize)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .animation(.spring(duration: 0.25), value: isHovered)
    }

    private func colorSwatch(_ color: NoteColor) -> some View {
        let isSelected = color == note.colorTag
        return Circle()
            .fill(Color(hex: color.hexBackground))
            .frame(width: 13, height: 13)
            .overlay {
                Circle().strokeBorder(
                    isSelected ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.2),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            }
            .onTapGesture {
                note.colorTag = color
                // Color changes are not debounced — commit immediately since
                // the task(id:) watches note.body, not colorTag.
                commitSave()
            }
    }

    // MARK: - Save

    /// Persists the note to SwiftData and synchronises widget snapshots.
    /// Always called on the main actor; safe to call from onDisappear.
    private func commitSave() {
        note.modifiedAt = Date()
        try? context.save()
        pushWidgetSnapshots()
    }

    /// Fetches all widget-slotted notes and writes them to SharedDataClient,
    /// which triggers a WidgetKit timeline reload.
    private func pushWidgetSnapshots() {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.widgetSlot != nil },
            sortBy: [SortDescriptor(\.widgetSlot)]
        )
        let notes = (try? context.fetch(descriptor)) ?? []
        let snapshots = notes.compactMap { $0.snapshot() }
        SharedDataClient.shared.write(snapshots: snapshots)
    }
}

// MARK: - Layout constants

private enum Layout {
    /// Matches the system WidgetKit container corner radius on macOS/iOS.
    static let cornerRadius: CGFloat = 20

    /// Inner content margin matching WidgetKit's 16 pt canonical inset.
    static let contentPadding: CGFloat = 16

    /// Height reserved for the color toolbar below the text area.
    static let toolbarHeight: CGFloat = 36
}

// MARK: - VisualEffectView (macOS)

#if os(macOS)
/// Thin NSViewRepresentable bridge exposing NSVisualEffectView to SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif

// MARK: - SizePresetBar

/// Pill-shaped S / M / L buttons that map to WidgetKit system size footprints.
/// Rendered inside NoteCardView's toolbar trailing slot; never shown in
/// read-only or iOS contexts because panelResizeAction defaults to nil.
private struct SizePresetBar: View {

    let onResize: (CGSize) -> Void

    /// Width × height presets aligned to WidgetKit point dimensions.
    private let presets: [(label: String, size: CGSize)] = [
        ("S", CGSize(width: 155, height: 155)),
        ("M", CGSize(width: 329, height: 155)),
        ("L", CGSize(width: 329, height: 345)),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.label) { preset in
                Button(preset.label) { onResize(preset.size) }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    // Capsule with material fill: crisp at any background color.
                    .background(.ultraThinMaterial, in: Capsule())
                    .buttonStyle(.plain)
                    .help("Resize panel to \(preset.label)")
            }
        }
    }
}

// MARK: - PanelResizeAction environment key

/// Bridges the AppKit resize callback from NotePanelController into the SwiftUI
/// environment. CGSize is used (rather than NSSize) to keep this key
/// platform-agnostic; on macOS the two types are identical.
private struct PanelResizeActionKey: EnvironmentKey {
    static let defaultValue: ((CGSize) -> Void)? = nil
}

extension EnvironmentValues {
    /// The closure to invoke when the user selects a size preset.
    /// Nil when the view is not hosted inside a floating NotePanel.
    var panelResizeAction: ((CGSize) -> Void)? {
        get { self[PanelResizeActionKey.self] }
        set { self[PanelResizeActionKey.self] = newValue }
    }
}

// MARK: - Previews

#Preview("Editable — Yellow") {
    NoteCardView(note: Note(body: "Buy oat milk\nCall dentist\nFinish architecture doc",
                            colorTag: .yellow))
        .frame(width: 329, height: 155)
}

#Preview("Read-only — Blue") {
    NoteCardView(note: Note(body: "Widget preview content.", colorTag: .blue),
                 isReadOnly: true)
        .frame(width: 155, height: 155)
}
