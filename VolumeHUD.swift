import AppKit

// A small, click-through overlay shown near the bottom-center of whichever
// screen the cursor is on. Displays the current volume percentage and a bar,
// then fades out shortly after. Built lazily and with a solid background so
// it can never render invisibly.
final class VolumeHUD {
    private let panelSize = NSSize(width: 200, height: 70)

    private var window: NSWindow?
    private var icon: NSImageView!
    private var label: NSTextField!
    private var bar: HUDBar!
    private var hideWork: DispatchWorkItem?

    func show(volume: Float, muted: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.show(volume: volume, muted: muted) }
            return
        }

        buildIfNeeded()
        guard let window else { return }

        let pct = Int((volume * 100).rounded())
        label.stringValue = muted ? "Muted" : "\(pct)%"
        bar.level = muted ? 0 : CGFloat(volume)
        bar.needsDisplay = true


        positionWindow(window)
        window.alphaValue = 1
        window.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // MARK: - Build (lazy, on first show)

    private func buildIfNeeded() {
        guard window == nil else { return }

        let w = NSWindow(contentRect: NSRect(origin: .zero, size: panelSize),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        
        w.isReleasedWhenClosed = false
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                .ignoresCycle, .fullScreenAuxiliary]
        w.appearance = NSAppearance(named: .darkAqua)
        w.alphaValue = 1

        let bg = NSView(frame: NSRect(origin: .zero, size: panelSize))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.5).cgColor
        bg.layer?.cornerRadius = 18
        bg.layer?.masksToBounds = true
        w.contentView = bg


        let lb = NSTextField(labelWithString: "0%")
        lb.font = .systemFont(ofSize: 24, weight: .semibold)
        lb.alignment = .center
        lb.textColor = .white
        lb.isBezeled = false
        lb.drawsBackground = false
        lb.frame = NSRect(x: 0, y: 32, width: panelSize.width, height: 28)
        bg.addSubview(lb)
        label = lb

        let br = HUDBar(frame: NSRect(x: 24, y: 22, width: panelSize.width - 48, height: 6))
        bg.addSubview(br)
        bar = br

        window = w
    }

    // MARK: - Hide

    private func fadeOut() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { window.orderOut(nil) })
    }

    // MARK: - Placement

    private func positionWindow(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let f = screen.frame
        let x = f.midX - panelSize.width / 2
        let y = f.minY + 20          // ~120pt above the bottom edge, centered
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

}

// Simple rounded progress bar drawn in the HUD.
final class HUDBar: NSView {
    var level: CGFloat = 0   // 0...1

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2

        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(0.25).setFill()
        track.fill()

        let clamped = max(0, min(1, level))
        guard clamped > 0 else { return }
        let width = max(bounds.height, bounds.width * clamped)
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        NSColor.white.setFill()
        fill.fill()
    }
}
