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
// Appearance contract — "physical paper" paradigm:
//   GlanceNote notes are modelled after physical pastel sticky notes. A yellow
//   note is always yellow, with dark ink on top — regardless of whether macOS
//   is running in Light or Dark Mode. Adopting the system Dark Mode colour
//   scheme turns the vibrancy blur dark and inverts semantic text colours to
//   white, both of which destroy readability against pastel backgrounds.
//
//   To enforce a stable, light-mode-only rendering contract:
//
//   1. NSVisualEffectView.appearance is pinned to NSAppearance(named: .aqua).
//      This forces the blur material to always sample and composite in the
//      Aqua (light) colour space, producing a clean bright frost even when
//      the system appearance is Dark. The host desktop content still bleeds
//      through the blur; only AppKit's tinting pass is locked to light mode.
//
//   2. The SwiftUI subtree receives .environment(\.colorScheme, .light).
//      This propagates the light colour scheme to all SwiftUI children,
//      ensuring .ultraThinMaterial, system materials, and any remaining
//      semantic colour tokens resolve to their light-mode values without
//      requiring manual overrides at every call site.
//
//   3. All text and border values use explicit, hard-coded dark shades
//      (black at varying opacities) rather than semantic Color.primary /
//      Color.secondary. This eliminates any residual appearance-adaptive
//      path and guarantees consistent contrast against pastel backgrounds.

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
        // Propagate a forced light colour scheme to all SwiftUI children so
        // that system materials (.ultraThinMaterial, etc.) and any remaining
        // semantic colour tokens resolve to their light-mode variants. The
        // NSVisualEffectView appearance is pinned separately in VisualEffectView.
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        // Static dark border — appearance-independent, always readable against
        // the forced-light pastel background.
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
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

    /// Two-layer background: NSVisualEffectView (pinned to light appearance)
    /// for live desktop vibrancy, note colour tint composited on top.
    ///
    /// Layer order (bottom to top):
    ///   1. VisualEffectView — blur sampled from behind the window, always
    ///      rendered in Aqua (light) space via the pinned NSAppearance.
    ///   2. Color tint at 0.55 opacity — restored to a higher value now that
    ///      the vibrancy base is always light and will not compete with the
    ///      pastel overlay in dark mode.
    private var background: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color(hex: note.colorTag.hexBackground).opacity(0.55)
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
                    ? AnyShapeStyle(Color.black.opacity(0.35))
                    : AnyShapeStyle(Color.black.opacity(0.82))
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
                // Hard-coded dark value — appearance-independent ink on paper.
                .foregroundStyle(Color.black.opacity(0.85))
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
            // Static dark tint — readable against any pastel background without
            // competing with body text. Hidden on hover when resize controls
            // are available.
            Text(note.modifiedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(Color.black.opacity(0.45))
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
                // Single dark ring — static, appearance-independent.
                // A selected swatch gets a stronger stroke; unselected swatches
                // get a hairline separator to distinguish them from the background.
                Circle().strokeBorder(
                    isSelected ? Color.black.opacity(0.5) : Color.black.opacity(0.15),
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
/// Material and blending mode are configured at the call site.
///
/// Appearance contract:
///   The view's appearance is pinned to NSAppearance(named: .aqua) so that
///   the vibrancy material always composites in the light colour space,
///   regardless of the system Dark Mode setting. Without this pin, AppKit
///   inherits the window's effective appearance and renders a dark, murky
///   blur in Dark Mode — which conflicts with the pastel note tints layered
///   on top. Pinning to .aqua keeps the blur bright and clean in all
///   system appearance configurations.
///
///   State is always .active. Panels may be non-key while still visible;
///   .active ensures the blur renders at full fidelity regardless of focus.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // Pin to Aqua (light) appearance. This call is the single point of
        // enforcement for the "physical paper" rendering contract: the blur
        // base is always a bright, clean frost regardless of system appearance.
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        // Appearance is not updated here — it is intentionally pinned at
        // construction time and must not be overwritten on subsequent passes.
    }
}

// MARK: - SizePresetBar

/// Pill-shaped S / M / L buttons that map to WidgetKit system size footprints.
/// Rendered inside NoteCardView's toolbar trailing slot; never shown in
/// read-only contexts because panelResizeAction defaults to nil.
private struct SizePresetBar: View {

    let onResize: (CGSize) -> Void

    /// Named size presets. Values mirror NotePanel.Preset and must be kept
    /// in sync with the constants defined there.
    private let presets: [(label: String, size: CGSize)] = [
        ("S", CGSize(width: 240, height: 240)),
        ("M", CGSize(width: 400, height: 240)),
        ("L", CGSize(width: 400, height: 440)),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.label) { preset in
                Button(preset.label) { onResize(preset.size) }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    // Static dark label — readable against the forced-light
                    // capsule background at any system appearance.
                    .foregroundStyle(Color.black.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    // .ultraThinMaterial resolves to its light variant because
                    // the parent view tree carries .environment(\.colorScheme, .light).
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
