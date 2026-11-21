import SwiftUI
import AppKit

// MARK: - Glass Scrollbar

extension View {
    /// Replaces the default system scrollbar with a subtle, corner-safe overlay pill
    /// that stays clear of rounded glass panel edges and blends with the surface.
    func glassScrollbars(top: CGFloat = 8, bottom: CGFloat = 16, trailing: CGFloat = 6) -> some View {
        background(
            GlassScrollConfigurator(insets: NSEdgeInsets(top: top, left: 0, bottom: bottom, right: trailing))
                .allowsHitTesting(false)
        )
    }
}

/// Minimal overlay scroller that avoids the opaque grey track and stark white thumb
/// of macOS's default scroller inside floating glass panels.
private final class GlassScroller: NSScroller {
    private var isPointerInside = false
    private var hoverArea: NSTrackingArea?

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        redrawLayers()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        redrawLayers()
        super.mouseExited(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redrawLayers()
    }

    private func redrawLayers() {
        needsDisplay = true
        layer?.sublayers?.forEach { $0.setNeedsDisplay() }
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var isExpanded: Bool {
        isPointerInside || rect(for: .knobSlot).width > 8
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard isExpanded || flag else { return }
        let width: CGFloat = 8.5
        let trackRect = NSRect(
            x: slotRect.maxX - width,
            y: slotRect.minY + 1,
            width: width,
            height: max(0, slotRect.height - 2)
        )
        guard trackRect.height > width else { return }
        let color = isDark
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor.black.withAlphaComponent(0.06)
        color.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: width / 2, yRadius: width / 2).fill()
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.height > 4 else { return }
        let active = isExpanded || isHighlighted
        let width: CGFloat = active ? 6.5 : 4.5
        let rightMargin: CGFloat = 1.0
        let pillRect = NSRect(
            x: max(knobRect.minX, knobRect.maxX - rightMargin - width),
            y: knobRect.minY + 1,
            width: min(width, knobRect.width),
            height: max(width, knobRect.height - 2)
        )
        let fill = isDark
            ? NSColor.white.withAlphaComponent(active ? 0.62 : 0.38)
            : NSColor.black.withAlphaComponent(active ? 0.52 : 0.32)
        fill.setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pillRect.width / 2, yRadius: pillRect.width / 2).fill()
    }
}

private struct GlassScrollConfigurator: NSViewRepresentable {
    let insets: NSEdgeInsets

    func makeNSView(context: Context) -> HelperView {
        HelperView(insets: insets)
    }

    func updateNSView(_ nsView: HelperView, context: Context) {
        nsView.insets = insets
        nsView.attachIfNeeded()
    }

    final class HelperView: NSView {
        var insets: NSEdgeInsets
        private var styleObserver: NSObjectProtocol?
        private weak var attachedScrollView: NSScrollView?

        init(insets: NSEdgeInsets) {
            self.insets = insets
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit {
            if let styleObserver {
                NotificationCenter.default.removeObserver(styleObserver)
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let styleObserver {
                NotificationCenter.default.removeObserver(styleObserver)
                self.styleObserver = nil
            }
            if newWindow == nil {
                attachedScrollView = nil
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && styleObserver == nil {
                styleObserver = NotificationCenter.default.addObserver(
                    forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.attachIfNeeded()
                }
            }
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
        }

        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
        }

        func attachIfNeeded() {
            if attachedScrollView?.window == nil {
                attachedScrollView = nil
            }
            guard let scrollView = attachedScrollView ?? findScrollView() else { return }
            attachedScrollView = scrollView
            if !(scrollView.verticalScroller is GlassScroller) {
                let scroller = GlassScroller()
                scroller.scrollerStyle = .overlay
                scrollView.verticalScroller = scroller
            }
            if scrollView.scrollerStyle != .overlay {
                scrollView.scrollerStyle = .overlay
            }
            let current = scrollView.scrollerInsets
            if current.top != insets.top
                || current.bottom != insets.bottom
                || current.left != insets.left
                || current.right != insets.right {
                scrollView.scrollerInsets = insets
                scrollView.tile()
            }
        }

        private func findScrollView() -> NSScrollView? {
            var current: NSView? = self
            while let view = current {
                if let sv = view as? NSScrollView { return sv }
                if let parent = view.superview {
                    for sibling in parent.subviews where sibling !== view {
                        if framesMatch(sibling.frame, view.frame),
                           let sv = firstScrollView(in: sibling) {
                            return sv
                        }
                    }
                }
                current = view.superview
            }
            return nil
        }

        private func framesMatch(_ a: NSRect, _ b: NSRect) -> Bool {
            a.width > 0 && a.height > 0
                && abs(a.minX - b.minX) < 1
                && abs(a.minY - b.minY) < 1
                && abs(a.width - b.width) < 1
                && abs(a.height - b.height) < 1
        }

        private func firstScrollView(in view: NSView) -> NSScrollView? {
            if let sv = view as? NSScrollView { return sv }
            for subview in view.subviews {
                if let sv = firstScrollView(in: subview) { return sv }
            }
            return nil
        }
    }
}
