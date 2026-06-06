// GlanceNote/Shared/NoteCardView.swift
//
// Primary rendering surface for a single note.
// Contexts of use:
//   1. macOS floating NotePanel  — full editing, debounced auto-save, widget sync
//   2. WidgetKit preview         — read-only snapshot (isReadOnly = true)
//
// Appearance modes — "physical paper" vs Liquid Glass:
//
//   Pastel mode (default):
//     The card mimics a physical sticky note. NSVisualEffectView is pinned to
//     Aqua so the blur base is always a bright frost regardless of Dark Mode.
//     A pastel color tint sits on top. All text uses hard-coded dark values
//     (black at varying opacities) for guaranteed contrast against light paper.
//     .environment(\.colorScheme, .light) propagates the contract to all
//     SwiftUI children so system materials also resolve to their light variants.
//
//   Liquid Glass mode (macOS 26+ only, opt-in via toolbar toggle):
//     The entire background is handed to the system glass compositor via
//     .glassEffect(.clear, in: shape). NotePanel already has isOpaque=false
//     and backgroundColor=.clear, so the compositor can see straight through
//     to the desktop — no extra window config needed.
//     The forced-light colorScheme override is intentionally absent in this
//     mode; the glass surface handles vibrancy and the text palette switches
//     to semantic adaptive values so it reads well over any wallpaper.
//     On macOS < 26 the toggle is hidden and this mode is never activated.

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

    @AppStorage("isNoteGlassEnabled") private var isNoteGlassEnabled = false

    /// Tracks cursor presence for the toolbar hover transition.
    @State private var isHovered = false

    // glass only makes sense on a live panel, never in a read-only widget preview
    private var glassActive: Bool { isNoteGlassEnabled && !isReadOnly }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
        }
        .modifier(NoteAppearanceModifier(glassActive: glassActive))
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

    /// In pastel mode: VisualEffectView (Aqua-pinned) + color tint.
    /// In glass mode: Color.clear — the glass compositor owns the surface
    /// completely; putting anything here would block the refraction path.
    @ViewBuilder
    private var background: some View {
        if glassActive {
            // gotta leave this empty or the glass compositor hits a solid wall
            Color.clear
        } else {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(hex: note.colorTag.hexBackground).opacity(0.55)
            }
            .ignoresSafeArea()
        }
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
                // glass mode gets adaptive color so it reads over any wallpaper;
                // pastel mode stays hard-coded dark for guaranteed ink-on-paper feel
                .foregroundStyle(glassActive
                                 ? Color.primary.opacity(0.88)
                                 : Color.black.opacity(0.85))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, Layout.contentPadding)
                .padding(.top, Layout.contentPadding)
                .padding(.bottom, Layout.toolbarHeight)

            colorToolbar
        }
    }

    // MARK: - Color toolbar

    /// Left side: five pastel swatches + optional glass swatch (macOS 26+).
    /// Right side: Spacer + trailingSlot (timestamp / resize pills).
    /// The two sides are mutually exclusive in selection state — picking any
    /// pastel color kills glass mode, and picking the glass swatch kills the
    /// active pastel selection visually (though colorTag is preserved so it
    /// comes back when the user turns glass off).
    private var colorToolbar: some View {
        HStack(spacing: 6) {
            ForEach(NoteColor.allCases, id: \.self) { color in
                colorSwatch(color)
            }
            // glass swatch lives in the left cluster with the color swatches,
            // not off on the right — that's the whole point of this refactor
            if #available(macOS 26.0, *), !isReadOnly {
                glassSwatch
            }
            Spacer()
            trailingSlot
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.bottom, 10)
        .frame(height: Layout.toolbarHeight)
    }

    /// Crossfades between timestamp (rest) and S/M/L resize pills (hover).
    private var trailingSlot: some View {
        ZStack(alignment: .trailing) {
            Text(note.modifiedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(glassActive
                                 ? Color.secondary
                                 : Color.black.opacity(0.45))
                .opacity(isHovered && onResize != nil ? 0 : 1)

            if let resize = onResize {
                SizePresetBar(onResize: resize)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .animation(.spring(duration: 0.25), value: isHovered)
    }

    /// A 13×13 circle swatch that represents Liquid Glass mode.
    /// Visually matches the pastel swatches in size and selection-ring logic.
    /// An ultraThinMaterial fill + sparkle icon signals "glass" without
    /// needing a hard-coded color that would look arbitrary.
    /// Only inserted on macOS 26+ where .glassEffect is actually available.
    @available(macOS 26.0, *)
    private var glassSwatch: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 13, height: 13)
            .overlay {
                // tiny sparkle to distinguish this from the solid pastel circles
                Image(systemName: "sparkle")
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            .overlay {
                // same selection ring logic as the pastel swatches — 1.5pt when
                // active, 0.5pt hairline when not, so the whole row feels consistent
                Circle().strokeBorder(
                    isNoteGlassEnabled ? Color.black.opacity(0.5) : Color.black.opacity(0.15),
                    lineWidth: isNoteGlassEnabled ? 1.5 : 0.5
                )
            }
            .onTapGesture {
                isNoteGlassEnabled = true
                commitSave()
            }
            .help("Liquid Glass (Beta)")
    }

    private func colorSwatch(_ color: NoteColor) -> some View {
        let isSelected = color == note.colorTag && !isNoteGlassEnabled
        // swatch rings go adaptive in glass mode — no hard-coded black against
        // an unknown wallpaper; pastel mode keeps the static dark ring
        let selectedColor: Color = glassActive ? .primary.opacity(0.55) : .black.opacity(0.5)
        let normalColor:   Color = glassActive ? .primary.opacity(0.2)  : .black.opacity(0.15)
        return Circle()
            .fill(Color(hex: color.hexBackground))
            .frame(width: 13, height: 13)
            .overlay {
                Circle().strokeBorder(
                    isSelected ? selectedColor : normalColor,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            }
            .onTapGesture {
                note.colorTag = color
                // kill glass mode if they explicitly pick a standard paper color —
                // the two modes are mutually exclusive in the selection UI
                isNoteGlassEnabled = false
                // color changes skip the debounce — task(id:) only watches body
                commitSave()
            }
    }

    // MARK: - Save

    private func commitSave() {
        note.modifiedAt = Date()
        try? context.save()
        pushWidgetSnapshots()
    }

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

// MARK: - NoteAppearanceModifier

/// Handles all the appearance branching for a note card in one place so
/// NoteCardView.body stays readable.
///
/// Pastel path (glass off, or macOS < 26):
///   - Forces .light colorScheme so materials and semantic colors resolve correctly
///   - Clips to the card corner radius
///   - Adds a 0.5pt dark border to anchor the card against dark wallpapers
///
/// Glass path (glass on, macOS 26+):
///   - No colorScheme override — the glass compositor handles vibrancy
///   - Clips to the same corner radius
///   - .glassEffect(.clear) replaces the entire background surface
///   - No explicit border — the glass specular edge is sufficient
private struct NoteAppearanceModifier: ViewModifier {

    let glassActive: Bool

    private let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)

    func body(content: Content) -> some View {
        if glassActive {
            if #available(macOS 26.0, *) {
                content
                    .clipShape(shape)
                    // hand the whole background surface to the glass compositor;
                    // NotePanel is already isOpaque=false + backgroundColor=.clear
                    // so the compositor can see straight through to the desktop
                    .glassEffect(.clear, in: shape)
            } else {
                // shouldn't actually reach here since the toggle is hidden on
                // older OS, but belt-and-suspenders never hurt anyone
                pastelContent(content)
            }
        } else {
            pastelContent(content)
        }
    }

    @ViewBuilder
    private func pastelContent(_ content: Content) -> some View {
        content
            // lock everything below us to light appearance so the pastel
            // tints and hard-coded dark text are always rendering against
            // a bright base, never a dark murky one
            .environment(\.colorScheme, .light)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            }
    }
}

