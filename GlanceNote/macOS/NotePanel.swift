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
//
// Hit-testing and cursor architecture:
//   The panel view hierarchy is:
//
//       NotePanel (NSPanel)
//       └── PanelContainerView           ← custom hitTest gate
//           ├── NSHostingView            ← SwiftUI content (PanelChromeView)
//           └── ResizeHandleView × 4    ← edge strips, drawn on top
//
//   PanelContainerView.hitTest ensures that pointer events landing in the
//   outer edgeHandleThickness-pt strip are routed exclusively to the
//   ResizeHandleView that covers that strip, or returned nil (pass-through
//   to the window) if no handle is present. This prevents NSHostingView's
//   internally registered NSTrackingArea from consuming edge events.
//
//   ResizeHandleView registers its own NSTrackingArea with .cursorUpdate
//   so cursor changes are reliable even when SwiftUI invalidates cursor
//   rects during layout.
//
//   PanelChromeView limits its .onHover tracking to a Rectangle inset by
//   edgeHandleThickness, so the SwiftUI hover state never activates from
//   edge-zone mouse movement.

import AppKit
import SwiftUI

// MARK: - Shared layout constant

/// Width of the edge strip that belongs exclusively to resize handle views.
/// All three layers (PanelContainerView, ResizeHandleView, PanelChromeView)
/// read this single value so they remain geometrically consistent.
private let edgeHandleThickness: CGFloat = 6

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

        // PanelContainerView acts as a hit-test gate (see file-level comments).
        // NSHostingView and ResizeHandleViews are siblings inside it, keeping
        // the SwiftUI and AppKit view hierarchies strictly separate.
        let container = PanelContainerView()
        panel.contentView = container

        // NSHostingView fills the container edge-to-edge. The hit-test gate in
        // PanelContainerView, the inset hover detector in PanelChromeView, and
        // the NSTrackingArea in each ResizeHandleView together ensure that the
        // outer edgeHandleThickness strip is functionally owned by the handles.
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

            // Hover detector — deliberately inset so its NSTrackingArea does
            // not cover the outer edge strip owned by ResizeHandleViews.
            // A filled Rectangle is used (rather than Color.clear) because
            // SwiftUI only registers a tracking area for views with a defined
            // hit-test shape; clear Color with no contentShape is ignored.
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .padding(edgeHandleThickness)
                .onHover { isHovered = $0 }
                .allowsHitTesting(false)   // Gestures still pass to content below.

            // Close button — top-right corner, appears on hover only.
            if isHovered {
                closeButton
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
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

    // MARK: Cursor tracking via NSTrackingArea
    //
    // resetCursorRects() is not used here. On borderless NSPanels, AppKit can
    // invalidate cursor rects during SwiftUI layout passes, causing the resize
    // cursor to disappear unexpectedly. NSTrackingArea with .cursorUpdate fires
    // an independent cursor-update event that is not subject to that cycle.

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove stale areas before installing a fresh one.
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,   // .inVisibleRect expands this to the view's visible bounds.
            options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    /// Called by AppKit's cursor-update event mechanism. More reliable than
    /// resetCursorRects on borderless panels because it is not invalidated
    /// by SwiftUI layout cycles.
    override func cursorUpdate(with event: NSEvent) {
        resizeCursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        resizeCursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// Accepts the initial click without requiring the panel to become key
    /// first, so the first drag gesture on an unfocused panel works correctly.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var resizeCursor: NSCursor {
        (edge == .left || edge == .right) ? .resizeLeftRight : .resizeUpDown
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

// MARK: - PanelContainerView

/// Root content view for NotePanel.
///
/// Acts as a hit-test gate between the NSHostingView (SwiftUI) and the
/// ResizeHandleViews (AppKit) that share the same container. The override
/// routes pointer events as follows:
///
///   - Point over a ResizeHandleView  →  ResizeHandleView (always wins)
///   - Point in edge strip, no handle →  nil  (bubbles to window frame)
///   - Point in interior              →  normal super.hitTest result
///
/// Returning nil for interior-edge points prevents NSHostingView's
/// NSTrackingArea from consuming events that belong to the resize zone,
/// eliminating cursor-mode conflicts without inletting the hosting view.
final class PanelContainerView: NSView {

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)

        // ResizeHandleViews own the edge strip unconditionally.
        if hit is ResizeHandleView { return hit }

        // For any other hit target, enforce an interior-only zone.
        // Points within edgeHandleThickness of any edge return nil so the
        // window's resize machinery (and ResizeHandleView tracking areas)
        // receive undivided access to cursor and drag events there.
        if !bounds.insetBy(dx: edgeHandleThickness, dy: edgeHandleThickness).contains(point) {
            return nil
        }

        return hit
    }
}
