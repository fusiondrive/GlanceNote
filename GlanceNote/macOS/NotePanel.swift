// GlanceNote/macOS/NotePanel.swift
//
// Frameless floating NSPanel that hosts a single note surface.
//
// Panel characteristics:
//   - No title bar or standard window chrome.
//   - Floats above normal windows at .floating level.
//   - Visible on all Spaces via .canJoinAllSpaces.
//   - Edge-drag resizing via ResizeHandleView overlays.
//   - Auto-hiding hover chrome (close button, size presets) via PanelChromeView.

import AppKit
import SwiftUI

// MARK: - NotePanel

final class NotePanel: NSPanel {

    // MARK: Sizing constants

    static let minimumSize = NSSize(width: 160, height: 120)

    /// Point dimensions matching WidgetKit system families.
    enum Preset {
        static let small  = NSSize(width: 155, height: 155)
        static let medium = NSSize(width: 329, height: 155)
        static let large  = NSSize(width: 329, height: 345)
    }

    // MARK: Init

    init(frame: NSRect, noteID: UUID) {
        super.init(
            contentRect: frame,
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .resizable,
                .utilityWindow,
            ],
            backing: .buffered,
            defer: false
        )
        configure(noteID: noteID)
    }

    // MARK: Configuration

    private func configure(noteID: UUID) {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Transparent backing — the SwiftUI layer provides its own surface.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // The panel must become key so embedded text fields accept input.
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = true
        minSize = NotePanel.minimumSize

        // Per-note autosave key so each panel independently remembers its frame.
        setFrameAutosaveName("NotePanel-\(noteID.uuidString)")
    }

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotePanelController

/// Owns a NotePanel and its full SwiftUI view hierarchy.
/// Wraps the caller-supplied content in PanelChromeView so the hover
/// overlay is always present without the content needing to know about it.
final class NotePanelController {

    let panel: NotePanel
    let noteID: UUID

    // MARK: Init

    init<Content: View>(noteID: UUID,
                        frame: NSRect,
                        onClose: @escaping () -> Void,
                        @ViewBuilder content: () -> Content) {
        self.noteID = noteID
        self.panel  = NotePanel(frame: frame, noteID: noteID)

        // Wrap the content in the chrome overlay so resize/close actions
        // can manipulate the panel without the content layer coupling to AppKit.
        let root = PanelChromeView(
            onClose: onClose,
            onResize: { [weak panel] size in
                guard let panel else { return }
                var newFrame = panel.frame
                // Anchor resize to the top-left corner so the note does not
                // appear to jump as its height changes.
                newFrame.origin.y  += newFrame.height - size.height
                newFrame.size.width  = size.width
                newFrame.size.height = size.height
                panel.setFrame(newFrame, display: true, animate: true)
                panel.saveFrame(usingName: panel.frameAutosaveName)
            },
            content: content
        )

        // AppKit does not support adding subviews into an NSHostingView.
        // The solution is a plain NSView container as the panel's root content
        // view. NSHostingView and ResizeHandleViews are installed as siblings
        // within that container, keeping the SwiftUI and AppKit hierarchies
        // completely separate.
        let container = NSView()
        container.autoresizesSubviews = true
        panel.contentView = container

        // Hosting view fills the container entirely.
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Resize handles are siblings of the hosting view, not its subviews.
        installResizeHandles(in: container)
    }

    // MARK: Visibility

    func show() { panel.orderFront(nil) }
    func close() { panel.orderOut(nil) }

    // MARK: Edge resize handles

    /// Installs four transparent ResizeHandleViews as siblings of NSHostingView
    /// inside the shared container. This avoids the unsupported pattern of
    /// subviewing into NSHostingView.
    private func installResizeHandles(in container: NSView) {
        let thickness: CGFloat = 6
        for edge in ResizeEdge.allCases {
            let handle = ResizeHandleView(edge: edge, panel: panel)
            handle.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(handle)
            handle.activate(in: container, thickness: thickness)
        }
    }
}

// MARK: - PanelChromeView

/// Wraps panel content with two responsibilities:
///   1. Injects the resize callback into the SwiftUI environment so any
///      descendant (NoteCardView's toolbar) can invoke it without coupling
///      to AppKit types.
///   2. Overlays a close button that appears only while the cursor is inside
///      the panel. Size controls live in NoteCardView's toolbar to avoid
///      any positional collision with content views.
private struct PanelChromeView<Content: View>: View {

    let onClose:  () -> Void
    let onResize: (CGSize) -> Void
    let content:  Content

    @State private var isHovered = false

    init(onClose: @escaping () -> Void,
         onResize: @escaping (CGSize) -> Void,
         @ViewBuilder content: () -> Content) {
        self.onClose  = onClose
        self.onResize = onResize
        self.content  = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Inject resize action so NoteCardView's toolbar can consume it
            // via @Environment without knowing about AppKit or NotePanel.
            content
                .environment(\.panelResizeAction, onResize)

            // Close button — top-right corner, appears on hover only.
            if isHovered {
                closeButton
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: Close button

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Close note")
    }
}

// MARK: - ResizeEdge

enum ResizeEdge: CaseIterable {
    case left, right, top, bottom
}

// MARK: - ResizeHandleView

/// Transparent NSView at a panel edge. Tracks drag events to resize the panel.
final class ResizeHandleView: NSView {

    private let edge: ResizeEdge
    private weak var panel: NotePanel?

    // Captured at mouseDown so the frame computation stays consistent.
    private var dragOrigin:   NSPoint = .zero
    private var initialFrame: NSRect  = .zero

    init(edge: ResizeEdge, panel: NotePanel) {
        self.edge  = edge
        self.panel = panel
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: Constraint installation

    func activate(in parent: NSView, thickness t: CGFloat) {
        NSLayoutConstraint.activate(constraints(in: parent, thickness: t))
    }

    private func constraints(in parent: NSView, thickness t: CGFloat) -> [NSLayoutConstraint] {
        switch edge {
        case .left:
            return [leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                    topAnchor.constraint(equalTo: parent.topAnchor),
                    bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                    widthAnchor.constraint(equalToConstant: t)]
        case .right:
            return [trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                    topAnchor.constraint(equalTo: parent.topAnchor),
                    bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                    widthAnchor.constraint(equalToConstant: t)]
        case .bottom:
            return [leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                    trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                    bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                    heightAnchor.constraint(equalToConstant: t)]
        case .top:
            return [leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                    trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                    topAnchor.constraint(equalTo: parent.topAnchor),
                    heightAnchor.constraint(equalToConstant: t)]
        }
    }

    // MARK: Cursor rects

    override func resetCursorRects() {
        let cursor: NSCursor = (edge == .left || edge == .right) ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: Drag handling

    override func mouseDown(with event: NSEvent) {
        dragOrigin   = event.locationInWindow
        initialFrame = panel?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel else { return }

        let d = NSPoint(x: event.locationInWindow.x - dragOrigin.x,
                        y: event.locationInWindow.y - dragOrigin.y)
        var f = initialFrame

        switch edge {
        case .left:   f.origin.x += d.x; f.size.width  -= d.x
        case .right:                      f.size.width  += d.x
        case .bottom: f.origin.y += d.y; f.size.height -= d.y
        case .top:                        f.size.height += d.y
        }

        f.size.width  = max(f.size.width,  NotePanel.minimumSize.width)
        f.size.height = max(f.size.height, NotePanel.minimumSize.height)

        panel.setFrame(f, display: true, animate: false)
    }
}