// MARK: - Layout constants

private enum Layout {
    static let cornerRadius:   CGFloat = 20
    static let contentPadding: CGFloat = 16
    static let toolbarHeight:  CGFloat = 36
}

// MARK: - VisualEffectView

/// NSViewRepresentable bridge exposing NSVisualEffectView to SwiftUI.
///
/// Appearance is pinned to .aqua at construction time so the blur base is
/// always a bright, clean frost — never the dark murky surface that AppKit
/// produces when it inherits a Dark Mode window appearance.
/// State is always .active so non-key panels still render at full fidelity.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // pin to Aqua here and never touch it again — this is the single
        // enforcement point for the "physical paper" light-mode contract
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        // intentionally not updating appearance — it must stay pinned to .aqua
    }
}

// MARK: - SizePresetBar

/// S / M / L preset buttons in the toolbar trailing slot.
private struct SizePresetBar: View {

    let onResize: (CGSize) -> Void

    @AppStorage("isNoteGlassEnabled") private var isNoteGlassEnabled = false

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
                    .foregroundStyle(isNoteGlassEnabled
                                     ? Color.secondary
                                     : Color.black.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    // ultraThinMaterial resolves to its light variant in pastel mode
                    // because NoteAppearanceModifier pushes .light into the environment
                    .background(.ultraThinMaterial, in: Capsule())
                    .buttonStyle(.plain)
                    .help("Resize panel to \(preset.label)")
            }
        }
    }
}

// MARK: - PanelResizeAction environment key

private struct PanelResizeActionKey: EnvironmentKey {
    static let defaultValue: ((CGSize) -> Void)? = nil
}

extension EnvironmentValues {
    var panelResizeAction: ((CGSize) -> Void)? {
        get { self[PanelResizeActionKey.self] }
        set { self[PanelResizeActionKey.self] = newValue }
    }
}

// MARK: - Previews

#Preview("Editable — Yellow") {
    NoteCardView(note: Note(body: "Buy oat milk\nCall dentist\nFinish architecture doc",
                            colorTag: .yellow))
        .frame(width: 400, height: 240)
}

#Preview("Read-only — Blue") {
    NoteCardView(note: Note(body: "Widget preview content.", colorTag: .blue),
                 isReadOnly: true)
        .frame(width: 240, height: 240)
}
