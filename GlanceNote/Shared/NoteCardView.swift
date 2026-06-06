// GlanceNote/Shared/NoteCardView.swift
//
// Primary rendering surface for a single note.
// Contexts of use:
//   1. macOS floating NotePanel  — full editing, debounced auto-save, widget sync
//   2. WidgetKit preview         — read-only snapshot (isReadOnly = true)
//
// Visual specification: corner radius, padding, and proportions mirror the
// system WidgetKit container so the panel and the widget feel identical.
//
// Dark mode implementation:
//   The card background is built from two layers:
//     1. NSVisualEffectView (.hudWindow, .behindWindow) — samples the live
//        desktop content and produces an adaptive blur tint that automatically
//        tracks light/dark appearance, exactly as native macOS widgets do.
//     2. Color(hex:).opacity(0.45) — overlays the per-note color tint on top
//        of the vibrancy layer. Opacity is kept below 0.5 so the vibrancy
//        material remains legible in dark mode rather than being buried under
//        an opaque color plane.
//   All text uses semantic system colors (Color.primary / Color.secondary)
//   so contrast adapts automatically with appearance. The timestamp uses
//   Color.secondary at a restrained opacity so it remains readable without
//   competing with body content.
//   A 0.5 pt border applied via .overlay(RoundedRectangle.strokeBorder)
//   anchors the card silhouette against dark wallpapers; the stroke color
//   is NSColor.separatorColor, which AppKit keys to the current appearance.

import AppKit
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
    /// Nil in WidgetKit preview contexts.
    @Environment(\.panelResizeAction) private var onResize

    /// Tracks cursor presence for the toolbar hover transition.
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        // Razor-thin adaptive border. NSColor.separatorColor is keyed to the
        // current AppKit appearance and resolves correctly in both light and
        // dark environments without a hard-coded value.
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
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

    /// Two-layer background: NSVisualEffectView for live desktop vibrancy,
    /// note color tint composited on top.
    ///
    /// Layer order (bottom to top):
    ///   1. NSVisualEffectView (.hudWindow, .behindWindow) — adaptive blur that
    ///      bleeds the desktop wallpaper tint in both light and dark appearances.
    ///   2. Color tint at 0.45 opacity — preserves vibrancy visibility in dark
    ///      mode while still expressing the per-note color identity.
    private var background: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color(hex: note.colorTag.hexBackground).opacity(0.45)
        }
        .ignoresSafeArea()
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
                // Color.primary is a semantic value — AppKit maps it to the
                // correct contrast level for the current appearance without
                // any manual dark-mode branching.
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

    /// Shared trailing position: timestamp is visible at rest, S/M/L pills
    /// fade in on hover. Both layers occupy the same ZStack frame so the
    /// layout never shifts.
    private var trailingSlot: some View {
        ZStack(alignment: .trailing) {
            // Timestamp — Color.secondary at 0.7 opacity clears the WCAG AA
            // contrast threshold on dark frosted backgrounds without competing
            // with body text. Hidden on hover when resize controls are available.
            Text(note.modifiedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(Color.secondary.opacity(0.7))
                .opacity(isHovered && onResize != nil ? 0 : 1)

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
                // Two-ring border system:
                //   Inner ring — selection indicator or default separator.
                //   Outer ring — overlay-blended white at 0.12 opacity;
                //     prevents light-colored swatches from disappearing
                //     against a dark vibrancy background.
                ZStack {
                    Circle().strokeBorder(
                        isSelected ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
                    Circle().strokeBorder(
                        Color.white.opacity(0.12),
                        lineWidth: 0.5
                    )
                    .blendMode(.overlay)
                }
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
    /// Matches the system WidgetKit container corner radius.
    static let cornerRadius: CGFloat = 20

    /// Inner content margin matching WidgetKit's 16 pt canonical inset.
    static let contentPadding: CGFloat = 16

    /// Height reserved for the color toolbar below the text area.
    static let toolbarHeight: CGFloat = 36
}

// MARK: - VisualEffectView

/// Thin NSViewRepresentable bridge exposing NSVisualEffectView to SwiftUI.
///
/// Material and blending mode are configured at the call site so this view
/// remains reusable. State is always .active — panels may be non-key while
/// still visible, and .active ensures the blur is rendered at full fidelity
/// regardless of focus state.
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

// MARK: - SizePresetBar

/// Pill-shaped S / M / L buttons that map to WidgetKit system size footprints.
/// Rendered inside NoteCardView's toolbar trailing slot; never shown in
/// read-only contexts because panelResizeAction defaults to nil.
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
                    .background(.ultraThinMaterial, in: Capsule())
                    .buttonStyle(.plain)
                    .help("Resize panel to \(preset.label)")
            }
        }
    }
}

// MARK: - PanelResizeAction environment key

/// Bridges the AppKit resize callback from NotePanelController into the SwiftUI
/// environment so NoteCardView stays decoupled from AppKit types.
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
